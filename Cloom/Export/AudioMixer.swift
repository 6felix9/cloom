import AVFoundation
import Foundation

struct MuteInterval: Codable, Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
}

enum AudioMixerError: Error, LocalizedError, Equatable {
    case missingVideoSource
    case cannotReadSource
    case exportUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideoSource: "The video track to mux audio into is missing."
        case .cannotReadSource: "Cloom could not read an audio track."
        case .exportUnavailable: "This Mac cannot create the final MP4."
        case let .exportFailed(message): "MP4 audio muxing failed: \(message)"
        }
    }
}

enum AudioMixer {
    static func mux(
        videoURL: URL,
        microphoneURL: URL,
        systemAudioURL: URL,
        includeSystemAudio: Bool,
        muteIntervals: [MuteInterval] = [],
        outputURL: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw AudioMixerError.missingVideoSource
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw AudioMixerError.cannotReadSource
        }
        let videoTimeRange = try await sourceVideo.load(.timeRange)
        try videoTrack.insertTimeRange(videoTimeRange, of: sourceVideo, at: .zero)
        let duration = videoTimeRange.duration

        var audioParameters: [AVMutableAudioMixInputParameters] = []
        let hasSystem = includeSystemAudio && FileManager.default.fileExists(atPath: systemAudioURL.path)
        let baseVolume: Float = hasSystem ? 0.501187 : 1.0

        if FileManager.default.fileExists(atPath: microphoneURL.path) {
            let micAsset = AVURLAsset(url: microphoneURL)
            let micTracks = try await micAsset.loadTracks(withMediaType: .audio)
            if let sourceMic = micTracks.first,
               let targetMic = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let micTimeRange = try await sourceMic.load(.timeRange)
                let range = CMTimeRange(
                    start: micTimeRange.start,
                    duration: min(micTimeRange.duration, duration)
                )
                try targetMic.insertTimeRange(range, of: sourceMic, at: .zero)
                let parameters = AVMutableAudioMixInputParameters(track: targetMic)
                parameters.setVolume(baseVolume, at: .zero)
                for interval in muteIntervals {
                    let start = CMTime(seconds: interval.startSeconds, preferredTimescale: 600)
                    let end = CMTime(seconds: interval.endSeconds, preferredTimescale: 600)
                    parameters.setVolume(0.0, at: start)
                    parameters.setVolume(baseVolume, at: end)
                }
                audioParameters.append(parameters)
            }
        }

        if hasSystem {
            let sysAsset = AVURLAsset(url: systemAudioURL)
            let sysTracks = try await sysAsset.loadTracks(withMediaType: .audio)
            if let sourceSys = sysTracks.first,
               let targetSys = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let sysTimeRange = try await sourceSys.load(.timeRange)
                let range = CMTimeRange(
                    start: sysTimeRange.start,
                    duration: min(sysTimeRange.duration, duration)
                )
                try targetSys.insertTimeRange(range, of: sourceSys, at: .zero)
                let parameters = AVMutableAudioMixInputParameters(track: targetSys)
                parameters.setVolume(baseVolume, at: .zero)
                audioParameters.append(parameters)
            }
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = audioParameters

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw AudioMixerError.exportUnavailable
        }
        session.audioMix = mix
        session.shouldOptimizeForNetworkUse = true
        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            throw AudioMixerError.exportFailed(error.localizedDescription)
        }
    }
}
