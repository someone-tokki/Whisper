import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(SettingsRoute.rootRoutes) { route in
                        NavigationLink(value: route) {
                            SettingsNavigationRowContent(
                                icon: route.icon,
                                title: route.title,
                                subtitle: route.subtitle
                            )
                        }
                    }
                }

                Section("文件") {
                    SettingsInfoRow(icon: "folder", title: "资料页根目录", value: "Files > 我的 iPhone > Whisper")
                    SettingsInfoRow(icon: "arrow.triangle.2.circlepath", title: "同步方式", value: "直接读取 Files 中的文件夹；外部增删改会自动同步")
                    Button {
                        library.refresh()
                    } label: {
                        Label("重新读取当前文件夹", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
                    .edgeBackGesture {
                        popSettingsRoute()
                    }
            }
            .edgeBackGesture(isEnabled: !path.isEmpty) {
                popSettingsRoute()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .general:
            GeneralSettingsView()
                .environmentObject(settings)
        case .playback:
            PlaybackSettingsView()
                .environmentObject(settings)
                .environmentObject(player)
        case .subtitle:
            SubtitleSettingsView()
                .environmentObject(settings)
                .environmentObject(player)
        case .subtitleSpeech:
            SubtitleSpeechSettingsView()
                .environmentObject(settings)
        case .remote:
            RemoteSettingsView()
                .environmentObject(settings)
        case .about:
            AboutSettingsView()
        }
    }

    private func popSettingsRoute() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}

private enum SettingsRoute: Hashable, Identifiable {
    case general
    case playback
    case subtitle
    case subtitleSpeech
    case remote
    case about

    var id: Self { self }

    static let rootRoutes: [SettingsRoute] = [.general, .playback, .subtitle, .remote, .about]

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .playback:
            return "play.circle"
        case .subtitle:
            return "captions.bubble"
        case .subtitleSpeech:
            return "speaker.wave.2"
        case .remote:
            return "dot.radiowaves.left.and.right"
        case .about:
            return "info.circle"
        }
    }

    var title: String {
        switch self {
        case .general:
            return "常规"
        case .playback:
            return "播放"
        case .subtitle:
            return "字幕"
        case .subtitleSpeech:
            return "字幕转语音"
        case .remote:
            return "遥控"
        case .about:
            return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "主题、搜索过滤器"
        case .playback:
            return "控制层、快进快退、后台播放"
        case .subtitle:
            return "显示、语言、字体与朗读"
        case .subtitleSpeech:
            return "开关、语速、音量与语言"
        case .remote:
            return "耳机和锁屏控制映射"
        case .about:
            return "版本、作者与项目主页"
        }
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section("主题") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        settings.theme = theme
                    } label: {
                        HStack {
                            Text(theme.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.theme == theme {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("语言") {
                Picker("应用语言", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }
            }

            Section {
                ForEach(SearchFilter.allCases) { filter in
                    Toggle(isOn: settings.binding(for: filter)) {
                        Label {
                            Text(LocalizedStringKey(filter.title))
                        } icon: {
                            Image(systemName: filter.systemImage)
                        }
                    }
                }
            } header: {
                Text("过滤器")
            } footer: {
                Text("用于搜索页显示与查找的项目类型。")
            }
        }
        .navigationTitle("常规")
    }
}

private struct PlaybackSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        List {
            Section {
                Toggle("自动隐藏菜单", isOn: $settings.autoHideVideoControls)
            }

            Section {
                Stepper(value: $settings.skipForwardSeconds, in: 1...120, step: 1) {
                    SettingsValueRow(title: "快进", value: "\(Int(settings.skipForwardSeconds))s")
                }

                Stepper(value: $settings.skipBackwardSeconds, in: 1...120, step: 1) {
                    SettingsValueRow(title: "快退", value: "\(Int(settings.skipBackwardSeconds))s")
                }
            }

            Section {
                Toggle("后台播放", isOn: Binding(
                    get: { settings.backgroundPlaybackEnabled },
                    set: { player.setBackgroundPlaybackEnabled($0) }
                ))
            } footer: {
                Text("此开关控制应用内播放策略；iOS 后台音频还需要项目开启 Background Audio 能力。")
            }
        }
        .navigationTitle("播放")
    }
}

private struct SubtitleSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        List {
            Section {
                Toggle("显示字幕", isOn: Binding(
                    get: { settings.subtitlesEnabled },
                    set: { player.setSubtitlesEnabled($0) }
                ))

                Picker("首选字幕语言", selection: $settings.preferredSubtitleLanguage) {
                    ForEach(SubtitleLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }

                NavigationLink(value: SettingsRoute.subtitleSpeech) {
                    SettingsValueRow(
                        title: "字幕转语音",
                        value: settings.subtitleSpeechEnabled ? "开启" : "关闭"
                    )
                }
            }

            Section {
                Picker("字体", selection: $settings.subtitleFont) {
                    ForEach(SubtitleFontFamily.allCases) { font in
                        Text(LocalizedStringKey(font.title)).tag(font)
                    }
                }

                Picker("字体样式", selection: $settings.subtitleFontStyle) {
                    ForEach(SubtitleFontStyle.allCases) { style in
                        Text(LocalizedStringKey(style.title)).tag(style)
                    }
                }

                Toggle("文字轮廓", isOn: $settings.subtitleOutlineEnabled)
                Toggle("文字阴影", isOn: $settings.subtitleShadowEnabled)
            }
        }
        .navigationTitle("字幕")
        .onAppear {
            if player.state.subtitlesEnabled != settings.subtitlesEnabled {
                player.setSubtitlesEnabled(settings.subtitlesEnabled)
            }
        }
    }
}

private struct SubtitleSpeechSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                Toggle("字幕转语音", isOn: $settings.subtitleSpeechEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    SettingsValueRow(title: "语速", value: String(format: "%.1fx", settings.subtitleSpeechRate))
                    Slider(value: $settings.subtitleSpeechRate, in: 0.3...2.0, step: 0.1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettingsValueRow(title: "音量", value: "\(Int(settings.subtitleSpeechVolume * 100))%")
                    Slider(value: $settings.subtitleSpeechVolume, in: 0...1, step: 0.01)
                }

                Picker("语言", selection: $settings.subtitleSpeechLanguage) {
                    ForEach(SubtitleSpeechLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }
            }
        }
        .navigationTitle("字幕转语音")
    }
}

private struct RemoteSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                Picker("上一首按钮", selection: $settings.remotePreviousAction) {
                    ForEach(RemoteCommandAction.allCases) { action in
                        Text(LocalizedStringKey(action.title)).tag(action)
                    }
                }

                Picker("下一首按钮", selection: $settings.remoteNextAction) {
                    ForEach(RemoteCommandAction.allCases) { action in
                        Text(LocalizedStringKey(action.title)).tag(action)
                    }
                }
            } footer: {
                Text("这里对应耳机、锁屏、控制中心上的上一首/下一首按钮。")
            }
        }
        .navigationTitle("遥控")
    }
}

private struct AboutSettingsView: View {
    private let githubURL = URL(string: "https://github.com/someone-tokki/Whisper")!

    var body: some View {
        List {
            Section {
                SettingsInfoRow(icon: "app", title: "版本号", value: appVersion)
                SettingsInfoRow(icon: "person", title: "作者", value: "someone-tokki")
                Link(destination: githubURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("GitHub")
                                .foregroundStyle(.primary)
                            Text("someone-tokki/Whisper")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("关于")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

private struct SettingsNavigationRowContent: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                Text(LocalizedStringKey(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            Text(LocalizedStringKey(value))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                Text(LocalizedStringKey(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
