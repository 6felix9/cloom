import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
protocol ScreenCapturing: AnyObject {
    func start(selection: any ScreenCaptureSelection, configuration: SCStreamConfiguration,
               workspace: RecordingWorkspace, epoch: Double) async throws
    func stop() async throws
}

@MainActor
protocol CameraCapturing: AnyObject {
    var previewSession: AVCaptureSession { get }
    func start(deviceID: String, workspace: RecordingWorkspace, epoch: Double) async throws
    func stop() async throws
}

protocol RecordingClock: Sendable {
    func nowSeconds() -> Double
}

struct HostRecordingClock: RecordingClock {
    func nowSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

protocol CountdownSleeping: Sendable {
    func sleepForCountdown() async throws
}

struct ThreeSecondCountdownSleeper: CountdownSleeping {
    func sleepForCountdown() async throws { try await Task.sleep(for: .seconds(3)) }
}

@MainActor
protocol RecordingWorkspaceCreating {
    func create(settings: RecordingSettings) throws -> RecordingWorkspace
}

@MainActor
struct RecordingWorkspaceFactory: RecordingWorkspaceCreating {
    func create(settings: RecordingSettings) throws -> RecordingWorkspace {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try RecordingWorkspace.create(
            baseDirectory: support.appending(path: "Cloom/Recordings", directoryHint: .isDirectory),
            settings: settings
        )
    }
}

@MainActor
struct RecordingSessionConfiguration {
    let source: any ScreenCaptureSelection
    let settings: RecordingSettings
}

enum RecordingSessionError: Error, LocalizedError {
    case missingDevices
    case operationInProgress
    case invalidEpoch

    var errorDescription: String? {
        switch self {
        case .missingDevices: "Select a camera and microphone before recording."
        case .operationInProgress: "A recording operation is already in progress."
        case .invalidEpoch: "The recording clock returned an invalid time."
        }
    }
}

@MainActor
final class RecordingSessionController {
    private let coordinator: RecordingCoordinator
    private let screenCapture: any ScreenCapturing
    private let cameraCapture: any CameraCapturing
    private let workspaceFactory: any RecordingWorkspaceCreating
    private let clock: any RecordingClock
    private let countdownSleeper: any CountdownSleeping
    private var operationInProgress = false
    private(set) var workspace: RecordingWorkspace?
    private(set) var overlayStore: OverlayEventStore?
    private(set) var epoch: Double?
    private(set) var cleanupConcerns: [String] = []
    var previewSession: AVCaptureSession { cameraCapture.previewSession }

    init(coordinator: RecordingCoordinator,
         screenCapture: any ScreenCapturing = ScreenCaptureService(),
         cameraCapture: any CameraCapturing = CameraCaptureService(),
         workspaceFactory: any RecordingWorkspaceCreating = RecordingWorkspaceFactory(),
         clock: any RecordingClock = HostRecordingClock(),
         countdownSleeper: any CountdownSleeping = ThreeSecondCountdownSleeper()) {
        self.coordinator = coordinator
        self.screenCapture = screenCapture
        self.cameraCapture = cameraCapture
        self.workspaceFactory = workspaceFactory
        self.clock = clock
        self.countdownSleeper = countdownSleeper
    }

    func start(configuration: RecordingSessionConfiguration) async throws {
        guard !operationInProgress else { throw RecordingSessionError.operationInProgress }
        // Invalid duplicate starts must not enter cleanup for the active recording.
        try coordinator.beginPreparing()
        operationInProgress = true
        defer { operationInProgress = false }
        workspace = nil
        overlayStore = nil
        epoch = nil
        cleanupConcerns = []
        var attemptedCamera = false
        var attemptedScreen = false
        do {
            let workspace = try workspaceFactory.create(settings: configuration.settings)
            self.workspace = workspace
            var initialOverlay = OverlayState.default
            initialOverlay.shape = configuration.settings.overlayShape
            initialOverlay.size = configuration.settings.overlaySize
            overlayStore = try OverlayEventStore(fileURL: workspace.overlayURL, initialState: initialOverlay)
            guard let cameraID = configuration.settings.cameraDeviceID, !cameraID.isEmpty,
                  let microphoneID = configuration.settings.microphoneDeviceID, !microphoneID.isEmpty else {
                throw RecordingSessionError.missingDevices
            }
            try coordinator.beginCountdown()
            try await countdownSleeper.sleepForCountdown()
            try Task.checkCancellation()
            let epoch = clock.nowSeconds()
            guard epoch.isFinite, epoch >= 0 else { throw RecordingSessionError.invalidEpoch }
            self.epoch = epoch
            let streamConfiguration = ScreenStreamConfigurationFactory.make(
                includeSystemAudio: configuration.settings.includeSystemAudio,
                microphoneDeviceID: microphoneID
            )
            attemptedCamera = true
            try await cameraCapture.start(deviceID: cameraID, workspace: workspace, epoch: epoch)
            try Task.checkCancellation()
            attemptedScreen = true
            try await screenCapture.start(selection: configuration.source, configuration: streamConfiguration,
                                          workspace: workspace, epoch: epoch)
            try Task.checkCancellation()
            try coordinator.beginRecording()
        } catch {
            if attemptedScreen {
                do { try await screenCapture.stop() } catch { cleanupConcerns.append(error.localizedDescription) }
            }
            if attemptedCamera {
                do { try await cameraCapture.stop() } catch { cleanupConcerns.append(error.localizedDescription) }
            }
            recordFailure(error)
            throw error
        }
    }

    func stop() async throws {
        guard !operationInProgress else { throw RecordingSessionError.operationInProgress }
        guard coordinator.phase == .recording, let workspace else {
            throw RecordingTransitionError.invalid(from: coordinator.phase, action: "stop")
        }
        operationInProgress = true
        defer { operationInProgress = false }
        var failure: Error?
        do { try await screenCapture.stop() } catch { failure = error }
        do { try await cameraCapture.stop() } catch {
            if failure == nil { failure = error } else { cleanupConcerns.append(error.localizedDescription) }
        }
        do { try overlayStore?.finish() } catch {
            if failure == nil { failure = error } else { cleanupConcerns.append(error.localizedDescription) }
        }
        do {
            if let failure { throw failure }
            try workspace.markCaptureComplete()
            try coordinator.beginExporting()
        } catch {
            recordFailure(error)
            throw error
        }
    }

    private func recordFailure(_ error: Error) {
        do { try workspace?.markFailed(message: error.localizedDescription) }
        catch { cleanupConcerns.append("Could not persist failed manifest: \(error.localizedDescription)") }
        coordinator.fail(.captureFailed(error.localizedDescription))
    }
}
