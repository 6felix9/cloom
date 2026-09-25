import AVFoundation
import Foundation

// Capture files share the recording epoch as time zero: each stream's warm-up delay is a leading empty edit.
// The anchor is the first instant at which the screen and every enabled essential stream have real media.
struct RecordingTimeline: Equatable, Sendable {
    let screenStart: CMTime
    let cameraStart: CMTime?
    let microphoneStart: CMTime?

    var anchor: CMTime {
        [cameraStart, microphoneStart].compactMap { $0 }.reduce(screenStart, CMTimeMaximum)
    }

    // System audio is excluded from the anchor: it is optional and aligned to the anchor without trimming.
    static func resolve(screenURL: URL, cameraURL: URL?, microphoneURL: URL?) async throws -> RecordingTimeline {
        guard let screenStart = try? await firstSampleTime(of: screenURL, mediaType: .video) else {
            throw VideoCompositorError.missingScreenVideo
        }
        return RecordingTimeline(
            screenStart: screenStart,
            cameraStart: try? await firstSampleTime(of: cameraURL, mediaType: .video),
            microphoneStart: try? await firstSampleTime(of: microphoneURL, mediaType: .audio)
        )
    }

    static func firstSampleTime(of url: URL?, mediaType: AVMediaType) async throws -> CMTime? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: mediaType).first else {
            return nil
        }
        return try await track.load(.segments).first(where: { !$0.isEmpty })?.timeMapping.target.start
    }
}
