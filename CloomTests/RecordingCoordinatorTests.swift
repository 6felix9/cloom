import XCTest
@testable import Cloom

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    func testHappyPathTransitionsReachFinished() throws {
        let coordinator = RecordingCoordinator()
        let output = URL(fileURLWithPath: "/tmp/cloom.mp4")

        try coordinator.beginPreparing()
        try coordinator.beginCountdown(seconds: 3)
        try coordinator.beginRecording()
        try coordinator.beginStopping()
        try coordinator.beginExporting()
        try coordinator.finish(outputURL: output)

        XCTAssertEqual(coordinator.phase, .finished(outputURL: output))
    }

    func testStoppingCanOnlyBeginFromRecording() throws {
        let coordinator = RecordingCoordinator()

        XCTAssertThrowsError(try coordinator.beginStopping())
        XCTAssertEqual(coordinator.phase, .idle)

        try coordinator.beginPreparing()
        try coordinator.beginCountdown(seconds: 3)
        try coordinator.beginRecording()
        try coordinator.beginStopping()

        XCTAssertEqual(coordinator.phase, .stopping)
        XCTAssertThrowsError(try coordinator.beginStopping())
        XCTAssertEqual(coordinator.phase, .stopping)
    }

    func testCountdownTicksDownToOneThenRecords() throws {
        let coordinator = RecordingCoordinator()
        try coordinator.beginPreparing()

        try coordinator.beginCountdown(seconds: 3)
        XCTAssertEqual(coordinator.phase, .countdown(remaining: 3))
        try coordinator.tickCountdown()
        XCTAssertEqual(coordinator.phase, .countdown(remaining: 2))
        try coordinator.tickCountdown()
        XCTAssertEqual(coordinator.phase, .countdown(remaining: 1))
        XCTAssertThrowsError(try coordinator.tickCountdown())
        XCTAssertEqual(coordinator.phase, .countdown(remaining: 1))

        try coordinator.beginRecording()
        XCTAssertEqual(coordinator.phase, .recording)
    }

    func testCountdownRejectsInvalidStartsAndTicks() throws {
        let coordinator = RecordingCoordinator()

        XCTAssertThrowsError(try coordinator.tickCountdown())
        XCTAssertEqual(coordinator.phase, .idle)

        try coordinator.beginPreparing()
        XCTAssertThrowsError(try coordinator.beginCountdown(seconds: 0))
        XCTAssertEqual(coordinator.phase, .preparing)
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
