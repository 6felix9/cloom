import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import Cloom

@MainActor
final class RecordingSessionControllerTests: XCTestCase {
    func testStartUsesOneEpochForScreenAndCameraAndPersistsOverlay() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }

        try await fixture.controller.start(configuration: .fixture)

        XCTAssertEqual(fixture.screen.startedEpoch, 42)
        XCTAssertEqual(fixture.camera.startedEpoch, 42)
        XCTAssertEqual(fixture.order.events, ["camera.start", "screen.start"])
        XCTAssertEqual(fixture.coordinator.phase, .recording)
        XCTAssertEqual(fixture.screen.configuration?.microphoneCaptureDeviceID, "test-microphone")
        XCTAssertEqual(fixture.camera.deviceID, "test-camera")
        let events = try JSONDecoder().decode(
            [TimedOverlayEvent].self,
            from: Data(contentsOf: fixture.factory.workspace.overlayURL)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.timeSeconds, 0)
        XCTAssertEqual(events.first?.state.shape, .roundedSquare)
        XCTAssertEqual(events.first?.state.size, .large)
        XCTAssertTrue(fixture.controller.workspace === fixture.factory.workspace)
    }

    func testCountdownHoldsCaptureUntilSleeperCompletes() async throws {
        let sleeper = ControlledCountdownSleeper()
        let fixture = try Fixture(sleeper: sleeper)
        defer { fixture.removeWorkspace() }
        let start = Task { try await fixture.controller.start(configuration: .fixture) }
        await sleeper.waitUntilSleeping()

        XCTAssertEqual(fixture.coordinator.phase, .countdown)
        XCTAssertTrue(fixture.order.events.isEmpty)
        await sleeper.resume()
        try await start.value
        XCTAssertEqual(fixture.coordinator.phase, .recording)
    }

    func testScreenFailureStopsBothServicesAndPreservesFailedWorkspace() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        fixture.screen.startError = TestError.failed

        do {
            try await fixture.controller.start(configuration: .fixture)
            XCTFail("Expected screen capture start to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .failed)
        }

        XCTAssertEqual(fixture.order.events, ["camera.start", "screen.start", "screen.stop", "camera.stop"])
        XCTAssertEqual(try fixture.persistedManifest().captureState, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.factory.workspace.overlayURL.path))
        guard case .failed = fixture.coordinator.phase else { return XCTFail("Expected failed phase") }
    }

    func testCameraFailureCleansUpPartiallyStartedCameraWithoutStartingScreen() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        fixture.camera.startError = TestError.failed

        do {
            try await fixture.controller.start(configuration: .fixture)
            XCTFail("Expected camera start to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .failed)
        }

        XCTAssertEqual(fixture.order.events, ["camera.start", "camera.stop"])
        XCTAssertEqual(try fixture.persistedManifest().captureState, .failed)
    }

    func testCountdownFailureMarksWorkspaceFailedBeforeStartingCapture() async throws {
        let fixture = try Fixture(sleeper: FailingCountdownSleeper())
        defer { fixture.removeWorkspace() }

        do {
            try await fixture.controller.start(configuration: .fixture)
            XCTFail("Expected countdown cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertTrue(fixture.order.events.isEmpty)
        XCTAssertEqual(try fixture.persistedManifest().captureState, .failed)
    }

    func testStopFinalizesBothSourcesAndEntersExportingWithoutDeletingArtifacts() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        try await fixture.controller.start(configuration: .fixture)
        let artifact = Data("source-artifact".utf8)
        try artifact.write(to: fixture.factory.workspace.screenURL)

        try await fixture.controller.stop()

        XCTAssertEqual(fixture.order.events.suffix(2), ["screen.stop", "camera.stop"])
        XCTAssertEqual(fixture.coordinator.phase, .exporting(progress: 0))
        XCTAssertEqual(try fixture.persistedManifest().captureState, .captureComplete)
        XCTAssertEqual(try Data(contentsOf: fixture.factory.workspace.screenURL), artifact)
    }

    func testStopImmediatelyEntersStoppingBeforeCaptureTeardownCompletes() async throws {
        let gate = ControlledStopGate()
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        fixture.screen.stopGate = gate
        try await fixture.controller.start(configuration: .fixture)

        let stop = Task { try await fixture.controller.stop() }
        await gate.waitUntilBlocked()

        XCTAssertEqual(fixture.coordinator.phase, .stopping)
        await gate.resume()
        try await stop.value
        XCTAssertEqual(fixture.coordinator.phase, .exporting(progress: 0))
    }

    func testScreenStopFailureStillStopsCameraAndMarksWorkspaceFailed() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        try await fixture.controller.start(configuration: .fixture)
        fixture.screen.stopError = TestError.failed

        do {
            try await fixture.controller.stop()
            XCTFail("Expected stop failure")
        } catch {
            XCTAssertEqual(error as? TestError, .failed)
        }

        XCTAssertEqual(fixture.order.events.suffix(2), ["screen.stop", "camera.stop"])
        XCTAssertEqual(try fixture.persistedManifest().captureState, .failed)
        guard case .failed = fixture.coordinator.phase else { return XCTFail("Expected failed phase") }
    }

    func testDuplicateStartDoesNotTearDownActiveRecording() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }
        try await fixture.controller.start(configuration: .fixture)

        do {
            try await fixture.controller.start(configuration: .fixture)
            XCTFail("Expected invalid transition")
        } catch {
            XCTAssertTrue(error is RecordingTransitionError)
        }

        XCTAssertEqual(fixture.coordinator.phase, .recording)
        XCTAssertEqual(fixture.order.events, ["camera.start", "screen.start"])
    }

    func testMissingDeviceSelectionFailsBeforeCaptureStarts() async throws {
        let fixture = try Fixture()
        defer { fixture.removeWorkspace() }

        do {
            try await fixture.controller.start(configuration: RecordingSessionConfiguration(
                source: SessionTestScreenSelection(), settings: .default
            ))
            XCTFail("Expected missing selected devices to fail")
        } catch {
            XCTAssertTrue(fixture.order.events.isEmpty)
            guard case .failed = fixture.coordinator.phase else { return XCTFail("Expected failed phase") }
        }
    }

    func testScreenOnlyStartAndStopSkipCameraAndMicrophone() async throws {
        let fixture = try Fixture(settings: .screenOnly)
        defer { fixture.removeWorkspace() }

        try await fixture.controller.start(configuration: fixture.configuration)

        XCTAssertEqual(fixture.order.events, ["screen.start"])
        XCTAssertFalse(try XCTUnwrap(fixture.screen.configuration).captureMicrophone)

        try await fixture.controller.stop()

        XCTAssertEqual(fixture.order.events, ["screen.start", "screen.stop"])
    }

    func testEnabledCameraWithoutSelectionFailsBeforeCaptureStarts() async throws {
        var settings = RecordingSettings.screenOnly
        settings.includeCamera = true
        let fixture = try Fixture(settings: settings)
        defer { fixture.removeWorkspace() }

        do {
            try await fixture.controller.start(configuration: fixture.configuration)
            XCTFail("Expected missing camera selection")
        } catch RecordingSessionError.missingCamera {
            XCTAssertTrue(fixture.order.events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnabledMicrophoneWithoutSelectionFailsBeforeCaptureStarts() async throws {
        var settings = RecordingSettings.screenOnly
        settings.includeMicrophone = true
        let fixture = try Fixture(settings: settings)
        defer { fixture.removeWorkspace() }

        do {
            try await fixture.controller.start(configuration: fixture.configuration)
            XCTFail("Expected missing microphone selection")
        } catch RecordingSessionError.missingMicrophone {
            XCTAssertTrue(fixture.order.events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum TestError: Error { case failed }

private struct FixedRecordingClock: RecordingClock {
    func nowSeconds() -> Double { 42 }
}

private struct ImmediateCountdownSleeper: CountdownSleeping {
    func sleepForCountdown() async throws {}
}

private struct FailingCountdownSleeper: CountdownSleeping {
    func sleepForCountdown() async throws { throw CancellationError() }
}

private actor ControlledCountdownSleeper: CountdownSleeping {
    private var sleeping = false
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func sleepForCountdown() async throws {
        await withCheckedContinuation { continuation in
            completion = continuation
            sleeping = true
            entered?.resume()
            entered = nil
        }
    }

    func waitUntilSleeping() async {
        if sleeping { return }
        await withCheckedContinuation { entered = $0 }
    }

    func resume() { completion?.resume(); completion = nil }
}

private actor ControlledStopGate {
    private var blocked = false
    private var entered: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            completion = continuation
            blocked = true
            entered?.resume()
            entered = nil
        }
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { entered = $0 }
    }

    func resume() { completion?.resume(); completion = nil }
}

@MainActor
private final class CaptureOrder { var events: [String] = [] }

@MainActor
private final class FakeScreenCapture: ScreenCapturing {
    let order: CaptureOrder
    var startedEpoch: Double?
    var configuration: SCStreamConfiguration?
    var startError: Error?
    var stopError: Error?
    var stopGate: ControlledStopGate?

    init(order: CaptureOrder) { self.order = order }
    func start(selection: any ScreenCaptureSelection, configuration: SCStreamConfiguration,
               workspace: RecordingWorkspace, epoch: Double) async throws {
        order.events.append("screen.start")
        startedEpoch = epoch
        self.configuration = configuration
        if let startError { throw startError }
    }
    func stop() async throws {
        order.events.append("screen.stop")
        if let stopGate { await stopGate.wait() }
        if let stopError { throw stopError }
    }
}

@MainActor
private final class FakeCameraCapture: CameraCapturing {
    let order: CaptureOrder
    let previewSession = AVCaptureSession()
    var startedEpoch: Double?
    var deviceID: String?
    var startError: Error?
    init(order: CaptureOrder) { self.order = order }
    func start(deviceID: String, workspace: RecordingWorkspace, epoch: Double) async throws {
        order.events.append("camera.start")
        startedEpoch = epoch
        self.deviceID = deviceID
        if let startError { throw startError }
    }
    func stop() async throws { order.events.append("camera.stop") }
}

@MainActor
private final class FakeWorkspaceFactory: RecordingWorkspaceCreating {
    let root: URL
    let workspace: RecordingWorkspace
    init(settings: RecordingSettings = .fixture) throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
    }
    func create(settings: RecordingSettings) throws -> RecordingWorkspace { workspace }
}

@MainActor
private struct Fixture {
    let order = CaptureOrder()
    let coordinator = RecordingCoordinator()
    let factory: FakeWorkspaceFactory
    let screen: FakeScreenCapture
    let camera: FakeCameraCapture
    let controller: RecordingSessionController
    private let settings: RecordingSettings
    init(
        settings: RecordingSettings = .fixture,
        sleeper: any CountdownSleeping = ImmediateCountdownSleeper()
    ) throws {
        self.settings = settings
        factory = try FakeWorkspaceFactory(settings: settings)
        screen = FakeScreenCapture(order: order)
        camera = FakeCameraCapture(order: order)
        controller = RecordingSessionController(
            coordinator: coordinator, screenCapture: screen, cameraCapture: camera,
            workspaceFactory: factory, clock: FixedRecordingClock(), countdownSleeper: sleeper
        )
    }
    func removeWorkspace() { try? FileManager.default.removeItem(at: factory.root) }
    func persistedManifest() throws -> RecordingManifest {
        try JSONDecoder().decode(RecordingManifest.self, from: Data(contentsOf: factory.workspace.manifestURL))
    }
    var configuration: RecordingSessionConfiguration {
        RecordingSessionConfiguration(source: SessionTestScreenSelection(), settings: settings)
    }
}

private extension RecordingSettings {
    static var fixture: RecordingSettings {
        RecordingSettings(includeSystemAudio: true, overlayShape: .roundedSquare, overlaySize: .large,
                          cameraDeviceID: "test-camera", microphoneDeviceID: "test-microphone")
    }

    static var screenOnly: RecordingSettings {
        var settings = RecordingSettings.default
        settings.includeCamera = false
        settings.includeMicrophone = false
        return settings
    }
}

private extension RecordingSessionConfiguration {
    static var fixture: RecordingSessionConfiguration {
        RecordingSessionConfiguration(source: SessionTestScreenSelection(), settings: .fixture)
    }
}

@MainActor
private final class SessionTestScreenSelection: ScreenCaptureSelection {
    var filter: SCContentFilter { fatalError("Capture fake never reads the hardware filter") }
    let title = "Test Display"
    let kind = CaptureSourceKind.display
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let presentationFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let pointPixelScale = CGFloat(2)
}
