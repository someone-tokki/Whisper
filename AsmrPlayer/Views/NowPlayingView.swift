import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    let contentProgress: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.08),
                    Color(red: 0.11, green: 0.13, blue: 0.15),
                    Color(red: 0.09, green: 0.11, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                artworkIcon

                VStack(spacing: 8) {
                    titleText

                    Text(player.state.subtitleURL == nil ? (player.statusMessage ?? "未加载字幕") : player.state.subtitleURL?.lastPathComponent ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(contentProgress)
                        .offset(y: 6 * (1 - contentProgress))
                }

                if let remaining = player.state.remainingSleepTime {
                    Label("睡眠定时 \(player.formattedTime(remaining))", systemImage: "timer")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.10), in: Capsule())
                        .opacity(contentProgress)
                        .offset(y: 6 * (1 - contentProgress))
                }
            }
            .padding(24)
        }
    }

    private var artworkIcon: some View {
        Image(systemName: player.state.isPlaying ? "waveform.circle.fill" : "moon.zzz.circle.fill")
            .font(.system(size: 92, weight: .light))
            .foregroundStyle(.mint)
            .symbolEffect(.pulse, isActive: player.state.isPlaying)
            .scaleEffect(0.96 + contentProgress * 0.04)
    }

    private var titleText: some View {
        Text(player.state.title)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .opacity(0.6 + contentProgress * 0.4)
    }
}
