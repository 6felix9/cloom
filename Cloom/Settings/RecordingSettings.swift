import Foundation

enum OverlayShape: String, Codable, CaseIterable, Sendable {
    case circle
    case roundedSquare
}

enum OverlaySize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

struct RecordingSettings: Codable, Equatable, Sendable {
    var includeSystemAudio: Bool
    var overlayShape: OverlayShape
    var overlaySize: OverlaySize
    var cameraDeviceID: String?
    var microphoneDeviceID: String?

    static let `default` = RecordingSettings(
        includeSystemAudio: false,
        overlayShape: .circle,
        overlaySize: .medium,
        cameraDeviceID: nil,
        microphoneDeviceID: nil
    )
}
