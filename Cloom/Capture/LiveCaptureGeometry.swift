import AppKit
import CoreGraphics
import OSLog

@MainActor
enum LiveCaptureGeometry {
    static let logger = Logger(subsystem: "com.tzefoong.Cloom", category: "CaptureGeometry")

    static func screens() -> [ScreenDescriptor] {
        // NSScreen.screens[0] is the primary screen; map rather than compactMap so it stays first.
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenDescriptor(displayID: number?.uint32Value ?? 0, frame: screen.frame)
        }
    }

    /// CoreGraphics global bounds of an on-screen window, or nil once it has closed.
    static func windowBounds(_ id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// Current frame of the captured display or window in AppKit coordinates, or nil when it cannot be resolved.
    static func liveFrame(for source: any ScreenCaptureSelection) -> CGRect? {
        guard let target = source.target else { return nil }
        return CaptureFrameResolver.frame(for: target, screens: screens(), windowBounds: windowBounds)
    }
}
