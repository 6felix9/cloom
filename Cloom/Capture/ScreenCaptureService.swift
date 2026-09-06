import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    private var stream: SCStream?
    private var receiver: ScreenStreamReceiver?
    private var tracks: [CaptureMediaTrack] = []
    private var systemAudioTrack: CaptureMediaTrack?
    private var operationInProgress = false
    private(set) var warnings: [String] = []
    private let logger = Logger(subsystem: "com.tzefoong.Cloom", category: "ScreenCapture")

    func start(selection: any ScreenCaptureSelection, configuration: SCStreamConfiguration,
               workspace: RecordingWorkspace, epoch: Double) async throws {
        guard stream == nil, !operationInProgress else { throw RecordingSessionError.operationInProgress }
        operationInProgress = true
        defer { operationInProgress = false }
        warnings = []
        let screen = CaptureMediaTrack(url: workspace.screenURL,
                                       format: .video(width: configuration.width, height: configuration.height),
                                       epoch: epoch, label: "com.tzefoong.Cloom.screen")
        let microphone = configuration.captureMicrophone
            ? CaptureMediaTrack(url: workspace.microphoneURL, format: .audio,
                                epoch: epoch, label: "com.tzefoong.Cloom.microphone")
            : nil
        tracks = [screen] + [microphone].compactMap { $0 }
        let audio = configuration.capturesAudio
            ? CaptureMediaTrack(url: workspace.systemAudioURL, format: .audio,
                                epoch: epoch, label: "com.tzefoong.Cloom.system-audio") : nil
        systemAudioTrack = audio
        let receiver = ScreenStreamReceiver(screen: screen, microphone: microphone, audio: audio)
        self.receiver = receiver
        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: receiver)
        self.stream = stream
        do {
            try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: screen.queue)
            if let microphone {
                try stream.addStreamOutput(receiver, type: .microphone, sampleHandlerQueue: microphone.queue)
            }
            if let audio {
                do { try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: audio.queue) }
                catch {
                    warn("System audio is unavailable: \(error.localizedDescription)")
                    configuration.capturesAudio = false
                    systemAudioTrack = nil
                    try await stream.updateConfiguration(configuration)
                }
            }
            do {
                try await stream.startCapture()
            } catch {
                let failure = error as NSError
                guard configuration.capturesAudio, failure.domain == SCStreamErrorDomain,
                      failure.code == SCStreamError.Code.failedToStartAudioCapture.rawValue else { throw error }
                warn("System audio could not start; continuing without it: \(error.localizedDescription)")
                // A fresh stream avoids carrying failed start state into the microphone-only retry.
                try? await stream.stopCapture()
                configuration.capturesAudio = false
                let fallback = ScreenStreamReceiver(screen: screen, microphone: microphone, audio: nil)
                let retry = SCStream(filter: selection.filter, configuration: configuration, delegate: fallback)
                self.receiver = fallback
                self.stream = retry
                try retry.addStreamOutput(fallback, type: .screen, sampleHandlerQueue: screen.queue)
                if let microphone {
                    try retry.addStreamOutput(fallback, type: .microphone, sampleHandlerQueue: microphone.queue)
                }
                try await retry.startCapture()
            }
        } catch {
            // The controller calls stop as well; detach first so cleanup remains idempotent.
            _ = await finalizeCapture()
            throw error
        }
    }

    func stop() async throws {
        guard !operationInProgress else { throw RecordingSessionError.operationInProgress }
        operationInProgress = true
        defer { operationInProgress = false }
        if let failure = await finalizeCapture() { throw failure }
    }

    private func finalizeCapture() async -> Error? {
        guard let stream else { return nil }
        var failure: Error?
        do { try await stream.stopCapture() } catch { failure = error }
        if let streamFailure = receiver?.failure { failure = streamFailure }
        for track in tracks {
            do { try await track.finish() } catch { if failure == nil { failure = error } }
        }
        if let systemAudioTrack {
            do { try await systemAudioTrack.finish() }
            catch { warn("System audio was not recorded: \(error.localizedDescription)") }
        }
        self.stream = nil
        receiver = nil
        tracks = []
        systemAudioTrack = nil
        return failure
    }

    private func warn(_ message: String) {
        warnings.append(message)
        logger.warning("\(message, privacy: .public)")
    }
}

// Track state belongs to the configured callback queues; the delegate error has its own lock.
private final class ScreenStreamReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let screen: CaptureMediaTrack
    private let microphone: CaptureMediaTrack?
    private let audio: CaptureMediaTrack?
    private let lock = NSLock()
    private var streamFailure: Error?
    var failure: Error? { lock.withLock { streamFailure } }

    init(screen: CaptureMediaTrack, microphone: CaptureMediaTrack?, audio: CaptureMediaTrack?) {
        self.screen = screen
        self.microphone = microphone
        self.audio = audio
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { streamFailure = error }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: status) == .complete else { return }
            screen.consume(sampleBuffer)
        case .microphone:
            microphone?.consume(sampleBuffer)
        case .audio:
            audio?.consume(sampleBuffer)
        @unknown default:
            break
        }
    }
}
