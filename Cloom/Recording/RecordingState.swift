import Foundation

enum RecordingFailure: Error, Equatable, Sendable {
    case permissionDenied(CapturePermission)
    case captureFailed(String)
    case exportFailed(String)
}

enum RecordingPhase: Equatable, Sendable {
    case idle
    case preparing
    case countdown
    case recording
    case exporting(progress: Double)
    case finished(outputURL: URL)
    case failed(RecordingFailure)
}

enum RecordingTransitionError: Error, Equatable {
    case invalid(from: RecordingPhase, action: String)
}
