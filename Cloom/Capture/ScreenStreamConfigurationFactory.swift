import CoreMedia
import CoreVideo
import ScreenCaptureKit

enum ScreenStreamConfigurationFactory {
    static func make(
        includeSystemAudio: Bool,
        microphoneDeviceID: String
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 1920
        configuration.height = 1080
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = microphoneDeviceID
        configuration.capturesAudio = includeSystemAudio
        configuration.excludesCurrentProcessAudio = true
        return configuration
    }
}
