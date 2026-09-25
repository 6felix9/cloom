import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum VideoCompositorError: Error, LocalizedError, Equatable {
    case missingScreenVideo
    case cannotReadSource
    case cannotCreateWriter
    case videoWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScreenVideo: "The recoverable recording has no screen video."
        case .cannotReadSource: "Cloom could not read a captured media track."
        case .cannotCreateWriter: "Cloom could not create the final video writer."
        case let .videoWriteFailed(message): "Video rendering failed: \(message)"
        }
    }
}

enum VideoCompositor {
    static let outputSize = CGSize(width: 1920, height: 1080)

    static func render(
        screenURL: URL,
        cameraURL: URL?,
        events: [TimedOverlayEvent],
        anchor: CMTime = .zero,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) throws {
        guard FileManager.default.fileExists(atPath: screenURL.path) else {
            throw VideoCompositorError.missingScreenVideo
        }
        let screenAsset = AVURLAsset(url: screenURL)
        guard let screenTrack = screenAsset.tracks(withMediaType: .video).first else {
            throw VideoCompositorError.missingScreenVideo
        }
        let screenReader = try AVAssetReader(asset: screenAsset)
        let screenOutput = AVAssetReaderTrackOutput(track: screenTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        screenOutput.alwaysCopiesSampleData = false
        guard screenReader.canAdd(screenOutput) else { throw VideoCompositorError.cannotReadSource }
        screenReader.add(screenOutput)

        var cameraReader: AVAssetReader?
        var cameraOutput: AVAssetReaderTrackOutput?
        if let cameraURL, FileManager.default.fileExists(atPath: cameraURL.path) {
            let cameraAsset = AVURLAsset(url: cameraURL)
            if let cameraTrack = cameraAsset.tracks(withMediaType: .video).first,
               let reader = try? AVAssetReader(asset: cameraAsset) {
                let output = AVAssetReaderTrackOutput(track: cameraTrack, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ])
                output.alwaysCopiesSampleData = false
                if reader.canAdd(output) {
                    reader.add(output)
                    cameraReader = reader
                    cameraOutput = output
                }
            }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else { throw VideoCompositorError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoCompositorError.videoWriteFailed(writer.error?.localizedDescription ?? "writer did not start")
        }
        writer.startSession(atSourceTime: .zero)
        guard screenReader.startReading() else { throw VideoCompositorError.cannotReadSource }
        _ = cameraReader?.startReading()

        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let duration = max(screenAsset.duration.seconds - anchor.seconds, 0.001)
        let tolerance = CMTime(value: 1, timescale: 1_000)
        var nextCamera = cameraOutput?.copyNextSampleBuffer()
        var currentCamera: CVPixelBuffer?
        // Screen, camera and overlay events all share the epoch-relative source timeline; output time is
        // source time minus the anchor. Readers emit a black placeholder for each file's leading empty edit.
        func emit(_ screenSample: CMSampleBuffer, at sourceTime: CMTime) {
            autoreleasepool {
                while let sample = nextCamera, CMSampleBufferGetPresentationTimeStamp(sample) <= sourceTime {
                    currentCamera = CMSampleBufferGetImageBuffer(sample)
                    nextCamera = cameraOutput?.copyNextSampleBuffer()
                }

                guard let screenBuffer = CMSampleBufferGetImageBuffer(screenSample),
                      let pool = adaptor.pixelBufferPool else { return }
                var destination: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                      let destination else { return }
                let outputTime = CMTimeMaximum(CMTimeSubtract(sourceTime, anchor), .zero)
                let state = interpolatedState(at: sourceTime.seconds, events: events)
                var image = aspectFit(CIImage(cvPixelBuffer: screenBuffer), in: outputSize)
                if state.isVisible, let currentCamera {
                    image = cameraOverlay(CIImage(cvPixelBuffer: currentCamera), state: state)
                        .composited(over: image)
                }
                context.render(
                    image,
                    to: destination,
                    bounds: CGRect(origin: .zero, size: outputSize),
                    colorSpace: colorSpace
                )
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                if !adaptor.append(destination, withPresentationTime: outputTime) {
                    return
                }
                progress(min(outputTime.seconds / duration, 1))
            }
        }

        // Screen frames arrive only when content changes, so the frame showing at the anchor may predate it.
        var heldScreen: CMSampleBuffer?
        var reachedAnchor = false
        while let screenSample = screenOutput.copyNextSampleBuffer() {
            let sourceTime = CMSampleBufferGetPresentationTimeStamp(screenSample)
            if !reachedAnchor {
                if CMTimeAdd(sourceTime, tolerance) < anchor {
                    heldScreen = screenSample
                    continue
                }
                reachedAnchor = true
                if let heldScreen, sourceTime > CMTimeAdd(anchor, tolerance) {
                    emit(heldScreen, at: anchor)
                }
                heldScreen = nil
            }
            emit(screenSample, at: sourceTime)
            if writer.status == .failed { break }
        }
        if let heldScreen {
            emit(heldScreen, at: anchor)
        }
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw VideoCompositorError.videoWriteFailed(writer.error?.localizedDescription ?? "writer did not finish")
        }
    }

    private static func aspectFit(_ image: CIImage, in size: CGSize) -> CIImage {
        let scale = min(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (size.width - scaled.extent.width) / 2 - scaled.extent.minX
        let y = (size.height - scaled.extent.height) / 2 - scaled.extent.minY
        let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: black)
    }

    private static func cameraOverlay(_ image: CIImage, state: OverlayState) -> CIImage {
        let side = min(image.extent.width, image.extent.height)
        let crop = CGRect(
            x: image.extent.midX - side / 2,
            y: image.extent.midY - side / 2,
            width: side,
            height: side
        )
        var square = image.cropped(to: crop)
        square = square.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        square = square.transformed(by: CGAffineTransform(translationX: side, y: 0).scaledBy(x: -1, y: 1))
        let diameter = min(outputSize.width, outputSize.height) * CGFloat(state.size.presetFraction)
        square = square.transformed(by: CGAffineTransform(scaleX: diameter / side, y: diameter / side))
        let extent = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let rounded = CIFilter.roundedRectangleGenerator()
        rounded.extent = extent
        rounded.radius = state.shape == .circle ? Float(diameter / 2) : Float(diameter * 0.16)
        rounded.color = CIColor.white
        let masked = square.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: rounded.outputImage!
        ])
        let center = CGPoint(x: outputSize.width * state.centerX, y: outputSize.height * state.centerY)
        return masked.transformed(by: CGAffineTransform(translationX: center.x - diameter / 2,
                                                         y: center.y - diameter / 2))
    }

    private static func interpolatedState(at time: Double, events: [TimedOverlayEvent]) -> OverlayState {
        guard let index = events.lastIndex(where: { $0.timeSeconds <= time }) else { return .default }
        let current = events[index]
        guard index + 1 < events.count else { return current.state }
        let next = events[index + 1]
        var state = current.state
        let delta = next.timeSeconds - current.timeSeconds
        guard delta > 0, time >= next.timeSeconds - 0.15, current.state.size != next.state.size else {
            return state
        }
        let t = min(max((time - (next.timeSeconds - 0.15)) / 0.15, 0), 1)
        if t >= 0.5 {
            state.size = next.state.size
        }
        return state
    }
}
