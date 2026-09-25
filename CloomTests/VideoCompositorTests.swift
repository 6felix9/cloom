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

    func testAnchorTrimsWarmUpGapSoOutputOpensOnRealScreenContent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenURL = root.appending(path: "screen.mov")
        let outputURL = root.appending(path: "rendered.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 50,
                                           frames: [(50.2, 200), (50.3, 200), (50.4, 200)])

        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: nil,
            events: [TimedOverlayEvent(timeSeconds: 0, state: .default)],
            anchor: CMTime(seconds: 0.2, preferredTimescale: 600),
            outputURL: outputURL
        )

        let frames = try await MediaFixtures.decodedFrames(of: outputURL)
        assertTimes(frames.map(\.seconds), [0, 0.1, 0.2], accuracy: 0.002)
        XCTAssertGreaterThan(try XCTUnwrap(frames.first).gray(), 150, "First frame must not be black")
    }

    func testLatestFrameBeforeAnchorIsHeldAtOutputStart() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenURL = root.appending(path: "screen.mov")
        let outputURL = root.appending(path: "rendered.mov")
        // A static screen yields sparse frames; the frame on screen at the anchor may predate it.
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 50,
                                           frames: [(50.1, 60), (50.2, 200), (50.5, 120)])

        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: nil,
            events: [TimedOverlayEvent(timeSeconds: 0, state: .default)],
            anchor: CMTime(seconds: 0.3, preferredTimescale: 600),
            outputURL: outputURL
        )

        let frames = try await MediaFixtures.decodedFrames(of: outputURL)
        assertTimes(frames.map(\.seconds), [0, 0.2], accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(frames.first).gray(), 200, accuracy: 20)
        XCTAssertEqual(try XCTUnwrap(frames.last).gray(), 120, accuracy: 20)
    }

    func testSingleFrameBeforeAnchorStillProducesVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenURL = root.appending(path: "screen.mov")
        let outputURL = root.appending(path: "rendered.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 50, frames: [(50.1, 200)])

        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: nil,
            events: [TimedOverlayEvent(timeSeconds: 0, state: .default)],
            anchor: CMTime(seconds: 0.4, preferredTimescale: 600),
            outputURL: outputURL
        )

        let frames = try await MediaFixtures.decodedFrames(of: outputURL)
        assertTimes(frames.map(\.seconds), [0], accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(frames.first).gray(), 200, accuracy: 20)
    }

    func testCameraAndOverlayEventsShareScreenTimeline() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenURL = root.appending(path: "screen.mov")
        let cameraURL = root.appending(path: "camera.mov")
        let outputURL = root.appending(path: "rendered.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 50,
                                           frames: (1...6).map { (50 + Double($0) / 10, 100) })
        // Camera turns dark at +0.5 s; the overlay is hidden from +0.55 s (both epoch-relative).
        try await MediaFixtures.writeVideo(to: cameraURL, epoch: 50,
                                           frames: [(50.3, 250), (50.4, 250), (50.5, 20)])
        var hidden = OverlayState.default
        hidden.isVisible = false
        let events = [
            TimedOverlayEvent(timeSeconds: 0, state: .default),
            TimedOverlayEvent(timeSeconds: 0.55, state: hidden)
        ]

        try VideoCompositor.render(
            screenURL: screenURL,
            cameraURL: cameraURL,
            events: events,
            anchor: CMTime(seconds: 0.3, preferredTimescale: 600),
            outputURL: outputURL
        )

        let frames = try await MediaFixtures.decodedFrames(of: outputURL)
        let bubble = { (frame: MediaFixtures.DecodedFrame) in
            frame.gray(atX: OverlayState.default.centerX, y: OverlayState.default.centerY)
        }
        assertTimes(frames.map(\.seconds), [0, 0.1, 0.2, 0.3], accuracy: 0.002)
        guard frames.count == 4 else { return }
        XCTAssertEqual(bubble(frames[0]), 250, accuracy: 25)
        XCTAssertEqual(bubble(frames[1]), 250, accuracy: 25)
        XCTAssertEqual(bubble(frames[2]), 20, accuracy: 25)
        XCTAssertEqual(bubble(frames[3]), 100, accuracy: 25, "Overlay hides at epoch +0.55 s")
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

private func assertTimes(_ values: [Double], _ expected: [Double], accuracy: Double,
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(values.count, expected.count, "\(values) != \(expected)", file: file, line: line)
    for (value, target) in zip(values, expected) {
        XCTAssertEqual(value, target, accuracy: accuracy, "\(values) != \(expected)", file: file, line: line)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }
}
