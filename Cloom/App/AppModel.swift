import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var permissions: [CapturePermission: PermissionState]
    @Published var settings: RecordingSettings {
        didSet {
            settingsStore.save(settings)
        }
    }

    let recordingCoordinator: RecordingCoordinator

    private let permissionChecker: PermissionChecking
    private let settingsStore: SettingsStoring

    init(
        permissionChecker: PermissionChecking,
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        recordingCoordinator: RecordingCoordinator = RecordingCoordinator()
    ) {
        self.permissionChecker = permissionChecker
        self.settingsStore = settingsStore
        self.recordingCoordinator = recordingCoordinator
        self.settings = settingsStore.load()
        self.permissions = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map { ($0, .notDetermined) }
        )
    }

    static let live = AppModel(
        permissionChecker: SystemPermissionChecker(),
        settingsStore: UserDefaultsSettingsStore()
    )

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
