import SwiftUI

struct MiniPlayerView: View {
    enum Style {
        case wide
        case compact
    }

    @EnvironmentObject private var player: PlayerViewModel
    let style: Style
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(spacing: 0) {
                HStack(spacing: style == .wide ? 12 : 8) {
                    artwork

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.state.title)
                            .font((style == .wide ? Font.subheadline : Font.caption).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .animation(.easeInOut(duration: 0.18), value: style)
                        if style == .wide {
                            Text(player.state.activeSubtitle?.text ?? player.statusMessage ?? subtitleStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .offset(y: 3)))
                        }
                    }

                    Spacer(minLength: style == .wide ? 8 : 2)

                    Button {
                        player.togglePlay()
                    } label: {
                        Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(style == .wide ? .title3 : .headline)
                            .frame(width: style == .wide ? 34 : 28, height: style == .wide ? 34 : 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.state.sourceURL == nil)

                    if style == .wide {
                        Button {
                            player.skipForward()
                        } label: {
                            Image(systemName: "goforward")
                                .font(.title3)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.state.sourceURL == nil)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, style == .wide ? 12 : 10)
                .padding(.vertical, style == .wide ? 9 : 8)

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.red)
                        .frame(width: progressWidth(totalWidth: proxy.size.width), height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
            }
            .frame(height: style == .wide ? 62 : 62)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.08), value: style)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前播放")
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.82), Color.orange.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: mediaIconName)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(width: style == .wide ? 42 : 36, height: style == .wide ? 42 : 36)
    }

    private var mediaIconName: String {
        guard player.state.sourceURL != nil else { return "music.note" }
        return player.state.isVideo ? "film.fill" : "waveform"
    }

    private var subtitleStatus: String {
        if player.state.sourceURL == nil {
            return "选择一个文件开始播放"
        }
        return player.state.subtitleURL == nil ? "未加载字幕" : "字幕已加载"
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard player.state.duration > 0 else { return 0 }
        let progress = min(max(player.state.currentTime / player.state.duration, 0), 1)
        return totalWidth * progress
    }
}
