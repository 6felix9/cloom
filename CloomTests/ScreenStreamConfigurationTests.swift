import CoreMedia
import CoreVideo
import XCTest
@testable import Cloom

final class ScreenStreamConfigurationTests: XCTestCase {
    func testMicrophoneOnlyConfiguration() {
        let configuration = ScreenStreamConfigurationFactory.make(
            contentSize: CGSize(width: 1920, height: 1080),
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
            contentSize: CGSize(width: 1920, height: 1080),
            includeSystemAudio: true,
            includeMicrophone: true,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertTrue(configuration.capturesAudio)
    }

    func testScreenOnlyConfigurationDoesNotCaptureMicrophone() {
        let configuration = ScreenStreamConfigurationFactory.make(
            contentSize: CGSize(width: 1920, height: 1080),
            includeSystemAudio: false,
            includeMicrophone: false,
            microphoneDeviceID: "stored-but-disabled"
        )

        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertNil(configuration.microphoneCaptureDeviceID)
    }

    func testSystemAudioDoesNotRequireMicrophoneCapture() {
        let configuration = ScreenStreamConfigurationFactory.make(
            contentSize: CGSize(width: 1920, height: 1080),
            includeSystemAudio: true,
            includeMicrophone: false,
            microphoneDeviceID: nil
        )

        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertTrue(configuration.capturesAudio)
    }

    func testStreamKeepsContentAspectRatioInsideCanvas() {
        XCTAssertEqual(streamSize(for: CGSize(width: 1440, height: 900)), [1728, 1080], "16:10 display")
        XCTAssertEqual(streamSize(for: CGSize(width: 800, height: 1200)), [720, 1080], "Portrait window")
        XCTAssertEqual(streamSize(for: CGSize(width: 400, height: 300)), [1440, 1080], "Small window scales up")
        XCTAssertEqual(streamSize(for: CGSize(width: 1000, height: 700)), [1542, 1080], "Rounds to even")
        XCTAssertEqual(streamSize(for: CGSize(width: 3000, height: 400)), [1920, 256], "Wide window fits width")
        XCTAssertEqual(streamSize(for: .zero), [1920, 1080], "Unknown size")
    }

    func testWindowCaptureScalesToFitWithoutShadows() {
        let configuration = ScreenStreamConfigurationFactory.make(
            contentSize: CGSize(width: 400, height: 300),
            includeSystemAudio: false,
            includeMicrophone: false,
            microphoneDeviceID: nil
        )

        XCTAssertTrue(configuration.scalesToFit)
        XCTAssertTrue(configuration.ignoreShadowsSingleWindow)
        XCTAssertTrue(configuration.preservesAspectRatio)
    }

    private func streamSize(for contentSize: CGSize) -> [Int] {
        let configuration = ScreenStreamConfigurationFactory.make(
            contentSize: contentSize,
            includeSystemAudio: false,
            includeMicrophone: false,
            microphoneDeviceID: nil
        )
        return [configuration.width, configuration.height]
    }
}
