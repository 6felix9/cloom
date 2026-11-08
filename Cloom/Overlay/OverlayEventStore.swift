import Foundation

enum OverlayEventStoreError: Error, Equatable {
    case negativeTimestamp
    case nonMonotonicTimestamp
}

final class OverlayEventStore {
    let fileURL: URL
    private(set) var events: [TimedOverlayEvent]
    /// Width ÷ height of the captured content the overlay is normalized to.
    let aspectRatio: Double

    init(fileURL: URL, initialState: OverlayState, aspectRatio: Double = 1) throws {
        self.fileURL = fileURL
        self.aspectRatio = aspectRatio
        events = [TimedOverlayEvent(timeSeconds: 0, state: initialState.clamped(aspectRatio: aspectRatio))]
        try persist(events)
    }

    func append(state: OverlayState, at timeSeconds: Double) throws {
        guard timeSeconds >= 0 else {
            throw OverlayEventStoreError.negativeTimestamp
        }
        guard let latestEvent = events.last, timeSeconds >= latestEvent.timeSeconds else {
            throw OverlayEventStoreError.nonMonotonicTimestamp
        }
        let clampedState = state.clamped(aspectRatio: aspectRatio)
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
