import Foundation
import XCTest
@testable import Cloom

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchMVPChoices() {
        let settings = RecordingSettings.default

        XCTAssertFalse(settings.includeSystemAudio)
        XCTAssertTrue(settings.includeCamera)
        XCTAssertTrue(settings.includeMicrophone)
        XCTAssertEqual(settings.overlayShape, .circle)
        XCTAssertEqual(settings.overlaySize, .medium)
        XCTAssertNil(settings.cameraDeviceID)
        XCTAssertNil(settings.microphoneDeviceID)
    }

    func testLegacySettingsDecodeWithInputsEnabled() throws {
        let data = Data(
            #"{"includeSystemAudio":false,"overlayShape":"circle","overlaySize":"medium","cameraDeviceID":"camera-1","microphoneDeviceID":"mic-1"}"#.utf8
        )

        let settings = try JSONDecoder().decode(RecordingSettings.self, from: data)

        XCTAssertTrue(settings.includeCamera)
        XCTAssertTrue(settings.includeMicrophone)
        XCTAssertEqual(settings.cameraDeviceID, "camera-1")
        XCTAssertEqual(settings.microphoneDeviceID, "mic-1")
    }

    func testDisablingInputsPreservesSelectedDeviceIDs() {
        var settings = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "camera-1",
            microphoneDeviceID: "mic-1"
        )

        settings.includeCamera = false
        settings.includeMicrophone = false

        XCTAssertEqual(settings.cameraDeviceID, "camera-1")
        XCTAssertEqual(settings.microphoneDeviceID, "mic-1")
    }

    func testUserDefaultsStoreRoundTripsSettings() throws {
        let suiteName = "CloomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let expected = RecordingSettings(
            includeSystemAudio: true,
            overlayShape: .roundedSquare,
            overlaySize: .large,
            cameraDeviceID: "camera-1",
            microphoneDeviceID: "mic-1"
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testAppModelLoadsAndPersistsSettings() {
        let initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .roundedSquare,
            overlaySize: .small,
            cameraDeviceID: "camera-2",
            microphoneDeviceID: "mic-2"
        )
        let store = InMemorySettingsStore(value: initial)
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: store
        )

        XCTAssertEqual(model.settings, initial)

        model.settings.includeSystemAudio = true

        XCTAssertTrue(store.value.includeSystemAudio)
    }
}
