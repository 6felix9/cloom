import Foundation
import XCTest
@testable import Cloom

final class RecordingOutputNamerTests: XCTestCase {
    func testNameUsesTimestampAndDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: first)
        let second = RecordingOutputNamer.availableURL(in: directory, date: date)

        XCTAssertEqual(first.pathExtension, "mp4")
        XCTAssertEqual(
            second.deletingPathExtension().lastPathComponent,
            first.deletingPathExtension().lastPathComponent + " 2"
        )
    }

    func testMultipleCollisionsIncrementSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: first)
        let second = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: second)
        let third = RecordingOutputNamer.availableURL(in: directory, date: date)

        XCTAssertEqual(
            third.deletingPathExtension().lastPathComponent,
            first.deletingPathExtension().lastPathComponent + " 3"
        )
    }
}
