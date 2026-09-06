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
        let selection = CaptureSourceSelection(
            filter: filter,
            title: title,
            kind: kind,
            contentRect: contentRect,
            presentationFrame: CaptureDisplayFrameResolver.resolve(
                contentRect: contentRect,
                screenFrames: NSScreen.screens.map(\.frame)
            ),
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        resume(with: .success(selection))
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
