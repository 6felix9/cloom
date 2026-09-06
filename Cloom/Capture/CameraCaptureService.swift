import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum CameraCaptureError: Error, LocalizedError {
    case deviceUnavailable
    case cannotAddInput
    case cannotAddOutput
    case didNotStart
    case missingClock
    case invalidTimestamp

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The selected camera is no longer available."
        case .cannotAddInput: "The selected camera cannot be added to the capture session."
        case .cannotAddOutput: "Camera video output is unavailable."
        case .didNotStart: "The camera capture session could not start."
        case .missingClock: "The camera capture session has no synchronization clock."
        case .invalidTimestamp: "A camera frame could not be synchronized."
        }
    }
}

@MainActor
final class CameraCaptureService: CameraCapturing {
    private let engine = CameraCaptureEngine()
    var previewSession: AVCaptureSession { engine.session }
    private var operationInProgress = false
    private var active = false

    func start(deviceID: String, workspace: RecordingWorkspace, epoch: Double) async throws {
        guard !active, !operationInProgress else { throw RecordingSessionError.operationInProgress }
        operationInProgress = true
        defer { operationInProgress = false }
        do {
            try await engine.start(deviceID: deviceID, url: workspace.cameraURL, epoch: epoch)
            active = true
        } catch {
            try? await engine.stop()
            throw error
        }
    }

    func stop() async throws {
        guard !operationInProgress else { throw RecordingSessionError.operationInProgress }
        operationInProgress = true
        defer { operationInProgress = false; active = false }
        try await engine.stop()
    }
}

// Blocking session configuration/start/stop runs on sessionQueue. Frame handling has a separate queue.
private final class CameraCaptureEngine: @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tzefoong.Cloom.camera-session")
    private var receiver: CameraFrameReceiver?
    private var output: AVCaptureVideoDataOutput?
    private var runtimeObserver: NSObjectProtocol?

    func start(deviceID: String, url: URL, epoch: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    guard let device = AVCaptureDevice(uniqueID: deviceID), device.hasMediaType(.video) else {
                        throw CameraCaptureError.deviceUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    let track = CaptureMediaTrack(url: url, format: .video(width: nil, height: nil),
                                                  epoch: epoch, label: "com.tzefoong.Cloom.camera-frames")
                    let receiver = CameraFrameReceiver(session: session, track: track)
                    self.receiver = receiver
                    self.output = output
                    session.beginConfiguration()
                    do {
                        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                        guard session.canAddInput(input) else { throw CameraCaptureError.cannotAddInput }
                        session.addInput(input)
                        guard session.canAddOutput(output) else { throw CameraCaptureError.cannotAddOutput }
                        session.addOutput(output)
                        output.setSampleBufferDelegate(receiver, queue: track.queue)
                        session.commitConfiguration()
                    } catch {
                        session.commitConfiguration()
                        throw error
                    }
                    runtimeObserver = NotificationCenter.default.addObserver(
                        forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
                    ) { notification in
                        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                            ?? CameraCaptureError.didNotStart
                        track.recordFailure(error)
                    }
                    session.startRunning()
                    guard session.isRunning else { throw CameraCaptureError.didNotStart }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async throws {
        let track: CaptureMediaTrack? = await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning { session.stopRunning() }
                output?.setSampleBufferDelegate(nil, queue: nil)
                if let runtimeObserver { NotificationCenter.default.removeObserver(runtimeObserver) }
                runtimeObserver = nil
                let track = receiver?.track
                session.beginConfiguration()
                for input in session.inputs { session.removeInput(input) }
                for output in session.outputs { session.removeOutput(output) }
                session.commitConfiguration()
                receiver = nil
                output = nil
                continuation.resume(returning: track)
            }
        }
        try await track?.finish()
    }
}

private final class CameraFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let track: CaptureMediaTrack
    private let session: AVCaptureSession

    init(session: AVCaptureSession, track: CaptureMediaTrack) {
        self.session = session
        self.track = track
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let clock = session.synchronizationClock else {
            track.recordFailure(CameraCaptureError.missingClock)
            return
        }
        // AVCapture timestamps use synchronizationClock, which is not assumed to be the host clock.
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
                                                     arrayToFill: nil, entriesNeededOut: &count) == noErr,
              count > 0 else { track.recordFailure(CameraCaptureError.invalidTimestamp); return }
        var timing = Array(repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                                     arrayToFill: &timing, entriesNeededOut: nil) == noErr else {
            track.recordFailure(CameraCaptureError.invalidTimestamp)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMSyncConvertTime(timing[index].presentationTimeStamp,
                                                                    from: clock, to: hostClock)
            if timing[index].decodeTimeStamp.isNumeric {
                timing[index].decodeTimeStamp = CMSyncConvertTime(timing[index].decodeTimeStamp,
                                                                 from: clock, to: hostClock)
            }
        }
        var synchronized: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
                                                    sampleTimingEntryCount: timing.count, sampleTimingArray: &timing,
                                                    sampleBufferOut: &synchronized) == noErr,
              let synchronized else { track.recordFailure(CameraCaptureError.invalidTimestamp); return }
        track.consume(synchronized)
    }
}
