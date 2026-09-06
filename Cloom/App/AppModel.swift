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
    @Published private(set) var selectedCaptureSource: (any ScreenCaptureSelection)?
    @Published private(set) var captureSourceError: Error?

    let recordingCoordinator: RecordingCoordinator

    private let permissionChecker: PermissionChecking
    private let settingsStore: SettingsStoring
    private let deviceDiscovery: CaptureDeviceDiscovering
    private let sourcePicker: ScreenSourcePicking

    init(
        permissionChecker: PermissionChecking,
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        recordingCoordinator: RecordingCoordinator = RecordingCoordinator(),
        deviceDiscovery: CaptureDeviceDiscovering = AVCaptureDeviceDiscovery(),
        sourcePicker: ScreenSourcePicking = ScreenSourcePicker()
    ) {
        self.permissionChecker = permissionChecker
        self.settingsStore = settingsStore
        self.recordingCoordinator = recordingCoordinator
        self.deviceDiscovery = deviceDiscovery
        self.sourcePicker = sourcePicker
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

    var isReadyToRecord: Bool {
        isReadyToConfigure &&
            selectedCaptureSource != nil &&
            settings.cameraDeviceID != nil &&
            settings.microphoneDeviceID != nil
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
            settings.cameraDeviceID = fallbackDeviceID(for: .camera, in: cameraDevices)
        }

        if !microphoneDevices.contains(where: { $0.id == settings.microphoneDeviceID }) {
            settings.microphoneDeviceID = fallbackDeviceID(for: .microphone, in: microphoneDevices)
        }
    }

    func selectCamera(id: String) {
        settings.cameraDeviceID = id
    }

    func selectMicrophone(id: String) {
        settings.microphoneDeviceID = id
    }

    func selectCaptureSource() async {
        captureSourceError = nil

        do {
            guard let selection = try await sourcePicker.present() else {
                return
            }

            selectedCaptureSource = selection
        } catch {
            captureSourceError = error
        }
    }

    private func fallbackDeviceID(
        for kind: CaptureDeviceKind,
        in devices: [CaptureDeviceOption]
    ) -> String? {
        if let preferredID = deviceDiscovery.preferredDeviceID(for: kind),
           let preferredDevice = devices.first(where: { $0.id == preferredID }) {
            return preferredDevice.id
        }

        return devices.first?.id
    }
}
