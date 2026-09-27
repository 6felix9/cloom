import CoreGraphics
import ScreenCaptureKit

enum CaptureSourceKind: String, Codable, Sendable {
    case display
    case window
}

/// Identity of the captured content, resolved to a live frame when recording starts.
enum CaptureTarget: Equatable, Sendable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
}

@MainActor
protocol ScreenCaptureSelection: AnyObject, Sendable {
    var filter: SCContentFilter { get }
    var title: String { get }
    var kind: CaptureSourceKind { get }
    var contentRect: CGRect { get }
    /// Nil before macOS 15.2, or when the filter does not name its display or window.
    var target: CaptureTarget? { get }
    /// Pick-time estimate in AppKit coordinates, used only when `target` cannot be resolved.
    var presentationFrame: CGRect { get }
    var pointPixelScale: CGFloat { get }
}

@MainActor
final class CaptureSourceSelection: ScreenCaptureSelection, @unchecked Sendable {
    let filter: SCContentFilter
    let title: String
    let kind: CaptureSourceKind
    let contentRect: CGRect
    let target: CaptureTarget?
    let presentationFrame: CGRect
    let pointPixelScale: CGFloat

    init(
        filter: SCContentFilter,
        title: String,
        kind: CaptureSourceKind,
        contentRect: CGRect,
        target: CaptureTarget?,
        presentationFrame: CGRect,
        pointPixelScale: CGFloat
    ) {
        self.filter = filter
        self.title = title
        self.kind = kind
        self.contentRect = contentRect
        self.target = target
        self.presentationFrame = presentationFrame
        self.pointPixelScale = pointPixelScale
    }
}
