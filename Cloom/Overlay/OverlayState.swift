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

    /// Keeps the whole bubble inside a frame of the given width ÷ height. The bubble's diameter is a fraction of the
    /// frame's short edge, so along the long edge it spans a smaller normalized share and can sit closer to that edge.
    func clamped(aspectRatio: Double = 1) -> OverlayState {
        let aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        let halfFraction = size.presetFraction / 2
        let insetX = halfFraction * min(1, 1 / aspectRatio)
        let insetY = halfFraction * min(1, aspectRatio)
        return OverlayState(
            centerX: min(max(centerX, insetX), 1 - insetX),
            centerY: min(max(centerY, insetY), 1 - insetY),
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
