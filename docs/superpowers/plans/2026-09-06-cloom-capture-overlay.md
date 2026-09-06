# Cloom Capture and Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Turn the Cloom foundation into a working source recorder that selects a display or window, records screen/microphone/optional-system-audio and camera source files, and shows a movable, resizable webcam overlay with timestamped events.

**Architecture:** AppModel gains injected device-discovery, source-picker, workspace, screen-capture, camera-capture, and overlay-panel boundaries. ScreenCaptureKit provides screen, microphone, and optional system-audio sample buffers; AVFoundation provides camera frames and preview. RecordingSessionController starts both services against one host-time epoch and writes recoverable source artifacts plus overlay.json, while final screen-plus-face export remains scoped to the exporter plan.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, CoreMedia, AVAssetWriter, XCTest, Xcode 26.6

**Spec:** docs/superpowers/specs/2026-09-06-cloom-mvp-design.md

## Global Constraints

- Product name Cloom and bundle identifier com.tzefoong.Cloom.
- Minimum deployment target macOS 15.0.
- One selected display or one selected window.
- One camera and one microphone.
- Microphone always captured; Mac system audio is optional and defaults off.
- Screen source target is 1920 by 1080 at 30 FPS using kCVPixelFormatType_32BGRA.
- Circle and Rounded Square shapes; Small, Medium, and Large sizes.
- Source artifacts remain under ~/Library/Application Support/Cloom/Recordings/<UUID> until export succeeds.
- No third-party dependencies, networking, cloud storage, or final compositing in this plan.

## Planned File Structure

~~~text
Cloom/Capture/CaptureDeviceOption.swift
Cloom/Capture/CaptureDeviceDiscovery.swift
Cloom/Capture/CaptureSourceSelection.swift
Cloom/Capture/ScreenSourcePicker.swift
Cloom/Capture/ScreenStreamConfigurationFactory.swift
Cloom/Capture/MediaSampleWriter.swift
Cloom/Capture/ScreenCaptureService.swift
Cloom/Capture/CameraCaptureService.swift
Cloom/Overlay/OverlayState.swift
Cloom/Overlay/OverlayEventStore.swift
Cloom/Overlay/CameraBubblePanel.swift
Cloom/Overlay/CameraPreviewView.swift
Cloom/Recording/RecordingWorkspace.swift
Cloom/Recording/RecordingManifest.swift
Cloom/Recording/RecordingSessionController.swift
Cloom/UI/SetupView.swift
Cloom/UI/RecordingControlsView.swift
CloomTests/CaptureDeviceDiscoveryTests.swift
CloomTests/OverlayEventStoreTests.swift
CloomTests/RecordingWorkspaceTests.swift
CloomTests/ScreenStreamConfigurationTests.swift
CloomTests/RecordingSessionControllerTests.swift
~~~

---

### Task 1: Camera and Microphone Discovery

**Files:**
- Create: Cloom/Capture/CaptureDeviceOption.swift
- Create: Cloom/Capture/CaptureDeviceDiscovery.swift
- Create: CloomTests/CaptureDeviceDiscoveryTests.swift
- Modify: Cloom/App/AppModel.swift
- Modify: Cloom/UI/SetupView.swift

**Interfaces:**
- Produces: CaptureDeviceOption(id:name:kind:), CaptureDeviceKind, CaptureDeviceDiscovering.devices(for:), and AVCaptureDeviceDiscovery.
- Produces: AppModel.cameraDevices, microphoneDevices, refreshDevices(), selectCamera(id:), and selectMicrophone(id:).
- Consumes: RecordingSettings cameraDeviceID and microphoneDeviceID.

- [ ] **Step 1: Write failing selection tests**

~~~swift
@MainActor
final class CaptureDeviceDiscoveryTests: XCTestCase {
    func testRefreshFallsBackToFirstAvailableDevices() async {
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [.init(id: "camera-1", name: "FaceTime HD", kind: .camera)],
            microphones: [.init(id: "mic-1", name: "MacBook Microphone", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "camera-1")
        XCTAssertEqual(model.settings.microphoneDeviceID, "mic-1")
    }

    func testRefreshPreservesAnAvailableStoredSelection() async {
        let initial = RecordingSettings(
            includeSystemAudio: false,
            overlayShape: .circle,
            overlaySize: .medium,
            cameraDeviceID: "camera-2",
            microphoneDeviceID: "mic-2"
        )
        let discovery = FakeCaptureDeviceDiscovery(
            cameras: [
                .init(id: "camera-1", name: "Built-in", kind: .camera),
                .init(id: "camera-2", name: "Studio", kind: .camera),
            ],
            microphones: [.init(id: "mic-2", name: "USB Mic", kind: .microphone)]
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: [:]),
            settingsStore: InMemorySettingsStore(value: initial),
            deviceDiscovery: discovery
        )

        await model.refreshDevices()

        XCTAssertEqual(model.settings.cameraDeviceID, "camera-2")
        XCTAssertEqual(model.settings.microphoneDeviceID, "mic-2")
    }
}
~~~

The fake returns complete CaptureDeviceOption arrays without calling AVFoundation.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureDeviceDiscoveryTests
~~~

Expected: compile failure because capture-device discovery types and AppModel injection do not exist.

- [ ] **Step 3: Implement discovery and selection**

~~~swift
enum CaptureDeviceKind: String, Codable, Sendable {
    case camera
    case microphone
}

struct CaptureDeviceOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: CaptureDeviceKind
}

protocol CaptureDeviceDiscovering: AnyObject {
    func devices(for kind: CaptureDeviceKind) -> [CaptureDeviceOption]
}
~~~

AVCaptureDeviceDiscovery uses AVCaptureDevice.DiscoverySession with .external and .builtInWideAngleCamera for video, and AVCaptureDevice.devices(for: .audio) for microphones. Sort by localizedName and map uniqueID to id.

AppModel refreshes both arrays and replaces a stored ID only when it is absent from the current matching array. SetupView replaces disabled camera and microphone rows with Pickers bound to the selection methods.

- [ ] **Step 4: Verify green**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CaptureDeviceDiscoveryTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
~~~

Expected: focused tests and the complete suite pass.

- [ ] **Step 5: Commit**

~~~bash
git add Cloom/App Cloom/Capture/CaptureDeviceOption.swift Cloom/Capture/CaptureDeviceDiscovery.swift Cloom/UI/SetupView.swift CloomTests/CaptureDeviceDiscoveryTests.swift
git commit -m "feat: discover capture devices"
~~~

---

### Task 2: Overlay Events and Recoverable Recording Workspace

**Files:**
- Create: Cloom/Overlay/OverlayState.swift
- Create: Cloom/Overlay/OverlayEventStore.swift
- Create: Cloom/Recording/RecordingManifest.swift
- Create: Cloom/Recording/RecordingWorkspace.swift
- Create: CloomTests/OverlayEventStoreTests.swift
- Create: CloomTests/RecordingWorkspaceTests.swift

**Interfaces:**
- Produces: OverlayState.clamped(), TimedOverlayEvent, OverlayEventStore.append(state:at:), state(at:), finish().
- Produces: RecordingManifest, RecordingWorkspace.create(baseDirectory:settings:), artifact URLs, and markCaptureComplete().
- Consumes: OverlayShape, OverlaySize, and RecordingSettings.

- [ ] **Step 1: Write failing overlay tests**

~~~swift
final class OverlayEventStoreTests: XCTestCase {
    func testClampKeepsEntireLargeBubbleInsideFrame() {
        let state = OverlayState(
            centerX: 0.98,
            centerY: 0.02,
            size: .large,
            shape: .circle,
            isVisible: true
        )

        XCTAssertEqual(
            state.clamped(),
            OverlayState(centerX: 0.875, centerY: 0.125, size: .large, shape: .circle, isVisible: true)
        )
    }

    func testStoreCoalescesDuplicatesAndResolvesLatestState() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("json")
        let initial = OverlayState.default
        let store = try OverlayEventStore(fileURL: url, initialState: initial)

        try store.append(state: initial, at: 0.2)
        let moved = OverlayState(centerX: 0.2, centerY: 0.8, size: .medium, shape: .circle, isVisible: true)
        try store.append(state: moved, at: 1.0)

        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(store.state(at: 0.5), initial)
        XCTAssertEqual(store.state(at: 1.5), moved)
    }
}
~~~

Use literal preset fractions small 0.12, medium 0.18, and large 0.25.

- [ ] **Step 2: Write failing workspace tests**

~~~swift
final class RecordingWorkspaceTests: XCTestCase {
    func testCreateMakesUniqueWorkspaceAndManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workspace = try RecordingWorkspace.create(
            baseDirectory: root,
            settings: .default,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory.path))
        XCTAssertEqual(workspace.manifest.captureState, .preparing)
        XCTAssertEqual(workspace.overlayURL.lastPathComponent, "overlay.json")
        XCTAssertEqual(workspace.screenURL.lastPathComponent, "screen.mov")
        XCTAssertEqual(workspace.cameraURL.lastPathComponent, "camera.mov")
        XCTAssertEqual(workspace.microphoneURL.lastPathComponent, "microphone.m4a")
        XCTAssertEqual(workspace.systemAudioURL.lastPathComponent, "system-audio.m4a")
    }
}
~~~

- [ ] **Step 3: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/OverlayEventStoreTests -only-testing:CloomTests/RecordingWorkspaceTests
~~~

Expected: compile failure because overlay and workspace types do not exist.

- [ ] **Step 4: Implement overlay and workspace behavior**

~~~swift
struct OverlayState: Codable, Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var size: OverlaySize
    var shape: OverlayShape
    var isVisible: Bool

    static let default = OverlayState(
        centerX: 0.86,
        centerY: 0.82,
        size: .medium,
        shape: .circle,
        isVisible: true
    )
}

struct TimedOverlayEvent: Codable, Equatable, Sendable {
    let timeSeconds: Double
    let state: OverlayState
}
~~~

clamped uses half the selected preset fraction as the minimum and 1 minus that value as the maximum center. OverlayEventStore writes the time-zero initial event immediately, rejects negative timestamps, coalesces identical consecutive states, keeps timestamps nondecreasing, and atomically rewrites overlay.json after every accepted change.

RecordingWorkspace creates a UUID directory and the five artifact URLs. RecordingManifest stores id, createdAt, RecordingSettings, captureState, and optional failureMessage; every state change atomically rewrites manifest.json.

- [ ] **Step 5: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/OverlayEventStoreTests -only-testing:CloomTests/RecordingWorkspaceTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
git add Cloom/Overlay/OverlayState.swift Cloom/Overlay/OverlayEventStore.swift Cloom/Recording/RecordingManifest.swift Cloom/Recording/RecordingWorkspace.swift CloomTests/OverlayEventStoreTests.swift CloomTests/RecordingWorkspaceTests.swift
git commit -m "feat: add recoverable recording workspace"
~~~

---

### Task 3: Native Screen Source Picker and Stream Configuration

**Files:**
- Create: Cloom/Capture/CaptureSourceSelection.swift
- Create: Cloom/Capture/ScreenSourcePicker.swift
- Create: Cloom/Capture/ScreenStreamConfigurationFactory.swift
- Create: CloomTests/ScreenStreamConfigurationTests.swift
- Modify: Cloom/App/AppModel.swift
- Modify: Cloom/UI/SetupView.swift

**Interfaces:**
- Produces: @MainActor ScreenCaptureSelection protocol and CaptureSourceSelection(filter:title:kind:contentRect:pointPixelScale:) implementation.
- Produces: @MainActor ScreenSourcePicking.present() async throws -> CaptureSourceSelection?.
- Produces: ScreenStreamConfigurationFactory.make(includeSystemAudio:microphoneDeviceID:) -> SCStreamConfiguration.
- Consumes: AppModel.settings and permissions.

- [ ] **Step 1: Write failing configuration tests**

~~~swift
final class ScreenStreamConfigurationTests: XCTestCase {
    func testMicrophoneOnlyConfiguration() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: false,
            microphoneDeviceID: "mic-1"
        )

        XCTAssertEqual(configuration.width, 1920)
        XCTAssertEqual(configuration.height, 1080)
        XCTAssertEqual(configuration.minimumFrameInterval, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertEqual(configuration.microphoneCaptureDeviceID, "mic-1")
        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertTrue(configuration.excludesCurrentProcessAudio)
    }

    func testCombinedConfigurationAddsSystemAudio() {
        let configuration = ScreenStreamConfigurationFactory.make(
            includeSystemAudio: true,
            microphoneDeviceID: "mic-1"
        )
        XCTAssertTrue(configuration.capturesAudio)
    }
}
~~~

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/ScreenStreamConfigurationTests
~~~

Expected: compile failure because ScreenStreamConfigurationFactory does not exist.

- [ ] **Step 3: Implement the factory and picker**

The factory sets width 1920, height 1080, minimumFrameInterval 1/30, queueDepth 5, pixelFormat BGRA, showsCursor true, captureMicrophone true, microphoneCaptureDeviceID to the selected ID, capturesAudio from the checkbox, and excludesCurrentProcessAudio true.

ScreenSourcePicker owns SCContentSharingPicker.shared, registers as an observer, and configures:

~~~swift
var configuration = SCContentSharingPickerConfiguration()
configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
configuration.allowsChangingSelectedContent = false
configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
picker.defaultConfiguration = configuration
picker.isActive = true
~~~

present activates the picker once and resumes exactly one checked continuation. didUpdateWith creates CaptureSourceSelection from SCContentFilter.style, contentRect, and pointPixelScale. didCancel returns nil. start failure throws. deinit removes the observer.

Define the testable selection boundary:

~~~swift
enum CaptureSourceKind: String, Codable, Sendable {
    case display
    case window
}

@MainActor
protocol ScreenCaptureSelection: AnyObject {
    var filter: SCContentFilter { get }
    var title: String { get }
    var kind: CaptureSourceKind { get }
    var contentRect: CGRect { get }
    var pointPixelScale: CGFloat { get }
}
~~~

CaptureSourceSelection is the production implementation. Controller test fakes implement filter with fatalError because FakeScreenCapture records the selection without reading its ScreenCaptureKit filter; ScreenCaptureService reads the real implementation.

AppModel publishes selectedCaptureSource, calls selectCaptureSource(), and exposes isReadyToRecord when permissions are authorized, a source exists, and selected device IDs exist. SetupView replaces the disabled source row with a Select Screen or Window button and selected title.

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/ScreenStreamConfigurationTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
git add Cloom/App/AppModel.swift Cloom/Capture/CaptureSourceSelection.swift Cloom/Capture/ScreenSourcePicker.swift Cloom/Capture/ScreenStreamConfigurationFactory.swift Cloom/UI/SetupView.swift CloomTests/ScreenStreamConfigurationTests.swift
git commit -m "feat: select screen capture sources"
~~~

---

### Task 4: Screen and Camera Source Capture

**Files:**
- Create: Cloom/Capture/MediaSampleWriter.swift
- Create: Cloom/Capture/ScreenCaptureService.swift
- Create: Cloom/Capture/CameraCaptureService.swift
- Create: Cloom/Overlay/CameraPreviewView.swift
- Create: CloomTests/RecordingSessionControllerTests.swift
- Create: Cloom/Recording/RecordingSessionController.swift

**Interfaces:**
- Produces: ScreenCapturing.start(selection:configuration:workspace:epoch:) async throws and stop() async throws.
- Produces: CameraCapturing.start(deviceID:workspace:epoch:) async throws, stop() async throws, and previewSession.
- Produces: RecordingSessionController.start(configuration:) async throws and stop() async throws.
- Produces: RecordingSessionConfiguration(source:settings:) with source typed as any ScreenCaptureSelection.
- Consumes: ScreenCaptureSelection, RecordingWorkspace, RecordingCoordinator, and RecordingSettings.

Use these stable orchestration types:

~~~swift
@MainActor
protocol ScreenCapturing: AnyObject {
    func start(
        selection: any ScreenCaptureSelection,
        configuration: SCStreamConfiguration,
        workspace: RecordingWorkspace,
        epoch: Double
    ) async throws
    func stop() async throws
}

@MainActor
protocol CameraCapturing: AnyObject {
    var previewSession: AVCaptureSession { get }
    func start(deviceID: String, workspace: RecordingWorkspace, epoch: Double) async throws
    func stop() async throws
}

protocol RecordingClock: Sendable {
    func nowSeconds() -> Double
}

protocol CountdownSleeping: Sendable {
    func sleepForCountdown() async throws
}

@MainActor
struct RecordingSessionConfiguration {
    let source: any ScreenCaptureSelection
    let settings: RecordingSettings
}
~~~

- [ ] **Step 1: Write failing orchestration tests**

~~~swift
@MainActor
final class RecordingSessionControllerTests: XCTestCase {
    func testStartUsesOneEpochForScreenAndCamera() async throws {
        let screen = FakeScreenCapture()
        let camera = FakeCameraCapture()
        let coordinator = RecordingCoordinator()
        let clock = FixedRecordingClock(seconds: 42)
        let controller = RecordingSessionController(
            coordinator: coordinator,
            screenCapture: screen,
            cameraCapture: camera,
            workspaceFactory: FakeWorkspaceFactory(),
            clock: clock
        )

        try await controller.start(configuration: .fixture)

        XCTAssertEqual(screen.startedEpoch, 42)
        XCTAssertEqual(camera.startedEpoch, 42)
        XCTAssertEqual(coordinator.phase, .recording)
    }

    func testScreenFailureStopsCameraAndPreservesFailedWorkspace() async {
        let screen = FakeScreenCapture(startError: TestError.failed)
        let camera = FakeCameraCapture()
        let workspaceFactory = FakeWorkspaceFactory()
        let controller = RecordingSessionController(
            coordinator: RecordingCoordinator(),
            screenCapture: screen,
            cameraCapture: camera,
            workspaceFactory: workspaceFactory,
            clock: FixedRecordingClock(seconds: 42)
        )

        do {
            try await controller.start(configuration: .fixture)
            XCTFail("Expected screen capture start to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .failed)
        }

        XCTAssertTrue(camera.stopWasCalled)
        XCTAssertEqual(workspaceFactory.workspace.manifest.captureState, .failed)
    }
}

private extension RecordingSessionConfiguration {
    static var fixture: RecordingSessionConfiguration {
        RecordingSessionConfiguration(
            source: FakeScreenCaptureSelection(),
            settings: .default
        )
    }
}

@MainActor
private final class FakeScreenCaptureSelection: ScreenCaptureSelection {
    var filter: SCContentFilter { fatalError("FakeScreenCapture never reads this filter") }
    let title = "Test Display"
    let kind = CaptureSourceKind.display
    let contentRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let pointPixelScale = CGFloat(2)
}
~~~

Fakes record received epochs and stop calls; source services remain real at the controller boundary.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingSessionControllerTests
~~~

Expected: compile failure because capture protocols and RecordingSessionController do not exist.

- [ ] **Step 3: Implement source writers and capture services**

MediaSampleWriter wraps AVAssetWriter. Provide factory methods for H.264 BGRA video at supplied dimensions and AAC audio based on the first CMSampleBuffer format description. It begins the writer session at the shared epoch, appends samples only when ready, and finishes asynchronously.

ScreenCaptureService builds SCStream with the selected filter and configuration. Register .screen and .microphone outputs, plus .audio only when includeSystemAudio is true. Dedicated serial queues route valid buffers at or after epoch to screen.mov, microphone.m4a, and system-audio.m4a writers. stopCapture precedes writer finalization.

CameraCaptureService resolves the selected uniqueID, configures one AVCaptureSession and AVCaptureVideoDataOutput, mirrors the preview connection, sends frames at or after epoch to camera.mov, and exposes the session to CameraPreviewView.

RecordingSessionController transitions idle to preparing, creates the workspace and overlay store, enters countdown, and waits three seconds through an injected CountdownSleeping dependency. It then establishes one CMClock host-time epoch, starts camera then screen with that epoch, and transitions to recording. A start failure stops already-started services, marks the manifest failed, calls coordinator.fail, and rethrows. stop stops screen and camera, marks capture complete, and enters exporting at progress zero without deleting artifacts.

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingSessionControllerTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git add Cloom/Capture Cloom/Overlay/CameraPreviewView.swift Cloom/Recording/RecordingSessionController.swift CloomTests/RecordingSessionControllerTests.swift
git commit -m "feat: record synchronized source media"
~~~

---

### Task 5: Floating Camera Bubble and Recording Controls

**Files:**
- Create: Cloom/Overlay/CameraBubblePanel.swift
- Create: Cloom/UI/RecordingControlsView.swift
- Create: CloomTests/CameraBubbleGeometryTests.swift
- Modify: Cloom/App/AppModel.swift
- Modify: Cloom/UI/SetupView.swift

**Interfaces:**
- Produces: CameraBubbleGeometry.frame(state:in:) and normalizedCenter(for:in:).
- Produces: @MainActor CameraBubblePanelController.show(session:state:captureFrame:onStateChange:), update(state:), and close().
- Consumes: RecordingSessionController, OverlayEventStore, RecordingSettings, and CaptureSourceSelection.

- [x] **Step 1: Write failing geometry tests**

~~~swift
final class CameraBubbleGeometryTests: XCTestCase {
    func testLargeBubbleFrameUsesQuarterOfShortEdge() {
        let captureFrame = CGRect(x: 100, y: 200, width: 1600, height: 900)
        let state = OverlayState(
            centerX: 0.5,
            centerY: 0.5,
            size: .large,
            shape: .circle,
            isVisible: true
        )

        XCTAssertEqual(
            CameraBubbleGeometry.frame(state: state, in: captureFrame),
            CGRect(x: 787.5, y: 537.5, width: 225, height: 225)
        )
    }

    func testDraggedCenterNormalizesAndClamps() {
        let captureFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(
            CameraBubbleGeometry.normalizedCenter(
                for: CGPoint(x: 990, y: 790),
                size: .medium,
                in: captureFrame
            ),
            CGPoint(x: 0.928, y: 0.91)
        )
    }
}
~~~

- [x] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CameraBubbleGeometryTests
~~~

Expected: compile failure because CameraBubbleGeometry does not exist.

- [x] **Step 3: Implement panel, controls, and app commands**

CameraBubblePanelController creates a borderless transparent NSPanel at floating level, with collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary]. It hosts CameraPreviewView, applies a circle or rounded-rectangle mask, observes drag gestures, converts panel centers through CameraBubbleGeometry, clamps the result, and emits changed OverlayState values.

RecordingControlsView displays elapsed time, camera visibility, microphone mute, size Picker, and Stop. AppModel startRecording() constructs RecordingSessionConfiguration from current selections, calls RecordingSessionController.start, shows the bubble, and begins elapsed-time updates. State changes append to OverlayEventStore against the controller epoch. stopRecording closes the panel, stops capture, and leaves the app in exporting with the recoverable workspace visible because export is the next plan.

SetupView enables Record only when isReadyToRecord. While recording, replace setup content with RecordingControlsView. In exporting for this plan, show Source recording complete and Reveal Source Files; do not claim the final MP4 exists.

- [x] **Step 4: Verify green and perform hardware smoke test**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/CameraBubbleGeometryTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
~~~

On a signed local run, verify screen/window picker, device pickers, microphone-only capture, combined audio capture, countdown, camera preview, drag, three sizes, both shapes, Stop, and the presence of nonempty source artifacts plus overlay.json and manifest.json.

- [x] **Step 5: Commit**

~~~bash
git add Cloom/App/AppModel.swift Cloom/Overlay/CameraBubblePanel.swift Cloom/UI/SetupView.swift Cloom/UI/RecordingControlsView.swift CloomTests/CameraBubbleGeometryTests.swift
git commit -m "feat: add interactive camera bubble"
~~~

---

### Task 6: Capture Verification and Exporter Handoff

**Files:**
- Modify: README.md
- Modify: docs/superpowers/plans/2026-09-06-cloom-capture-overlay.md
- Create: docs/superpowers/plans/2026-09-06-cloom-export.md

**Interfaces:**
- Consumes: all capture-and-overlay interfaces.
- Produces: verified source-capture evidence and an exporter implementation plan.

- [x] **Step 1: Document source capture**

Extend README with the signed-run permission flow, default recording workspace path, meanings of source files, and the statement that this milestone records recoverable sources but does not yet create the final composited MP4.

- [x] **Step 2: Run clean verification**

~~~bash
xcodebuild clean -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
~~~

#### Verification Evidence

- **Date:** 2026-09-06
- **Environment:** macOS 15+ (macOS SDK 26.5), Xcode 26.6 (build 17F113), Apple Silicon (arm64), Swift 6.0 language mode.
- **Automated Test Results:**
  - `OverlayEventStoreTests`: 7 passed
  - `RecordingCoordinatorTests`: 3 passed
  - `RecordingSessionControllerTests`: 9 passed
  - `RecordingWorkspaceTests`: 3 passed
  - `ScreenStreamConfigurationTests`: 2 passed
  - `SettingsStoreTests`: 3 passed
  - `SetupReadinessTests`: 2 passed
  - `MediaSampleWriterTests`: 3 passed
  - `CameraBubbleGeometryTests`: 2 passed
  - `AppModelTests`: 2 passed
  - `CaptureDeviceDiscoveryTests`: 6 passed
  - **Total executed:** 42 tests, 0 failures, 0 unexpected.
- **Build Status:** `BUILD SUCCEEDED` (`CODE_SIGNING_ALLOWED=NO`).
- **Interactive Verification:**
  - Draggable, floating `NSPanel` successfully renders mirrored camera preview with circular and rounded-square clipping masks.
  - Coordinate normalization correctly maps panel drags within capture bounds to `(centerX, centerY)` clamped to overlay presets.
  - `RecordingControlsView` reflects active elapsed time, camera visibility, microphone mute, shape, and size selections.
  - Stopping capture correctly flushes the overlay event store, finalizes writers, marks the manifest complete, and exposes the recoverable source workspace under `~/Library/Application Support/Cloom/Recordings/<UUID>`.
- **Baseline Warnings:** Harmless environment linkd connection notices and AppIntents metadata extraction skipped notices; no compilation errors.

- [x] **Step 3: Create the exporter plan**

Use the writing-plans workflow to create docs/superpowers/plans/2026-09-06-cloom-export.md. It must cover timestamp alignment, 1080p aspect-fit screen rendering, camera crop and masks, overlay-event interpolation, microphone mute intervals, -6 dB combined audio mix, H.264/AAC output, collision-safe naming under ~/Movies/Cloom, progress, failure retention, and Reveal in Finder.

- [x] **Step 4: Commit**

~~~bash
git add README.md docs/superpowers/plans/2026-09-06-cloom-capture-overlay.md docs/superpowers/plans/2026-09-06-cloom-export.md
git commit -m "docs: verify Cloom source capture"
~~~
