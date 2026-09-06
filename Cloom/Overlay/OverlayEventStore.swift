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
        events = [TimedOverlayEvent(timeSeconds: 0, state: initialState)]
        try persist()
    }

    func append(state: OverlayState, at timeSeconds: Double) throws {
        guard timeSeconds >= 0 else {
            throw OverlayEventStoreError.negativeTimestamp
        }
        guard let latestEvent = events.last, timeSeconds >= latestEvent.timeSeconds else {
            throw OverlayEventStoreError.nonMonotonicTimestamp
        }
        guard latestEvent.state != state else {
            return
        }

        events.append(TimedOverlayEvent(timeSeconds: timeSeconds, state: state))
        try persist()
    }

    func state(at timeSeconds: Double) -> OverlayState {
        events.last(where: { $0.timeSeconds <= timeSeconds })?.state ?? events[0].state
    }

    func finish() throws {
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }
}
