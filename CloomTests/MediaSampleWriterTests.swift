import AVFoundation
import CoreVideo
import XCTest
@testable import Cloom

final class MediaSampleWriterTests: XCTestCase, @unchecked Sendable {
    func testAudioUsesCapturedFormatAndFinalizesAACAtSharedEpoch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "microphone.mov")
        let sample = try audioSample(at: 42)
        let writer = try MediaSampleWriter.audio(url: url, firstSample: sample, epoch: 42)

        XCTAssertFalse(try writer.append(audioSample(at: 41)))
        XCTAssertTrue(try writer.append(sample))
        try await writer.finish()

        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(descriptions.first)
        let description = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format))
        XCTAssertEqual(description.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(description.pointee.mSampleRate, 48_000)
        XCTAssertEqual(description.pointee.mChannelsPerFrame, 1)
    }

    func testVideoDiscardsPreEpochSamplesAndFinalizesPlayableMovie() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "screen.mov")
        let writer = try MediaSampleWriter.video(url: url, width: 64, height: 64, epoch: 42)

        XCTAssertFalse(try writer.append(videoSample(at: 41)))
        XCTAssertTrue(try writer.append(videoSample(at: 42)))
        try await writer.finish()

        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let range = try await XCTUnwrap(tracks.first).load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.001)
        XCTAssertGreaterThan(range.duration.seconds, 0)
        XCTAssertThrowsError(try writer.append(videoSample(at: 43)))
        try await writer.finish()
    }

    func testEmptyWriterReportsMissingMediaInsteadOfCompletingSuccessfully() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try MediaSampleWriter.video(
            url: root.appending(path: "screen.mov"), width: 64, height: 64, epoch: 42
        )
        do {
            try await writer.finish()
            XCTFail("Expected no-samples failure")
        } catch {
            XCTAssertEqual(error as? MediaSampleWriterError, .noSamples)
        }
    }

    private func audioSample(at seconds: Double) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        ), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 2048,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: 2048, flags: 0, blockBufferOut: &block
        ), noErr)
        let data = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data, offsetIntoDestination: 0,
                                                dataLength: 2048), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48_000),
                                        decodeTimeStamp: .invalid)
        var size = 2
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: try XCTUnwrap(format),
            sampleCount: 1024, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }

    private func videoSample(at seconds: Double) throws -> CMSampleBuffer {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image
        ), kCVReturnSuccess)
        let buffer = try XCTUnwrap(image)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(buffer) {
            memset(bytes, 0, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format
        ), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }
}
