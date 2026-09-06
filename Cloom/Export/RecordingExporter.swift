import Foundation

protocol RecordingExporting: Sendable {
    func export(
        workspace: RecordingWorkspace,
        muteIntervals: [MuteInterval],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

extension RecordingExporting {
    func export(
        workspace: RecordingWorkspace,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await export(workspace: workspace, muteIntervals: [], progress: progress)
    }
}

struct RecordingExporter: RecordingExporting {
    private let outputDirectory: URL?

    init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory
    }

    static func cameraURL(for workspace: RecordingWorkspace) -> URL? {
        workspace.manifest.settings.includeCamera ? workspace.cameraURL : nil
    }

    func export(
        workspace: RecordingWorkspace,
        muteIntervals: [MuteInterval] = [],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let moviesDir: URL
        if let outputDirectory {
            moviesDir = outputDirectory
        } else {
            let baseMovies = try fileManager.url(
                for: .moviesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            moviesDir = baseMovies.appending(path: "Cloom", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: moviesDir, withIntermediateDirectories: true)
        let finalOutputURL = RecordingOutputNamer.availableURL(in: moviesDir)
        let renderedVideoURL = workspace.directory.appending(path: "rendered-video.mov")
        try? fileManager.removeItem(at: renderedVideoURL)

        let events: [TimedOverlayEvent]
        if let data = try? Data(contentsOf: workspace.overlayURL),
           let decoded = try? JSONDecoder().decode([TimedOverlayEvent].self, from: data) {
            events = decoded
        } else {
            events = [TimedOverlayEvent(timeSeconds: 0, state: .default)]
        }

        try await Task.detached(priority: .userInitiated) {
            try VideoCompositor.render(
                screenURL: workspace.screenURL,
                cameraURL: Self.cameraURL(for: workspace),
                events: events,
                outputURL: renderedVideoURL
            ) { fraction in
                progress(fraction * 0.9)
            }
        }.value

        do {
            try await AudioMixer.mux(
                videoURL: renderedVideoURL,
                microphoneURL: workspace.microphoneURL,
                systemAudioURL: workspace.systemAudioURL,
                includeSystemAudio: workspace.manifest.settings.includeSystemAudio,
                muteIntervals: muteIntervals,
                outputURL: finalOutputURL
            )
            progress(1.0)
            try? fileManager.removeItem(at: renderedVideoURL)
            return finalOutputURL
        } catch {
            try? fileManager.removeItem(at: finalOutputURL)
            throw error
        }
    }
}
