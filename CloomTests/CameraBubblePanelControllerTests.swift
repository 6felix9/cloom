import AVFoundation
import XCTest
@testable import Cloom

@MainActor
final class CameraBubblePanelControllerTests: XCTestCase {
    private let state = OverlayState(centerX: 0.5, centerY: 0.5, size: .large, shape: .circle, isVisible: true)
    // Gives an integral bubble frame; AppKit rounds panel frames to whole points.
    private let initialFrame = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testFollowingMovedWindowKeepsNormalizedPlacementWithoutEmittingOverlayChange() {
        let controller = CameraBubblePanelController()
        var changes: [OverlayState] = []
        controller.show(session: AVCaptureSession(), state: state, captureFrame: initialFrame) { changes.append($0) }
        defer { controller.close() }

        let moved = CGRect(x: 1920, y: 100, width: 800, height: 1200)
        controller.followCaptureFrame(moved)

        XCTAssertEqual(controller.panelFrame, CameraBubbleGeometry.frame(state: state, in: moved))
        XCTAssertTrue(changes.isEmpty, "Following the window must not record an overlay event")
    }

    func testLostWindowKeepsLastFrame() {
        let controller = CameraBubblePanelController()
        controller.show(session: AVCaptureSession(), state: state, captureFrame: initialFrame) { _ in }
        defer { controller.close() }

        controller.followCaptureFrame(nil)
        controller.followCaptureFrame(.zero)

        XCTAssertEqual(controller.panelFrame, CameraBubbleGeometry.frame(state: state, in: initialFrame))
    }

    func testSizeChangeAfterFollowingUsesNewFrame() {
        let controller = CameraBubblePanelController()
        controller.show(session: AVCaptureSession(), state: state, captureFrame: initialFrame) { _ in }
        defer { controller.close() }
        let moved = CGRect(x: -1200, y: 300, width: 1000, height: 700)
        controller.followCaptureFrame(moved)

        var small = state
        small.size = .small
        controller.update(state: small)

        XCTAssertEqual(controller.panelFrame, CameraBubbleGeometry.frame(state: small, in: moved))
    }
}
