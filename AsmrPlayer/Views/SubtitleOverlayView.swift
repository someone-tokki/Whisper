import SwiftUI

struct SubtitleOverlayView: View {
    enum Style {
        case panel
        case floating
    }

    @EnvironmentObject private var settings: AppSettings

    let cue: SubtitleCue?
    var style: Style = .panel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)

            Text(cue?.text ?? " ")
                .font(subtitleFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .shadow(color: settings.subtitleShadowEnabled ? .black.opacity(0.72) : .clear, radius: 3, x: 0, y: 1)
                .shadow(color: settings.subtitleOutlineEnabled ? .black.opacity(0.65) : .clear, radius: 1, x: 0, y: 0)
        }
        .frame(minHeight: 58)
        .fixedSize(horizontal: false, vertical: style == .floating)
        .accessibilityLabel(cue?.text ?? "无字幕")
    }

    private var backgroundColor: Color {
        switch style {
        case .panel:
            Color.black.opacity(0.72)
        case .floating:
            Color.black.opacity(0.58)
        }
    }

    private var subtitleFont: Font {
        let weight: Font.Weight = settings.subtitleFontStyle == .bold ? .bold : .medium
        switch settings.subtitleFont {
        case .system:
            return .body.weight(weight)
        case .rounded:
            return .system(.body, design: .rounded).weight(weight)
        case .pingFang, .helveticaNeue, .avenirNext, .notoSans:
            return .custom(settings.subtitleFont.fontName ?? "HelveticaNeue", size: 17).weight(weight)
        }
    }
}
