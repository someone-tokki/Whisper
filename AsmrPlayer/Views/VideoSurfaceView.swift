import AVFoundation
import SwiftUI
import UIKit

struct VideoSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        context.coordinator.currentPlayer = player
        context.coordinator.currentVideoGravity = videoGravity
        context.coordinator.readyLayer = view.playerLayer
        onLayerReady?(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if context.coordinator.currentPlayer !== player {
            uiView.playerLayer.player = player
            context.coordinator.currentPlayer = player
        }
        if context.coordinator.currentVideoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
            context.coordinator.currentVideoGravity = videoGravity
        }
        if uiView.playerLayer.bounds.size != uiView.bounds.size {
            uiView.playerLayer.frame = uiView.bounds
        }
        CATransaction.commit()
        if context.coordinator.readyLayer !== uiView.playerLayer {
            context.coordinator.readyLayer = uiView.playerLayer
            onLayerReady?(uiView.playerLayer)
        }
    }

    final class Coordinator {
        weak var currentPlayer: AVPlayer?
        var currentVideoGravity: AVLayerVideoGravity?
        weak var readyLayer: AVPlayerLayer?
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override func layoutSubviews() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layoutSubviews()
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        guard layer === playerLayer else {
            return super.action(for: layer, forKey: event)
        }

        switch event {
        case "bounds", "position", "frame", "transform", "contentsRect", "videoGravity":
            return NSNull()
        default:
            return super.action(for: layer, forKey: event)
        }
    }
}

struct AudioPictureInPictureHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        if layer.superlayer !== view.layer {
            layer.removeFromSuperlayer()
            view.layer.addSublayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = CGRect(x: 0, y: 0, width: max(uiView.bounds.width, 320), height: max(uiView.bounds.height, 180))
        if layer.superlayer !== uiView.layer {
            layer.removeFromSuperlayer()
            uiView.layer.addSublayer(layer)
        }
    }
}

struct VideoInteractionCaptureView: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onLeftDoubleTap: () -> Void
    var onRightDoubleTap: () -> Void
    var onPanChanged: (_ startLocation: CGPoint, _ translation: CGSize) -> Void
    var onPanEnded: (_ startLocation: CGPoint, _ translation: CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSingleTap: onSingleTap,
            onLeftDoubleTap: onLeftDoubleTap,
            onRightDoubleTap: onRightDoubleTap,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator

        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onLeftDoubleTap = onLeftDoubleTap
        context.coordinator.onRightDoubleTap = onRightDoubleTap
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSingleTap: () -> Void
        var onLeftDoubleTap: () -> Void
        var onRightDoubleTap: () -> Void
        var onPanChanged: (_ startLocation: CGPoint, _ translation: CGSize) -> Void
        var onPanEnded: (_ startLocation: CGPoint, _ translation: CGSize) -> Void
        private var panStartLocation: CGPoint?

        init(
            onSingleTap: @escaping () -> Void,
            onLeftDoubleTap: @escaping () -> Void,
            onRightDoubleTap: @escaping () -> Void,
            onPanChanged: @escaping (_ startLocation: CGPoint, _ translation: CGSize) -> Void,
            onPanEnded: @escaping (_ startLocation: CGPoint, _ translation: CGSize) -> Void
        ) {
            self.onSingleTap = onSingleTap
            self.onLeftDoubleTap = onLeftDoubleTap
            self.onRightDoubleTap = onRightDoubleTap
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
        }

        @MainActor @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onSingleTap()
        }

        @MainActor @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            if location.x < view.bounds.midX {
                onLeftDoubleTap()
            } else {
                onRightDoubleTap()
            }
        }

        @MainActor @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let translationSize = CGSize(width: translation.x, height: translation.y)

            switch recognizer.state {
            case .began:
                panStartLocation = recognizer.location(in: view)
            case .changed:
                guard let panStartLocation else { return }
                onPanChanged(panStartLocation, translationSize)
            case .ended, .cancelled, .failed:
                guard let panStartLocation else { return }
                onPanEnded(panStartLocation, translationSize)
                self.panStartLocation = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer,
                  let view = gestureRecognizer.view else {
                return true
            }
            let velocity = (gestureRecognizer as? UIPanGestureRecognizer)?.velocity(in: view) ?? .zero
            return abs(velocity.x) > 80 || abs(velocity.y) > 80
        }
    }
}
