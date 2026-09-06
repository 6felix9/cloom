import Foundation

final class RecordingWorkspace: @unchecked Sendable {
    let directory: URL
    let overlayURL: URL
    let screenURL: URL
    let cameraURL: URL
    let microphoneURL: URL
    let systemAudioURL: URL
    let manifestURL: URL
    private let lock = NSLock()
    private var _manifest: RecordingManifest
    var manifest: RecordingManifest {
        lock.withLock { _manifest }
    }

    private init(directory: URL, manifest: RecordingManifest) {
        self.directory = directory
        overlayURL = directory.appending(path: "overlay.json")
        screenURL = directory.appending(path: "screen.mov")
        cameraURL = directory.appending(path: "camera.mov")
        microphoneURL = directory.appending(path: "microphone.m4a")
        systemAudioURL = directory.appending(path: "system-audio.m4a")
        manifestURL = directory.appending(path: "manifest.json")
        self._manifest = manifest
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
        try workspace.persistManifest(manifest)
        return workspace
    }

    func markCaptureComplete() throws {
        var candidateManifest = manifest
        candidateManifest.captureState = .captureComplete
        candidateManifest.failureMessage = nil
        try persistManifest(candidateManifest)
        lock.withLock { _manifest = candidateManifest }
    }

    func markFailed(message: String) throws {
        var candidateManifest = manifest
        candidateManifest.captureState = .failed
        candidateManifest.failureMessage = message
        try persistManifest(candidateManifest)
        lock.withLock { _manifest = candidateManifest }
    }

    private func persistManifest(_ manifest: RecordingManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }
}
