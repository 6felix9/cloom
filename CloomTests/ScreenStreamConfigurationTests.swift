import CoreMedia
import CoreVideo
import XCTest
@testable import Cloom

final class ScreenStreamConfigurationTests: XCTestCase {
    func testMicrophoneOnlyConfiguration() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: false,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertEqual(configuration.width, 1920)
        XCTAssertEqual(configuration.height, 1080)
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertEqual(configuration.microphoneCaptureDeviceID, "mic-1")
        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
    }

    func testCombinedConfigurationAddsSystemAudio() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: true,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertTrue(configuration.capturesAudio)
    }
}
