import AVFoundation
import CoreMedia
import XCTest
@testable import Cloom

final class RecordingTimelineTests: XCTestCase, @unchecked Sendable {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCaptureFilesKeepEachStreamStartRelativeToEpoch() async throws {
        let screenURL = root.appending(path: "screen.mov")
        let microphoneURL = root.appending(path: "microphone.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 10, frames: [(10.5, 200), (10.6, 200)])
        try await MediaFixtures.writeAudio(to: microphoneURL, epoch: 10, start: 10.3, duration: 0.2)

        let screenStart = try await RecordingTimeline.firstSampleTime(of: screenURL, mediaType: .video)
        let microphoneStart = try await RecordingTimeline.firstSampleTime(of: microphoneURL, mediaType: .audio)

        XCTAssertEqual(try XCTUnwrap(screenStart).seconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(microphoneStart).seconds, 0.3, accuracy: 0.025)
    }

    func testAnchorIsLatestStartOfScreenCameraAndMicrophone() async throws {
        let screenURL = root.appending(path: "screen.mov")
        let cameraURL = root.appending(path: "camera.mov")
        let microphoneURL = root.appending(path: "microphone.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 10, frames: [(10.2, 200), (10.5, 200)])
        try await MediaFixtures.writeVideo(to: cameraURL, epoch: 10, frames: [(10.1, 200), (10.5, 200)])
        try await MediaFixtures.writeAudio(to: microphoneURL, epoch: 10, start: 10.4, duration: 0.2)

        let timeline = try await RecordingTimeline.resolve(
            screenURL: screenURL, cameraURL: cameraURL, microphoneURL: microphoneURL
        )

        XCTAssertEqual(timeline.screenStart.seconds, 0.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(timeline.cameraStart).seconds, 0.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(timeline.microphoneStart).seconds, 0.4, accuracy: 0.025)
        XCTAssertEqual(timeline.anchor.seconds, 0.4, accuracy: 0.025)
    }

    func testMissingOptionalStreamsDoNotMoveAnchor() async throws {
        let screenURL = root.appending(path: "screen.mov")
        try await MediaFixtures.writeVideo(to: screenURL, epoch: 10, frames: [(10.2, 200), (10.3, 200)])

        let timeline = try await RecordingTimeline.resolve(
            screenURL: screenURL,
            cameraURL: root.appending(path: "missing-camera.mov"),
            microphoneURL: nil
        )

        XCTAssertNil(timeline.cameraStart)
        XCTAssertNil(timeline.microphoneStart)
        XCTAssertEqual(timeline.anchor.seconds, 0.2, accuracy: 0.001)
    }

    func testMissingScreenVideoThrows() async {
        do {
            _ = try await RecordingTimeline.resolve(
                screenURL: root.appending(path: "missing.mov"), cameraURL: nil, microphoneURL: nil
            )
            XCTFail("Expected missing screen video error")
        } catch {
            XCTAssertEqual(error as? VideoCompositorError, .missingScreenVideo)
        }
    }
}
