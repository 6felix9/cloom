import CoreGraphics
import ScreenCaptureKit

enum CaptureSourceKind: String, Codable, Sendable {
    case display
    case window
}

@MainActor
protocol ScreenCaptureSelection: AnyObject {
    var filter: SCContentFilter { get }
    var title: String { get }
    var kind: CaptureSourceKind { get }
    var contentRect: CGRect { get }
    var pointPixelScale: CGFloat { get }
}

@MainActor
final class CaptureSourceSelection: ScreenCaptureSelection {
    let filter: SCContentFilter
    let title: String
    let kind: CaptureSourceKind
    let contentRect: CGRect
    let pointPixelScale: CGFloat

    init(
        filter: SCContentFilter,
        title: String,
        kind: CaptureSourceKind,
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) {
        self.filter = filter
        self.title = title
        self.kind = kind
        self.contentRect = contentRect
        self.pointPixelScale = pointPixelScale
    }
}
