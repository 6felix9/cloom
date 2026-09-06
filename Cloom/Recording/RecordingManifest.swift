import Foundation

enum RecordingCaptureState: String, Codable, Equatable, Sendable {
    case preparing
    case capturing
    case captureComplete
    case failed
}

struct RecordingManifest: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let settings: RecordingSettings
    var captureState: RecordingCaptureState
    var failureMessage: String?
}
