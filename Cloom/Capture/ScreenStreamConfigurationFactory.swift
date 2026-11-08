import CoreMedia
import CoreVideo
import ScreenCaptureKit

enum ScreenStreamConfigurationFactory {
    static func make(
        contentSize: CGSize,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        microphoneDeviceID: String?
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let size = streamSize(for: contentSize)
        configuration.width = size.width
        configuration.height = size.height
        // Window capture otherwise only scales down and includes the shadow, letterboxing the content unpredictably.
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.captureMicrophone = includeMicrophone
        configuration.microphoneCaptureDeviceID = includeMicrophone ? microphoneDeviceID : nil
        configuration.capturesAudio = includeSystemAudio
        configuration.excludesCurrentProcessAudio = true
        return configuration
    }

    /// Content aspect ratio fitted inside 1920×1080 with even dimensions, so the raw track carries no letterbox.
    private static func streamSize(for contentSize: CGSize) -> (width: Int, height: Int) {
        guard contentSize.width > 0, contentSize.height > 0 else { return (1920, 1080) }
        let scale = min(1920 / contentSize.width, 1080 / contentSize.height)
        func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (min(even(contentSize.width * scale), 1920), min(even(contentSize.height * scale), 1080))
    }
}
