import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var theme: AppTheme { didSet { save(theme.rawValue, for: Keys.theme) } }
    @Published var searchFilters: Set<SearchFilter> { didSet { save(searchFilters.map(\.rawValue), for: Keys.searchFilters) } }
    @Published var autoHideVideoControls: Bool { didSet { save(autoHideVideoControls, for: Keys.autoHideVideoControls) } }
    @Published var skipForwardSeconds: Double { didSet { save(skipForwardSeconds, for: Keys.skipForwardSeconds) } }
    @Published var skipBackwardSeconds: Double { didSet { save(skipBackwardSeconds, for: Keys.skipBackwardSeconds) } }
    @Published var backgroundPlaybackEnabled: Bool { didSet { save(backgroundPlaybackEnabled, for: Keys.backgroundPlaybackEnabled) } }
    @Published var subtitlesEnabled: Bool { didSet { save(subtitlesEnabled, for: Keys.subtitlesEnabled) } }
    @Published var preferredSubtitleLanguage: SubtitleLanguage { didSet { save(preferredSubtitleLanguage.rawValue, for: Keys.preferredSubtitleLanguage) } }
    @Published var subtitleSpeechEnabled: Bool { didSet { save(subtitleSpeechEnabled, for: Keys.subtitleSpeechEnabled) } }
    @Published var subtitleSpeechRate: Double { didSet { save(subtitleSpeechRate, for: Keys.subtitleSpeechRate) } }
    @Published var subtitleSpeechVolume: Double { didSet { save(subtitleSpeechVolume, for: Keys.subtitleSpeechVolume) } }
    @Published var subtitleSpeechLanguage: SubtitleSpeechLanguage { didSet { save(subtitleSpeechLanguage.rawValue, for: Keys.subtitleSpeechLanguage) } }
    @Published var subtitleFont: SubtitleFontFamily { didSet { save(subtitleFont.rawValue, for: Keys.subtitleFont) } }
    @Published var subtitleFontStyle: SubtitleFontStyle { didSet { save(subtitleFontStyle.rawValue, for: Keys.subtitleFontStyle) } }
    @Published var subtitleOutlineEnabled: Bool { didSet { save(subtitleOutlineEnabled, for: Keys.subtitleOutlineEnabled) } }
    @Published var subtitleShadowEnabled: Bool { didSet { save(subtitleShadowEnabled, for: Keys.subtitleShadowEnabled) } }
    @Published var remotePreviousAction: RemoteCommandAction { didSet { save(remotePreviousAction.rawValue, for: Keys.remotePreviousAction) } }
    @Published var remoteNextAction: RemoteCommandAction { didSet { save(remoteNextAction.rawValue, for: Keys.remoteNextAction) } }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        let filterValues = defaults.stringArray(forKey: Keys.searchFilters) ?? SearchFilter.defaultSet.map(\.rawValue)
        let filters = Set(filterValues.compactMap(SearchFilter.init(rawValue:)))
        searchFilters = filters.isEmpty ? SearchFilter.defaultSet : filters
        autoHideVideoControls = defaults.object(forKey: Keys.autoHideVideoControls) as? Bool ?? true
        skipForwardSeconds = defaults.object(forKey: Keys.skipForwardSeconds) as? Double ?? 15
        skipBackwardSeconds = defaults.object(forKey: Keys.skipBackwardSeconds) as? Double ?? 5
        backgroundPlaybackEnabled = defaults.object(forKey: Keys.backgroundPlaybackEnabled) as? Bool ?? true
        subtitlesEnabled = defaults.object(forKey: Keys.subtitlesEnabled) as? Bool ?? true
        preferredSubtitleLanguage = SubtitleLanguage(rawValue: defaults.string(forKey: Keys.preferredSubtitleLanguage) ?? "") ?? .chinese
        subtitleSpeechEnabled = defaults.object(forKey: Keys.subtitleSpeechEnabled) as? Bool ?? false
        let savedSubtitleSpeechRate = defaults.object(forKey: Keys.subtitleSpeechRate) as? Double ?? 1.0
        subtitleSpeechRate = min(max(savedSubtitleSpeechRate, 0.3), 2.0)
        let savedSubtitleSpeechVolume = defaults.object(forKey: Keys.subtitleSpeechVolume) as? Double ?? 0.15
        subtitleSpeechVolume = min(max(savedSubtitleSpeechVolume, 0), 1)
        subtitleSpeechLanguage = SubtitleSpeechLanguage(rawValue: defaults.string(forKey: Keys.subtitleSpeechLanguage) ?? "") ?? .chinese
        subtitleFont = SubtitleFontFamily(rawValue: defaults.string(forKey: Keys.subtitleFont) ?? "") ?? .system
        subtitleFontStyle = SubtitleFontStyle(rawValue: defaults.string(forKey: Keys.subtitleFontStyle) ?? "") ?? .regular
        subtitleOutlineEnabled = defaults.object(forKey: Keys.subtitleOutlineEnabled) as? Bool ?? true
        subtitleShadowEnabled = defaults.object(forKey: Keys.subtitleShadowEnabled) as? Bool ?? true
        remotePreviousAction = RemoteCommandAction(rawValue: defaults.string(forKey: Keys.remotePreviousAction) ?? "") ?? .previousTrack
        remoteNextAction = RemoteCommandAction(rawValue: defaults.string(forKey: Keys.remoteNextAction) ?? "") ?? .nextTrack
    }

    func binding(for filter: SearchFilter) -> Binding<Bool> {
        Binding(
            get: { self.searchFilters.contains(filter) },
            set: { isEnabled in
                if isEnabled {
                    self.searchFilters.insert(filter)
                } else {
                    self.searchFilters.remove(filter)
                }
            }
        )
    }

    func allowsSearchResult(kind: LibraryItem.Kind, fileExtension: String) -> Bool {
        let filter = SearchFilter(kind: kind, fileExtension: fileExtension)
        return searchFilters.contains(filter)
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case video
    case audio
    case image
    case subtitle
    case document
    case folder
    case other

    var id: Self { self }

    static let defaultSet: Set<SearchFilter> = [.video, .audio, .subtitle, .folder]

    init(kind: LibraryItem.Kind, fileExtension: String) {
        switch kind {
        case .folder:
            self = .folder
        case .subtitle:
            self = .subtitle
        case .media:
            self = MediaLibrary.isVideoExtension(fileExtension) ? .video : .audio
        case .image:
            self = .image
        case .document:
            self = .document
        case .other:
            self = .other
        }
    }

    var title: String {
        switch self {
        case .video: "视频"
        case .audio: "音频"
        case .image: "图像"
        case .subtitle: "字幕"
        case .document: "文档"
        case .folder: "文件夹"
        case .other: "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .subtitle: "captions.bubble"
        case .document: "doc.text"
        case .folder: "folder"
        case .other: "shippingbox"
        }
    }
}

enum SubtitleLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english
    case japanese
    case auto

    var id: Self { self }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "Japanese"
        case .auto: "更多/自动"
        }
    }

    var filenameHints: [String] {
        switch self {
        case .chinese: ["zh", "zh-cn", "chs", "sc", "cn", "中文", "简体"]
        case .english: ["en", "eng", "english"]
        case .japanese: ["ja", "jp", "jpn", "japanese", "日本語", "日文"]
        case .auto: []
        }
    }
}

enum SubtitleSpeechLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english
    case japanese

    var id: Self { self }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        case .japanese: "Japanese"
        }
    }

    var voiceLanguageCode: String {
        switch self {
        case .chinese: "zh-CN"
        case .english: "en-US"
        case .japanese: "ja-JP"
        }
    }
}

enum SubtitleFontFamily: String, CaseIterable, Identifiable {
    case system
    case rounded
    case pingFang
    case helveticaNeue
    case avenirNext
    case notoSans

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "系统字体"
        case .rounded: "系统圆体"
        case .pingFang: "PingFang SC"
        case .helveticaNeue: "Helvetica Neue"
        case .avenirNext: "Avenir Next"
        case .notoSans: "Noto Sans"
        }
    }

    var fontName: String? {
        switch self {
        case .system, .rounded: nil
        case .pingFang: "PingFangSC-Regular"
        case .helveticaNeue: "HelveticaNeue"
        case .avenirNext: "AvenirNext-Regular"
        case .notoSans: "NotoSans-Regular"
        }
    }
}

enum SubtitleFontStyle: String, CaseIterable, Identifiable {
    case regular
    case bold

    var id: Self { self }

    var title: String {
        switch self {
        case .regular: "普通"
        case .bold: "加粗"
        }
    }
}

enum RemoteCommandAction: String, CaseIterable, Identifiable {
    case previousTrack
    case nextTrack
    case skipForward
    case skipBackward

    var id: Self { self }

    var title: String {
        switch self {
        case .previousTrack: "上一首曲目"
        case .nextTrack: "下一首曲目"
        case .skipForward: "快进"
        case .skipBackward: "快退"
        }
    }
}

private enum Keys {
    static let theme = "settings.theme"
    static let searchFilters = "settings.searchFilters"
    static let autoHideVideoControls = "settings.autoHideVideoControls"
    static let skipForwardSeconds = "settings.skipForwardSeconds"
    static let skipBackwardSeconds = "settings.skipBackwardSeconds"
    static let backgroundPlaybackEnabled = "settings.backgroundPlaybackEnabled"
    static let subtitlesEnabled = "settings.subtitlesEnabled"
    static let preferredSubtitleLanguage = "settings.preferredSubtitleLanguage"
    static let subtitleSpeechEnabled = "settings.subtitleSpeechEnabled"
    static let subtitleSpeechRate = "settings.subtitleSpeechRate"
    static let subtitleSpeechVolume = "settings.subtitleSpeechVolume"
    static let subtitleSpeechLanguage = "settings.subtitleSpeechLanguage"
    static let subtitleFont = "settings.subtitleFont"
    static let subtitleFontStyle = "settings.subtitleFontStyle"
    static let subtitleOutlineEnabled = "settings.subtitleOutlineEnabled"
    static let subtitleShadowEnabled = "settings.subtitleShadowEnabled"
    static let remotePreviousAction = "settings.remotePreviousAction"
    static let remoteNextAction = "settings.remoteNextAction"
}
