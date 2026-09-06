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
    var includeCamera: Bool = true
    var includeMicrophone: Bool = true
    var overlayShape: OverlayShape
    var overlaySize: OverlaySize
    var cameraDeviceID: String?
    var microphoneDeviceID: String?

    static let `default` = RecordingSettings(
        includeSystemAudio: false,
        includeCamera: true,
        includeMicrophone: true,
        overlayShape: .circle,
        overlaySize: .medium,
        cameraDeviceID: nil,
        microphoneDeviceID: nil
    )
}

extension RecordingSettings {
    private enum CodingKeys: String, CodingKey {
        case includeSystemAudio
        case includeCamera
        case includeMicrophone
        case overlayShape
        case overlaySize
        case cameraDeviceID
        case microphoneDeviceID
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        includeSystemAudio = try values.decode(Bool.self, forKey: .includeSystemAudio)
        includeCamera = try values.decodeIfPresent(Bool.self, forKey: .includeCamera) ?? true
        includeMicrophone = try values.decodeIfPresent(Bool.self, forKey: .includeMicrophone) ?? true
        overlayShape = try values.decode(OverlayShape.self, forKey: .overlayShape)
        overlaySize = try values.decode(OverlaySize.self, forKey: .overlaySize)
        cameraDeviceID = try values.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        microphoneDeviceID = try values.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
    }
}
