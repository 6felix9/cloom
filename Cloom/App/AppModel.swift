import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var permissions: [CapturePermission: PermissionState]

    let recordingCoordinator: RecordingCoordinator

    private let permissionChecker: PermissionChecking

    init(
        permissionChecker: PermissionChecking,
        recordingCoordinator: RecordingCoordinator = RecordingCoordinator()
    ) {
        self.permissionChecker = permissionChecker
        self.recordingCoordinator = recordingCoordinator
        self.permissions = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map { ($0, .notDetermined) }
        )
    }

    static let live = AppModel(permissionChecker: SystemPermissionChecker())

    func refreshPermissions() async {
        for permission in CapturePermission.allCases {
            permissions[permission] = permissionChecker.status(for: permission)
        }
    }

    func request(_ permission: CapturePermission) async {
        permissions[permission] = await permissionChecker.request(permission)
    }

    func openSettings(for permission: CapturePermission) {
        permissionChecker.openSettings(for: permission)
    }
}
