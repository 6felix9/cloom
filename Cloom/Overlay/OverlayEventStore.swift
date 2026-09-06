import Foundation

enum OverlayEventStoreError: Error, Equatable {
    case negativeTimestamp
    case nonMonotonicTimestamp
}

final class OverlayEventStore {
    let fileURL: URL
    private(set) var events: [TimedOverlayEvent]

    init(fileURL: URL, initialState: OverlayState) throws {
        self.fileURL = fileURL
        events = [TimedOverlayEvent(timeSeconds: 0, state: initialState.clamped())]
        try persist(events)
    }

    func append(state: OverlayState, at timeSeconds: Double) throws {
        guard timeSeconds >= 0 else {
            throw OverlayEventStoreError.negativeTimestamp
        }
        guard let latestEvent = events.last, timeSeconds >= latestEvent.timeSeconds else {
            throw OverlayEventStoreError.nonMonotonicTimestamp
        }
        let clampedState = state.clamped()
        guard latestEvent.state != clampedState else {
            return
        }

        let candidateEvents = events + [TimedOverlayEvent(timeSeconds: timeSeconds, state: clampedState)]
        try persist(candidateEvents)
        events = candidateEvents
    }

    func state(at timeSeconds: Double) -> OverlayState {
        events.last(where: { $0.timeSeconds <= timeSeconds })?.state ?? events[0].state
    }

    func finish() throws {
        try persist(events)
    }

    private func persist(_ events: [TimedOverlayEvent]) throws {
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }
}
