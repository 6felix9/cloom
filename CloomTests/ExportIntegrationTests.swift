import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import Cloom

@MainActor
final class ExportIntegrationTests: XCTestCase {
    func testStartSnapshotsSettingsForRecordingControls() async throws {
        var screenOnly = RecordingSettings.default
        screenOnly.includeCamera = false
        screenOnly.includeMicrophone = false
        let coordinator = RecordingCoordinator()
        let order = CaptureOrder()
        let factory = try FakeWorkspaceFactory(settings: screenOnly)
        defer { try? FileManager.default.removeItem(at: factory.root) }
        let controller = RecordingSessionController(
            coordinator: coordinator,
            screenCapture: FakeScreenCapture(order: order),
            cameraCapture: FakeCameraCapture(order: order),
            workspaceFactory: factory,
            clock: FixedClock(),
            countdownSleeper: ImmediateSleeper()
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [.screen: .authorized]),
            settingsStore: InMemorySettingsStore(value: screenOnly),
            recordingCoordinator: coordinator,
            sourcePicker: FakeSourcePicker(),
            sessionController: controller,
            exporter: FakeExporter(result: .success(URL(fileURLWithPath: "/tmp/cloom-snapshot.mp4")))
        )

        await model.selectCaptureSource()
        await model.startRecording()
        model.settings.includeCamera = true
        model.settings.includeMicrophone = true

        XCTAssertEqual(model.activeRecordingSettings?.includeCamera, false)
        XCTAssertEqual(model.activeRecordingSettings?.includeMicrophone, false)

        await model.stopRecording()
    }

    func testStopRecordingTriggersExporterAndFinishes() async throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/cloom-finished.mp4")
        let fakeExporter = FakeExporter(result: .success(expectedURL))
        let coordinator = RecordingCoordinator()
        let order = CaptureOrder()
        let factory = try FakeWorkspaceFactory()
        defer { try? FileManager.default.removeItem(at: factory.root) }

        let controller = RecordingSessionController(
            coordinator: coordinator,
            screenCapture: FakeScreenCapture(order: order),
            cameraCapture: FakeCameraCapture(order: order),
            workspaceFactory: factory,
            clock: FixedClock(),
            countdownSleeper: ImmediateSleeper()
        )

        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: .testSettings),
            recordingCoordinator: coordinator,
            sessionController: controller,
            exporter: fakeExporter
        )

        try await controller.start(configuration: .init(source: FakeSource(), settings: .testSettings))
        XCTAssertEqual(coordinator.phase, .recording)

        await model.stopRecording()

        XCTAssertEqual(coordinator.phase, .finished(outputURL: expectedURL))
        XCTAssertEqual(fakeExporter.exportCallCount, 1)
    }

    func testExportFailureTransitionsToFailedState() async throws {
        let fakeExporter = FakeExporter(result: .failure(VideoCompositorError.missingScreenVideo))
        let coordinator = RecordingCoordinator()
        let order = CaptureOrder()
        let factory = try FakeWorkspaceFactory()
        defer { try? FileManager.default.removeItem(at: factory.root) }

        let controller = RecordingSessionController(
            coordinator: coordinator,
            screenCapture: FakeScreenCapture(order: order),
            cameraCapture: FakeCameraCapture(order: order),
            workspaceFactory: factory,
            clock: FixedClock(),
            countdownSleeper: ImmediateSleeper()
        )

        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: .testSettings),
            recordingCoordinator: coordinator,
            sessionController: controller,
            exporter: fakeExporter
        )

        try await controller.start(configuration: .init(source: FakeSource(), settings: .testSettings))
        XCTAssertEqual(coordinator.phase, .recording)

        await model.stopRecording()

        if case .failed = coordinator.phase {
            XCTAssertNotNil(model.recordingError)
        } else {
            XCTFail("Expected failed phase, got \(coordinator.phase)")
        }
    }

    func testRetryExportRetriesAndCanSucceed() async throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/cloom-retry-success.mp4")
        let fakeExporter = FakeExporter(result: .failure(VideoCompositorError.missingScreenVideo))
        let coordinator = RecordingCoordinator()
        let order = CaptureOrder()
        let factory = try FakeWorkspaceFactory()
        defer { try? FileManager.default.removeItem(at: factory.root) }

        let controller = RecordingSessionController(
            coordinator: coordinator,
            screenCapture: FakeScreenCapture(order: order),
            cameraCapture: FakeCameraCapture(order: order),
            workspaceFactory: factory,
            clock: FixedClock(),
            countdownSleeper: ImmediateSleeper()
        )

        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: .testSettings),
            recordingCoordinator: coordinator,
            sessionController: controller,
            exporter: fakeExporter
        )

        try await controller.start(configuration: .init(source: FakeSource(), settings: .testSettings))
        XCTAssertEqual(coordinator.phase, .recording)

        await model.stopRecording()

        fakeExporter.result = .success(expectedURL)
        await model.retryExport()

        XCTAssertEqual(coordinator.phase, .finished(outputURL: expectedURL))
    }
}

private extension RecordingSettings {
    static var testSettings: RecordingSettings {
        RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "camera-1",
            microphoneDeviceID: "mic-1"
        )
    }
}

private final class FakeExporter: RecordingExporting, @unchecked Sendable {
    var result: Result<URL, Error>
    private(set) var exportCallCount = 0

    init(result: Result<URL, Error>) {
        self.result = result
    }

    func export(
        workspace: RecordingWorkspace,
        muteIntervals: [MuteInterval],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        exportCallCount += 1
        progress(0.5)
        progress(1.0)
        return try result.get()
    }
}

@MainActor
private final class CaptureOrder { var events: [String] = [] }

@MainActor
private final class FakeScreenCapture: ScreenCapturing {
    let order: CaptureOrder
    init(order: CaptureOrder) { self.order = order }
    func start(selection: any ScreenCaptureSelection, configuration: SCStreamConfiguration,
               workspace: RecordingWorkspace, epoch: Double) async throws {
        order.events.append("screen.start")
    }
    func stop() async throws { order.events.append("screen.stop") }
}

@MainActor
private final class FakeCameraCapture: CameraCapturing {
    let order: CaptureOrder
    let previewSession = AVCaptureSession()
    init(order: CaptureOrder) { self.order = order }
    func start(deviceID: String, workspace: RecordingWorkspace, epoch: Double) async throws {
        order.events.append("camera.start")
    }
    func stop() async throws { order.events.append("camera.stop") }
}

@MainActor
private final class FakeWorkspaceFactory: RecordingWorkspaceCreating {
    let root: URL
    let workspace: RecordingWorkspace
    init(settings: RecordingSettings = .testSettings) throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
    }
    func create(settings: RecordingSettings) throws -> RecordingWorkspace { workspace }
}

@MainActor
private final class FakeSourcePicker: ScreenSourcePicking {
    func present() async throws -> (any ScreenCaptureSelection)? { FakeSource() }
}

private struct FixedClock: RecordingClock {
    func nowSeconds() -> Double { 100 }
}

private struct ImmediateSleeper: CountdownSleeping {
    func sleepForCountdown() async throws {}
}

@MainActor
private final class FakeSource: ScreenCaptureSelection {
    var filter: SCContentFilter { fatalError("Filter unused in fake") }
    let title = "Test Screen"
    let kind = CaptureSourceKind.display
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let presentationFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let pointPixelScale = CGFloat(2)
}
