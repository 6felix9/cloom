import Foundation

struct OverlayState: Codable, Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var size: OverlaySize
    var shape: OverlayShape
    var isVisible: Bool

    static let `default` = OverlayState(
        centerX: 0.86,
        centerY: 0.82,
        size: .medium,
        shape: .circle,
        isVisible: true
    )

    func clamped() -> OverlayState {
        let inset = size.presetFraction / 2
        return OverlayState(
            centerX: min(max(centerX, inset), 1 - inset),
            centerY: min(max(centerY, inset), 1 - inset),
            size: size,
            shape: shape,
            isVisible: isVisible
        )
    }
}

struct TimedOverlayEvent: Codable, Equatable, Sendable {
    let timeSeconds: Double
    let state: OverlayState
}

extension OverlaySize {
    var presetFraction: Double {
        switch self {
        case .small:
            0.12
        case .medium:
            0.18
        case .large:
            0.25
        }
    }
}
