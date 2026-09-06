import CoreMedia
import CoreVideo
import XCTest
@testable import Cloom

final class ScreenStreamConfigurationTests: XCTestCase {
    func testMicrophoneOnlyConfiguration() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: false,
            includeMicrophone: true,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertEqual(configuration.width, 1920)
        XCTAssertEqual(configuration.height, 1080)
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(configuration.queueDepth, 5)
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertTrue(configuration.showsCursor)
        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertEqual(configuration.microphoneCaptureDeviceID, "mic-1")
        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
    }

    func testCombinedConfigurationAddsSystemAudio() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: true,
            includeMicrophone: true,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertTrue(configuration.capturesAudio)
    }

    func testScreenOnlyConfigurationDoesNotCaptureMicrophone() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: false,
            includeMicrophone: false,
            microphoneDeviceID: "stored-but-disabled"
        )

        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertNil(configuration.microphoneCaptureDeviceID)
    }

    func testSystemAudioDoesNotRequireMicrophoneCapture() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: true,
            includeMicrophone: false,
            microphoneDeviceID: nil
        )

        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertTrue(configuration.capturesAudio)
    }
}
