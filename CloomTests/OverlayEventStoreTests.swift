import Foundation
import XCTest
@testable import Cloom

final class OverlayEventStoreTests: XCTestCase {
    func testClampKeepsEntireLargeBubbleInsideFrame() {
        let state = OverlayState(
            centerX: 0.98,
            centerY: 0.02,
            size: .large,
            shape: .circle,
            isVisible: true
        )

        XCTAssertEqual(
            state.clamped(),
            OverlayState(centerX: 0.875, centerY: 0.125, size: .large, shape: .circle, isVisible: true)
        )
    }

    func testStoreCoalescesDuplicatesResolvesLatestStateAndPersistsAcceptedEvents() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = OverlayState.default
        let store = try OverlayEventStore(fileURL: url, initialState: initial)

        try store.append(state: initial, at: 0.2)
        let moved = OverlayState(centerX: 0.2, centerY: 0.8, size: .medium, shape: .circle, isVisible: true)
        try store.append(state: moved, at: 1.0)

        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.state(at: 0.5), initial)
        XCTAssertEqual(store.state(at: 1.5), moved)
        XCTAssertEqual(try persistedEvents(at: url), [
            TimedOverlayEvent(timeSeconds: 0, state: initial),
            TimedOverlayEvent(timeSeconds: 1, state: moved),
        ])
    }

    func testStoreRejectsNegativeTimestampWithoutChangingPersistedEvents() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = OverlayState.default
        let store = try OverlayEventStore(fileURL: url, initialState: initial)
        let persistedBeforeRejection = try Data(contentsOf: url)

        XCTAssertThrowsError(try store.append(state: movedState, at: -0.01))

        XCTAssertEqual(store.events, [TimedOverlayEvent(timeSeconds: 0, state: initial)])
        XCTAssertEqual(try Data(contentsOf: url), persistedBeforeRejection)
    }

    func testStoreRejectsTimestampEarlierThanLatestEventWithoutChangingPersistedEvents() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = OverlayState.default
        let store = try OverlayEventStore(fileURL: url, initialState: initial)
        try store.append(state: movedState, at: 1.0)
        let persistedBeforeRejection = try Data(contentsOf: url)

        XCTAssertThrowsError(try store.append(state: OverlayState.default, at: 0.5))

        XCTAssertEqual(store.events, [
            TimedOverlayEvent(timeSeconds: 0, state: initial),
            TimedOverlayEvent(timeSeconds: 1, state: movedState),
        ])
        XCTAssertEqual(try Data(contentsOf: url), persistedBeforeRejection)
    }

    private var movedState: OverlayState {
        OverlayState(centerX: 0.2, centerY: 0.8, size: .medium, shape: .circle, isVisible: true)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func persistedEvents(at url: URL) throws -> [TimedOverlayEvent] {
        try JSONDecoder().decode([TimedOverlayEvent].self, from: Data(contentsOf: url))
    }
}
