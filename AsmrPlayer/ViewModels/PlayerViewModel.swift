import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state = PlayerState()
    @Published private(set) var subtitles: [SubtitleCue] = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var pictureInPicture = PictureInPictureService()
    var subtitleAutoloadHandler: ((URL) -> Void)?
    let settings: AppSettings

    let player = AVPlayer()

    private var timeObserver: Any?
    private var sleepTimerTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var activeMediaSecurityURL: URL?
    private let progressStore = PlaybackProgressStore.shared
    private var pendingRestoreURL: URL?
    private var lastProgressSaveDate = Date.distantPast
    private var didHandleCurrentItemEnd = false
    private weak var durationLoadedItem: AVPlayerItem?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenSubtitleID: UUID?

    convenience init() {
        self.init(settings: AppSettings.shared)
    }

    init(settings: AppSettings) {
        self.settings = settings
        state.subtitlesEnabled = settings.subtitlesEnabled
        configureAudioSession(activate: false, reportsErrors: false)
        configurePictureInPicture()
        addPeriodicObserver()
        configureRemoteCommands()
    }

    func openMedia(url: URL) {
        let shouldResumePlayback = state.isPlaying
        let previousState = state
        releaseActiveMediaSecurityScope()
        retainMediaSecurityScopeIfNeeded(for: url)
        let assetURL = url
        pictureInPicture.handleMediaWillChange(from: previousState, to: assetURL)
        let item = AVPlayerItem(url: assetURL)
        player.replaceCurrentItem(with: item)
        state.playbackQueue.select(assetURL)
        player.volume = state.volume
        state.sourceURL = assetURL
        state.title = MediaLibrary.displayName(for: assetURL)
        state.isVideo = MediaLibrary.isVideo(assetURL)
        state.currentTime = 0
        state.duration = 0
        state.isPlaying = false
        state.subtitleURL = nil
        state.activeSubtitle = nil
        subtitles = []
        pendingRestoreURL = assetURL
        lastProgressSaveDate = .distantPast
        didHandleCurrentItemEnd = false
        durationLoadedItem = nil
        updateDuration(for: item)
        subtitleAutoloadHandler?(assetURL)
        if shouldResumePlayback {
            play()
        }
    }

    @discardableResult
    func openSubtitle(url: URL, reportsErrors: Bool = true) -> Bool {
        do {
            let subtitleURL = url
            subtitles = try MediaLibrary.secureRead(from: subtitleURL) {
                try SubtitleParser.parse(url: subtitleURL)
            }
            state.subtitleURL = subtitleURL
            refreshActiveSubtitle()
            statusMessage = "已加载字幕：\(subtitleURL.lastPathComponent)"
            return true
        } catch {
            if reportsErrors {
                errorMessage = "无法读取字幕：\(error.localizedDescription)"
            }
            return false
        }
    }

    func togglePlay() {
        state.isPlaying ? pause() : play()
    }

    func play() {
        guard player.currentItem != nil else { return }
        configureAudioSession(activate: true)
        player.playImmediately(atRate: state.playbackRate)
        state.isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        state.isPlaying = false
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(state.duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        state.currentTime = clamped
        if state.duration <= 0 || clamped < state.duration - 0.5 {
            didHandleCurrentItemEnd = false
        }
        refreshActiveSubtitle()
        updateNowPlaying()
    }

    func skip(_ delta: TimeInterval) {
        seek(to: state.currentTime + delta)
    }

    func skipForward() {
        skip(settings.skipForwardSeconds)
    }

    func skipBackward() {
        skip(-settings.skipBackwardSeconds)
    }

    func setPlaybackQueue(_ queue: PlaybackQueue) {
        state.playbackQueue = queue
    }

    func playPreviousItem() {
        guard let url = state.playbackQueue.previousURL(mode: state.playbackMode) else { return }
        openMedia(url: url)
        play()
    }

    func playNextItem() {
        guard let url = state.playbackQueue.nextURL(mode: state.playbackMode) else { return }
        openMedia(url: url)
        play()
    }

    func cyclePlaybackMode() {
        switch state.playbackMode {
        case .repeatAll:
            state.playbackMode = .repeatOne
        case .repeatOne:
            state.playbackMode = .shuffle
        case .shuffle:
            state.playbackMode = .repeatAll
        }
    }

    func setRate(_ rate: Float) {
        state.playbackRate = rate
        if state.isPlaying {
            player.rate = rate
        }
        updateNowPlaying()
    }

    func setVolume(_ volume: Float) {
        state.volume = min(max(volume, 0), 1)
        player.volume = state.volume
    }

    func setBackgroundPlaybackEnabled(_ isEnabled: Bool) {
        settings.backgroundPlaybackEnabled = isEnabled
        configureAudioSession(activate: state.isPlaying)
    }

    func setVideoDisplayMode(_ mode: VideoDisplayMode) {
        state.videoDisplayMode = mode
    }

    func setVideoPlayerLayer(_ layer: AVPlayerLayer) {
        pictureInPicture.setVideoPlayerLayer(layer)
    }

    func togglePictureInPicture() {
        pictureInPicture.toggle(for: state)
    }

    func canStartPictureInPicture() -> Bool {
        pictureInPicture.canStart(for: state)
    }

    func toggleSubtitlesEnabled() {
        state.subtitlesEnabled.toggle()
        settings.subtitlesEnabled = state.subtitlesEnabled
        refreshActiveSubtitle()
    }

    func setSubtitlesEnabled(_ isEnabled: Bool) {
        state.subtitlesEnabled = isEnabled
        settings.subtitlesEnabled = isEnabled
        refreshActiveSubtitle()
    }

    func setSubtitleFontScale(_ scale: Double) {
        state.subtitleFontScale = min(max(scale, 0.75), 1.8)
    }

    func setSubtitleVerticalOffset(_ offset: Double) {
        state.subtitleVerticalOffset = min(max(offset, -120), 120)
    }

    func nudgeSubtitle(_ delta: TimeInterval) {
        state.subtitleOffset += delta
        refreshActiveSubtitle()
    }

    func resetSubtitleOffset() {
        state.subtitleOffset = 0
        refreshActiveSubtitle()
    }

    func setSleepTimer(minutes: Double?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard let minutes, minutes > 0 else {
            state.sleepTimerDuration = nil
            state.sleepTimerPausedRemaining = nil
            state.sleepTimerEnd = nil
            return
        }

        setSleepTimer(duration: minutes * 60)
    }

    func setSleepTimer(duration: TimeInterval?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard let duration, duration > 0 else {
            state.sleepTimerDuration = nil
            state.sleepTimerPausedRemaining = nil
            state.sleepTimerEnd = nil
            return
        }

        state.sleepTimerDuration = duration
        startSleepTimer(remaining: duration)
    }

    func pauseSleepTimer() {
        guard let remaining = state.remainingSleepTime else { return }
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        state.sleepTimerEnd = nil
        state.sleepTimerPausedRemaining = max(remaining, 1)
    }

    func resumeSleepTimer() {
        guard let remaining = state.sleepTimerPausedRemaining, remaining > 0 else { return }
        startSleepTimer(remaining: remaining)
    }

    func toggleSleepTimer(duration: TimeInterval) {
        if state.isSleepTimerRunning {
            pauseSleepTimer()
        } else if state.isSleepTimerPaused {
            resumeSleepTimer()
        } else {
            setSleepTimer(duration: duration)
        }
    }

    private func startSleepTimer(remaining: TimeInterval) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        state.sleepTimerPausedRemaining = nil
        state.sleepTimerEnd = Date().addingTimeInterval(remaining)
        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let remaining = self.state.remainingSleepTime else {
                    self.sleepTimerTask = nil
                    return
                }
                if remaining <= 0 {
                    self.pause()
                    self.state.sleepTimerDuration = nil
                    self.state.sleepTimerEnd = nil
                    self.sleepTimerTask = nil
                    return
                }
                self.objectWillChange.send()
            }
        }
    }

    func formattedTime(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "00:00" }
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func configureAudioSession(activate: Bool, reportsErrors: Bool = true) {
        do {
            let session = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category = settings.backgroundPlaybackEnabled ? .playback : .ambient
            let preferredOptions: AVAudioSession.CategoryOptions = settings.backgroundPlaybackEnabled
                ? [.allowAirPlay, .allowBluetoothA2DP]
                : []
            do {
                try session.setCategory(category, mode: .default, options: preferredOptions)
            } catch {
                try session.setCategory(category, mode: .default, options: [])
            }
            if activate {
                try session.setActive(true)
            }
        } catch {
            if reportsErrors {
                errorMessage = "音频会话配置失败：\(error.localizedDescription)"
            }
        }
    }

    private func configurePictureInPicture() {
        pictureInPicture.prepareHandler = { [weak self] in
            self?.configureAudioSession(activate: true)
        }
        pictureInPicture.playHandler = { [weak self] in
            self?.play()
        }
        pictureInPicture.pauseHandler = { [weak self] in
            self?.pause()
        }
        pictureInPicture.skipHandler = { [weak self] seconds in
            self?.skip(seconds)
        }
        pictureInPicture.errorHandler = { [weak self] message in
            self?.errorMessage = message
        }
        pictureInPicture.statusHandler = { [weak self] isActive in
            self?.statusMessage = isActive ? "已开启画中画" : nil
        }
    }

    private func addPeriodicObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.refreshActiveSubtitle()
                self.pictureInPicture.update(with: self.state)
                self.savePlaybackProgress()
                self.handlePlaybackEndIfNeeded()
            }
        }
    }

    private func handlePlaybackEndIfNeeded() {
        guard state.isPlaying,
              !didHandleCurrentItemEnd,
              state.duration > 0,
              state.currentTime >= state.duration - 0.25 else {
            return
        }
        didHandleCurrentItemEnd = true

        switch state.playbackMode {
        case .repeatOne:
            seek(to: 0)
            play()
        case .repeatAll, .shuffle:
            playNextItem()
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play()
            }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: settings.skipBackwardSeconds)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipBackward()
            }
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: settings.skipForwardSeconds)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipForward()
            }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performRemoteAction(self?.settings.remotePreviousAction ?? .previousTrack)
            }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performRemoteAction(self?.settings.remoteNextAction ?? .nextTrack)
            }
            return .success
        }
    }

    private func performRemoteAction(_ action: RemoteCommandAction) {
        switch action {
        case .previousTrack:
            playPreviousItem()
        case .nextTrack:
            playNextItem()
        case .skipForward:
            skipForward()
        case .skipBackward:
            skipBackward()
        }
    }

    private func updateDuration(for item: AVPlayerItem?) {
        guard let item else { return }
        guard durationLoadedItem !== item else { return }
        durationLoadedItem = item
        durationTask?.cancel()
        durationTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            do {
                let duration = try await item.asset.load(.duration).seconds
                guard !Task.isCancelled, duration.isFinite, duration > 0 else { return }
                self.state.duration = duration
                if let pending = self.pendingRestoreURL {
                    self.pendingRestoreURL = nil
                    self.restoreProgress(for: pending)
                }
                self.updateNowPlaying()
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "无法读取媒体时长：\(error.localizedDescription)"
            }
        }
    }

    private func refreshActiveSubtitle() {
        guard state.subtitlesEnabled else {
            state.activeSubtitle = nil
            stopSubtitleSpeech()
            return
        }
        let subtitleTime = state.currentTime + state.subtitleOffset
        state.activeSubtitle = subtitles.first { $0.contains(subtitleTime) }
        speakActiveSubtitleIfNeeded()
    }

    private func speakActiveSubtitleIfNeeded() {
        guard settings.subtitleSpeechEnabled, state.isPlaying, let cue = state.activeSubtitle else {
            if state.activeSubtitle == nil {
                lastSpokenSubtitleID = nil
            }
            return
        }
        guard cue.id != lastSpokenSubtitleID else { return }
        lastSpokenSubtitleID = cue.id
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: cue.text)
        utterance.voice = bestSubtitleSpeechVoice(for: settings.subtitleSpeechLanguage)
        let speechRate = AVSpeechUtteranceDefaultSpeechRate * Float(settings.subtitleSpeechRate)
        utterance.rate = min(max(speechRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = Float(settings.subtitleSpeechVolume)
        speechSynthesizer.speak(utterance)
    }

    private func bestSubtitleSpeechVoice(for language: SubtitleSpeechLanguage) -> AVSpeechSynthesisVoice? {
        let matchingVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language.voiceLanguageCode }
            .sorted { lhs, rhs in
                let lhsIsFemale = lhs.gender == .female
                let rhsIsFemale = rhs.gender == .female
                if lhsIsFemale != rhsIsFemale {
                    return lhsIsFemale
                }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.identifier < rhs.identifier
            }
        return matchingVoices.first ?? AVSpeechSynthesisVoice(language: language.voiceLanguageCode)
    }

    private func stopSubtitleSpeech() {
        lastSpokenSubtitleID = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private func restoreProgress(for url: URL) {
        guard let record = progressStore.record(for: url), !record.completed else { return }
        guard record.duration > 0, record.position > 1, record.duration - record.position > 5 else { return }
        seek(to: record.position)
    }

    private func savePlaybackProgress() {
        guard let url = state.sourceURL, state.duration > 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressSaveDate) >= 2 else { return }
        lastProgressSaveDate = now
        progressStore.save(position: state.currentTime, duration: state.duration, for: url)
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func retainMediaSecurityScopeIfNeeded(for url: URL) {
        guard !url.path.hasPrefix(documentsDirectory.path) else { return }
        if url.startAccessingSecurityScopedResource() {
            activeMediaSecurityURL = url
        }
    }

    private func releaseActiveMediaSecurityScope() {
        activeMediaSecurityURL?.stopAccessingSecurityScopedResource()
        activeMediaSecurityURL = nil
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? state.playbackRate : 0
        ]
        if state.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = state.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
