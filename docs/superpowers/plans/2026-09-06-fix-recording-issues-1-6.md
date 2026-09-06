# Fix Recording Issues #1-#6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve GitHub issues #1 through #6 by supporting optional camera and microphone capture, correct multi-display bubble placement, conditional readable recording controls, and an immediate single-click stopping transition.

**Architecture:** Persist explicit input-inclusion flags and carry the immutable settings snapshot through capture and export. Resolve ScreenCaptureKit rectangles into an AppKit presentation display before showing the bubble, and add `.stopping` between recording and export so UI state changes before asynchronous teardown. Keep hardware services behind their existing protocols and test decisions through observable configuration, service-call order, exported tracks, and pure geometry.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, CoreImage, XCTest, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-09-06-optional-capture-and-recording-controls-design.md`

## Global Constraints

- Support macOS 15.0 and later.
- Use only first-party Apple frameworks; add no packages or CocoaPods.
- Preserve Swift 6 strict-concurrency correctness and zero compiler warnings.
- Preserve 1920 by 1080 at 30 FPS H.264 video and AAC audio when audio exists.
- Keep overlay coordinates normalized from 0 through 1 for export.
- Delete a recording workspace only after verified export success.
- Write tests before production code and observe each focused test fail for the intended missing behavior.

---

### Task 1: Persist Optional Input Choices and Make Readiness Conditional

**Files:**
- Modify: `Cloom/Settings/RecordingSettings.swift`
- Modify: `Cloom/App/AppModel.swift`
- Modify: `Cloom/UI/SetupView.swift`
- Modify: `CloomTests/SettingsStoreTests.swift`
- Modify: `CloomTests/SetupReadinessTests.swift`
- Modify: `CloomTests/AppModelTests.swift`

**Interfaces:**
- Produces: `RecordingSettings.includeCamera: Bool` and `RecordingSettings.includeMicrophone: Bool`, both defaulting to `true` and default-decoding legacy payloads to `true`.
- Produces: `AppModel.hasScreenCapturePermission`, conditional `isReadyToConfigure`, and conditional `isReadyToRecord`.
- Consumes: existing permission dictionary, selected source, and selected device IDs.

- [ ] **Step 1: Add failing persistence and readiness tests**

Add a legacy payload decode test whose literal JSON omits the new fields, and extend defaults/round-trip assertions:

```swift
func testLegacySettingsDecodeWithInputsEnabled() throws {
    let data = Data(#"{"includeSystemAudio":false,"overlayShape":"circle","overlaySize":"medium","cameraDeviceID":"camera-1","microphoneDeviceID":"mic-1"}"#.utf8)
    let settings = try JSONDecoder().decode(RecordingSettings.self, from: data)

    XCTAssertTrue(settings.includeCamera)
    XCTAssertTrue(settings.includeMicrophone)
    XCTAssertEqual(settings.cameraDeviceID, "camera-1")
    XCTAssertEqual(settings.microphoneDeviceID, "mic-1")
}
```

Add setup/readiness tests with hand-built permission maps:

```swift
func testScreenOnlyConfigurationIgnoresCameraAndMicrophonePermissions() async {
    let settings = RecordingSettings(
        includeSystemAudio: false,
        includeCamera: false,
        includeMicrophone: false,
        overlayShape: .circle,
        overlaySize: .medium,
        cameraDeviceID: nil,
        microphoneDeviceID: nil
    )
    let model = AppModel(
        permissionChecker: FakePermissionChecker(statuses: [
            .screen: .authorized, .camera: .denied, .microphone: .denied,
        ]),
        settingsStore: InMemorySettingsStore(value: settings),
        sourcePicker: FakeScreenSourcePicker(results: [.selection(FakeScreenCaptureSelection(title: "Display 1"))])
    )

    await model.refreshPermissions()
    await model.selectCaptureSource()

    XCTAssertTrue(model.hasScreenCapturePermission)
    XCTAssertTrue(model.isReadyToConfigure)
    XCTAssertTrue(model.isReadyToRecord)
}
```

Add separate cases proving an enabled camera and enabled microphone each still require their matching permission and nonempty device ID.

Add a persistence assertion that switching `includeCamera` or `includeMicrophone` off leaves the corresponding stored device ID unchanged so re-enabling restores the previous choice.

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/SettingsStoreTests -only-testing:CloomTests/SetupReadinessTests -only-testing:CloomTests/AppModelTests
```

Expected: compilation or assertion failures because the two inclusion properties and conditional readiness behavior do not exist.

- [ ] **Step 3: Implement backward-compatible settings and readiness**

Add defaulted stored properties so existing memberwise call sites continue compiling:

```swift
struct RecordingSettings: Codable, Equatable, Sendable {
    var includeSystemAudio: Bool
    var includeCamera: Bool = true
    var includeMicrophone: Bool = true
    var overlayShape: OverlayShape
    var overlaySize: OverlaySize
    var cameraDeviceID: String?
    var microphoneDeviceID: String?
}
```

Add custom decoding in an extension so the memberwise initializer remains available:

```swift
extension RecordingSettings {
    private enum CodingKeys: String, CodingKey {
        case includeSystemAudio, includeCamera, includeMicrophone
        case overlayShape, overlaySize, cameraDeviceID, microphoneDeviceID
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        includeSystemAudio = try values.decode(Bool.self, forKey: .includeSystemAudio)
        includeCamera = try values.decodeIfPresent(Bool.self, forKey: .includeCamera) ?? true
        includeMicrophone = try values.decodeIfPresent(Bool.self, forKey: .includeMicrophone) ?? true
        overlayShape = try values.decode(OverlayShape.self, forKey: .overlayShape)
        overlaySize = try values.decode(OverlaySize.self, forKey: .overlaySize)
        cameraDeviceID = try values.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        microphoneDeviceID = try values.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
    }
}
```

Update `RecordingSettings.default` with both flags enabled. In `AppModel`, implement:

```swift
var hasScreenCapturePermission: Bool {
    permissions[.screen] == .authorized
}

var isReadyToConfigure: Bool {
    hasScreenCapturePermission &&
        (!settings.includeCamera || permissions[.camera] == .authorized) &&
        (!settings.includeMicrophone || permissions[.microphone] == .authorized)
}

var isReadyToRecord: Bool {
    isReadyToConfigure &&
        selectedCaptureSource != nil &&
        (!settings.includeCamera || settings.cameraDeviceID?.isEmpty == false) &&
        (!settings.includeMicrophone || settings.microphoneDeviceID?.isEmpty == false)
}
```

In `SetupView`, show recording configuration once `hasScreenCapturePermission` is true. Add explicit include toggles, conditionally show each device picker, and show `overlaySection` only when camera is included. Make device bindings assign nil as well as concrete IDs. Replace the fixed Record-button help text with a computed message that names the missing enabled requirement and use `Ready to record` when all prerequisites pass.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command. Expected: all selected suites pass with zero failures.

- [ ] **Step 5: Commit the settings/readiness slice**

```bash
git add Cloom/Settings/RecordingSettings.swift Cloom/App/AppModel.swift Cloom/UI/SetupView.swift CloomTests/SettingsStoreTests.swift CloomTests/SetupReadinessTests.swift CloomTests/AppModelTests.swift
git commit -m "feat: make recording inputs optional"
```

### Task 2: Make Camera and Microphone Capture Optional

**Files:**
- Modify: `Cloom/Capture/ScreenStreamConfigurationFactory.swift`
- Modify: `Cloom/Capture/ScreenCaptureService.swift`
- Modify: `Cloom/Recording/RecordingSessionController.swift`
- Modify: `CloomTests/ScreenStreamConfigurationTests.swift`
- Modify: `CloomTests/RecordingSessionControllerTests.swift`

**Interfaces:**
- Consumes: input flags and optional device IDs from Task 1.
- Produces: `ScreenStreamConfigurationFactory.make(includeSystemAudio:includeMicrophone:microphoneDeviceID:)`.
- Produces: `RecordingSessionError.missingCamera` and `.missingMicrophone`.
- Preserves: `ScreenCapturing` and `CameraCapturing` protocols.

- [ ] **Step 1: Add failing stream-configuration tests**

Update existing calls with `includeMicrophone: true`, then add:

```swift
func testScreenOnlyConfigurationDoesNotCaptureMicrophone() {
    let configuration = ScreenStreamConfigurationFactory.make(
        includeSystemAudio: false,
        includeMicrophone: false,
        microphoneDeviceID: "stored-but-disabled"
    )

    XCTAssertFalse(configuration.captureMicrophone)
    XCTAssertNil(configuration.microphoneCaptureDeviceID)
}

func testSystemAudioDoesNotRequireMicrophoneCapture() {
    let configuration = ScreenStreamConfigurationFactory.make(
        includeSystemAudio: true,
        includeMicrophone: false,
        microphoneDeviceID: nil
    )

    XCTAssertFalse(configuration.captureMicrophone)
    XCTAssertTrue(configuration.capturesAudio)
}
```

- [ ] **Step 2: Add failing session-controller tests**

Create a screen-only settings fixture and assert real controller decisions through fake service events and the captured configuration:

```swift
func testScreenOnlyStartAndStopSkipCameraAndMicrophone() async throws {
    let fixture = try Fixture(settings: .screenOnly)
    defer { fixture.removeWorkspace() }

    try await fixture.controller.start(configuration: fixture.configuration)

    XCTAssertEqual(fixture.order.events, ["screen.start"])
    XCTAssertFalse(try XCTUnwrap(fixture.screen.configuration).captureMicrophone)

    try await fixture.controller.stop()

    XCTAssertEqual(fixture.order.events, ["screen.start", "screen.stop"])
}
```

Add separate tests proving an enabled camera or microphone without its selected ID fails before either service starts.

- [ ] **Step 3: Run focused capture tests and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/ScreenStreamConfigurationTests -only-testing:CloomTests/RecordingSessionControllerTests
```

Expected: failures because microphone capture is unconditional and the controller rejects or starts both devices unconditionally.

- [ ] **Step 4: Implement optional stream outputs and services**

Change the factory signature and preserve all existing video settings:

```swift
static func make(
    includeSystemAudio: Bool,
    includeMicrophone: Bool,
    microphoneDeviceID: String?
) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.width = 1920
    configuration.height = 1080
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configuration.queueDepth = 5
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = true
    configuration.captureMicrophone = includeMicrophone
    configuration.microphoneCaptureDeviceID = includeMicrophone ? microphoneDeviceID : nil
    configuration.capturesAudio = includeSystemAudio
    configuration.excludesCurrentProcessAudio = true
    return configuration
}
```

In `ScreenCaptureService.start`, create and register a microphone track only when `configuration.captureMicrophone` is true. Change `ScreenStreamReceiver.microphone` to `CaptureMediaTrack?` and consume with optional chaining.

In `RecordingSessionController.start`, validate enabled IDs separately, call the new factory, and conditionally start the camera:

```swift
if configuration.settings.includeCamera,
   configuration.settings.cameraDeviceID?.isEmpty != false {
    throw RecordingSessionError.missingCamera
}
if configuration.settings.includeMicrophone,
   configuration.settings.microphoneDeviceID?.isEmpty != false {
    throw RecordingSessionError.missingMicrophone
}

let streamConfiguration = ScreenStreamConfigurationFactory.make(
    includeSystemAudio: configuration.settings.includeSystemAudio,
    includeMicrophone: configuration.settings.includeMicrophone,
    microphoneDeviceID: configuration.settings.microphoneDeviceID
)
```

Start camera only when enabled. In `stop`, stop camera only when `workspace.manifest.settings.includeCamera` is true. Preserve cleanup order, failure aggregation, manifest transitions, and screen finalization.

- [ ] **Step 5: Run focused capture tests and verify GREEN**

Run the Step 3 command. Expected: all selected suites pass.

- [ ] **Step 6: Commit the optional-capture slice**

```bash
git add Cloom/Capture/ScreenStreamConfigurationFactory.swift Cloom/Capture/ScreenCaptureService.swift Cloom/Recording/RecordingSessionController.swift CloomTests/ScreenStreamConfigurationTests.swift CloomTests/RecordingSessionControllerTests.swift
git commit -m "feat: skip disabled capture inputs"
```

### Task 3: Export Valid Video With No Camera or Microphone

**Files:**
- Modify: `Cloom/Export/RecordingExporter.swift`
- Modify: `CloomTests/AudioMixerTests.swift`
- Modify: `CloomTests/RecordingExporterTests.swift`

**Interfaces:**
- Consumes: immutable settings in `RecordingWorkspace.manifest`.
- Produces: screen-only and system-audio-only MP4s through the existing `RecordingExporting` interface.
- Preserves: `VideoCompositor.render(...cameraURL: URL?...)` and missing-file-tolerant `AudioMixer` behavior.

- [ ] **Step 1: Add a failing manifest-gating exporter test**

Create short real screen and camera tracks in a workspace whose `includeCamera` is false. Fill the screen frames blue, fill the camera frames red, place the overlay at the center, export, and inspect the center pixel of the first output frame. Assert it remains blue, proving the disabled camera was not composited. Use test-only `writeVideo(url:epoch:bgra:)` and `firstFrameBGRA(url:x:y:)` helpers built from `MediaSampleWriter`, `AVAssetReader`, and `CVPixelBuffer`; both helpers stay in `RecordingExporterTests.swift`. Also add a screen-only workspace with no audio and assert one video track and zero audio tracks:

```swift
func testExportWithoutCameraOrAudioCreatesVideoOnlyMP4() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = RecordingSettings.default
    settings.includeCamera = false
    settings.includeMicrophone = false
    let workspace = try RecordingWorkspace.create(baseDirectory: root, settings: settings)
    try await writeVideo(url: workspace.screenURL, epoch: 100, bgra: (255, 0, 0, 255))

    let output = try await RecordingExporter(
        outputDirectory: root.appending(path: "Movies", directoryHint: .isDirectory)
    ).export(workspace: workspace) { _ in }
    let asset = AVURLAsset(url: output)

    XCTAssertEqual(try await asset.loadTracks(withMediaType: .video).count, 1)
    XCTAssertEqual(try await asset.loadTracks(withMediaType: .audio).count, 0)
}
```

- [ ] **Step 2: Add a no-audio mixer regression test**

Call `AudioMixer.mux` with a real short video and absent audio URLs, then assert the MP4 has one video track and zero audio tracks. Add a second real-media case with an absent microphone file and a present system-audio file; assert the output has one video and one audio track.

- [ ] **Step 3: Run focused export tests and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/AudioMixerTests -only-testing:CloomTests/RecordingExporterTests
```

Expected: the manifest-gating test fails because the exporter currently passes the camera URL whenever the file exists. The no-audio test may already pass and then serves as a characterization test for behavior relied on by this feature.

- [ ] **Step 4: Gate camera composition on the capture snapshot**

```swift
let cameraURL = workspace.manifest.settings.includeCamera ? workspace.cameraURL : nil
try VideoCompositor.render(
    screenURL: workspace.screenURL,
    cameraURL: cameraURL,
    events: events,
    outputURL: renderedVideoURL
) { fraction in
    progress(fraction * 0.9)
}
```

Keep the existing audio file-existence checks. If the real no-audio test exposes an AVFoundation failure, export the video-only composition without an audio mix.

- [ ] **Step 5: Run focused export tests and verify GREEN**

Run the Step 3 command. Expected: all selected suites pass and screen-only output has exactly one video track and no audio tracks.

- [ ] **Step 6: Commit the export slice**

```bash
git add Cloom/Export/RecordingExporter.swift CloomTests/AudioMixerTests.swift CloomTests/RecordingExporterTests.swift
git commit -m "feat: export recordings without optional media"
```

### Task 4: Resolve the Bubble's Presentation Display

**Files:**
- Create: `Cloom/Capture/CaptureDisplayFrameResolver.swift`
- Create: `CloomTests/CaptureDisplayFrameResolverTests.swift`
- Modify: `Cloom/Capture/CaptureSourceSelection.swift`
- Modify: `Cloom/Capture/ScreenSourcePicker.swift`
- Modify: `Cloom/App/AppModel.swift`
- Modify: test fakes conforming to `ScreenCaptureSelection` in `CloomTests/AppModelTests.swift`, `CloomTests/RecordingSessionControllerTests.swift`, and `CloomTests/ExportIntegrationTests.swift`

**Interfaces:**
- Produces: `CaptureDisplayFrameResolver.resolve(contentRect:screenFrames:mainScreenFrame:) -> CGRect`.
- Produces: `ScreenCaptureSelection.presentationFrame: CGRect` in AppKit global coordinates.
- Consumes: `SCContentFilter.contentRect` and `NSScreen.screens` frames.

- [ ] **Step 1: Add failing coordinate conversion and display-selection tests**

Use literal display layouts and expected AppKit frames:

```swift
func testDisplayAboveMainConvertsFromScreenCaptureCoordinates() {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)

    XCTAssertEqual(
        CaptureDisplayFrameResolver.resolve(
            contentRect: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            screenFrames: [main, above],
            mainScreenFrame: main
        ),
        above
    )
}

func testWindowUsesDisplayWithLargestIntersection() {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

    XCTAssertEqual(
        CaptureDisplayFrameResolver.resolve(
            contentRect: CGRect(x: 1800, y: 100, width: 800, height: 600),
            screenFrames: [main, right],
            mainScreenFrame: main
        ),
        right
    )
}
```

Add cases for left and below displays plus a nonintersecting rectangle choosing the nearest screen.

- [ ] **Step 2: Run the resolver suite and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureDisplayFrameResolverTests
```

Expected: compilation failure because the resolver does not exist.

- [ ] **Step 3: Implement the pure resolver**

```swift
enum CaptureDisplayFrameResolver {
    static func resolve(
        contentRect: CGRect,
        screenFrames: [CGRect],
        mainScreenFrame: CGRect?
    ) -> CGRect {
        guard let mainScreenFrame else { return contentRect }
        let converted = CGRect(
            x: contentRect.minX,
            y: mainScreenFrame.maxY - contentRect.maxY,
            width: contentRect.width,
            height: contentRect.height
        )
        guard !screenFrames.isEmpty else { return converted }

        let ranked = screenFrames.map { frame in
            (frame: frame, area: intersectionArea(frame, converted))
        }
        if let best = ranked.max(by: { $0.area < $1.area }), best.area > 0 {
            return best.frame
        }
        return screenFrames.min(by: {
            squaredDistance($0.center, converted.center) < squaredDistance($1.center, converted.center)
        }) ?? converted
    }
}
```

Keep `intersectionArea`, rectangle-center calculation, and squared distance private and deterministic.

- [ ] **Step 4: Carry and consume the presentation frame**

Add `presentationFrame` to `ScreenCaptureSelection` and `CaptureSourceSelection.init`. In `ScreenSourcePicker.didUpdate`, resolve it once:

```swift
let screens = NSScreen.screens
let presentationFrame = CaptureDisplayFrameResolver.resolve(
    contentRect: filter.contentRect,
    screenFrames: screens.map(\.frame),
    mainScreenFrame: screens.first?.frame
)
```

Import AppKit in the picker. Pass `source.presentationFrame`, rather than `source.contentRect`, to `bubblePanel.show`. Update every fake selection with a literal `presentationFrame`.

- [ ] **Step 5: Run resolver, bubble geometry, and model tests and verify GREEN**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureDisplayFrameResolverTests -only-testing:CloomTests/CameraBubbleGeometryTests -only-testing:CloomTests/AppModelTests -only-testing:CloomTests/RecordingSessionControllerTests -only-testing:CloomTests/ExportIntegrationTests
```

Expected: all selected suites pass.

- [ ] **Step 6: Commit the display-resolution slice**

```bash
git add Cloom/Capture/CaptureDisplayFrameResolver.swift Cloom/Capture/CaptureSourceSelection.swift Cloom/Capture/ScreenSourcePicker.swift Cloom/App/AppModel.swift CloomTests/CaptureDisplayFrameResolverTests.swift CloomTests/AppModelTests.swift CloomTests/RecordingSessionControllerTests.swift CloomTests/ExportIntegrationTests.swift
git commit -m "fix: place camera bubble on captured display"
```

### Task 5: Enter Stopping State on the First Stop Action

**Files:**
- Modify: `Cloom/Recording/RecordingState.swift`
- Modify: `Cloom/Recording/RecordingCoordinator.swift`
- Modify: `Cloom/Recording/RecordingSessionController.swift`
- Modify: `Cloom/UI/RecordingStatusView.swift`
- Modify: `Cloom/UI/SetupView.swift`
- Modify: `CloomTests/RecordingCoordinatorTests.swift`
- Modify: `CloomTests/RecordingSessionControllerTests.swift`

**Interfaces:**
- Produces: `RecordingPhase.stopping` and `RecordingCoordinator.beginStopping()`.
- Changes: `beginExporting()` accepts `.stopping` for normal flow and `.failed` for retry.
- Preserves: stop errors enter `.failed` and leave the workspace recoverable.

- [ ] **Step 1: Add failing coordinator transition tests**

```swift
func testHappyPathTransitionsThroughStopping() throws {
    let coordinator = RecordingCoordinator()
    let output = URL(fileURLWithPath: "/tmp/cloom.mp4")

    try coordinator.beginPreparing()
    try coordinator.beginCountdown()
    try coordinator.beginRecording()
    try coordinator.beginStopping()
    try coordinator.beginExporting()
    try coordinator.finish(outputURL: output)

    XCTAssertEqual(coordinator.phase, .finished(outputURL: output))
}

func testSecondStopTransitionIsRejectedWithoutChangingState() throws {
    let coordinator = RecordingCoordinator()
    try coordinator.beginPreparing()
    try coordinator.beginCountdown()
    try coordinator.beginRecording()
    try coordinator.beginStopping()

    XCTAssertThrowsError(try coordinator.beginStopping())
    XCTAssertEqual(coordinator.phase, .stopping)
}
```

- [ ] **Step 2: Add a failing suspended-stop controller test**

Give `FakeScreenCapture` a controlled stop continuation. Start `controller.stop()` in a task, wait until fake screen stop suspends, and assert phase before resuming:

```swift
func testStopEntersStoppingBeforeCaptureTeardownCompletes() async throws {
    let stopper = ControlledStopper()
    let fixture = try Fixture(screenStopper: stopper)
    defer { fixture.removeWorkspace() }
    try await fixture.controller.start(configuration: fixture.configuration)

    let stop = Task { try await fixture.controller.stop() }
    await stopper.waitUntilStoppedCalled()

    XCTAssertEqual(fixture.coordinator.phase, .stopping)

    await stopper.resume()
    try await stop.value
    XCTAssertEqual(fixture.coordinator.phase, .exporting(progress: 0))
}
```

- [ ] **Step 3: Run stopping tests and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingCoordinatorTests -only-testing:CloomTests/RecordingSessionControllerTests
```

Expected: compilation failure because `.stopping` and `beginStopping()` do not exist.

- [ ] **Step 4: Implement the state transition at the root cause**

```swift
func beginStopping() throws {
    guard phase == .recording else { throw invalidTransition("beginStopping") }
    phase = .stopping
}

func beginExporting() throws {
    switch phase {
    case .stopping, .failed:
        phase = .exporting(progress: 0)
    default:
        throw invalidTransition("beginExporting")
    }
}
```

In `RecordingSessionController.stop`, validate the current recording/workspace, call `try coordinator.beginStopping()`, and only then set `operationInProgress` and reach the first `await`. Update exhaustive UI switches: `SetupView` keeps `.stopping` in `RecordingControlsView`, and `RecordingStatusView` renders `Stopping recording`.

- [ ] **Step 5: Run stopping tests and verify GREEN**

Run the Step 3 command. Expected: both suites pass, including the assertion made while teardown is suspended.

- [ ] **Step 6: Commit the stopping-state slice**

```bash
git add Cloom/Recording/RecordingState.swift Cloom/Recording/RecordingCoordinator.swift Cloom/Recording/RecordingSessionController.swift Cloom/UI/RecordingStatusView.swift Cloom/UI/SetupView.swift CloomTests/RecordingCoordinatorTests.swift CloomTests/RecordingSessionControllerTests.swift
git commit -m "fix: transition immediately when stopping"
```

### Task 6: Show Readable Controls Only for Active Inputs

**Files:**
- Modify: `Cloom/App/AppModel.swift`
- Modify: `Cloom/UI/RecordingControlsView.swift`
- Create: `CloomTests/RecordingControlVisibilityTests.swift`
- Modify: `CloomTests/ExportIntegrationTests.swift`

**Interfaces:**
- Produces: `AppModel.activeRecordingSettings: RecordingSettings?`.
- Produces: `RecordingControlVisibility.init(settings:)`, `showsCamera`, and `showsMicrophone`.
- Consumes: `.stopping` from Task 5 and optional-input settings from Task 1.

- [ ] **Step 1: Add failing visibility tests for all four combinations**

Test a behavior model rather than SwiftUI source text:

```swift
func testVisibilityMatchesCapturedInputCombination() {
    for (camera, microphone, expectedCamera, expectedMicrophone) in [
        (true, true, true, true),
        (true, false, true, false),
        (false, true, false, true),
        (false, false, false, false),
    ] {
        var settings = RecordingSettings.default
        settings.includeCamera = camera
        settings.includeMicrophone = microphone
        let visibility = RecordingControlVisibility(settings: settings)

        XCTAssertEqual(visibility.showsCamera, expectedCamera)
        XCTAssertEqual(visibility.showsMicrophone, expectedMicrophone)
    }
}
```

Add an AppModel integration assertion that `activeRecordingSettings` equals the settings used to start and does not change when `model.settings` later changes.

- [ ] **Step 2: Run visibility and integration tests and verify RED**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingControlVisibilityTests -only-testing:CloomTests/ExportIntegrationTests
```

Expected: compilation failure because the visibility model and active snapshot do not exist.

- [ ] **Step 3: Capture immutable active settings and gate runtime actions**

In `AppModel.startRecording`, snapshot before starting:

```swift
let activeSettings = settings
activeRecordingSettings = activeSettings
try await sessionController.start(
    configuration: RecordingSessionConfiguration(source: source, settings: activeSettings)
)
```

Only start mute interval tracking and show the bubble when their inputs are enabled. Clear the snapshot in `recordAnother()`.

Implement the pure visibility type alongside the view:

```swift
struct RecordingControlVisibility: Equatable {
    let showsCamera: Bool
    let showsMicrophone: Bool

    init(settings: RecordingSettings?) {
        showsCamera = settings?.includeCamera == true
        showsMicrophone = settings?.includeMicrophone == true
    }
}
```

- [ ] **Step 4: Replace the cramped HStack with labeled vertical groups**

Use `RecordingControlVisibility(settings: model.activeRecordingSettings)` and build camera/microphone groups conditionally. Use a full-width `VStack(alignment: .leading, spacing: 14)` and `LabeledContent` rows. Apply `.labelsHidden()` to nested pickers so only the row label renders.

The stop label reflects state:

```swift
@ViewBuilder
private var stopLabel: some View {
    if model.recordingCoordinator.phase == .stopping {
        HStack {
            ProgressView().controlSize(.small)
            Text("Stopping...")
        }
        .frame(minWidth: 150)
    } else {
        Label("Stop Recording", systemImage: "stop.fill")
            .frame(minWidth: 150)
    }
}
```

Keep the button disabled unless phase is exactly `.recording`. Do not give the complete control group a fixed width larger than the setup window's minimum usable content width.

- [ ] **Step 5: Run visibility and integration tests and verify GREEN**

Run the Step 2 command. Expected: all selected suites pass.

- [ ] **Step 6: Commit the controls slice**

```bash
git add Cloom/App/AppModel.swift Cloom/UI/RecordingControlsView.swift CloomTests/RecordingControlVisibilityTests.swift CloomTests/ExportIntegrationTests.swift
git commit -m "fix: show controls for active inputs"
```

### Task 7: Full Verification and GitHub Manual-Verification Notes

**Files:**
- Modify only if verification exposes an in-scope failure: files already listed in Tasks 1-6 and their corresponding tests.
- External updates: GitHub issues #1, #2, #3, #4, #5, and #6.

**Interfaces:**
- Consumes: all implementation and tests from Tasks 1-6.
- Produces: fresh full-suite and build evidence plus one issue-specific manual-verification comment on every issue.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`, zero failed tests, and no compiler warnings introduced by this change.

- [ ] **Step 2: Run the unsigned app build**

```bash
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` and no compiler warnings introduced by this change.

- [ ] **Step 3: Review scope and workspace hygiene**

```bash
git status --short
git diff --check
git diff --stat
```

Expected: only the approved plan, implementation, and tests are changed; whitespace check exits zero.

- [ ] **Step 4: Prepare six issue-specific comments**

Each comment must include:

```text
Implemented in the current repository checkout.

Automated verification:
- Full macOS test suite: passed.
- Unsigned macOS app build: passed.

Manual verification requested:
- Complete the issue-specific checklist below on representative hardware.

These manual checks are still pending and should be completed on representative hardware before closing the issue.
```

Use these issue-specific checks:

- #1: select a secondary display; confirm the bubble opens there, drags to every edge without jumping screens, and appears at the matching normalized location in export; repeat with a window mostly on each display.
- #2: disable camera; record and export; confirm no bubble or camera/size/shape controls appear and the MP4 contains only the screen plus chosen audio; re-enable camera and confirm the saved device returns.
- #3: disable microphone; verify a silent export with system audio off and a system-audio-only export with it on; confirm Mute Microphone is hidden; re-enable microphone and confirm the saved device returns.
- #4: at the minimum setup window size, verify labels never wrap character by character, controls do not overlap, and alignment remains consistent for every input combination.
- #5: verify both on shows camera/size/shape/mute, camera only omits mute, microphone only shows mute without camera controls, and both off shows only timer/status/stop.
- #6: click Stop once; confirm immediate `Stopping...` feedback, disabled repeat action, automatic export transition, and recoverable failure UI if finalization is forced to fail.

- [ ] **Step 5: Post one comment to each issue and capture URLs**

Use `gh issue comment <number> --body-file <temporary-file>` for each issue so multiline Markdown is preserved. Do not claim the manual checks passed. Record the resulting six comment URLs for the final report.

- [ ] **Step 6: Final status check**

```bash
git status --short --branch
```

Report exact test/build outcomes, implementation commit IDs, six comment URLs, and hardware verification still pending.
