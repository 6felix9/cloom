import CoreGraphics
import ScreenCaptureKit
import XCTest
@testable import Cloom

@MainActor
final class AppModelTests: XCTestCase {
    func testRefreshReadsEveryRequiredPermission() async {
        let checker = FakePermissionChecker(statuses: [
            .screen: .authorized,
            .camera: .denied,
            .microphone: .authorized,
        ])
        let model = AppModel(permissionChecker: checker)

        await model.refreshPermissions()

        XCTAssertEqual(model.permissions[.screen], .authorized)
        XCTAssertEqual(model.permissions[.camera], .denied)
        XCTAssertEqual(model.permissions[.microphone], .authorized)
        XCTAssertEqual(checker.statusRequests, Set(CapturePermission.allCases))
    }

    func testRequestStoresReturnedStatus() async {
        let checker = FakePermissionChecker(statuses: [.camera: .notDetermined])
        checker.requestResults[.camera] = .authorized
        let model = AppModel(permissionChecker: checker)

        await model.request(.camera)

        XCTAssertEqual(model.permissions[.camera], .authorized)
    }

    func testCaptureSourceCancellationPreservesExistingSelection() async {
        let selection = FakeScreenCaptureSelection(title: "Display 1")
        let picker = FakeScreenSourcePicker(results: [.selection(selection), .cancellation])
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(),
            sourcePicker: picker
        )

        await model.selectCaptureSource()
        await model.selectCaptureSource()

        XCTAssertTrue(model.selectedCaptureSource === selection)
        XCTAssertNil(model.captureSourceError)
    }

    func testCaptureSourceStartupErrorPreservesExistingSelectionAndSurfacesError() async {
        let selection = FakeScreenCaptureSelection(title: "Window 1")
        let picker = FakeScreenSourcePicker(results: [.selection(selection), .failure(.unavailable)])
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(),
            sourcePicker: picker
        )

        await model.selectCaptureSource()
        await model.selectCaptureSource()

        XCTAssertTrue(model.selectedCaptureSource === selection)
        XCTAssertNotNil(model.captureSourceError)
    }

    func testReadinessRequiresASelectedSourceAndDeviceIDs() async {
        let statuses = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map {
                ($0, PermissionState.authorized)
            }
        )
        let settings = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "camera-1",
            microphoneDeviceID: "mic-1"
        )
        let selection = FakeScreenCaptureSelection(title: "Display 1")
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: statuses),
            settingsStore: InMemorySettingsStore(value: settings),
            sourcePicker: FakeScreenSourcePicker(results: [.selection(selection)])
        )

        await model.refreshPermissions()
        XCTAssertFalse(model.isReadyToRecord)

        await model.selectCaptureSource()

        XCTAssertTrue(model.isReadyToRecord)
    }

    func testScreenOnlyReadinessRequiresOnlyScreenPermissionAndSource() async {
        var settings = RecordingSettings.default
        settings.includeCamera = false
        settings.includeMicrophone = false
        let selection = FakeScreenCaptureSelection(title: "Display 1")
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [
                .screen: .authorized,
                .camera: .denied,
                .microphone: .denied,
            ]),
            settingsStore: InMemorySettingsStore(value: settings),
            sourcePicker: FakeScreenSourcePicker(results: [.selection(selection)])
        )

        await model.refreshPermissions()
        await model.selectCaptureSource()

        XCTAssertTrue(model.isReadyToRecord)
    }

    func testEnabledMicrophoneRequiresASelectedDevice() async {
        var settings = RecordingSettings.default
        settings.includeCamera = false
        settings.microphoneDeviceID = nil
        let selection = FakeScreenCaptureSelection(title: "Display 1")
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [
                .screen: .authorized,
                .camera: .denied,
                .microphone: .authorized,
            ]),
            settingsStore: InMemorySettingsStore(value: settings),
            sourcePicker: FakeScreenSourcePicker(results: [.selection(selection)])
        )

        await model.refreshPermissions()
        await model.selectCaptureSource()

        XCTAssertFalse(model.isReadyToRecord)
    }
}

@MainActor
final class FakePermissionChecker: PermissionChecking {
    var statuses: [CapturePermission: PermissionState]
    var requestResults: [CapturePermission: PermissionState] = [:]
    private(set) var statusRequests: Set<CapturePermission> = []
    private(set) var openedSettings: [CapturePermission] = []

    init(statuses: [CapturePermission: PermissionState]) {
        self.statuses = statuses
    }

    func status(for permission: CapturePermission) -> PermissionState {
        statusRequests.insert(permission)
        return statuses[permission] ?? .notDetermined
    }

    func request(_ permission: CapturePermission) async -> PermissionState {
        requestResults[permission] ?? statuses[permission] ?? .notDetermined
    }

    func openSettings(for permission: CapturePermission) {
        openedSettings.append(permission)
    }
}

@MainActor
final class FakeScreenCaptureSelection: ScreenCaptureSelection {
    private(set) var title: String
    let kind: CaptureSourceKind = .display
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let presentationFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let pointPixelScale: CGFloat = 1

    var filter: SCContentFilter {
        fatalError("FakeScreenCaptureSelection.filter should not be read by AppModel tests")
    }

    init(title: String) {
        self.title = title
    }
}

@MainActor
final class FakeScreenSourcePicker: ScreenSourcePicking {
    enum Result {
        case selection(any ScreenCaptureSelection)
        case cancellation
        case failure(FakeScreenSourcePickerError)
    }

    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func present() async throws -> (any ScreenCaptureSelection)? {
        switch results.removeFirst() {
        case let .selection(selection):
            return selection
        case .cancellation:
            return nil
        case let .failure(error):
            throw error
        }
    }
}

enum FakeScreenSourcePickerError: Error {
    case unavailable
}
