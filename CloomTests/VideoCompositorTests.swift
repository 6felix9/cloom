import AVFoundation
import CoreMedia
import CoreVideo
import XCTest
@testable import Cloom

final class VideoCompositorTests: XCTestCase, @unchecked Sendable {
    func testCompositingScreenVideoProduces1080pOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let screenURL = root.appending(path: "screen.mov")
        let outputURL = root.appending(path: "rendered.mov")

        let writer = try MediaSampleWriter.video(url: screenURL, width: 320, height: 240, epoch: 100)
        try writer.append(videoSample(at: 100))
        try writer.append(videoSample(at: 100.1))
        try await writer.finish()

        let recorder = ProgressRecorder()
        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: nil,
            events: [TimedOverlayEvent(timeSeconds: 0, state: .default)],
            outputURL: outputURL
        ) { progress in
            recorder.record(progress)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(recorder.values.isEmpty)

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let naturalSize = try await tracks[0].load(.naturalSize)
        XCTAssertEqual(naturalSize.width, 1920)
        XCTAssertEqual(naturalSize.height, 1080)
    }

    func testCompositingWithCameraAndEventsSucceeds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let screenURL = root.appending(path: "screen.mov")
        let cameraURL = root.appending(path: "camera.mov")
        let outputURL = root.appending(path: "rendered.mov")

        let screenWriter = try MediaSampleWriter.video(url: screenURL, width: 640, height: 360, epoch: 50)
        try screenWriter.append(videoSample(at: 50))
        try screenWriter.append(videoSample(at: 50.1))
        try await screenWriter.finish()

        let cameraWriter = try MediaSampleWriter.video(url: cameraURL, width: 320, height: 240, epoch: 50)
        try cameraWriter.append(videoSample(at: 50))
        try cameraWriter.append(videoSample(at: 50.1))
        try await cameraWriter.finish()

        let events = [
            TimedOverlayEvent(timeSeconds: 0, state: OverlayState(centerX: 0.8, centerY: 0.8, size: .small, shape: .circle, isVisible: true)),
            TimedOverlayEvent(timeSeconds: 0.05, state: OverlayState(centerX: 0.5, centerY: 0.5, size: .large, shape: .roundedSquare, isVisible: true))
        ]

        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: cameraURL,
            events: events,
            outputURL: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }

    func testMissingScreenVideoThrowsError() {
        let fakeURL = FileManager.default.temporaryDirectory.appending(path: "missing.mov")
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "output.mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        XCTAssertThrowsError(
            try VideoCompositor.render(
                screenURL: fakeURL,
                cameraURL: nil,
                events: [],
                outputURL: outputURL
            )
        ) { error in
            XCTAssertEqual(error as? VideoCompositorError, .missingScreenVideo)
        }
    }

    private func videoSample(at seconds: Double) throws -> CMSampleBuffer {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image
        ), kCVReturnSuccess)
        let buffer = try XCTUnwrap(image)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(buffer) {
            memset(bytes, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format
        ), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }
}
