import XCTest
@testable import Cloom

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    func testHappyPathTransitionsReachFinished() throws {
        let coordinator = RecordingCoordinator()
        let output = URL(fileURLWithPath: "/tmp/cloom.mp4")

        try coordinator.beginPreparing()
        try coordinator.beginCountdown()
        try coordinator.beginRecording()
        try coordinator.beginExporting()
        try coordinator.finish(outputURL: output)

        XCTAssertEqual(coordinator.phase, .finished(outputURL: output))
    }

    func testInvalidTransitionPreservesCurrentPhase() {
        let coordinator = RecordingCoordinator()

        XCTAssertThrowsError(try coordinator.beginRecording())
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFailureCanBeReset() {
        let coordinator = RecordingCoordinator()
        coordinator.fail(.captureFailed("Camera disconnected"))
        XCTAssertEqual(coordinator.phase, .failed(.captureFailed("Camera disconnected")))

        coordinator.reset()
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
