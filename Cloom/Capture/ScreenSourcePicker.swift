import Foundation
import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
protocol ScreenSourcePicking: AnyObject {
    func present() async throws -> (any ScreenCaptureSelection)?
}

@MainActor
final class ScreenSourcePicker: NSObject, ScreenSourcePicking {
    private enum PickerError: Error {
        case alreadyPresenting
    }

    private let picker: SCContentSharingPicker
    private let observer: Observer
    private var continuation: CheckedContinuation<(any ScreenCaptureSelection)?, Error>?

    init(picker: SCContentSharingPicker = .shared) {
        self.picker = picker
        self.observer = Observer()
        super.init()

        observer.owner = self

        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        picker.defaultConfiguration = configuration
        picker.add(observer)
    }

    deinit {
        picker.remove(observer)
    }

    func present() async throws -> (any ScreenCaptureSelection)? {
        guard continuation == nil else {
            throw PickerError.alreadyPresenting
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            picker.isActive = true
            picker.present()
        }
    }

    private func didCancel() {
        resume(with: .success(nil))
    }

    private func didUpdate(with filter: SCContentFilter) {
        let kind: CaptureSourceKind
        let title: String

        switch filter.style {
        case .display:
            kind = .display
            title = "Selected display"
        case .window:
            kind = .window
            title = "Selected window"
        default:
            resume(with: .success(nil))
            return
        }

        let contentRect = filter.contentRect
        let target = Self.target(of: filter, kind: kind)
        let screenFrames = NSScreen.screens.map(\.frame)
        LiveCaptureGeometry.logger.info(
            "Picked \(kind.rawValue, privacy: .public): target \(String(describing: target), privacy: .public), contentRect \(String(describing: contentRect), privacy: .public), included \(Self.includedFrames(of: filter), privacy: .public), screens \(String(describing: screenFrames), privacy: .public)"
        )
        let selection = CaptureSourceSelection(
            filter: filter,
            title: title,
            kind: kind,
            contentRect: contentRect,
            target: target,
            presentationFrame: CaptureFrameResolver.resolve(
                contentRect: contentRect,
                screenFrames: screenFrames
            ),
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        resume(with: .success(selection))
    }

    private static func target(of filter: SCContentFilter, kind: CaptureSourceKind) -> CaptureTarget? {
        guard #available(macOS 15.2, *) else { return nil }
        switch kind {
        case .display: return filter.includedDisplays.first.map { .display($0.displayID) }
        case .window: return filter.includedWindows.first.map { .window($0.windowID) }
        }
    }

    private static func includedFrames(of filter: SCContentFilter) -> String {
        guard #available(macOS 15.2, *) else { return "unavailable" }
        let displays = filter.includedDisplays.map { "display \($0.displayID) \($0.frame)" }
        let windows = filter.includedWindows.map { "window \($0.windowID) \($0.frame)" }
        return String(describing: displays + windows)
    }

    private func didFailToStart(with error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<(any ScreenCaptureSelection)?, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private final class Observer: NSObject, @unchecked Sendable, SCContentSharingPickerObserver {
        weak var owner: ScreenSourcePicker?

        func contentSharingPicker(
            _ picker: SCContentSharingPicker,
            didCancelFor stream: SCStream?
        ) {
            Task { @MainActor [weak owner] in
                owner?.didCancel()
            }
        }

        func contentSharingPicker(
            _ picker: SCContentSharingPicker,
            didUpdateWith filter: SCContentFilter,
            for stream: SCStream?
        ) {
            Task { @MainActor [weak owner] in
                owner?.didUpdate(with: filter)
            }
        }

        func contentSharingPickerStartDidFailWithError(_ error: Error) {
            Task { @MainActor [weak owner] in
                owner?.didFailToStart(with: error)
            }
        }
    }
}
