import Combine
import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published private(set) var phase: RecordingPhase = .idle

    func beginPreparing() throws {
        guard phase == .idle else {
            throw invalidTransition("beginPreparing")
        }
        phase = .preparing
    }

    func beginCountdown() throws {
        guard phase == .preparing else {
            throw invalidTransition("beginCountdown")
        }
        phase = .countdown
    }

    func beginRecording() throws {
        guard phase == .countdown else {
            throw invalidTransition("beginRecording")
        }
        phase = .recording
    }

    func beginStopping() throws {
        guard phase == .recording else {
            throw invalidTransition("beginStopping")
        }
        phase = .stopping
    }

    func beginExporting() throws {
        switch phase {
        case .stopping, .failed:
            phase = .exporting(progress: 0)
        default:
            throw invalidTransition("beginExporting")
        }
    }

    func updateExportProgress(_ progress: Double) throws {
        guard case .exporting = phase else {
            throw invalidTransition("updateExportProgress")
        }
        phase = .exporting(progress: min(max(progress, 0), 1))
    }

    func finish(outputURL: URL) throws {
        guard case .exporting = phase else {
            throw invalidTransition("finish")
        }
        phase = .finished(outputURL: outputURL)
    }

    func fail(_ failure: RecordingFailure) {
        guard case .finished = phase else {
            phase = .failed(failure)
            return
        }
    }

    func reset() {
        phase = .idle
    }

    private func invalidTransition(_ action: String) -> RecordingTransitionError {
        .invalid(from: phase, action: action)
    }
}
