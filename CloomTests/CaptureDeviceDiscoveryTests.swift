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
}

@MainActor
final class FakeCaptureDeviceDiscovery: CaptureDeviceDiscovering {
    let cameras: [CaptureDeviceOption]
    let microphones: [CaptureDeviceOption]

    init(cameras: [CaptureDeviceOption], microphones: [CaptureDeviceOption]) {
        self.cameras = cameras
        self.microphones = microphones
    }

    func devices(for kind: CaptureDeviceKind) -> [CaptureDeviceOption] {
        switch kind {
        case .camera:
            cameras
        case .microphone:
            microphones
        }
    }
}
