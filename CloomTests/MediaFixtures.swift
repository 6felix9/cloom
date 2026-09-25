import AVFoundation
import CoreMedia
import CoreVideo
import XCTest

// Short synthetic media for timeline tests. Gray levels and tones make alignment observable after encoding.
enum MediaFixtures {
    static func videoSample(at seconds: Double, gray: UInt8) throws -> CMSampleBuffer {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &image
        ), kCVReturnSuccess)
        let buffer = try XCTUnwrap(image)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(buffer) {
            memset(bytes, Int32(gray), CVPixelBufferGetDataSize(buffer))
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

    static let audioFramesPerSample = 1024

    /// A 1024-frame mono 48 kHz buffer; a non-zero amplitude writes a 1 kHz tone.
    static func audioSample(at seconds: Double, amplitude: Double = 0) throws -> CMSampleBuffer {
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
        let frames = (0..<audioFramesPerSample).map { index in
            Int16(amplitude * sin(2 * .pi * 1_000 * Double(index) / 48_000))
        }
        let length = frames.count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: 0, blockBufferOut: &block
        ), noErr)
        let data = try XCTUnwrap(block)
        try frames.withUnsafeBytes { bytes in
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(
                with: try XCTUnwrap(bytes.baseAddress), blockBuffer: data,
                offsetIntoDestination: 0, dataLength: length
            ), noErr)
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48_000),
                                        decodeTimeStamp: .invalid)
        var size = 2
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: try XCTUnwrap(format),
            sampleCount: audioFramesPerSample, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }

    /// Writes contiguous audio buffers covering `start ..< start + duration` into an epoch-based capture file.
    static func writeAudio(to url: URL, epoch: Double, start: Double, duration: Double,
                           amplitude: Double = 0) async throws {
        let step = Double(audioFramesPerSample) / 48_000
        let count = Int((duration / step).rounded(.up))
        let writer = try MediaSampleWriter.audio(
            url: url, firstSample: try audioSample(at: start, amplitude: amplitude), epoch: epoch
        )
        for index in 0..<count {
            let sample = try audioSample(at: start + Double(index) * step, amplitude: amplitude)
            while try !writer.append(sample) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        try await writer.finish()
    }

    /// Writes one frame per entry, `(epoch-based time, gray level)`, into an epoch-based capture file.
    static func writeVideo(to url: URL, epoch: Double, frames: [(Double, UInt8)],
                           width: Int = 320, height: Int = 240) async throws {
        let writer = try MediaSampleWriter.video(url: url, width: width, height: height, epoch: epoch)
        for (time, gray) in frames {
            let sample = try videoSample(at: time, gray: gray)
            while try !writer.append(sample) {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        try await writer.finish()
    }

    struct DecodedFrame {
        let seconds: Double
        let buffer: CVPixelBuffer

        /// Green channel at a normalized point with a bottom-left origin, matching Core Image coordinates.
        func gray(atX x: Double = 0.5, y: Double = 0.5) -> Int {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return -1 }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let column = min(Int(x * Double(width)), width - 1)
            let row = min(Int((1 - y) * Double(height)), height - 1)
            let pixel = base.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer) + column * 4)
            return Int(pixel.load(fromByteOffset: 1, as: UInt8.self))
        }
    }

    static func decodedFrames(of url: URL) async throws -> [DecodedFrame] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [DecodedFrame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(DecodedFrame(seconds: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                                       buffer: buffer))
        }
        return frames
    }

    /// Output time of the first decoded audio frame whose magnitude exceeds `threshold`.
    static func firstAudibleSeconds(of url: URL, threshold: Int16 = 1_000) async throws -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        while let sample = output.copyNextSampleBuffer() {
            guard let format = CMSampleBufferGetFormatDescription(sample),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let channels = Int(description.mChannelsPerFrame)
            var bytes = [Int16](repeating: 0, count: CMBlockBufferGetDataLength(block) / 2)
            _ = bytes.withUnsafeMutableBytes { destination in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: destination.count,
                                           destination: destination.baseAddress!)
            }
            if let index = bytes.firstIndex(where: { abs(Int32($0)) > Int32(threshold) }) {
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                return start + Double(index / channels) / description.mSampleRate
            }
        }
        return nil
    }
}
