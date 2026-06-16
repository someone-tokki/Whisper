import SwiftUI
import UIKit

struct ExpandedPlayerView: View {
    @EnvironmentObject private var player: PlayerViewModel
    let close: () -> Void
    let contentProgress: CGFloat

    var body: some View {
        if player.state.isVideo {
            FullscreenVideoPlayerView(close: close, contentProgress: contentProgress)
        } else {
            audioPlayer
        }
    }

    private var audioPlayer: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        expandedArtwork
                            .padding(.horizontal, 20)

                        SubtitleOverlayView(cue: player.state.activeSubtitle)
                            .padding(.horizontal, 20)
                            .opacity(contentProgress)
                            .offset(y: 8 * (1 - contentProgress))

                        PlayerControlsView()
                            .padding(.horizontal, 20)
                            .opacity(contentProgress)
                            .offset(y: 10 * (1 - contentProgress))
                    }
                    .padding(.vertical, 18)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("收起播放器")
                }
            }
        }
    }

    private var expandedArtwork: some View {
        NowPlayingView(
            contentProgress: contentProgress
        )
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FullscreenVideoPlayerView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var settings: AppSettings
    let close: () -> Void
    let contentProgress: CGFloat
    @State private var showControls = true
    @State private var showMoreControls = false
    @State private var showSubtitleTools = false
    @State private var showSubtitlePicker = false
    @State private var isInterfaceLocked = false
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var gestureMode: VideoGestureMode?
    @State private var gestureStartTime: TimeInterval = 0
    @State private var gestureTargetTime: TimeInterval = 0
    @State private var gestureStartVolume: Float = 1
    @State private var gestureStartBrightness: CGFloat = UIScreen.main.brightness
    @State private var hud: VideoHUD?
    @State private var hudTask: Task<Void, Never>?
    @State private var lockedControlsVisible = true
    @State private var hideLockedControlsTask: Task<Void, Never>?
    @State private var controlsAutoHideToken = 0
    @State private var lockedControlsAutoHideToken = 0
    @State private var hudHideToken = 0
    @State private var lastControlTapTime: TimeInterval = 0
    var body: some View {
        GeometryReader { proxy in
            let safeArea = effectiveSafeArea(proxy.safeAreaInsets, size: proxy.size)

            ZStack {
                Color.black.ignoresSafeArea()

                VideoSurfaceView(
                    player: player.player,
                    videoGravity: player.state.videoDisplayMode.videoGravity,
                    onLayerReady: { layer in
                        player.setVideoPlayerLayer(layer)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
                .transaction { transaction in
                    transaction.animation = nil
                }
                .animation(nil, value: showControls)
                .animation(nil, value: showSubtitleTools)
                .animation(nil, value: isInterfaceLocked)
                .animation(nil, value: lockedControlsVisible)

                if !isInterfaceLocked {
                    interactionLayer(in: proxy.size, safeArea: safeArea)
                        .zIndex(1)
                }
                subtitleLayer
                    .zIndex(2)

                if let hud {
                    VideoHUDView(hud: hud)
                        .opacity(1)
                        .zIndex(4)
                }

                lockedOverlay(safeArea: safeArea, size: proxy.size)
                    .opacity(isInterfaceLocked ? 1 : 0)
                    .allowsHitTesting(isInterfaceLocked)
                    .zIndex(3)

                controlOverlay(safeArea: safeArea, size: proxy.size)
                    .opacity(showControls && !isInterfaceLocked ? 1 : 0)
                    .allowsHitTesting(showControls && !isInterfaceLocked)
                    .zIndex(5)

                subtitleTools
                    .opacity(showSubtitleTools && !isInterfaceLocked ? 1 : 0)
                    .allowsHitTesting(showSubtitleTools && !isInterfaceLocked)
                    .zIndex(6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .transaction { transaction in
                transaction.disablesAnimations = false
            }
        }
        .onAppear {
            scheduleControlsAutoHide()
        }
        .onDisappear {
            cancelControlsAutoHide()
            cancelLockedControlsAutoHide()
            cancelHUDHide()
            OrientationManager.shared.unlock()
        }
        .sheet(isPresented: $showMoreControls) {
            PlayerMoreControlsView()
                .environmentObject(player)
                .environmentObject(library)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSubtitlePicker) {
            SubtitlePickerView(startDirectory: library.defaultSubtitleDirectory(for: player.state.sourceURL)) { item in
                library.importSubtitle(from: item.url, player: player)
                showSubtitlePicker = false
            }
            .environmentObject(library)
        }
        .onChange(of: showMoreControls) { _, newValue in
            newValue ? cancelControlsAutoHide() : scheduleControlsAutoHide()
        }
        .onChange(of: player.state.isPlaying) { _, _ in
            scheduleControlsAutoHide()
        }
        .animation(nil, value: showControls)
        .animation(nil, value: isInterfaceLocked)
        .animation(nil, value: showSubtitleTools)
        .animation(nil, value: showMoreControls)
    }

    private func effectiveSafeArea(_ proxySafeArea: EdgeInsets, size: CGSize) -> EdgeInsets {
        let windowInsets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
        let isPortrait = size.height >= size.width

        return EdgeInsets(
            top: max(proxySafeArea.top, windowInsets.top, isPortrait ? 64 : 8),
            leading: max(proxySafeArea.leading, windowInsets.left, isPortrait ? 0 : 44),
            bottom: max(proxySafeArea.bottom, windowInsets.bottom, isPortrait ? 34 : 21),
            trailing: max(proxySafeArea.trailing, windowInsets.right, isPortrait ? 0 : 44)
        )
    }

    private var subtitleLayer: some View {
        VStack {
            Spacer()

            if let cue = player.state.activeSubtitle {
                SubtitleOverlayView(cue: cue, style: .floating)
                    .scaleEffect(player.state.subtitleFontScale)
                    .padding(.horizontal, 28)
                    .padding(.bottom, (showControls ? 132 : 42) + player.state.subtitleVerticalOffset)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: player.state.subtitleVerticalOffset)
        .allowsHitTesting(false)
    }

    private func controlOverlay(safeArea: EdgeInsets, size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                topBar(safeArea: safeArea, isLandscape: isLandscape)

                Spacer()

                bottomBar(safeArea: safeArea, isLandscape: isLandscape)
            }

            floatingLockButton(safeArea: safeArea, size: size, isLandscape: isLandscape, isLocked: isInterfaceLocked)
        }
        .foregroundStyle(.white)
        .opacity(0.35 + contentProgress * 0.65)
    }

    private func lockedOverlay(safeArea: EdgeInsets, size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        return ZStack(alignment: .topLeading) {
            lockedTapLayer
            if lockedControlsVisible {
                floatingLockButton(
                    safeArea: safeArea,
                    size: size,
                    isLandscape: isLandscape,
                    isLocked: true
                )
            }
        }
    }

    private func topBar(safeArea: EdgeInsets, isLandscape: Bool) -> some View {
        HStack(spacing: 12) {
            overlayButton("xmark", isLandscape: isLandscape, action: close)
                .accessibilityLabel("关闭视频")

            Text(player.state.title)
                .font(isLandscape ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

            Menu {
                Section("画面比例") {
                    ForEach(VideoDisplayMode.allCases) { mode in
                        Button {
                            player.setVideoDisplayMode(mode)
                            showHUD(.message(mode.title, systemImage: "rectangle.arrowtriangle.2.inward"))
                            scheduleHUDHide()
                            scheduleControlsAutoHide()
                        } label: {
                            Label(mode.title, systemImage: player.state.videoDisplayMode == mode ? "checkmark" : "rectangle")
                        }
                    }
                }

                Button {
                    showSubtitleTools = true
                    cancelControlsAutoHide()
                } label: {
                    Label("字幕快捷调整", systemImage: "captions.bubble")
                }

                Button {
                    showMoreControls = true
                } label: {
                    Label("播放选项", systemImage: "ellipsis")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.26), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("视频选项")
        }
        .padding(.leading, safeArea.leading + 18)
        .padding(.trailing, safeArea.trailing + 18)
        .padding(.top, isLandscape ? max(safeArea.top - 2, 2) : max(safeArea.top - 12, 6))
        .padding(.bottom, isLandscape ? 10 : 16)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0.34), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private func floatingLockButton(safeArea: EdgeInsets, size: CGSize, isLandscape: Bool, isLocked: Bool) -> some View {
        let topOffset = isLandscape
            ? max((size.height - 44) / 2, safeArea.top + 72)
            : max(safeArea.top + size.height * 0.34, 260)

        return Button {
            isLocked ? unlockInterface() : lockInterface()
        } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: isLandscape ? 18 : 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isLandscape ? 42 : 52, height: isLandscape ? 42 : 52)
                .background(.black.opacity(0.34), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? "解锁播放器界面" : "锁定播放器界面")
        .padding(.leading, safeArea.leading + 18)
        .padding(.top, topOffset)
    }

    private var lockedTapLayer: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleLockButtonVisibility()
            }
    }

    private func bottomBar(safeArea: EdgeInsets, isLandscape: Bool) -> some View {
        VStack(spacing: isLandscape ? 10 : 18) {
            progressControl
            transportControls(isLandscape: isLandscape)
        }
        .padding(.leading, safeArea.leading + (isLandscape ? 18 : 24))
        .padding(.trailing, safeArea.trailing + (isLandscape ? 18 : 24))
        .padding(.top, isLandscape ? 14 : 34)
        .padding(.bottom, max(safeArea.bottom + (isLandscape ? 10 : 16), isLandscape ? 16 : 28))
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.40), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
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
                        cancelControlsAutoHide()
                        showHUD(.seek(target: value, duration: player.state.duration, delta: value - player.state.currentTime))
                    }
                ),
                in: 0...max(player.state.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: sliderValue)
                        isSeeking = false
                        showHUD(.seek(target: sliderValue, duration: player.state.duration, delta: 0))
                        scheduleHUDHide()
                        scheduleControlsAutoHide()
                    } else {
                        cancelControlsAutoHide()
                        sliderValue = player.state.currentTime
                        showHUD(.seek(target: sliderValue, duration: player.state.duration, delta: 0))
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(player.formattedTime(player.state.currentTime))
                Spacer()
                Text("-\(player.formattedTime(max(player.state.duration - player.state.currentTime, 0)))")
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func transportControls(isLandscape: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: isLandscape ? 18 : 6) {
                videoTransportButton("pip.enter", iconSize: isLandscape ? 19 : 18, isLandscape: isLandscape) {
                    player.togglePictureInPicture()
                    scheduleControlsAutoHide()
                }
                .accessibilityLabel("开启画中画")

                videoTransportButton("backward.end.fill", iconSize: isLandscape ? 18 : 18, isLandscape: isLandscape) {
                    player.playPreviousItem()
                    scheduleControlsAutoHide()
                }

                videoTransportButton("gobackward", iconSize: isLandscape ? 22 : 22, isLandscape: isLandscape) {
                    skipBackwardWithFeedback()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, isLandscape ? 6 : 0)

            Button {
                player.togglePlay()
                scheduleControlsAutoHide()
            } label: {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isLandscape ? 26 : 38, weight: .semibold))
                    .frame(width: isLandscape ? 110 : 74, height: isLandscape ? 42 : 74)
                    .background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: isLandscape ? 14 : 37, style: .continuous))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.state.isPlaying ? "暂停" : "播放")
            .frame(width: isLandscape ? 118 : 80)
            .padding(.horizontal, isLandscape ? 4 : 0)

            HStack(spacing: isLandscape ? 18 : 6) {
                videoTransportButton("goforward", iconSize: isLandscape ? 22 : 22, isLandscape: isLandscape) {
                    skipForwardWithFeedback()
                }

                videoTransportButton("forward.end.fill", iconSize: isLandscape ? 18 : 18, isLandscape: isLandscape) {
                    player.playNextItem()
                    scheduleControlsAutoHide()
                }

                videoTransportButton(player.state.playbackMode.systemImage, iconSize: isLandscape ? 19 : 18, isLandscape: isLandscape) {
                    player.cyclePlaybackMode()
                    showHUD(.message(player.state.playbackMode.title, systemImage: player.state.playbackMode.systemImage))
                    scheduleHUDHide()
                    scheduleControlsAutoHide()
                }
                .accessibilityLabel(player.state.playbackMode.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isLandscape ? 6 : 0)
        }
    }

    private var subtitleTools: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack {
                    Label("字幕", systemImage: "captions.bubble")
                        .font(.headline)
                    Spacer()
                    Button {
                        showSubtitleTools = false
                        scheduleControlsAutoHide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Toggle("显示字幕", isOn: Binding(
                    get: { player.state.subtitlesEnabled },
                    set: { _ in player.toggleSubtitlesEnabled() }
                ))
                .tint(.blue)

                Button {
                    showSubtitlePicker = true
                } label: {
                    HStack {
                        Label(player.state.subtitleURL?.lastPathComponent ?? "选择外挂字幕", systemImage: "folder")
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Button("-0.1s") { player.nudgeSubtitle(-0.1) }
                    Text(String(format: "%+.1fs", player.state.subtitleOffset))
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity)
                    Button("+0.1s") { player.nudgeSubtitle(0.1) }
                    Button {
                        player.resetSubtitleOffset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 8) {
                    Text("字号")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Slider(
                        value: Binding(
                            get: { player.state.subtitleFontScale },
                            set: { player.setSubtitleFontScale($0) }
                        ),
                        in: 0.75...1.8
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("位置")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Slider(
                        value: Binding(
                            get: { player.state.subtitleVerticalOffset },
                            set: { player.setSubtitleVerticalOffset($0) }
                        ),
                        in: -120...120
                    )
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private func interactionLayer(in size: CGSize, safeArea: EdgeInsets) -> some View {
        VideoInteractionCaptureView(
            onSingleTap: {
                toggleControls()
            },
            onLeftDoubleTap: {
                skipBackwardWithFeedback()
            },
            onRightDoubleTap: {
                skipForwardWithFeedback()
            },
            onPanChanged: { startLocation, translation in
                handleDragChanged(startLocation: startLocation, translation: translation, size: size)
            },
            onPanEnded: { startLocation, translation in
                handleDragEnded(startLocation: startLocation, translation: translation, size: size)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func handleDragChanged(startLocation: CGPoint, translation: CGSize, size: CGSize) {
        guard !isInterfaceLocked else { return }
        cancelControlsAutoHide()
        if gestureMode == nil {
            let horizontal = abs(translation.width)
            let vertical = abs(translation.height)
            guard max(horizontal, vertical) >= 12 else { return }
            if horizontal > vertical {
                gestureMode = .seek
                gestureStartTime = player.state.currentTime
                gestureTargetTime = gestureStartTime
            } else {
                gestureMode = startLocation.x < size.width / 2 ? .brightness : .volume
                gestureStartVolume = player.state.volume
                gestureStartBrightness = UIScreen.main.brightness
            }
        }

        switch gestureMode {
        case .seek:
            let sensitivity = min(max(player.state.duration / 3600, 0.03), 0.16)
            let delta = TimeInterval(translation.width) * sensitivity
            gestureTargetTime = min(max(gestureStartTime + delta, 0), max(player.state.duration, 0))
            showHUD(.seek(target: gestureTargetTime, duration: player.state.duration, delta: gestureTargetTime - gestureStartTime))
        case .brightness:
            let next = min(max(gestureStartBrightness - translation.height / max(size.height, 1), 0), 1)
            UIScreen.main.brightness = next
            showHUD(.level(title: "亮度", systemImage: "sun.max.fill", value: Double(next)))
        case .volume:
            let next = min(max(Double(gestureStartVolume) - Double(translation.height / max(size.height, 1)), 0), 1)
            player.setVolume(Float(next))
            showHUD(.level(title: "音量", systemImage: "speaker.wave.2.fill", value: next))
        case nil:
            break
        }
    }

    private func handleDragEnded(startLocation: CGPoint, translation: CGSize, size: CGSize) {
        guard !isInterfaceLocked else { return }
        if gestureMode == .seek {
            player.seek(to: gestureTargetTime)
        }
        gestureMode = nil
        scheduleHUDHide()
        scheduleControlsAutoHide()
    }

    private func toggleControls() {
        guard !isInterfaceLocked else { return }
        guard !showMoreControls, !showSubtitleTools else { return }
        let now = CACurrentMediaTime()
        guard now - lastControlTapTime > 0.18 else { return }
        lastControlTapTime = now

        if showControls {
            hideVideoControls()
        } else {
            showVideoControls()
        }
    }

    private func lockInterface() {
        cancelControlsAutoHide()
        cancelLockedControlsAutoHide()
        cancelHUDHide()
        OrientationManager.shared.lockToCurrentOrientation()
        withAnimation(.easeInOut(duration: 0.2)) {
            isInterfaceLocked = true
            showControls = false
            showSubtitleTools = false
            showMoreControls = false
            lockedControlsVisible = true
            hud = nil
        }
        scheduleLockedControlsAutoHide()
    }

    private func unlockInterface() {
        cancelLockedControlsAutoHide()
        OrientationManager.shared.unlock()
        withAnimation(.easeInOut(duration: 0.2)) {
            isInterfaceLocked = false
            showControls = true
            lockedControlsVisible = true
        }
        scheduleControlsAutoHide()
    }

    private func skipWithFeedback(_ seconds: TimeInterval) {
        player.skip(seconds)
        showHUD(.skip(seconds))
        scheduleHUDHide()
        scheduleControlsAutoHide()
    }

    private func showVideoControls() {
        cancelControlsAutoHide()
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }
        scheduleControlsAutoHide()
    }

    private func hideVideoControls() {
        cancelControlsAutoHide()
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = false
        }
    }

    private func skipForwardWithFeedback() {
        skipWithFeedback(settings.skipForwardSeconds)
    }

    private func skipBackwardWithFeedback() {
        skipWithFeedback(-settings.skipBackwardSeconds)
    }

    private func showHUD(_ next: VideoHUD) {
        cancelHUDHide()
        withAnimation(.easeInOut(duration: 0.16)) {
            hud = next
        }
    }

    private func cancelHUDHide() {
        hudHideToken &+= 1
        hudTask?.cancel()
        hudTask = nil
    }

    private func scheduleHUDHide() {
        cancelHUDHide()
        let token = hudHideToken
        hudTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard hudHideToken == token else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    hud = nil
                }
            }
        }
    }

    private func cancelControlsAutoHide() {
        controlsAutoHideToken &+= 1
        hideControlsTask?.cancel()
        hideControlsTask = nil
    }

    private func scheduleControlsAutoHide() {
        cancelControlsAutoHide()
        guard !isInterfaceLocked else {
            scheduleLockedControlsAutoHide()
            return
        }
        guard settings.autoHideVideoControls, player.state.isPlaying, showControls, !showMoreControls, !showSubtitleTools else { return }
        let token = controlsAutoHideToken
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard controlsAutoHideToken == token else { return }
                guard player.state.isPlaying, !isInterfaceLocked, !showMoreControls, !showSubtitleTools else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    showControls = false
                }
            }
        }
    }

    private func toggleLockButtonVisibility() {
        guard isInterfaceLocked else {
            lockInterface()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            lockedControlsVisible.toggle()
        }
        if lockedControlsVisible {
            scheduleLockedControlsAutoHide()
        } else {
            cancelLockedControlsAutoHide()
        }
    }

    private func cancelLockedControlsAutoHide() {
        lockedControlsAutoHideToken &+= 1
        hideLockedControlsTask?.cancel()
        hideLockedControlsTask = nil
    }

    private func scheduleLockedControlsAutoHide() {
        cancelLockedControlsAutoHide()
        guard isInterfaceLocked, lockedControlsVisible else { return }
        let token = lockedControlsAutoHideToken
        hideLockedControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                guard lockedControlsAutoHideToken == token else { return }
                guard isInterfaceLocked, lockedControlsVisible else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    lockedControlsVisible = false
                }
            }
        }
    }

    private func videoTransportButton(_ systemName: String, iconSize: CGFloat, isLandscape: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: isLandscape ? 48 : 44, height: isLandscape ? 48 : 44)
                .background(.white.opacity(isLandscape ? 0.16 : 0.0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func overlayButton(_ systemName: String, isLandscape: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isLandscape ? 18 : 21, weight: .semibold))
                .frame(width: isLandscape ? 40 : 52, height: isLandscape ? 40 : 52)
                .background(.black.opacity(0.26), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private enum VideoGestureMode {
    case seek
    case brightness
    case volume
}

private enum VideoHUD: Equatable {
    case skip(TimeInterval)
    case seek(target: TimeInterval, duration: TimeInterval, delta: TimeInterval)
    case level(title: String, systemImage: String, value: Double)
    case message(String, systemImage: String)
}

private struct VideoHUDView: View {
    let hud: VideoHUD

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title.weight(.semibold))

            Text(primaryText)
                .font(.headline.monospacedDigit())

            if let secondaryText {
                Text(secondaryText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.76))
            }

            if let level {
                ProgressView(value: level)
                    .tint(.white)
                    .frame(width: 140)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch hud {
        case .skip(let seconds):
            seconds < 0 ? "gobackward" : "goforward"
        case .seek:
            "arrow.left.and.right"
        case .level(_, let systemImage, _), .message(_, let systemImage):
            systemImage
        }
    }

    private var primaryText: String {
        switch hud {
        case .skip(let seconds):
            seconds < 0 ? "-5s" : "+15s"
        case .seek(let target, let duration, _):
            "\(format(target)) / \(format(duration))"
        case .level(let title, _, let value):
            "\(title) \(Int((value * 100).rounded()))%"
        case .message(let text, _):
            text
        }
    }

    private var secondaryText: String? {
        switch hud {
        case .seek(_, _, let delta):
            return String(format: "%+.1fs", delta)
        default:
            return nil
        }
    }

    private var level: Double? {
        if case .level(_, _, let value) = hud {
            return value
        }
        return nil
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
