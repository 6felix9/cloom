import AppKit
import AVFoundation
import CoreGraphics
import Foundation

@MainActor
final class SystemPermissionChecker: PermissionChecking {
    private enum Key {
        static let screenCapturePermissionRequested = "screenCapturePermissionRequested.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func status(for permission: CapturePermission) -> PermissionState {
        switch permission {
        case .screen:
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }
            return defaults.bool(forKey: Key.screenCapturePermissionRequested)
                ? .denied
                : .notDetermined
        case .camera:
            return permissionState(for: AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return permissionState(for: AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    func request(_ permission: CapturePermission) async -> PermissionState {
        switch permission {
        case .screen:
            let granted = CGRequestScreenCaptureAccess()
            defaults.set(true, forKey: Key.screenCapturePermissionRequested)
            return granted ? .authorized : .denied
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : status(for: .camera)
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : status(for: .microphone)
        }
    }

    func openSettings(for permission: CapturePermission) {
        let pane: String
        switch permission {
        case .screen:
            pane = "Privacy_ScreenCapture"
        case .camera:
            pane = "Privacy_Camera"
        case .microphone:
            pane = "Privacy_Microphone"
        }

        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func permissionState(for status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .denied
        }
    }
}
