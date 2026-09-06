import XCTest
@testable import Cloom

final class RecordingControlVisibilityTests: XCTestCase {
    func testCameraAndMicrophoneExposeAllRelatedControls() {
        let visibility = RecordingControlVisibility(settings: settings(camera: true, microphone: true))

        XCTAssertTrue(visibility.showsCameraToggle)
        XCTAssertTrue(visibility.showsOverlayControls)
        XCTAssertTrue(visibility.showsMicrophoneMute)
    }

    func testCameraOnlyHidesMicrophoneMute() {
        let visibility = RecordingControlVisibility(settings: settings(camera: true, microphone: false))

        XCTAssertTrue(visibility.showsCameraToggle)
        XCTAssertTrue(visibility.showsOverlayControls)
        XCTAssertFalse(visibility.showsMicrophoneMute)
    }

    func testMicrophoneOnlyHidesCameraAndOverlayControls() {
        let visibility = RecordingControlVisibility(settings: settings(camera: false, microphone: true))

        XCTAssertFalse(visibility.showsCameraToggle)
        XCTAssertFalse(visibility.showsOverlayControls)
        XCTAssertTrue(visibility.showsMicrophoneMute)
    }

    func testScreenOnlyHidesEveryOptionalControl() {
        let visibility = RecordingControlVisibility(settings: settings(camera: false, microphone: false))

        XCTAssertFalse(visibility.showsCameraToggle)
        XCTAssertFalse(visibility.showsOverlayControls)
        XCTAssertFalse(visibility.showsMicrophoneMute)
    }

    private func settings(camera: Bool, microphone: Bool) -> RecordingSettings {
        var settings = RecordingSettings.default
        settings.includeCamera = camera
        settings.includeMicrophone = microphone
        return settings
    }
}
