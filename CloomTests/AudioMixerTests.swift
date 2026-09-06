import AVFoundation
import CoreMedia
import XCTest
@testable import Cloom

final class AudioMixerTests: XCTestCase, @unchecked Sendable {
    func testMuxingWithMicrophoneOnlyCreatesMP4WithAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoURL = root.appending(path: "video.mov")
        let micURL = root.appending(path: "mic.m4a")
        let outputURL = root.appending(path: "output.mp4")

        let videoWriter = try MediaSampleWriter.video(url: videoURL, width: 320, height: 240, epoch: 10)
        try videoWriter.append(videoSample(at: 10))
        try videoWriter.append(videoSample(at: 10.2))
        try await videoWriter.finish()

        let micWriter = try MediaSampleWriter.audio(url: micURL, firstSample: audioSample(at: 10), epoch: 10)
        try micWriter.append(audioSample(at: 10))
        try micWriter.append(audioSample(at: 10.1))
        try await micWriter.finish()

        try await AudioMixer.mux(
            videoURL: videoURL,
            microphoneURL: micURL,
            systemAudioURL: root.appending(path: "absent.m4a"),
            includeSystemAudio: false,
            muteIntervals: [],
            outputURL: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
    }

    func testMuxingWithSystemAudioAndMuteIntervalsSucceeds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoURL = root.appending(path: "video.mov")
        let micURL = root.appending(path: "mic.m4a")
        let sysURL = root.appending(path: "sys.m4a")
        let outputURL = root.appending(path: "output.mp4")

        let videoWriter = try MediaSampleWriter.video(url: videoURL, width: 320, height: 240, epoch: 10)
        try videoWriter.append(videoSample(at: 10))
        try videoWriter.append(videoSample(at: 10.2))
        try await videoWriter.finish()

        let micWriter = try MediaSampleWriter.audio(url: micURL, firstSample: audioSample(at: 10), epoch: 10)
        try micWriter.append(audioSample(at: 10))
        try await micWriter.finish()

        let sysWriter = try MediaSampleWriter.audio(url: sysURL, firstSample: audioSample(at: 10), epoch: 10)
        try sysWriter.append(audioSample(at: 10))
        try await sysWriter.finish()

        let muteInterval = MuteInterval(startSeconds: 0.05, endSeconds: 0.15)

        try await AudioMixer.mux(
            videoURL: videoURL,
            microphoneURL: micURL,
            systemAudioURL: sysURL,
            includeSystemAudio: true,
            muteIntervals: [muteInterval],
            outputURL: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertGreaterThanOrEqual(audioTracks.count, 1)
    }

    func testMissingVideoSourceThrowsError() async {
        let fakeVideoURL = FileManager.default.temporaryDirectory.appending(path: "missing.mov")
        let fakeAudioURL = FileManager.default.temporaryDirectory.appending(path: "missing.m4a")
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "output.mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            try await AudioMixer.mux(
                videoURL: fakeVideoURL,
                microphoneURL: fakeAudioURL,
                systemAudioURL: fakeAudioURL,
                includeSystemAudio: false,
                muteIntervals: [],
                outputURL: outputURL
            )
            XCTFail("Expected missing video error")
        } catch {
            XCTAssertEqual(error as? AudioMixerError, .missingVideoSource)
        }
    }

    func testMuxingWithoutAnyAudioCreatesVideoOnlyMP4() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appending(path: "video.mov")
        let missingAudioURL = root.appending(path: "missing.m4a")
        let outputURL = root.appending(path: "output.mp4")
        let videoWriter = try MediaSampleWriter.video(url: videoURL, width: 320, height: 240, epoch: 10)
        try videoWriter.append(videoSample(at: 10))
        try videoWriter.append(videoSample(at: 10.2))
        try await videoWriter.finish()

        try await AudioMixer.mux(
            videoURL: videoURL,
            microphoneURL: missingAudioURL,
            systemAudioURL: missingAudioURL,
            includeSystemAudio: false,
            outputURL: outputURL
        )

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 0)
    }

    func testMuxingWithSystemAudioAndNoMicrophoneCreatesAudioTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let videoURL = root.appending(path: "video.mov")
        let missingMicrophoneURL = root.appending(path: "missing-mic.m4a")
        let systemAudioURL = root.appending(path: "system.m4a")
        let outputURL = root.appending(path: "output.mp4")
        let videoWriter = try MediaSampleWriter.video(url: videoURL, width: 320, height: 240, epoch: 10)
        try videoWriter.append(videoSample(at: 10))
        try videoWriter.append(videoSample(at: 10.2))
        try await videoWriter.finish()
        let audioWriter = try MediaSampleWriter.audio(
            url: systemAudioURL,
            firstSample: audioSample(at: 10),
            epoch: 10
        )
        try audioWriter.append(audioSample(at: 10))
        try audioWriter.append(audioSample(at: 10.1))
        try await audioWriter.finish()

        try await AudioMixer.mux(
            videoURL: videoURL,
            microphoneURL: missingMicrophoneURL,
            systemAudioURL: systemAudioURL,
            includeSystemAudio: true,
            outputURL: outputURL
        )

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
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
