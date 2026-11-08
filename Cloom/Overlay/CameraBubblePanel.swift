import AppKit
import AVFoundation
import SwiftUI

enum CameraBubbleGeometry {
    static func diameter(for size: OverlaySize, in captureFrame: CGRect) -> CGFloat {
        min(captureFrame.width, captureFrame.height) * CGFloat(size.presetFraction)
    }

    static func aspectRatio(of captureFrame: CGRect) -> Double {
        captureFrame.height > 0 ? Double(captureFrame.width / captureFrame.height) : 1
    }

    static func frame(state: OverlayState, in captureFrame: CGRect) -> CGRect {
        let state = state.clamped(aspectRatio: aspectRatio(of: captureFrame))
        let diameter = diameter(for: state.size, in: captureFrame)
        let center = CGPoint(
            x: captureFrame.minX + captureFrame.width * state.centerX,
            y: captureFrame.minY + captureFrame.height * state.centerY
        )
        return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                      width: diameter, height: diameter)
    }

    static func normalizedCenter(for center: CGPoint, size: OverlaySize, in captureFrame: CGRect) -> CGPoint {
        guard captureFrame.width > 0, captureFrame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let diameter = diameter(for: size, in: captureFrame)
        let insetX = diameter / (2 * captureFrame.width)
        let insetY = diameter / (2 * captureFrame.height)
        return CGPoint(
            x: min(max((center.x - captureFrame.minX) / captureFrame.width, insetX), 1 - insetX),
            y: min(max((center.y - captureFrame.minY) / captureFrame.height, insetY), 1 - insetY)
        )
    }
}

@MainActor
final class CameraBubblePanelController: NSObject {
    private var panel: NSPanel?
    private var captureFrame = CGRect.zero
    private var state = OverlayState.default
    private var onStateChange: ((OverlayState) -> Void)?
    private var moveObserver: NSObjectProtocol?
    private var applyingFrame = false

    var panelFrame: CGRect? { panel?.frame }

    /// `captureFrame` is the captured display or window in AppKit global coordinates; the bubble stays inside it.
    func show(session: AVCaptureSession, state: OverlayState, captureFrame: CGRect,
              onStateChange: @escaping (OverlayState) -> Void) {
        close()
        self.captureFrame = captureFrame
        self.state = clamped(state)
        self.onStateChange = onStateChange

        let panel = NSPanel(contentRect: CameraBubbleGeometry.frame(state: self.state, in: captureFrame),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: CameraPreviewView(session: session))
        self.panel = panel
        applyAppearance()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidMove() }
        }
        panel.orderFrontRegardless()
    }

    func update(state: OverlayState) {
        self.state = clamped(state)
        guard let panel else { return }
        applyingFrame = true
        panel.setFrame(CameraBubbleGeometry.frame(state: self.state, in: captureFrame), display: true, animate: true)
        applyingFrame = false
        applyAppearance()
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        onStateChange = nil
    }

    private func panelDidMove() {
        guard !applyingFrame, let panel else { return }
        handleDrag(toCenter: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
    }

    /// Re-normalizes a dragged bubble and snaps it back inside the captured frame.
    func handleDrag(toCenter center: CGPoint) {
        guard let panel else { return }
        let normalized = CameraBubbleGeometry.normalizedCenter(for: center, size: state.size, in: captureFrame)
        state.centerX = normalized.x
        state.centerY = normalized.y
        state = clamped(state)
        applyingFrame = true
        panel.setFrameOrigin(CameraBubbleGeometry.frame(state: state, in: captureFrame).origin)
        applyingFrame = false
        onStateChange?(state)
    }

    private func clamped(_ state: OverlayState) -> OverlayState {
        state.clamped(aspectRatio: CameraBubbleGeometry.aspectRatio(of: captureFrame))
    }

    private func applyAppearance() {
        guard let view = panel?.contentView else { return }
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = state.shape == .circle ? view.bounds.width / 2 : view.bounds.width * 0.16
        panel?.alphaValue = state.isVisible ? 1 : 0.18
    }
}
