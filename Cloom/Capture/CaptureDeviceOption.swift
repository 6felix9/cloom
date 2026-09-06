import Foundation

enum CaptureDeviceKind: String, Codable, Sendable {
    case camera
    case microphone
}

struct CaptureDeviceOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: CaptureDeviceKind
}
