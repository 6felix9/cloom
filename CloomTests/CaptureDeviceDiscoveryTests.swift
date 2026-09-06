import XCTest
@testable import Cloom

@MainActor
final class CaptureDeviceDiscoveryTests: XCTestCase {
    func testRefreshFallsBackToFirstAvailableDevices() async {
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [.init(id: "camera-1", name: "FaceTime HD", kind: .camera)],
            microphones: [.init(id: "mic-1", name: "MacBook Microphone", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "camera-1")
        XCTAssertEqual(model.settings.microphoneDeviceID, "mic-1")
    }

    func testRefreshPreservesAnAvailableStoredSelection() async {
        let initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "camera-2",
            microphoneDeviceID: "mic-2"
        )
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [
                .init(id: "camera-1", name: "Built-in", kind: .camera),
                .init(id: "camera-2", name: "Studio", kind: .camera),
            ],
            microphones: [.init(id: "mic-2", name: "USB Mic", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: initial),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "camera-2")
        XCTAssertEqual(model.settings.microphoneDeviceID, "mic-2")
    }

    func testRefreshUsesPreferredDevicesWhenStoredSelectionsAreUnavailable() async {
        let initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "removed-camera",
            microphoneDeviceID: "removed-mic"
        )
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [
                .init(id: "camera-1", name: "Built-in", kind: .camera),
                .init(id: "camera-2", name: "Studio", kind: .camera),
            ],
            microphones: [
                .init(id: "mic-1", name: "Built-in Microphone", kind: .microphone),
                .init(id: "mic-2", name: "USB Microphone", kind: .microphone),
            ],
            preferredCameraID: "camera-2",
            preferredMicrophoneID: "mic-2"
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: initial),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "camera-2")
        XCTAssertEqual(model.settings.microphoneDeviceID, "mic-2")
    }

    func testRefreshRetainsUnavailableSelectionsWhileInputsAreDisabled() async {
        var initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "disconnected-camera",
            microphoneDeviceID: "disconnected-mic"
        )
        initial.includeCamera = false
        initial.includeMicrophone = false
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [.init(id: "built-in-camera", name: "Built-in", kind: .camera)],
            microphones: [.init(id: "built-in-mic", name: "Built-in", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: initial),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "disconnected-camera")
        XCTAssertEqual(model.settings.microphoneDeviceID, "disconnected-mic")
    }

    func testReenablingInputsReconcilesUnavailableRetainedSelections() async {
        var initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "disconnected-camera",
            microphoneDeviceID: "disconnected-mic"
        )
        initial.includeCamera = false
        initial.includeMicrophone = false
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [.init(id: "built-in-camera", name: "Built-in", kind: .camera)],
            microphones: [.init(id: "built-in-mic", name: "Built-in", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: initial),
            deviceDiscovery: discovery
        )
        await model.refreshDevices()

        model.setCameraCaptureEnabled(true)
        model.setMicrophoneCaptureEnabled(true)

        XCTAssertEqual(model.settings.cameraDeviceID, "built-in-camera")
        XCTAssertEqual(model.settings.microphoneDeviceID, "built-in-mic")
    }
}

@MainActor
final class FakeCaptureDeviceDiscovery: CaptureDeviceDiscovering {
    let cameras: [CaptureDeviceOption]
    let microphones: [CaptureDeviceOption]
    let preferredCameraID: String?
    let preferredMicrophoneID: String?

    init(
        cameras: [CaptureDeviceOption],
        microphones: [CaptureDeviceOption],
        preferredCameraID: String? = nil,
        preferredMicrophoneID: String? = nil
    ) {
        self.cameras = cameras
        self.microphones = microphones
        self.preferredCameraID = preferredCameraID
        self.preferredMicrophoneID = preferredMicrophoneID
    }

    func devices(for kind: CaptureDeviceKind) -> [CaptureDeviceOption] {
        switch kind {
        case .camera:
            cameras
        case .microphone:
            microphones
        }
    }

    func preferredDeviceID(for kind: CaptureDeviceKind) -> String? {
        switch kind {
        case .camera:
            preferredCameraID
        case .microphone:
            preferredMicrophoneID
        }
    }
}
