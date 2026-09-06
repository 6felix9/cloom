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
    @Published private(set) var cameraDevices: [CaptureDeviceOption] = []
    @Published private(set) var microphoneDevices: [CaptureDeviceOption] = []

    let recordingCoordinator: RecordingCoordinator

    private let permissionChecker: PermissionChecking
    private let settingsStore: SettingsStoring
    private let deviceDiscovery: CaptureDeviceDiscovering

    init(
        permissionChecker: PermissionChecking,
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        recordingCoordinator: RecordingCoordinator = RecordingCoordinator(),
        deviceDiscovery: CaptureDeviceDiscovering = AVCaptureDeviceDiscovery()
    ) {
        self.permissionChecker = permissionChecker
        self.settingsStore = settingsStore
        self.recordingCoordinator = recordingCoordinator
        self.deviceDiscovery = deviceDiscovery
        self.settings = settingsStore.load()
        self.permissions = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map { ($0, .notDetermined) }
        )
    }

    static let live = AppModel(
        permissionChecker: SystemPermissionChecker(),
        settingsStore: UserDefaultsSettingsStore()
    )

    var isReadyToConfigure: Bool {
        CapturePermission.allCases.allSatisfy {
            permissions[$0] == .authorized
        }
    }

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

    func refreshDevices() async {
        cameraDevices = deviceDiscovery.devices(for: .camera)
        microphoneDevices = deviceDiscovery.devices(for: .microphone)

        if !cameraDevices.contains(where: { $0.id == settings.cameraDeviceID }) {
            settings.cameraDeviceID = cameraDevices.first?.id
        }

        if !microphoneDevices.contains(where: { $0.id == settings.microphoneDeviceID }) {
            settings.microphoneDeviceID = microphoneDevices.first?.id
        }
    }

    func selectCamera(id: String) {
        settings.cameraDeviceID = id
    }

    func selectMicrophone(id: String) {
        settings.microphoneDeviceID = id
    }
}
