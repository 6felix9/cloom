import AVFoundation
import CoreMedia
import XCTest
@testable import Cloom

final class RecordingExporterTests: XCTestCase, @unchecked Sendable {
    func testExportCompositesAndMuxesWorkspaceSuccessfully() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: .default)

        let screenWriter = try MediaSampleWriter.video(url: workspace.screenURL, width: 320, height: 240, epoch: 100)
        try screenWriter.append(videoSample(at: 100))
        try screenWriter.append(videoSample(at: 100.1))
        try await screenWriter.finish()

        let micWriter = try MediaSampleWriter.audio(url: workspace.microphoneURL, firstSample: audioSample(at: 100), epoch: 100)
        try micWriter.append(audioSample(at: 100))
        try micWriter.append(audioSample(at: 100.1))
        try await micWriter.finish()

        let outputDirectory = root.appending(path: "Movies", directoryHint: .isDirectory)
        let exporter = RecordingExporter(outputDirectory: outputDirectory)

        let progressRecorder = ProgressRecorder()
        let outputURL = try await exporter.export(workspace: workspace) { progress in
            progressRecorder.record(progress)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(outputURL.pathExtension, "mp4")
        XCTAssertFalse(progressRecorder.values.isEmpty)
        XCTAssertEqual(progressRecorder.values.last ?? 0, 1.0, accuracy: 0.01)

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
    }

    func testExportMissingScreenVideoThrowsErrorAndPreservesWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: .default)
        let exporter = RecordingExporter(outputDirectory: root)

        do {
            _ = try await exporter.export(workspace: workspace) { _ in }
            XCTFail("Expected missing screen video error")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.manifestURL.path))
        }
    }

    func testDisabledCameraIsExcludedEvenWhenArtifactExists() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = RecordingSettings.default
        settings.includeCamera = false
        let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
        try Data("camera artifact".utf8).write(to: workspace.cameraURL)

        XCTAssertNil(RecordingExporter.cameraURL(for: workspace))
    }

    func testExportWithoutCameraOrAudioCreatesVideoOnlyMP4() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = RecordingSettings.default
        settings.includeCamera = false
        settings.includeMicrophone = false
        let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
        let screenWriter = try MediaSampleWriter.video(
            url: workspace.screenURL, width: 320, height: 240, epoch: 100
        )
        try screenWriter.append(videoSample(at: 100))
        try screenWriter.append(videoSample(at: 100.1))
        try await screenWriter.finish()

        let output = try await RecordingExporter(
            outputDirectory: root.appending(path: "Movies", directoryHint: .isDirectory)
        ).export(workspace: workspace) { _ in }
        let asset = AVURLAsset(url: output)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 0)
    }

    func testExportStartsOnRealContentWithAudioAlignedWhenStreamsWarmUpAtDifferentTimes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = RecordingSettings.default
        settings.includeCamera = true
        settings.includeMicrophone = true
        settings.includeSystemAudio = false
        let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
        // Epoch 100; camera, screen and microphone come online at +0.1, +0.2 and +0.4 seconds.
        // The screen changes from gray 200 to 120 exactly when the microphone starts.
        try await MediaFixtures.writeVideo(to: workspace.cameraURL, epoch: 100,
                                           frames: (1...8).map { (100 + Double($0) / 10, 250) })
        try await MediaFixtures.writeVideo(to: workspace.screenURL, epoch: 100,
                                           frames: (2...8).map { (100 + Double($0) / 10, $0 < 4 ? 200 : 120) })
        try await MediaFixtures.writeAudio(to: workspace.microphoneURL, epoch: 100,
                                           start: 100.4, duration: 0.5, amplitude: 8_000)

        let output = try await RecordingExporter(
            outputDirectory: root.appending(path: "Movies", directoryHint: .isDirectory)
        ).export(workspace: workspace) { _ in }

        let frames = try await MediaFixtures.decodedFrames(of: output)
        let first = try XCTUnwrap(frames.first)
        XCTAssertEqual(first.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(first.gray(), 120, accuracy: 25, "Export must open on content captured with the microphone")
        let audible = try await MediaFixtures.firstAudibleSeconds(of: output)
        XCTAssertEqual(try XCTUnwrap(audible), first.seconds, accuracy: 0.034)
        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoRange = try await XCTUnwrap(videoTracks.first).load(.timeRange)
        let audioRange = try await XCTUnwrap(audioTracks.first).load(.timeRange)
        XCTAssertEqual(audioRange.end.seconds, videoRange.end.seconds, accuracy: 0.034)
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

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        lock.withLock { values.append(value) }
    }
}
