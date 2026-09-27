# Fix Issue #1 — Camera Bubble Placement on the Recorded Display or Window

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a display or window is picked, the camera bubble opens on that display or window. It can be dragged anywhere inside it, follows the window if the window moves, and appears in the export where it sat on screen.

**Issue:** https://github.com/6felix9/cloom/issues/1 (reopened after `1d86061` by the window-capture repro in the second comment)

**Architecture:** At pick time, store the identity of the captured content (display ID or window ID) instead of guessing its position from `SCContentFilter.contentRect`. Resolve that identity to a live AppKit frame when recording starts, and keep polling it for windows. Size the raw screen stream to the content's aspect ratio, and have the compositor place the bubble relative to the fitted content rather than the full canvas, so export geometry matches what was on screen. Exclude Cloom's own windows from display captures so the live panel is not burned into the screen track.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, CoreGraphics window list, CoreImage, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-06-cloom-mvp-design.md` (CameraBubblePanel, lines 116-124; Cloom exclusion, lines 55 and 99)

## Root Cause

`AppModel.startRecording()` clamps the bubble to `source.presentationFrame`. That rect is computed once, when the source is picked, in `ScreenSourcePicker.didUpdate` (`Cloom/Capture/ScreenSourcePicker.swift:71-80`), by `CaptureDisplayFrameResolver.resolve(contentRect:screenFrames:)`:

1. **`contentRect` does not locate a window.** The SDK documents it only as "Size and location of content in points". For the desktop-independent window filter the picker returns, its origin does not describe the window's desktop position, so the resolver's largest-overlap guess can pick any screen. The origin is probably (0,0), which always resolves to the menu-bar screen. This is unconfirmed: probing needs Screen Recording permission, so the fix stops relying on the value, and Task 1 logs it.
2. **Window capture clamps to a whole screen.** Even when the guess lands on the right screen, the bubble is normalized against the screen, while export maps it onto the window's video.
3. **The rect is a pick-time snapshot.** The window can move between picking and Record, and during recording. The spec says the panel tracks the window (line 124); nothing does.

`CameraBubblePanelController.panelDidMove()` then clamps every drag back into the wrong rect, which is the snap-back in the report.

Export composites the camera from `camera.mov` at the normalized overlay position (`VideoCompositor.swift:118-121`), independent of where the panel sits on screen. So the bubble should be in exports, but in the wrong place, not missing.

## Related Defects in Scope

- **Window video is letterboxed unpredictably.** The stream is fixed at 1920×1080. For window capture, `scalesToFit` defaults to `false`, which the SDK header says "only scales down", and window shadows are captured because `ignoreShadowsSingleWindow` is unset. The compositor places the bubble relative to the full 1920×1080 canvas, so on tall or small windows it lands in the black bars.
- **Cloom's own windows are in display captures.** `SCContentSharingPickerConfiguration.excludedBundleIDs` only "Excludes bundle IDs for picking". The picked display filter still captures the live bubble panel and setup window. That panel is burned into `screen.mov` under the composited bubble: a shadow halo, an 18%-alpha ghost while the camera is hidden, and a second offset bubble on non-16:9 displays. Today this is mostly masked because the bubble opens on the wrong display. Task 1 unmasks it for every display recording.

## Global Constraints

- Support macOS 15.0 and later. APIs newer than 15.0 (`includedDisplays`/`includedWindows`: 15.2) go behind `#available`, with the current behavior as the fallback.
- First-party Apple frameworks only; Swift 6 strict concurrency; zero compiler warnings.
- Final output stays 1920×1080 @ 30 FPS H.264. Only the raw screen track's dimensions change.
- Overlay coordinates stay normalized 0...1, relative to the captured content.
- Tests before production code; watch each focused test fail first.
- The Xcode project uses synchronized groups, so new or renamed files need no `project.pbxproj` edits.

---

### Task 1: Resolve the Captured Display or Window at Record Time

**Files:**
- Rename: `Cloom/Capture/CaptureDisplayFrameResolver.swift` → `Cloom/Capture/CaptureFrameResolver.swift`
- Rename: `CloomTests/CaptureDisplayFrameResolverTests.swift` → `CloomTests/CaptureFrameResolverTests.swift`
- Create: `Cloom/Capture/LiveCaptureGeometry.swift`
- Modify: `Cloom/Capture/CaptureSourceSelection.swift`
- Modify: `Cloom/Capture/ScreenSourcePicker.swift`
- Modify: `Cloom/App/AppModel.swift`
- Modify: fakes conforming to `ScreenCaptureSelection` in `CloomTests/AppModelTests.swift`, `CloomTests/RecordingSessionControllerTests.swift`, `CloomTests/ExportIntegrationTests.swift`

**Interfaces:**
- Produces: `enum CaptureTarget: Equatable, Sendable { case display(CGDirectDisplayID); case window(CGWindowID) }`.
- Produces: `ScreenCaptureSelection.target: CaptureTarget?`. It is `nil` before macOS 15.2, or when the filter does not name its content.
- Produces: `struct ScreenDescriptor: Equatable, Sendable { let displayID: CGDirectDisplayID; let frame: CGRect }`, with AppKit frames and the first element being the primary screen.
- Produces: `CaptureFrameResolver.frame(for:screens:windowBounds:) -> CGRect?`, `CaptureFrameResolver.appKitRect(fromGlobal:primaryScreenFrame:)`, plus the existing `resolve(contentRect:screenFrames:)` heuristic, kept as the fallback.
- Produces: `LiveCaptureGeometry.liveFrame(for:) -> CGRect?` (`@MainActor`, reads `NSScreen` and `CGWindowListCopyWindowInfo`).
- Keeps: `ScreenCaptureSelection.presentationFrame`, now documented as the pick-time fallback.

- [ ] **Step 1: Rename the resolver and its tests; add failing target-resolution tests**

`git mv` both files and rename the type to `CaptureFrameResolver`. The existing heuristic tests stay as-is. Add:

```swift
private let mainScreen = ScreenDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
private let rightScreen = ScreenDescriptor(displayID: 2, frame: CGRect(x: 1920, y: -200, width: 2560, height: 1440))

func testDisplayTargetResolvesToScreenWithMatchingID() {
    XCTAssertEqual(
        CaptureFrameResolver.frame(for: .display(2), screens: [mainScreen, rightScreen], windowBounds: { _ in nil }),
        rightScreen.frame
    )
}

func testUnknownDisplayIsUnresolved() {
    XCTAssertNil(CaptureFrameResolver.frame(for: .display(9), screens: [mainScreen, rightScreen],
                                            windowBounds: { _ in nil }))
}

func testWindowTargetResolvesToWindowFrameNotItsScreen() {
    // CoreGraphics global rect: origin at the primary display's top-left, y grows down.
    let frame = CaptureFrameResolver.frame(
        for: .window(42), screens: [mainScreen, rightScreen],
        windowBounds: { $0 == 42 ? CGRect(x: 2000, y: 300, width: 800, height: 600) : nil }
    )
    XCTAssertEqual(frame, CGRect(x: 2000, y: 180, width: 800, height: 600))
}

func testWindowLeftOfAndAboveMainScreenFlipsIntoAppKitCoordinates() {
    let frame = CaptureFrameResolver.frame(
        for: .window(7), screens: [mainScreen],
        windowBounds: { _ in CGRect(x: -1500, y: -900, width: 1000, height: 700) }
    )
    XCTAssertEqual(frame, CGRect(x: -1500, y: 1280, width: 1000, height: 700))
}

func testClosedOrEmptyWindowIsUnresolved() {
    XCTAssertNil(CaptureFrameResolver.frame(for: .window(7), screens: [mainScreen], windowBounds: { _ in nil }))
    XCTAssertNil(CaptureFrameResolver.frame(for: .window(7), screens: [mainScreen], windowBounds: { _ in .zero }))
}
```

- [ ] **Step 2: Run the suite and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureFrameResolverTests
```

Expected: compilation fails because `ScreenDescriptor`, `CaptureTarget` and `frame(for:...)` do not exist yet.

- [ ] **Step 3: Implement the pure resolver**

```swift
struct ScreenDescriptor: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// AppKit global coordinates.
    let frame: CGRect
}

enum CaptureFrameResolver {
    /// Live frame of the captured content in AppKit global coordinates; `screens.first` must be the primary screen.
    static func frame(
        for target: CaptureTarget,
        screens: [ScreenDescriptor],
        windowBounds: (CGWindowID) -> CGRect?
    ) -> CGRect? {
        switch target {
        case let .display(id):
            return screens.first { $0.displayID == id }?.frame
        case let .window(id):
            guard let primary = screens.first?.frame,
                  let bounds = windowBounds(id), !bounds.isEmpty else { return nil }
            return appKitRect(fromGlobal: bounds, primaryScreenFrame: primary)
        }
    }

    /// Converts a CoreGraphics global rect (top-left origin, y down) to AppKit (bottom-left origin, y up).
    static func appKitRect(fromGlobal rect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // Existing resolve(contentRect:screenFrames:) stays as the pre-15.2 fallback, rewritten to use appKitRect.
}
```

Add `CaptureTarget` next to `CaptureSourceKind` in `CaptureSourceSelection.swift`. Add `target` to the protocol and to `CaptureSourceSelection.init`. Add `let target: CaptureTarget? = nil` to every test fake.

- [ ] **Step 4: Read the target in the picker**

```swift
private static func target(of filter: SCContentFilter, kind: CaptureSourceKind) -> CaptureTarget? {
    guard #available(macOS 15.2, *) else { return nil }
    switch kind {
    case .display: return filter.includedDisplays.first.map { .display($0.displayID) }
    case .window: return filter.includedWindows.first.map { .window($0.windowID) }
    }
}
```

Pass `target: Self.target(of: filter, kind: kind)` into `CaptureSourceSelection`. Log one line (category `CaptureGeometry`) with the kind, `contentRect`, target, included window/display frames and `NSScreen` frames. This settles the open questions below on the first run with real hardware.

- [ ] **Step 5: Add the live geometry adapter**

```swift
@MainActor
enum LiveCaptureGeometry {
    static func screens() -> [ScreenDescriptor] {
        // NSScreen.screens[0] is the primary screen; map, don't compactMap, so it stays first.
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenDescriptor(displayID: number?.uint32Value ?? 0, frame: screen.frame)
        }
    }

    static func windowBounds(_ id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    static func liveFrame(for source: any ScreenCaptureSelection) -> CGRect? {
        guard let target = source.target else { return nil }
        return CaptureFrameResolver.frame(for: target, screens: screens(), windowBounds: windowBounds)
    }
}
```

- [ ] **Step 6: Place the bubble with the live frame**

In `AppModel.startRecording()`, resolve after `sessionController.start` returns, because the 3-second countdown is inside it and the window may move during it:

```swift
let captureFrame = LiveCaptureGeometry.liveFrame(for: source) ?? source.presentationFrame
bubblePanel.show(session: sessionController.previewSession, state: overlayState,
                 captureFrame: captureFrame) { [weak self] state in
    self?.applyOverlay(state)
}
```

- [ ] **Step 7: Run the affected suites and verify GREEN; type-check the app**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureFrameResolverTests -only-testing:CloomTests/AppModelTests -only-testing:CloomTests/RecordingSessionControllerTests -only-testing:CloomTests/ExportIntegrationTests
```

- [ ] **Step 8: Commit**

```bash
git add -A Cloom/Capture Cloom/App/AppModel.swift CloomTests
git commit -m "fix: place camera bubble on the captured display or window"
```

### Task 2: Follow the Captured Window While Recording

**Files:**
- Modify: `Cloom/Overlay/CameraBubblePanel.swift`
- Modify: `Cloom/App/AppModel.swift`
- Create: `CloomTests/CameraBubblePanelControllerTests.swift`

**Interfaces:**
- Produces: `CameraBubblePanelController.show(session:state:captureFrame:frameProvider:onStateChange:)`, where `frameProvider: (@MainActor () -> CGRect?)? = nil`.
- Produces: `CameraBubblePanelController.followCaptureFrame(_ frame: CGRect?)` and a test-only `panelFrame: CGRect?`.

- [ ] **Step 1: Add failing controller tests**

Tests are hosted in the app, so a real borderless `NSPanel` can be created with an empty `AVCaptureSession`.

```swift
@MainActor
final class CameraBubblePanelControllerTests: XCTestCase {
    func testFollowingMovedWindowKeepsNormalizedPlacementWithoutEmittingOverlayChange() {
        let controller = CameraBubblePanelController()
        var changes: [OverlayState] = []
        let state = OverlayState(centerX: 0.5, centerY: 0.5, size: .large, shape: .circle, isVisible: true)
        controller.show(session: AVCaptureSession(), state: state,
                        captureFrame: CGRect(x: 0, y: 0, width: 1600, height: 900)) { changes.append($0) }
        defer { controller.close() }

        let moved = CGRect(x: 1920, y: 100, width: 800, height: 1200)
        controller.followCaptureFrame(moved)

        XCTAssertEqual(controller.panelFrame, CameraBubbleGeometry.frame(state: state, in: moved))
        XCTAssertTrue(changes.isEmpty, "Following the window must not record an overlay event")
    }

    func testLostWindowKeepsLastFrame() {
        // show(...), followCaptureFrame(nil) and followCaptureFrame(.zero) leave panelFrame unchanged.
    }
}
```

- [ ] **Step 2: Run and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CameraBubblePanelControllerTests
```

- [ ] **Step 3: Implement tracking**

```swift
private var trackingTask: Task<Void, Never>?

// in show(...), after the panel is created:
if let frameProvider {
    trackingTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.followCaptureFrame(frameProvider())
        }
    }
}

func followCaptureFrame(_ frame: CGRect?) {
    guard let frame, !frame.isEmpty, frame != captureFrame else { return }
    captureFrame = frame
    guard let panel else { return }
    applyingFrame = true
    panel.setFrame(CameraBubbleGeometry.frame(state: state, in: frame), display: true)
    applyingFrame = false
    applyAppearance()
}

var panelFrame: CGRect? { panel?.frame }
```

Cancel and clear `trackingTask` in `close()`. In `AppModel`, pass a provider only for window targets:

```swift
var frameProvider: (@MainActor () -> CGRect?)?
if case .window = source.target {
    frameProvider = { LiveCaptureGeometry.liveFrame(for: source) }
}
bubblePanel.show(session: sessionController.previewSession, state: overlayState,
                 captureFrame: captureFrame, frameProvider: frameProvider) { [weak self] state in
    self?.applyOverlay(state)
}
```

- [ ] **Step 4: Verify GREEN and commit**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CameraBubblePanelControllerTests -only-testing:CloomTests/CameraBubbleGeometryTests
git add Cloom/Overlay/CameraBubblePanel.swift Cloom/App/AppModel.swift CloomTests/CameraBubblePanelControllerTests.swift
git commit -m "fix: keep camera bubble on the captured window when it moves"
```

### Task 3: Size the Screen Stream to the Captured Content

**Files:**
- Modify: `Cloom/Capture/ScreenStreamConfigurationFactory.swift`
- Modify: `Cloom/Recording/RecordingSessionController.swift`
- Modify: `Cloom/App/AppModel.swift`
- Modify: `CloomTests/ScreenStreamConfigurationTests.swift`
- Modify: `CloomTests/RecordingSessionControllerTests.swift`

**Interfaces:**
- Produces: `ScreenStreamConfigurationFactory.make(contentSize:includeSystemAudio:includeMicrophone:microphoneDeviceID:)`.
- Produces: `RecordingSessionConfiguration.contentSize: CGSize`, set through `init(source:settings:contentSize: CGSize? = nil)`, which falls back to `source.contentRect.size`.

- [ ] **Step 1: Add failing configuration tests**

Pass `contentSize: CGSize(width: 1920, height: 1080)` in the four existing tests, then add:

```swift
func testStreamKeepsContentAspectRatioInsideCanvas() {
    XCTAssertEqual(size(for: CGSize(width: 1440, height: 900)), [1728, 1080])   // 16:10 display
    XCTAssertEqual(size(for: CGSize(width: 800, height: 1200)), [720, 1080])    // portrait window
    XCTAssertEqual(size(for: CGSize(width: 400, height: 300)), [1440, 1080])    // small window scales up
    XCTAssertEqual(size(for: CGSize(width: 1000, height: 700)), [1542, 1080])   // rounds to even
    XCTAssertEqual(size(for: .zero), [1920, 1080])                              // unknown size
}

func testWindowCaptureScalesToFitWithoutShadows() {
    let configuration = make(contentSize: CGSize(width: 400, height: 300))
    XCTAssertTrue(configuration.scalesToFit)
    XCTAssertTrue(configuration.ignoreShadowsSingleWindow)
}
```

In `RecordingSessionControllerTests`, start with `RecordingSessionConfiguration(source: SessionTestScreenSelection(), settings: .fixture, contentSize: CGSize(width: 800, height: 1200))` and assert `fixture.screen.configuration` is 720×1080. Also assert that `.fixture` (no explicit size) stays 1920×1080.

- [ ] **Step 2: Run and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/ScreenStreamConfigurationTests -only-testing:CloomTests/RecordingSessionControllerTests
```

- [ ] **Step 3: Implement**

```swift
// Content aspect ratio fitted inside 1920×1080 with even dimensions, so the raw track carries no letterbox.
private static func streamSize(for contentSize: CGSize) -> (width: Int, height: Int) {
    guard contentSize.width > 0, contentSize.height > 0 else { return (1920, 1080) }
    let scale = min(1920 / contentSize.width, 1080 / contentSize.height)
    func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }
    return (min(even(contentSize.width * scale), 1920), min(even(contentSize.height * scale), 1080))
}
```

Set `scalesToFit = true` and `ignoreShadowsSingleWindow = true`, and leave `preservesAspectRatio` at its default. `RecordingSessionController` passes `configuration.contentSize` to `make`. In `AppModel.startRecording()`, before `start`, compute `LiveCaptureGeometry.liveFrame(for: source)?.size` and pass it as `contentSize`.

- [ ] **Step 4: Verify GREEN and commit**

```bash
git add Cloom/Capture/ScreenStreamConfigurationFactory.swift Cloom/Recording/RecordingSessionController.swift Cloom/App/AppModel.swift CloomTests/ScreenStreamConfigurationTests.swift CloomTests/RecordingSessionControllerTests.swift
git commit -m "fix: capture screen stream at the content aspect ratio"
```

### Task 4: Place the Exported Bubble Relative to the Screen Content

**Files:**
- Modify: `Cloom/Export/VideoCompositor.swift`
- Modify: `CloomTests/VideoCompositorTests.swift`

**Interfaces:**
- Changes: the `cameraOverlay(_:state:in:)` placement and diameter now come from the aspect-fitted screen rect, not `outputSize`. 16:9 content is unaffected.

- [ ] **Step 1: Add a failing pillarbox placement test; keep the timeline test on 16:9**

```swift
func testCameraOverlayIsPlacedWithinPillarboxedScreenContent() async throws {
    // 320×240 (4:3) screen → fitted content 1440×1080 at x = 240 on the 1920×1080 canvas.
    try await MediaFixtures.writeVideo(to: screenURL, epoch: 50, frames: [(50.1, 100), (50.2, 100), (50.3, 100)])
    try await MediaFixtures.writeVideo(to: cameraURL, epoch: 50, frames: [(50.1, 250), (50.2, 250), (50.3, 250)])
    try VideoCompositor.render(screenURL: screenURL, cameraURL: cameraURL,
                               events: [TimedOverlayEvent(timeSeconds: 0, state: .default)],
                               anchor: CMTime(seconds: 0.1, preferredTimescale: 600), outputURL: outputURL)

    let frame = try XCTUnwrap(try await MediaFixtures.decodedFrames(of: outputURL).last)
    let contentX = (240 + OverlayState.default.centerX * 1440) / 1920               // 0.77
    XCTAssertEqual(frame.gray(atX: contentX, y: OverlayState.default.centerY), 250, accuracy: 25)
    XCTAssertEqual(frame.gray(atX: OverlayState.default.centerX, y: OverlayState.default.centerY), 100,
                   accuracy: 25, "Canvas-relative position is screen content, not the bubble")
    XCTAssertLessThan(frame.gray(atX: 0.05, y: 0.5), 20, "Pillarbox stays black")
}
```

`testCameraAndOverlayEventsShareScreenTimeline` samples the bubble at the canvas-relative default center on the default 320×240 fixture. Pass `width: 320, height: 180` to its screen fixture so it keeps testing timing only.

- [ ] **Step 2: Run and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/VideoCompositorTests
```

- [ ] **Step 3: Implement**

Extract `fittedRect(for extent: CGSize, in canvas: CGSize) -> CGRect` and use it in both `aspectFit` and `cameraOverlay`:

```swift
let diameter = min(content.width, content.height) * CGFloat(state.size.presetFraction)
let center = CGPoint(x: content.minX + content.width * state.centerX,
                     y: content.minY + content.height * state.centerY)
```

- [ ] **Step 4: Verify GREEN (compositor, exporter, integration) and commit**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/VideoCompositorTests -only-testing:CloomTests/RecordingExporterTests -only-testing:CloomTests/ExportIntegrationTests
git add Cloom/Export/VideoCompositor.swift CloomTests/VideoCompositorTests.swift
git commit -m "fix: position exported camera bubble within the screen content"
```

### Task 5: Keep Cloom's Windows Out of Display Captures

**Files:**
- Modify: `Cloom/Capture/ScreenCaptureService.swift`

**Interfaces:**
- Changes: display streams (primary and the system-audio retry) use a filter that excludes Cloom's `SCRunningApplication`. If it cannot be built, they use the picker filter.

- [ ] **Step 1: Build the excluding filter**

```swift
private func captureFilter(for selection: any ScreenCaptureSelection) async -> SCContentFilter {
    guard selection.kind == .display, #available(macOS 15.2, *),
          let display = selection.filter.includedDisplays.first else { return selection.filter }
    do {
        // currentProcess needs no TCC consent, so it avoids Sequoia's "bypass the private window picker" prompt.
        let content = try await SCShareableContent.currentProcess
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let cloom = content.applications.first(where: { $0.processID == pid }) else {
            logger.warning("Cloom is not in current-process shareable content; its windows stay in the capture")
            return selection.filter
        }
        return SCContentFilter(display: display, excludingApplications: [cloom], exceptingWindows: [])
    } catch {
        logger.warning("Could not exclude Cloom windows: \(error.localizedDescription, privacy: .public)")
        return selection.filter
    }
}
```

Excluding the application, not individual windows, covers the bubble panel, which is created after the stream starts. Swift 6 may reject sending the non-`Sendable` `SCShareableContent` across isolation. If so, switch to `@preconcurrency import ScreenCaptureKit`, as `ScreenSourcePicker` already does.

- [ ] **Step 2: Use it for both `SCStream` constructions, build, run the full suite, commit**

This path needs real ScreenCaptureKit, so there is no unit test. It is covered by the manual checks in Task 6.

```bash
git add Cloom/Capture/ScreenCaptureService.swift
git commit -m "fix: exclude Cloom windows from display captures"
```

### Task 6: Full Verification and Manual Hardware Checks

- [ ] **Step 1: Full suite and warning-free build**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 2: Manual checks on a two-monitor setup**

Watch the log with `log stream --predicate 'subsystem == "com.tzefoong.Cloom"'`.

1. Record the secondary display, with it arranged left, right, above, and below the primary. The bubble opens on it and drags to every edge and corner without snapping back.
2. Record a window on the primary display (the second comment's repro). The bubble opens over that window and stays inside it.
3. Record a window on the secondary display, then drag the window to the other display mid-recording. The bubble follows.
4. Record a portrait or small window and export. The bubble sits over the window content at the same relative spot as on screen, not in the black bars.
5. Record a display, hide the camera halfway, and export. There is no ghost or double bubble, and the setup window is not visible.
6. Check the `CaptureGeometry` log lines: `includedWindows` / `includedDisplays` are populated and the resolved frame matches the real window or display.

- [ ] **Step 3: Update `AGENTS.md` codebase map** with `CaptureFrameResolver.swift` and `LiveCaptureGeometry.swift` under `Capture/`.

- [ ] **Step 4: Draft the issue #1 comment** summarizing root cause, fix, and manual results. Confirm with the owner before posting.

## Open Questions and Risks

- [ ] **Does the picker's filter populate `includedWindows` / `includedDisplays`?** The headers expose them from macOS 15.2, but this is unverified for picker-created filters. The Task 1 log answers it on the first run. Contingency if they are empty: resolve the window by matching `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` entries whose bounds size equals `contentRect.size`, front-most first.
- [ ] **What is `contentRect`'s origin for window filters?** Irrelevant once targets resolve; logged for the record.
- [ ] **Does `SCShareableContent.currentProcess` list Cloom's own `SCRunningApplication`?** Unverified. Task 5 falls back and logs if not.
- [ ] **Deployment target.** On 15.0–15.1, window capture keeps the old screen-level heuristic. Alternative: raise the target to 15.2 and delete the fallback.

## Out of Scope

- Resizing the captured window mid-recording. The bubble follows on screen, but the stream size is fixed at start, so SCK letterboxes the new shape and the export mapping becomes approximate.
- `OverlayState.clamped()` insets both axes by `presetFraction / 2`, which is conservative on the long axis. It is harmless and unchanged.

## Environment Note

The machine this plan was written on has only Command Line Tools (no Xcode.app), so `xcodebuild` cannot run there. `swiftc -typecheck -swift-version 6 -target arm64-apple-macos15.0 -sdk $(xcrun --show-sdk-path) $(find Cloom -name '*.swift')` works for compile checks. Run the test steps on a machine with Xcode 26.
