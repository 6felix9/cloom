import CoreGraphics

struct ScreenDescriptor: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// AppKit global coordinates.
    let frame: CGRect
}

enum CaptureFrameResolver {
    /// Live frame of the captured content in AppKit global coordinates; `screens.first` must be the primary screen.
    static func frame(
        for target: CaptureTarget,
        screens: [ScreenDescriptor],
        windowBounds: (CGWindowID) -> CGRect?
    ) -> CGRect? {
        switch target {
        case let .display(id):
            return screens.first { $0.displayID == id }?.frame
        case let .window(id):
            guard let primary = screens.first?.frame,
                  let bounds = windowBounds(id), !bounds.isEmpty else { return nil }
            return appKitRect(fromGlobal: bounds, primaryScreenFrame: primary)
        }
    }

    /// Converts a CoreGraphics global rect (top-left origin, y down) to AppKit (bottom-left origin, y up).
    static func appKitRect(fromGlobal rect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Pick-time fallback when the filter does not name its display or window (before macOS 15.2).
    static func resolve(
        contentRect: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect {
        guard let primaryScreenFrame = screenFrames.first else { return contentRect }

        let appKitContentRect = appKitRect(fromGlobal: contentRect, primaryScreenFrame: primaryScreenFrame)

        let intersections = screenFrames.map { screenFrame in
            let intersection = screenFrame.intersection(appKitContentRect)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screenFrame, area)
        }
        if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        let contentCenter = CGPoint(x: appKitContentRect.midX, y: appKitContentRect.midY)
        return screenFrames.min { lhs, rhs in
            squaredDistance(from: contentCenter, to: lhs) < squaredDistance(from: contentCenter, to: rhs)
        } ?? appKitContentRect
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        return dx * dx + dy * dy
    }
}
