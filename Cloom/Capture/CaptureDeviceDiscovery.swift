import AVFoundation

@MainActor
protocol CaptureDeviceDiscovering: AnyObject {
    func devices(for kind: CaptureDeviceKind) -> [CaptureDeviceOption]
}

final class AVCaptureDeviceDiscovery: CaptureDeviceDiscovering {
    func devices(for kind: CaptureDeviceKind) -> [CaptureDeviceOption] {
        let devices: [AVCaptureDevice]

        switch kind {
        case .camera:
            devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external, .builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified
            ).devices
        case .microphone:
            devices = AVCaptureDevice.devices(for: .audio)
        }

        return devices
            .sorted {
                $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
            }
            .map {
                CaptureDeviceOption(id: $0.uniqueID, name: $0.localizedName, kind: kind)
            }
    }
}
