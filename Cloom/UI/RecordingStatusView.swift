import SwiftUI

struct RecordingStatusView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch coordinator.phase {
        case .idle:
            "Ready"
        case .preparing:
            "Preparing recording"
        case .countdown:
            "Starting in 3…"
        case .recording:
            "Recording"
        case let .exporting(progress):
            "Preparing video \(Int(progress * 100))%"
        case let .finished(outputURL):
            "Saved to \(outputURL.lastPathComponent)"
        case let .failed(failure):
            failure.message
        }
    }

    private var indicatorColor: Color {
        switch coordinator.phase {
        case .recording:
            .red
        case .failed:
            .orange
        case .finished:
            .green
        default:
            .secondary
        }
    }
}

private extension RecordingFailure {
    var message: String {
        switch self {
        case let .permissionDenied(permission):
            "\(permission.rawValue.capitalized) access is required"
        case let .captureFailed(message), let .exportFailed(message):
            message
        }
    }
}
