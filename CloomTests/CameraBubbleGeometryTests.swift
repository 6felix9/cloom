import CoreGraphics
import XCTest
@testable import Cloom

final class CameraBubbleGeometryTests: XCTestCase {
    func testLargeBubbleFrameUsesQuarterOfShortEdge() {
        let captureFrame = CGRect(x: 100, y: 200, width: 1600, height: 900)
        let state = OverlayState(centerX: 0.5, centerY: 0.5, size: .large, shape: .circle, isVisible: true)

        XCTAssertEqual(
            CameraBubbleGeometry.frame(state: state, in: captureFrame),
            CGRect(x: 787.5, y: 537.5, width: 225, height: 225)
        )
    }

    func testDraggedCenterNormalizesAndClamps() {
        let captureFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(
            CameraBubbleGeometry.normalizedCenter(
                for: CGPoint(x: 990, y: 790), size: .medium, in: captureFrame
            ),
            CGPoint(x: 0.928, y: 0.91)
        )
    }
}
