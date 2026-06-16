import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

@MainActor
final class PictureInPictureService: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false

    var playHandler: (() -> Void)?
    var pauseHandler: (() -> Void)?
    var skipHandler: ((TimeInterval) -> Void)?
    var prepareHandler: (() -> Void)?
    var errorHandler: ((String) -> Void)?
    var statusHandler: ((Bool) -> Void)?
    var restoreUserInterfaceHandler: ((@escaping (Bool) -> Void) -> Void)?

    private weak var videoPlayerLayer: AVPlayerLayer?
    let audioSubtitleLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var activeKind: PiPKind?
    private var startTask: Task<Void, Never>?
    private var audioRenderTask: Task<Void, Never>?
    private var latestState: PlayerState?
    private var audioTimebase: CMTimebase?
    private var renderSize = CGSize(width: 960, height: 540)
    private var lastRenderedSignature = ""
    private var lastPresentationTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var isPlaybackPaused = true
    private var playbackRate: Float = 1
    private var isHandlingRemoteSkip = false
    private var shouldResumeAfterRemoteSkip = false

    override init() {
        super.init()
        configureAudioSubtitleLayer()
    }

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func setVideoPlayerLayer(_ layer: AVPlayerLayer) {
        guard videoPlayerLayer !== layer else { return }
        videoPlayerLayer = layer
        if activeKind == .video {
            controller = nil
            activeKind = nil
            isActive = false
            isStarting = false
        }
    }

    func canStart(for state: PlayerState) -> Bool {
        if isActive || isStarting || controller?.isPictureInPictureActive == true { return true }
        guard isSupported, state.sourceURL != nil else { return false }
        if state.isVideo {
            return videoPlayerLayer?.player != nil
        }
        return true
    }

    func toggle(for state: PlayerState) {
        if isStarting {
            return
        }
        if controller?.isPictureInPictureActive == true || isActive {
            stop()
            return
        }

        latestState = state
        isStarting = true
        prepareHandler?()
        if !state.isPlaying {
            playHandler?()
        }

        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(state.isPlaying ? 80 : 360))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if state.isVideo {
                self.startVideoPiP()
            } else {
                self.startAudioSubtitlePiP(state: self.latestState ?? state)
            }
        }
    }

    func stop() {
        startTask?.cancel()
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        } else {
            reset()
        }
    }

    func handleMediaWillChange(from oldState: PlayerState, to newURL: URL) {
        guard isActive || isStarting || controller?.isPictureInPictureActive == true else { return }

        if oldState.isVideo || MediaLibrary.isVideo(newURL) {
            stop()
            return
        }

        latestState = nil
        duration = 0
        currentTime = 0
        isPlaybackPaused = true
        resetAudioSubtitleLayerForReuse(removeImage: false)
        syncAudioTimebase()
    }

    func update(with state: PlayerState) {
        latestState = state
        duration = state.duration
        currentTime = state.currentTime
        isPlaybackPaused = !state.isPlaying
        playbackRate = state.playbackRate
        syncAudioTimebase()
        controller?.invalidatePlaybackState()

        guard activeKind == .audioSubtitle else { return }
        renderAudioSubtitleFrame(state: state, force: false)
    }

    private func startVideoPiP() {
        guard isSupported else {
            reportError("当前设备不支持画中画。")
            reset()
            return
        }
        guard let videoPlayerLayer else {
            reportError("视频画中画暂时不可用，请先打开全屏视频播放器。")
            reset()
            return
        }
        guard videoPlayerLayer.player != nil else {
            reportError("视频画中画暂时不可用，请先打开全屏视频播放器。")
            reset()
            return
        }

        let nextController = AVPictureInPictureController(playerLayer: videoPlayerLayer)
        nextController?.delegate = self
        nextController?.canStartPictureInPictureAutomaticallyFromInline = true
        controller = nextController
        activeKind = .video

        guard let nextController else {
            reportError("系统暂时不能开启视频画中画，请确认视频正在播放且画面已显示。")
            reset()
            return
        }

        startAfterWarmup(controller: nextController, delay: .milliseconds(220))
    }

    private func startAudioSubtitlePiP(state: PlayerState) {
        guard isSupported else {
            reportError("当前设备不支持画中画。")
            reset()
            return
        }
        latestState = state
        resetAudioSubtitleLayerForReuse(removeImage: true)
        syncAudioTimebase()
        renderAudioSubtitleFrame(state: state, force: true)
        beginAudioFramePump(initialState: state)

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: audioSubtitleLayer,
            playbackDelegate: self
        )
        let nextController = AVPictureInPictureController(contentSource: source)
        nextController.delegate = self
        nextController.canStartPictureInPictureAutomaticallyFromInline = true
        controller = nextController
        activeKind = .audioSubtitle
        syncAudioTimebase()

        startAfterWarmup(controller: nextController, delay: .milliseconds(500))
    }

    private func configureAudioSubtitleLayer() {
        audioSubtitleLayer.videoGravity = .resizeAspect
        audioSubtitleLayer.backgroundColor = UIColor.black.cgColor
        audioSubtitleLayer.preventsDisplaySleepDuringVideoPlayback = true

        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        audioTimebase = timebase
        audioSubtitleLayer.controlTimebase = timebase
    }

    private func syncAudioTimebase() {
        guard let audioTimebase else { return }
        CMTimebaseSetTime(audioTimebase, time: CMTime(seconds: currentTime, preferredTimescale: 600))
        CMTimebaseSetRate(audioTimebase, rate: isPlaybackPaused ? 0 : Double(playbackRate))
    }

    private func resetAudioSubtitleLayerForReuse(removeImage: Bool) {
        lastRenderedSignature = ""
        lastPresentationTime = 0
        if removeImage || audioSubtitleLayer.status == .failed {
            audioSubtitleLayer.flushAndRemoveImage()
        } else {
            audioSubtitleLayer.flush()
        }
    }

    private func beginAudioFramePump(initialState: PlayerState) {
        latestState = initialState
        audioRenderTask?.cancel()
        audioRenderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let state = self.latestState {
                    self.duration = state.duration
                    self.currentTime = state.currentTime
                    self.isPlaybackPaused = !state.isPlaying
                    self.playbackRate = state.playbackRate
                    self.syncAudioTimebase()
                    self.renderAudioSubtitleFrame(state: state, force: true)
                    self.controller?.invalidatePlaybackState()
                }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func startAfterWarmup(
        controller nextController: AVPictureInPictureController,
        delay: Duration
    ) {
        startTask = Task { @MainActor [weak self, weak nextController] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
                guard let self, let nextController, self.controller === nextController else { return }
            if nextController.isPictureInPictureActive {
                return
            }
            nextController.startPictureInPicture()
        }
    }

    private func renderAudioSubtitleFrame(state: PlayerState, force: Bool) {
        let subtitle = state.activeSubtitle?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = [
            state.title,
            subtitle ?? "",
            state.isPlaying ? "playing" : "paused",
            "\(Int(renderSize.width))x\(Int(renderSize.height))"
        ].joined(separator: "|")
        guard force || signature != lastRenderedSignature else { return }
        lastRenderedSignature = signature

        if state.currentTime + 0.04 < lastPresentationTime {
            resetAudioSubtitleLayerForReuse(removeImage: true)
        }

        let presentationTime = max(state.currentTime, lastPresentationTime + 0.04)
        guard let sampleBuffer = makeSubtitleSampleBuffer(
            title: state.title,
            subtitle: subtitle,
            isPlaying: state.isPlaying,
            time: presentationTime
        ) else { return }

        if audioSubtitleLayer.status == .failed {
            audioSubtitleLayer.flush()
        }
        audioSubtitleLayer.enqueue(sampleBuffer)
        lastPresentationTime = presentationTime
    }

    private func makeSubtitleSampleBuffer(
        title: String,
        subtitle: String?,
        isPlaying: Bool,
        time: TimeInterval
    ) -> CMSampleBuffer? {
        let image = makeSubtitleImage(title: title, subtitle: subtitle, isPlaying: isPlaying)
        guard let pixelBuffer = makePixelBuffer(from: image) else { return nil }

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    private func makeSubtitleImage(title: String, subtitle: String?, isPlaying: Bool) -> UIImage {
        let size = renderSize
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = max(3, size.height * 0.012)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(22, size.height * 0.055), weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.62),
                .paragraphStyle: paragraph
            ]
            let hintAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(18, size.height * 0.043), weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.42),
                .paragraphStyle: paragraph
            ]

            let titleRect = CGRect(x: size.width * 0.1, y: size.height * 0.12, width: size.width * 0.8, height: size.height * 0.14)
            title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: titleAttributes, context: nil)

            if let subtitle, !subtitle.isEmpty {
                let subtitleRect = CGRect(x: size.width * 0.07, y: size.height * 0.28, width: size.width * 0.86, height: size.height * 0.48)
                drawAdaptiveSubtitle(
                    subtitle,
                    in: subtitleRect,
                    canvasSize: size,
                    paragraphStyle: paragraph
                )
            }

            let hint = isPlaying ? "Whisper" : "已暂停"
            let hintRect = CGRect(x: size.width * 0.1, y: size.height * 0.78, width: size.width * 0.8, height: size.height * 0.08)
            hint.draw(with: hintRect, options: [.usesLineFragmentOrigin], attributes: hintAttributes, context: nil)
        }
    }

    private func drawAdaptiveSubtitle(
        _ text: String,
        in rect: CGRect,
        canvasSize: CGSize,
        paragraphStyle: NSParagraphStyle
    ) {
        let maximumFontSize = max(38, min(canvasSize.width * 0.072, canvasSize.height * 0.125))
        let minimumFontSize = max(24, min(canvasSize.width * 0.042, canvasSize.height * 0.072))
        let fittedFontSize = bestSubtitleFontSize(
            for: text,
            in: rect,
            maximumFontSize: maximumFontSize,
            minimumFontSize: minimumFontSize,
            paragraphStyle: paragraphStyle
        )
        let fittedFont = UIFont.systemFont(ofSize: fittedFontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: fittedFont,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]

        let measuredHeight = measuredSubtitleSize(text, attributes: attributes, width: rect.width).height
        let verticallyCenteredRect = rect.insetBy(dx: 0, dy: max((rect.height - measuredHeight) / 2, 0))

        if measuredHeight <= rect.height {
            text.draw(
                with: verticallyCenteredRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        } else {
            let truncatingParagraph = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            truncatingParagraph.lineBreakMode = .byTruncatingTail
            attributes[.paragraphStyle] = truncatingParagraph
            text.draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                attributes: attributes,
                context: nil
            )
        }
    }

    private func bestSubtitleFontSize(
        for text: String,
        in rect: CGRect,
        maximumFontSize: CGFloat,
        minimumFontSize: CGFloat,
        paragraphStyle: NSParagraphStyle
    ) -> CGFloat {
        var low = minimumFontSize
        var high = maximumFontSize
        var best = minimumFontSize

        for _ in 0..<10 {
            let midpoint = (low + high) / 2
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: midpoint, weight: .semibold),
                .paragraphStyle: paragraphStyle
            ]
            let measuredSize = measuredSubtitleSize(text, attributes: attributes, width: rect.width)

            if measuredSize.width <= rect.width + 0.5 && measuredSize.height <= rect.height {
                best = midpoint
                low = midpoint
            } else {
                high = midpoint
            }
        }

        return max(min(best, maximumFontSize), minimumFontSize)
    }

    private func measuredSubtitleSize(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        width: CGFloat
    ) -> CGSize {
        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return CGSize(width: ceil(boundingRect.width), height: ceil(boundingRect.height))
    }

    private func makePixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        return pixelBuffer
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorHandler?(message)
        }
    }

    private func reset() {
        startTask?.cancel()
        startTask = nil
        audioRenderTask?.cancel()
        audioRenderTask = nil
        controller?.delegate = nil
        controller = nil
        activeKind = nil
        resetAudioSubtitleLayerForReuse(removeImage: true)
        isActive = false
        isStarting = false
        isHandlingRemoteSkip = false
        shouldResumeAfterRemoteSkip = false
        statusHandler?(false)
    }
}

extension PictureInPictureService: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            self?.isStarting = false
            self?.isActive = true
            self?.statusHandler?(true)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let nsError = error as NSError
        reportError("无法开启画中画：\(error.localizedDescription)（\(nsError.domain) \(nsError.code)）")
        DispatchQueue.main.async { [weak self] in
            guard self?.controller === pictureInPictureController else { return }
            self?.reset()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async { [weak self] in
            guard self?.controller === pictureInPictureController else { return }
            self?.reset()
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.controller === pictureInPictureController else {
                completionHandler(false)
                return
            }
            guard let restoreUserInterfaceHandler = self.restoreUserInterfaceHandler else {
                completionHandler(false)
                return
            }
            restoreUserInterfaceHandler(completionHandler)
        }
    }
}

extension PictureInPictureService: @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        DispatchQueue.main.async { [weak self] in
            if self?.isHandlingRemoteSkip == true, playing == false, self?.shouldResumeAfterRemoteSkip == true {
                return
            }
            playing ? self?.playHandler?() : self?.pauseHandler?()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        guard duration.isFinite, duration > 0 else {
            return CMTimeRange(start: .zero, duration: .positiveInfinity)
        }
        return CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        isPlaybackPaused
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        let width = max(Int(newRenderSize.width), 480)
        let height = max(Int(newRenderSize.height), 270)
        renderSize = CGSize(width: width, height: height)
        lastRenderedSignature = ""
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                completion()
                return
            }
            let wasPlaying = !self.isPlaybackPaused || self.latestState?.isPlaying == true
            self.isHandlingRemoteSkip = true
            self.shouldResumeAfterRemoteSkip = wasPlaying
            self.skipHandler?(skipInterval.seconds)
            if wasPlaying {
                self.isPlaybackPaused = false
                self.playHandler?()
            }
            completion()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.isHandlingRemoteSkip = false
                self?.shouldResumeAfterRemoteSkip = false
            }
        }
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}

private enum PiPKind {
    case video
    case audioSubtitle
}
