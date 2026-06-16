import SwiftUI

private struct EdgeBackGestureModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isTrackingEdgeDrag = false

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            Color(.systemBackground)
                .ignoresSafeArea()
                .opacity(isTrackingEdgeDrag ? 1 : 0)
                .allowsHitTesting(false)

            content
                .offset(x: dragOffset)
                .shadow(
                    color: .black.opacity(edgeProgress * 0.12),
                    radius: 18 * edgeProgress,
                    x: -8 * edgeProgress,
                    y: 0
                )
                .overlay(alignment: .leading) {
                    edgeHighlight
                }

            if isEnabled {
                edgeGestureCapture
            }
        }
    }

    private var edgeGestureCapture: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(width: 24)
            .ignoresSafeArea(edges: .leading)
            .highPriorityGesture(edgeBackGesture)
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard isEnabled else { return }
                guard value.startLocation.x <= 28 else { return }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal > 0, horizontal > vertical * 1.15 else { return }

                isTrackingEdgeDrag = true
                dragOffset = min(84, horizontal * 0.42)
            }
            .onEnded { value in
                guard isEnabled else { return }
                defer {
                    if !shouldNavigateBack(value) {
                        resetEdgeDrag()
                    }
                }

                guard shouldNavigateBack(value) else { return }

                withAnimation(.smooth(duration: 0.16, extraBounce: 0)) {
                    dragOffset = 112
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    action()
                    resetEdgeDrag(after: 0.12)
                }
            }
    }

    private var edgeProgress: CGFloat {
        min(max(dragOffset / 84, 0), 1)
    }

    private var edgeHighlight: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.14 * edgeProgress),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 28)
            .opacity(edgeProgress)
            .allowsHitTesting(false)
    }

    private func shouldNavigateBack(_ value: DragGesture.Value) -> Bool {
        guard value.startLocation.x <= 28 else { return false }

        let horizontal = value.translation.width
        let vertical = abs(value.translation.height)
        let predictedHorizontal = value.predictedEndTranslation.width
        guard horizontal > 48 || predictedHorizontal > 78 else { return false }
        guard horizontal > vertical * 1.35 else { return false }
        return true
    }

    private func resetEdgeDrag(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                dragOffset = 0
                isTrackingEdgeDrag = false
            }
        }
    }
}

extension View {
    func edgeBackGesture(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(EdgeBackGestureModifier(isEnabled: isEnabled, action: action))
    }
}
