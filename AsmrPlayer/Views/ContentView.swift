import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var library = LibraryViewModel()
    @StateObject private var playlistStore = PlaylistStore()
    @State private var selectedTab: AppTab = .library
    @State private var showExpandedPlayer = false
    @State private var showSearch = false
    @State private var compactChrome = false
    @State private var playerExpansionProgress: CGFloat = 0
    @State private var miniPlayerFrame: CGRect = .zero
    @State private var playerTransitionSourceFrame: CGRect = .zero
    @State private var playerTransitionMiniStyle: MiniPlayerView.Style = .wide
    @State private var playerTransitionToken = UUID()
    @State private var autoExpandedMediaURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            AudioPictureInPictureHostView(layer: player.pictureInPicture.audioSubtitleLayer)
                .frame(width: 320, height: 180)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(-1)

            Group {
                switch selectedTab {
                case .library:
                    LibraryView(compactChrome: $compactChrome)
                        .environmentObject(library)
                case .playlist:
                    PlaylistView(compactChrome: $compactChrome)
                        .environmentObject(library)
                        .environmentObject(playlistStore)
                case .settings:
                    SettingsView()
                        .environmentObject(library)
                        .environmentObject(playlistStore)
                        .environmentObject(settings)
                        .onAppear {
                            compactChrome = false
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomChromeView(
                selectedTab: $selectedTab,
                isCompact: compactChrome,
                showsMiniPlayer: selectedTab == .library || selectedTab == .playlist,
                activeCompactTab: selectedTab == .library ? .library : (selectedTab == .playlist ? .playlist : nil),
                expandChrome: {
                    withAnimation(.snappy(duration: 0.34)) {
                        compactChrome = false
                    }
                },
                expandPlayer: {
                    openExpandedPlayer()
                },
                openSearch: {
                    showSearch = true
                }
            )
            .environmentObject(player)
            .padding(.horizontal, 12)
            .padding(.bottom, 0)
            .opacity(showExpandedPlayer ? 0 : 1)
            .allowsHitTesting(!showExpandedPlayer)
            .zIndex(1)

            if showExpandedPlayer {
                PlayerExpansionOverlay(
                    progress: playerExpansionProgress,
                    sourceFrame: playerTransitionSourceFrame,
                    miniStyle: playerTransitionMiniStyle,
                    close: closeExpandedPlayer
                )
                    .environmentObject(player)
                    .environmentObject(library)
                    .environmentObject(playlistStore)
                    .environmentObject(settings)
                    .ignoresSafeArea()
                    .zIndex(2)
            }
        }
        .onPreferenceChange(MiniPlayerFramePreferenceKey.self) { frame in
            guard frame.width > 1, frame.height > 1 else { return }
            miniPlayerFrame = frame
        }
        .environmentObject(library)
        .environmentObject(playlistStore)
        .sheet(isPresented: $showSearch) {
            SearchView {
                selectedTab = .library
            }
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(playlistStore)
                .environmentObject(settings)
        }
        .onChange(of: player.state.sourceURL) { _, _ in
            autoExpandedMediaURL = nil
            scheduleVideoPlayerAutoOpen()
        }
        .onChange(of: player.state.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleVideoPlayerAutoOpen()
            } else {
                autoExpandedMediaURL = nil
            }
        }
        .onChange(of: player.pictureInPicture.isActive) { _, isActive in
            closeExpandedPlayerForPictureInPictureIfNeeded(isActive: isActive)
        }
        .onAppear {
            player.pictureInPicture.restoreUserInterfaceHandler = { completion in
                DispatchQueue.main.async {
                    openExpandedPlayerFromPictureInPicture(completion: completion)
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { player.errorMessage != nil || library.errorMessage != nil || playlistStore.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil; library.errorMessage = nil; playlistStore.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {
                player.errorMessage = nil
                library.errorMessage = nil
                playlistStore.errorMessage = nil
            }
        } message: {
            Text(player.errorMessage ?? library.errorMessage ?? playlistStore.errorMessage ?? "")
        }
    }

    private var playerAnimation: Animation {
        .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)
    }

    private var playerCloseAnimation: Animation {
        .smooth(duration: 0.36, extraBounce: 0)
    }

    private func openExpandedPlayer() {
        guard !showExpandedPlayer else { return }
        playerTransitionToken = UUID()
        playerTransitionSourceFrame = miniPlayerFrame
        playerTransitionMiniStyle = compactChrome ? .compact : .wide
        playerExpansionProgress = 0
        showExpandedPlayer = true

        DispatchQueue.main.async {
            withAnimation(playerAnimation) {
                playerExpansionProgress = 1
            }
        }
    }

    private func closeExpandedPlayerForPictureInPictureIfNeeded(isActive: Bool) {
        guard isActive, showExpandedPlayer else { return }
        closeExpandedPlayer()
    }

    private func openExpandedPlayerFromPictureInPicture(completion: @escaping (Bool) -> Void) {
        guard player.state.sourceURL != nil else {
            completion(false)
            return
        }

        if showExpandedPlayer {
            completion(true)
            return
        }

        openExpandedPlayer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            completion(showExpandedPlayer)
        }
    }

    private func closeExpandedPlayer() {
        guard showExpandedPlayer else { return }
        let token = UUID()
        playerTransitionToken = token
        playerTransitionSourceFrame = miniPlayerFrame

        withAnimation(playerCloseAnimation) {
            playerExpansionProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard playerTransitionToken == token, playerExpansionProgress == 0 else { return }
            showExpandedPlayer = false
        }
    }

    private func scheduleVideoPlayerAutoOpen() {
        DispatchQueue.main.async {
            openVideoPlayerIfNeeded()
        }
    }

    private func openVideoPlayerIfNeeded() {
        guard player.state.isPlaying,
              player.state.isVideo,
              let sourceURL = player.state.sourceURL,
              autoExpandedMediaURL != sourceURL else {
            return
        }

        autoExpandedMediaURL = sourceURL
        openExpandedPlayer()
    }
}

private struct PlayerExpansionOverlay: View {
    @EnvironmentObject private var player: PlayerViewModel
    let progress: CGFloat
    let sourceFrame: CGRect
    let miniStyle: MiniPlayerView.Style
    let close: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let targetFrame = CGRect(origin: .zero, size: proxy.size)
            let startFrame = validSourceFrame(in: targetFrame)
            let currentFrame = startFrame.interpolated(to: targetFrame, progress: progress)
            let cornerRadius = max(0, 31 * (1 - progress))
            let panelFillOpacity = normalizedProgress(from: 0.18, to: 0.58)
            let expandedOpacity = normalizedProgress(from: 0.52, to: 0.82)
            let detailsProgress = normalizedProgress(from: 0.68, to: 1)
            let miniOpacity = 1 - normalizedProgress(from: 0.18, to: 0.48)

            ZStack {
                Color.black
                    .opacity(0.30 * progress)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if progress > 0.96 {
                            close()
                        }
                    }

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemGroupedBackground))
                    .opacity(panelFillOpacity)

                MiniPlayerView(style: miniStyle, expand: {})
                    .environmentObject(player)
                    .opacity(miniOpacity)
                    .allowsHitTesting(false)

                ExpandedPlayerView(close: close, contentProgress: detailsProgress)
                    .environmentObject(player)
                    .opacity(expandedOpacity)
                    .allowsHitTesting(progress > 0.98)
            }
                .frame(width: currentFrame.width, height: currentFrame.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(
                    color: .black.opacity(0.18 * progress),
                    radius: 26 * progress,
                    y: 10 * progress
                )
                .position(x: currentFrame.midX, y: currentFrame.midY)
            }
            .ignoresSafeArea()
        }
    }

    private func validSourceFrame(in targetFrame: CGRect) -> CGRect {
        guard sourceFrame.width > 1, sourceFrame.height > 1 else {
            return CGRect(
                x: 12,
                y: max(targetFrame.height - 146, 0),
                width: max(targetFrame.width - 24, 1),
                height: 62
            )
        }
        return sourceFrame
    }

    private func normalizedProgress(from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return progress }
        return min(max((progress - start) / (end - start), 0), 1)
    }

}

private extension CGRect {
    func interpolated(to target: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (target.origin.x - origin.x) * progress,
            y: origin.y + (target.origin.y - origin.y) * progress,
            width: size.width + (target.size.width - size.width) * progress,
            height: size.height + (target.size.height - size.height) * progress
        )
    }
}
