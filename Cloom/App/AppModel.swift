import Combine
import Foundation
import AppKit
import CoreMedia

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
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var recordingError: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var overlayState: OverlayState
    @Published private(set) var activeRecordingSettings: RecordingSettings?

    let recordingCoordinator: RecordingCoordinator

    private let permissionChecker: PermissionChecking
    private let settingsStore: SettingsStoring
    private let deviceDiscovery: CaptureDeviceDiscovering
    private let sourcePicker: ScreenSourcePicking
    private let sessionController: RecordingSessionController
    private let exporter: any RecordingExporting
    private let bubblePanel = CameraBubblePanelController()
    private var elapsedTask: Task<Void, Never>?
    private var muteIntervals: [MuteInterval] = []
    private var activeMuteStartSeconds: Double?

    init(
        permissionChecker: PermissionChecking,
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        recordingCoordinator: RecordingCoordinator = RecordingCoordinator(),
        deviceDiscovery: CaptureDeviceDiscovering = AVCaptureDeviceDiscovery(),
        sourcePicker: ScreenSourcePicking = ScreenSourcePicker(),
        sessionController: RecordingSessionController? = nil,
        exporter: any RecordingExporting = RecordingExporter()
    ) {
        self.permissionChecker = permissionChecker
        self.settingsStore = settingsStore
        self.recordingCoordinator = recordingCoordinator
        self.deviceDiscovery = deviceDiscovery
        self.sourcePicker = sourcePicker
        self.exporter = exporter
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.overlayState = OverlayState(centerX: 0.86, centerY: 0.82,
                                         size: loadedSettings.overlaySize,
                                         shape: loadedSettings.overlayShape, isVisible: true)
        self.sessionController = sessionController ?? RecordingSessionController(coordinator: recordingCoordinator)
        self.permissions = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map { ($0, .notDetermined) }
        )
    }

    static let live = AppModel(
        permissionChecker: SystemPermissionChecker(),
        settingsStore: UserDefaultsSettingsStore()
    )

    var hasScreenCapturePermission: Bool {
        permissions[.screen] == .authorized
    }

    var isReadyToConfigure: Bool {
        hasScreenCapturePermission &&
            (!settings.includeCamera || permissions[.camera] == .authorized) &&
            (!settings.includeMicrophone || permissions[.microphone] == .authorized)
    }

    var isReadyToRecord: Bool {
        isReadyToConfigure &&
            selectedCaptureSource != nil &&
            (!settings.includeCamera || settings.cameraDeviceID?.isEmpty == false) &&
            (!settings.includeMicrophone || settings.microphoneDeviceID?.isEmpty == false)
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

    func startRecording() async {
        guard let source = selectedCaptureSource else { return }
        recordingError = nil
        warnings = []
        muteIntervals = []
        activeMuteStartSeconds = nil
        let recordingSettings = settings
        activeRecordingSettings = recordingSettings
        overlayState.shape = recordingSettings.overlayShape
        overlayState.size = recordingSettings.overlaySize
        if !recordingSettings.includeMicrophone {
            isMicrophoneMuted = false
        }
        do {
            try await sessionController.start(configuration: RecordingSessionConfiguration(
                source: source,
                settings: recordingSettings
            ))
            if recordingSettings.includeMicrophone, isMicrophoneMuted {
                activeMuteStartSeconds = 0.0
            }
            if recordingSettings.includeCamera {
                bubblePanel.show(session: sessionController.previewSession, state: overlayState,
                                 captureFrame: source.presentationFrame) { [weak self] state in
                    self?.applyOverlay(state)
                }
            }
            beginElapsedTimer()
        } catch {
            recordingError = error.localizedDescription
        }
    }

    func stopRecording() async {
        elapsedTask?.cancel()
        elapsedTask = nil
        bubblePanel.close()
        if let start = activeMuteStartSeconds, let epoch = sessionController.epoch {
            let nowSeconds = max(start, CMClockGetTime(CMClockGetHostTimeClock()).seconds - epoch)
            muteIntervals.append(MuteInterval(startSeconds: start, endSeconds: nowSeconds))
            activeMuteStartSeconds = nil
        }
        do {
            try await sessionController.stop()
            try await exportCurrentWorkspace()
        } catch {
            recordingError = error.localizedDescription
        }
    }

    func setMicrophoneMuted(_ muted: Bool) {
        guard activeRecordingSettings?.includeMicrophone == true else {
            isMicrophoneMuted = false
            return
        }
        isMicrophoneMuted = muted
        guard let epoch = sessionController.epoch, recordingCoordinator.phase == .recording else { return }
        let nowSeconds = max(0, CMClockGetTime(CMClockGetHostTimeClock()).seconds - epoch)
        if muted {
            if activeMuteStartSeconds == nil {
                activeMuteStartSeconds = nowSeconds
            }
        } else if let start = activeMuteStartSeconds {
            muteIntervals.append(MuteInterval(startSeconds: start, endSeconds: nowSeconds))
            activeMuteStartSeconds = nil
        }
    }

    func setCameraVisible(_ visible: Bool) {
        var state = overlayState
        state.isVisible = visible
        applyOverlay(state)
        bubblePanel.update(state: state)
    }

    func setOverlaySize(_ size: OverlaySize) {
        var state = overlayState
        state.size = size
        settings.overlaySize = size
        applyOverlay(state)
        bubblePanel.update(state: state)
    }

    func setOverlayShape(_ shape: OverlayShape) {
        var state = overlayState
        state.shape = shape
        settings.overlayShape = shape
        applyOverlay(state)
        bubblePanel.update(state: state)
    }

    func retryExport() async {
        recordingError = nil
        do {
            try recordingCoordinator.beginExporting()
            try await exportCurrentWorkspace()
        } catch {
            recordingError = error.localizedDescription
        }
    }

    func revealCurrentRecording() {
        guard let workspace = sessionController.workspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([workspace.directory])
    }

    func revealOutput(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func recordAnother() {
        recordingError = nil
        elapsedSeconds = 0
        activeRecordingSettings = nil
        isMicrophoneMuted = false
        recordingCoordinator.reset()
    }

    private func exportCurrentWorkspace() async throws {
        guard let workspace = sessionController.workspace else { return }
        do {
            let output = try await exporter.export(workspace: workspace, muteIntervals: muteIntervals) { [weak self] progress in
                Task { @MainActor in
                    try? self?.recordingCoordinator.updateExportProgress(progress)
                }
            }
            try recordingCoordinator.finish(outputURL: output)
            try? FileManager.default.removeItem(at: workspace.directory)
        } catch {
            recordingError = error.localizedDescription
            recordingCoordinator.fail(.exportFailed(error.localizedDescription))
            throw error
        }
    }

    private func beginElapsedTimer() {
        elapsedSeconds = 0
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.elapsedSeconds += 1
            }
        }
    }

    private func applyOverlay(_ state: OverlayState) {
        let state = state.clamped()
        overlayState = state
        guard let epoch = sessionController.epoch else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        do { try sessionController.overlayStore?.append(state: state, at: max(0, now - epoch)) }
        catch { warnings.append("Overlay change was not saved: \(error.localizedDescription)") }
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
