import AVFoundation
import XCTest
@testable import Cloom

@MainActor
final class CameraBubblePanelControllerTests: XCTestCase {
    private let state = OverlayState(centerX: 0.5, centerY: 0.5, size: .large, shape: .circle, isVisible: true)
    // A captured window on a display to the right of the primary. Integral bubble frames: AppKit rounds to points.
    private let window = CGRect(x: 2000, y: 200, width: 1600, height: 800)

    func testShowPlacesBubbleInsideCapturedWindow() throws {
        let controller = CameraBubblePanelController()
        controller.show(session: AVCaptureSession(), state: state, captureFrame: window) { _ in }
        defer { controller.close() }

        let frame = try XCTUnwrap(controller.panelFrame)
        XCTAssertTrue(window.contains(frame), "\(frame) is outside the captured window \(window)")
    }

    func testDraggingOntoAnotherDisplayKeepsBubbleInsideCapturedWindow() throws {
        let controller = CameraBubblePanelController()
        var changes: [OverlayState] = []
        controller.show(session: AVCaptureSession(), state: state, captureFrame: window) { changes.append($0) }
        defer { controller.close() }

        controller.handleDrag(toCenter: CGPoint(x: 500, y: 500))

        let frame = try XCTUnwrap(controller.panelFrame)
        XCTAssertTrue(window.contains(frame), "\(frame) left the captured window \(window)")
        XCTAssertEqual(frame.minX, window.minX, accuracy: 0.5)
        XCTAssertEqual(changes.last?.centerX ?? -1, 0.0625, accuracy: 0.0001)
    }

    func testDraggingToWindowCornersReachesTheEdges() throws {
        let controller = CameraBubblePanelController()
        controller.show(session: AVCaptureSession(), state: state, captureFrame: window) { _ in }
        defer { controller.close() }

        controller.handleDrag(toCenter: CGPoint(x: window.maxX + 300, y: window.maxY + 300))
        var frame = try XCTUnwrap(controller.panelFrame)
        XCTAssertEqual(frame.maxX, window.maxX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, window.maxY, accuracy: 0.5)

        controller.handleDrag(toCenter: CGPoint(x: window.minX - 300, y: window.minY - 300))
        frame = try XCTUnwrap(controller.panelFrame)
        XCTAssertEqual(frame.minX, window.minX, accuracy: 0.5)
        XCTAssertEqual(frame.minY, window.minY, accuracy: 0.5)
    }

    func testResizingBubbleNearEdgeStaysInsideCapturedWindow() throws {
        let controller = CameraBubblePanelController()
        controller.show(session: AVCaptureSession(), state: state, captureFrame: window) { _ in }
        defer { controller.close() }
        var small = state
        small.size = .small
        controller.update(state: small)
        controller.handleDrag(toCenter: CGPoint(x: window.minX, y: window.midY))

        var large = small
        large.centerX = 0.01
        large.size = .large
        controller.update(state: large)

        let frame = try XCTUnwrap(controller.panelFrame)
        XCTAssertTrue(window.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(frame) left \(window)")
    }
}
