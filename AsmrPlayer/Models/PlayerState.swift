import Foundation
import AVFoundation

enum VideoDisplayMode: String, CaseIterable, Identifiable {
    case fit
    case fill
    case crop

    var id: Self { self }

    var title: String {
        switch self {
        case .fit:
            "适应"
        case .fill:
            "填充"
        case .crop:
            "裁剪"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fit:
            .resizeAspect
        case .fill, .crop:
            .resizeAspectFill
        }
    }
}

enum PlaybackMode: String, CaseIterable, Identifiable {
    case repeatAll
    case repeatOne
    case shuffle

    var id: Self { self }

    var title: String {
        switch self {
        case .repeatOne:
            "单个循环"
        case .repeatAll:
            "顺序循环"
        case .shuffle:
            "随机播放"
        }
    }

    var systemImage: String {
        switch self {
        case .repeatOne:
            "repeat.1"
        case .repeatAll:
            "repeat"
        case .shuffle:
            "shuffle"
        }
    }
}

enum PlaybackMediaKind {
    case audio
    case video

    init(url: URL) {
        self = MediaLibrary.isVideo(url) ? .video : .audio
    }

    func matches(_ url: URL) -> Bool {
        switch self {
        case .audio:
            MediaLibrary.audioExtensions.contains(url.pathExtension.lowercased())
        case .video:
            MediaLibrary.videoExtensions.contains(url.pathExtension.lowercased())
        }
    }
}

enum PlaybackQueueSource {
    case none
    case folder(URL)
    case playlist(String)
}

struct PlaybackQueue {
    var source: PlaybackQueueSource = .none
    var mediaKind: PlaybackMediaKind?
    var items: [URL] = []
    var currentURL: URL?

    var currentIndex: Int? {
        guard let currentURL else { return nil }
        return items.firstIndex { Self.matches($0, currentURL) }
    }

    var canNavigate: Bool {
        !items.isEmpty
    }

    static func single(_ url: URL) -> PlaybackQueue {
        PlaybackQueue(
            source: .none,
            mediaKind: PlaybackMediaKind(url: url),
            items: [url],
            currentURL: url
        )
    }

    mutating func select(_ url: URL) {
        currentURL = url
        if mediaKind == nil {
            mediaKind = PlaybackMediaKind(url: url)
        }
        if items.isEmpty || !items.contains(where: { Self.matches($0, url) }) {
            items = [url]
            source = .none
        }
    }

    func nextURL(mode: PlaybackMode) -> URL? {
        guard !items.isEmpty else { return currentURL }
        if mode == .shuffle {
            return randomURL()
        }
        guard let currentIndex else { return items.first }
        let nextIndex = items.index(after: currentIndex)
        return nextIndex < items.endIndex ? items[nextIndex] : items.first
    }

    func previousURL(mode: PlaybackMode) -> URL? {
        guard !items.isEmpty else { return currentURL }
        if mode == .shuffle {
            return randomURL()
        }
        guard let currentIndex else { return items.last }
        let previousIndex = currentIndex - 1
        return previousIndex >= items.startIndex ? items[previousIndex] : items.last
    }

    private func randomURL() -> URL? {
        guard items.count > 1, let currentURL else { return items.first }
        let candidates = items.filter { !Self.matches($0, currentURL) }
        return candidates.randomElement() ?? items.first
    }

    private static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}

struct PlayerState {
    var title = "未选择音频"
    var sourceURL: URL?
    var playbackQueue = PlaybackQueue()
    var playbackMode: PlaybackMode = .repeatAll
    var isVideo = false
    var videoDisplayMode: VideoDisplayMode = .fit
    var subtitleURL: URL?
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var playbackRate: Float = 1.0
    var volume: Float = 1.0
    var subtitleOffset: TimeInterval = 0
    var subtitlesEnabled = true
    var subtitleFontScale: Double = 1.0
    var subtitleVerticalOffset: Double = 0
    var sleepTimerDuration: TimeInterval?
    var sleepTimerPausedRemaining: TimeInterval?
    var sleepTimerEnd: Date?
    var activeSubtitle: SubtitleCue?

    var remainingSleepTime: TimeInterval? {
        guard let sleepTimerEnd else { return sleepTimerPausedRemaining }
        return max(0, sleepTimerEnd.timeIntervalSinceNow)
    }

    var isSleepTimerRunning: Bool {
        sleepTimerEnd != nil
    }

    var isSleepTimerPaused: Bool {
        sleepTimerEnd == nil && sleepTimerPausedRemaining != nil
    }

    var sleepTimerProgress: Double? {
        guard let sleepTimerDuration, sleepTimerDuration > 0 else { return nil }
        guard let remainingSleepTime else { return nil }
        return min(max((sleepTimerDuration - remainingSleepTime) / sleepTimerDuration, 0), 1)
    }
}
