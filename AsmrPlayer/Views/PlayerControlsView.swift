import SwiftUI

struct PlayerControlsView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var showMoreControls = false

    var body: some View {
        VStack(spacing: 22) {
            progressControl
            transportControls
            volumeControl
        }
        .sheet(isPresented: $showMoreControls) {
            PlayerMoreControlsView()
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var progressControl: some View {
        VStack(spacing: 7) {
            Slider(
                value: Binding(
                    get: { isSeeking ? sliderValue : player.state.currentTime },
                    set: { value in
                        sliderValue = value
                        isSeeking = true
                    }
                ),
                in: 0...max(player.state.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: sliderValue)
                        isSeeking = false
                    }
                }
            )

            HStack {
                Text(player.formattedTime(player.state.currentTime))
                Spacer()
                Text(player.formattedTime(player.state.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 8) {
                transportButton("pip.enter", size: 19) {
                    player.togglePictureInPicture()
                }
                .accessibilityLabel("开启画中画")

                transportButton("backward.end.fill", size: 18) {
                    player.playPreviousItem()
                }

                transportButton("gobackward", size: 22) {
                    player.skipBackward()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4)

            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 74)
                    .background(Color.accentColor, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.state.sourceURL == nil)
            .accessibilityLabel(player.state.isPlaying ? "暂停" : "播放")
            .frame(width: 80)
            .padding(.horizontal, 2)

            HStack(spacing: 8) {
                transportButton("goforward", size: 22) {
                    player.skipForward()
                }

                transportButton("forward.end.fill", size: 18) {
                    player.playNextItem()
                }

                Button {
                    player.cyclePlaybackMode()
                } label: {
                    Image(systemName: player.state.playbackMode.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(player.state.sourceURL == nil ? Color.secondary.opacity(0.4) : Color.primary)
                        .frame(width: 36, height: 40)
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(player.state.sourceURL == nil)
                .accessibilityLabel(player.state.playbackMode.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Slider(
                value: Binding(
                    get: { Double(player.state.volume) },
                    set: { player.setVolume(Float($0)) }
                ),
                in: 0...1
            )

            Image(systemName: "speaker.wave.2.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Button {
                showMoreControls = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多播放选项")
        }
    }

    private func transportButton(_ systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(player.state.sourceURL == nil ? Color.secondary.opacity(0.4) : Color.primary)
                .frame(width: 42, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(player.state.sourceURL == nil)
    }
}

struct PlayerMoreControlsButton: View {
    @Binding var showMoreControls: Bool

    var body: some View {
        Button {
            showMoreControls = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
        }
        .accessibilityLabel("更多播放选项")
    }
}

struct PlayerMoreControlsView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @State private var timerMinutes: Double = 30
    @State private var showSubtitlePicker = false
    @State private var subtitlePickerStartDirectory: URL?

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    subtitleCard
                    rateCard
                    subtitleOffsetCard
                    sleepTimerCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("播放选项")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: syncTimerMinutes)
            .sheet(isPresented: $showSubtitlePicker) {
                SubtitlePickerView(startDirectory: subtitlePickerStartDirectory) { item in
                    library.importSubtitle(from: item.url, player: player)
                    showSubtitlePicker = false
                }
                .environmentObject(library)
            }
        }
    }

    private var subtitleCard: some View {
        controlCard {
            Button {
                subtitlePickerStartDirectory = library.defaultSubtitleDirectory(for: player.state.sourceURL)
                showSubtitlePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("外挂字幕")
                            .font(.headline)
                        Text(player.state.subtitleURL?.lastPathComponent ?? "加载字幕文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rateCard: some View {
        controlCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("播放速度")
                    .font(.headline)

                Picker("播放速度", selection: Binding(
                    get: { player.state.playbackRate },
                    set: { player.setRate($0) }
                )) {
                    ForEach(rates, id: \.self) { rate in
                        Text(rateLabel(rate)).tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var subtitleOffsetCard: some View {
        controlCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("字幕同步")
                        .font(.headline)

                    Spacer()

                    Button {
                        player.resetSubtitleOffset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重置字幕偏移")
                }

                HStack(spacing: 14) {
                    offsetButton(systemName: "minus") {
                        player.nudgeSubtitle(-0.1)
                    }

                    Text(String(format: "%+.1fs", player.state.subtitleOffset))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())

                    offsetButton(systemName: "plus") {
                        player.nudgeSubtitle(0.1)
                    }
                }
            }
        }
    }

    private var sleepTimerCard: some View {
        controlCard {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    sleepTimerRing

                    VStack(alignment: .leading, spacing: 7) {
                        Text("睡眠定时")
                            .font(.headline)

                        Text(sleepTimerStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if player.state.isSleepTimerRunning || player.state.isSleepTimerPaused {
                            Button {
                                player.setSleepTimer(duration: nil)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.tertiarySystemFill), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("取消睡眠定时")
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                        }

                        Button {
                            player.toggleSleepTimer(duration: timerMinutes * 60)
                        } label: {
                            Image(systemName: timerActionIcon)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.blue, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(timerActionLabel)
                    }
                    .animation(.smooth(duration: 0.22), value: player.state.isSleepTimerRunning)
                    .animation(.smooth(duration: 0.22), value: player.state.isSleepTimerPaused)
                }

                VStack(spacing: 8) {
                    Slider(value: $timerMinutes, in: 5...180, step: 5)

                    HStack {
                        Text("5 分钟")
                        Spacer()
                        Text("\(Int(timerMinutes)) 分钟")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("180 分钟")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }

            }
        }
    }

    private var sleepTimerRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 7)

            Circle()
                .trim(from: 0, to: player.state.sleepTimerProgress ?? 0)
                .stroke(
                    Color(red: 0.35, green: 0.68, blue: 1.0),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: player.state.remainingSleepTime == nil ? "moon" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(player.state.remainingSleepTime == nil ? Color.secondary : Color(red: 0.35, green: 0.68, blue: 1.0))
        }
        .frame(width: 64, height: 64)
        .animation(.smooth(duration: 0.28), value: player.state.sleepTimerProgress)
    }

    private var sleepTimerStatusText: String {
        guard let remaining = player.state.remainingSleepTime else {
            return "未开启"
        }
        return "剩余 \(player.formattedTime(remaining))"
    }

    private func controlCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func offsetButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(width: 54, height: 42)
        }
        .buttonStyle(.bordered)
    }

    private func syncTimerMinutes() {
        if let duration = player.state.sleepTimerDuration {
            timerMinutes = min(max((duration / 60).rounded(), 5), 180)
        } else if let remaining = player.state.remainingSleepTime {
            timerMinutes = min(max((remaining / 60).rounded(), 5), 180)
        }
    }

    private var timerActionIcon: String {
        if player.state.isSleepTimerRunning { return "pause.fill" }
        if player.state.isSleepTimerPaused { return "play.fill" }
        return "play.fill"
    }

    private var timerActionLabel: String {
        if player.state.isSleepTimerRunning { return "暂停睡眠定时" }
        if player.state.isSleepTimerPaused { return "继续睡眠定时" }
        return "开始睡眠定时"
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "1x" : String(format: "%.2gx", rate)
    }
}

struct SubtitlePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryViewModel
    @State private var directory: URL
    let select: (LibraryItem) -> Void

    init(startDirectory: URL?, select: @escaping (LibraryItem) -> Void) {
        _directory = State(initialValue: startDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        self.select = select
    }

    private var items: [LibraryItem] {
        library.subtitleBrowserItems(in: directory)
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "这个文件夹没有字幕",
                        systemImage: "captions.bubble",
                        description: Text("把 SRT、VTT、LRC、ASS 或 SSA 放进资料库文件夹后再选择。")
                    )
                } else {
                    Section(library.breadcrumbs(for: directory)) {
                        ForEach(items) { item in
                            Button {
                                open(item)
                            } label: {
                                SubtitleBrowserRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.canGoBack(from: directory) {
                        Button {
                            directory = library.parentDirectory(of: directory)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("返回上级")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                library.refresh()
            }
        }
    }

    private func open(_ item: LibraryItem) {
        switch item.kind {
        case .folder:
            directory = item.url
        case .subtitle:
            select(item)
        case .media, .image, .document, .other:
            break
        }
    }
}

private struct SubtitleBrowserRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.kind == .folder {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var iconName: String {
        item.kind == .folder ? "folder" : "captions.bubble"
    }

    private var iconColor: Color {
        item.kind == .folder ? .yellow : .blue
    }

    private var detailText: String {
        if item.kind == .folder {
            return "\(item.childCount ?? 0) 个项目"
        }
        let size = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
        let ext = item.fileExtension.isEmpty ? "文件" : item.fileExtension
        return "\(ext) \(size)"
    }
}
