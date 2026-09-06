import Foundation
import XCTest
@testable import Cloom

final class RecordingWorkspaceTests: XCTestCase {
    func testCreateMakesUniqueWorkspaceAndPersistsPreparingManifest() throws {
        let root = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let workspace = try RecordingWorkspace.create(
            baseDirectory: root,
            settings: .default,
            now: date
        )
        let secondWorkspace = try RecordingWorkspace.create(
            baseDirectory: root,
            settings: .default,
            now: date
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory.path))
        XCTAssertNotEqual(workspace.directory, secondWorkspace.directory)
        XCTAssertEqual(workspace.manifest.captureState, .preparing)
        XCTAssertEqual(workspace.overlayURL.lastPathComponent, "overlay.json")
        XCTAssertEqual(workspace.screenURL.lastPathComponent, "screen.mov")
        XCTAssertEqual(workspace.cameraURL.lastPathComponent, "camera.mov")
        XCTAssertEqual(workspace.microphoneURL.lastPathComponent, "microphone.m4a")
        XCTAssertEqual(workspace.systemAudioURL.lastPathComponent, "system-audio.m4a")
        XCTAssertEqual(try persistedManifest(at: workspace.manifestURL), workspace.manifest)
    }

    func testMarkCaptureCompletePersistsUpdatedManifest() throws {
        let root = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try RecordingWorkspace.create(
            baseDirectory: root,
            settings: .default,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try workspace.markCaptureComplete()

        XCTAssertEqual(workspace.manifest.captureState, .captureComplete)
        XCTAssertEqual(try persistedManifest(at: workspace.manifestURL), workspace.manifest)
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func persistedManifest(at url: URL) throws -> RecordingManifest {
        try JSONDecoder().decode(RecordingManifest.self, from: Data(contentsOf: url))
    }
}
