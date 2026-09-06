import CoreGraphics

enum CaptureDisplayFrameResolver {
    static func resolve(
        contentRect: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect {
        guard let primaryScreenFrame = screenFrames.first else { return contentRect }

        let appKitContentRect = CGRect(
            x: contentRect.minX,
            y: primaryScreenFrame.maxY - contentRect.maxY,
            width: contentRect.width,
            height: contentRect.height
        )
        guard !screenFrames.isEmpty else { return appKitContentRect }

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
