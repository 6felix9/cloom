import Foundation

enum CapturePermission: String, CaseIterable, Codable, Sendable {
    case screen
    case camera
    case microphone
}

enum PermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol PermissionChecking: AnyObject {
    func status(for permission: CapturePermission) -> PermissionState
    func request(_ permission: CapturePermission) async -> PermissionState
    func openSettings(for permission: CapturePermission)
}
