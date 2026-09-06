import Foundation

final class RecordingWorkspace {
    let directory: URL
    let overlayURL: URL
    let screenURL: URL
    let cameraURL: URL
    let microphoneURL: URL
    let systemAudioURL: URL
    let manifestURL: URL
    private(set) var manifest: RecordingManifest

    private init(directory: URL, manifest: RecordingManifest) {
        self.directory = directory
        overlayURL = directory.appending(path: "overlay.json")
        screenURL = directory.appending(path: "screen.mov")
        cameraURL = directory.appending(path: "camera.mov")
        microphoneURL = directory.appending(path: "microphone.m4a")
        systemAudioURL = directory.appending(path: "system-audio.m4a")
        manifestURL = directory.appending(path: "manifest.json")
        self.manifest = manifest
    }

    static func create(
        baseDirectory: URL,
        settings: RecordingSettings,
        now: Date = .now
    ) throws -> RecordingWorkspace {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )

        let id = UUID()
        let directory = baseDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let manifest = RecordingManifest(
            id: id,
            createdAt: now,
            settings: settings,
            captureState: .preparing,
            failureMessage: nil
        )
        let workspace = RecordingWorkspace(directory: directory, manifest: manifest)
        try workspace.persistManifest()
        return workspace
    }

    func markCaptureComplete() throws {
        manifest.captureState = .captureComplete
        manifest.failureMessage = nil
        try persistManifest()
    }

    func markFailed(message: String) throws {
        manifest.captureState = .failed
        manifest.failureMessage = message
        try persistManifest()
    }

    private func persistManifest() throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }
}
