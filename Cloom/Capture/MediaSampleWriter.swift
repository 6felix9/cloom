import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum MediaSampleWriterError: Error, Equatable, LocalizedError {
    case invalidFormat
    case cannotAddInput
    case cannotStart
    case cannotAppend
    case alreadyFinished
    case noSamples
    case didNotFinish

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "The captured media format is invalid."
        case .cannotAddInput: "The media writer cannot accept this capture format."
        case .cannotStart: "The media writer could not start."
        case .cannotAppend: "The media writer could not append a sample."
        case .alreadyFinished: "The media writer has already finished."
        case .noSamples: "No media samples were recorded."
        case .didNotFinish: "The media file could not be finalized."
        }
    }
}

// AVAssetWriter and input state are guarded together by lock, including completion callbacks.
final class MediaSampleWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let epoch: CMTime
    private let lock = NSLock()
    private var sampleCount = 0
    private var finishing = false
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var appendFailure: Error?

    private init(url: URL, fileType: AVFileType, mediaType: AVMediaType,
                 settings: [String: Any], sourceFormat: CMFormatDescription? = nil, epoch: Double) throws {
        guard epoch.isFinite, epoch >= 0 else { throw MediaSampleWriterError.invalidFormat }
        self.epoch = CMTime(seconds: epoch, preferredTimescale: 1_000_000_000)
        writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        input = AVAssetWriterInput(mediaType: mediaType, outputSettings: settings,
                                  sourceFormatHint: sourceFormat)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw MediaSampleWriterError.cannotAddInput }
        writer.add(input)
    }

    static func video(url: URL, width: Int, height: Int, epoch: Double) throws -> MediaSampleWriter {
        guard width > 0, height > 0 else { throw MediaSampleWriterError.invalidFormat }
        return try MediaSampleWriter(url: url, fileType: .mov, mediaType: .video, settings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ], epoch: epoch)
    }

    static func audio(url: URL, firstSample: CMSampleBuffer, epoch: Double) throws -> MediaSampleWriter {
        guard let format = CMSampleBufferGetFormatDescription(firstSample),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mSampleRate > 0, description.mChannelsPerFrame > 0 else {
            throw MediaSampleWriterError.invalidFormat
        }
        return try MediaSampleWriter(url: url, fileType: .m4a, mediaType: .audio, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: description.mSampleRate,
            AVNumberOfChannelsKey: description.mChannelsPerFrame,
            AVEncoderBitRateKey: 128_000
        ], sourceFormat: format, epoch: epoch)
    }

    @discardableResult
    func append(_ sample: CMSampleBuffer) throws -> Bool {
        try lock.withLock {
            guard !finishing, result == nil else { throw MediaSampleWriterError.alreadyFinished }
            if let appendFailure { throw appendFailure }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample),
                  timestamp.isNumeric, timestamp >= epoch else { return false }
            do {
                if writer.status == .unknown {
                    guard writer.startWriting() else { throw writer.error ?? MediaSampleWriterError.cannotStart }
                    writer.startSession(atSourceTime: epoch)
                }
                guard writer.status == .writing else { throw writer.error ?? MediaSampleWriterError.cannotAppend }
                guard input.isReadyForMoreMediaData else { return false }
                guard input.append(sample) else { throw writer.error ?? MediaSampleWriterError.cannotAppend }
                sampleCount += 1
                return true
            } catch {
                appendFailure = error
                throw error
            }
        }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let shouldFinish = lock.withLock {
                if let result { continuation.resume(with: result); return false }
                waiters.append(continuation)
                guard !finishing else { return false }
                finishing = true
                guard writer.status == .writing else {
                    completeLocked(.failure(appendFailure ?? writer.error ?? MediaSampleWriterError.noSamples))
                    return false
                }
                input.markAsFinished()
                return true
            }
            if shouldFinish {
                writer.finishWriting { [self] in
                    lock.withLock {
                        if let failure = appendFailure ?? writer.error {
                            completeLocked(.failure(failure))
                        } else if writer.status != .completed {
                            completeLocked(.failure(MediaSampleWriterError.didNotFinish))
                        } else if sampleCount == 0 {
                            completeLocked(.failure(MediaSampleWriterError.noSamples))
                        } else {
                            completeLocked(.success(()))
                        }
                    }
                }
            }
        }
    }

    private func completeLocked(_ result: Result<Void, Error>) {
        self.result = result
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(with: result) }
    }
}

// Each track owns a dedicated serial callback queue. No CMSampleBuffer crosses an actor boundary.
final class CaptureMediaTrack: @unchecked Sendable {
    private struct FinalizationSnapshot: Sendable {
        let writer: MediaSampleWriter?
        let failure: Error?
    }

    enum Format: Sendable {
        case video(width: Int?, height: Int?)
        case audio
    }

    let queue: DispatchQueue
    private let url: URL
    private let format: Format
    private let epoch: Double
    private var writer: MediaSampleWriter?
    private var failure: Error?
    private var accepting = true

    init(url: URL, format: Format, epoch: Double, label: String) {
        self.url = url
        self.format = format
        self.epoch = epoch
        queue = DispatchQueue(label: label)
    }

    func consume(_ sample: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard accepting, failure == nil, CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        guard timestamp.isNumeric, timestamp.seconds >= epoch else { return }
        do {
            if writer == nil {
                switch format {
                case let .video(width, height):
                    guard let description = CMSampleBufferGetFormatDescription(sample),
                          let image = CMSampleBufferGetImageBuffer(sample),
                          CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA else {
                        throw MediaSampleWriterError.invalidFormat
                    }
                    let dimensions = CMVideoFormatDescriptionGetDimensions(description)
                    writer = try MediaSampleWriter.video(url: url, width: width ?? Int(dimensions.width),
                                                         height: height ?? Int(dimensions.height), epoch: epoch)
                case .audio:
                    writer = try MediaSampleWriter.audio(url: url, firstSample: sample, epoch: epoch)
                }
            }
            try writer?.append(sample)
        } catch { failure = error }
    }

    func recordFailure(_ error: Error) {
        queue.async { [self] in if failure == nil { failure = error } }
    }

    func finish() async throws {
        let snapshot: FinalizationSnapshot = await withCheckedContinuation { continuation in
            queue.async { [self] in
                accepting = false
                continuation.resume(returning: FinalizationSnapshot(writer: writer, failure: failure))
            }
        }
        guard let writer = snapshot.writer else {
            throw snapshot.failure ?? MediaSampleWriterError.noSamples
        }
        do {
            try await writer.finish()
        } catch {
            throw snapshot.failure ?? error
        }
        if let failure = snapshot.failure { throw failure }
    }
}
