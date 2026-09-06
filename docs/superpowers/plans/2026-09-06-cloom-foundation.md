# Cloom Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a runnable native Cloom macOS application shell with privacy configuration, a tested recording state machine, permission handling, and persisted MVP settings.

**Architecture:** A SwiftUI app owns one AppModel on the main actor. AppModel composes a deterministic RecordingCoordinator, an injected permission checker, and an injected settings store so state transitions and permission behavior can be tested without activating capture hardware. ScreenCaptureKit and AVFoundation capture services are scoped to the next plan and will depend on the interfaces established here.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, CoreGraphics, XCTest, Xcode 26.6

**Spec:** docs/superpowers/specs/2026-09-06-cloom-mvp-design.md

## Global Constraints

- Product name: Cloom.
- Bundle identifier: com.tzefoong.Cloom.
- Minimum deployment target: macOS 15.0.
- Completed MVP output target: 1920 by 1080, 30 FPS, H.264 MP4.
- Microphone recording is enabled by default; Include Mac system audio defaults to off.
- Overlay shapes: Circle and Rounded Square. Sizes: Small, Medium, and Large.
- No third-party dependencies.
- App Sandbox is disabled for the local MVP.
- No analytics, networking, cloud storage, accounts, or App Store work.

## Planned File Structure

~~~text
Cloom.xcodeproj/project.pbxproj
Cloom/Info.plist
Cloom/Cloom.entitlements
Cloom/App/CloomApp.swift
Cloom/App/AppModel.swift
Cloom/Recording/RecordingState.swift
Cloom/Recording/RecordingCoordinator.swift
Cloom/Permissions/CapturePermission.swift
Cloom/Permissions/SystemPermissionChecker.swift
Cloom/Settings/RecordingSettings.swift
Cloom/Settings/SettingsStore.swift
Cloom/UI/SetupView.swift
Cloom/UI/PermissionRow.swift
Cloom/UI/RecordingStatusView.swift
CloomTests/RecordingCoordinatorTests.swift
CloomTests/AppModelTests.swift
CloomTests/SettingsStoreTests.swift
CloomTests/SetupReadinessTests.swift
.gitignore
README.md
~~~

---

### Task 1: Xcode Project and Recording State Machine

**Files:**
- Create: .gitignore
- Create: Cloom.xcodeproj/project.pbxproj
- Create: Cloom/Info.plist
- Create: Cloom/Cloom.entitlements
- Create: Cloom/App/CloomApp.swift
- Create: Cloom/Recording/RecordingState.swift
- Create: Cloom/Recording/RecordingCoordinator.swift
- Create: CloomTests/RecordingCoordinatorTests.swift

**Interfaces:**
- Produces: RecordingPhase, RecordingFailure, RecordingTransitionError.
- Produces: @MainActor final class RecordingCoordinator with phase, beginPreparing(), beginCountdown(), beginRecording(), beginExporting(), updateExportProgress(_:), finish(outputURL:), fail(_:), and reset().
- Consumes: no application interfaces.

- [x] **Step 1: Create the project shell and failing tests**

Create a macOS application target named Cloom and a unit-test target named CloomTests. Set SWIFT_VERSION = 6.0, MACOSX_DEPLOYMENT_TARGET = 15.0, PRODUCT_BUNDLE_IDENTIFIER = com.tzefoong.Cloom, GENERATE_INFOPLIST_FILE = NO, INFOPLIST_FILE = Cloom/Info.plist, and CODE_SIGN_ENTITLEMENTS = Cloom/Cloom.entitlements.

Info.plist must include:

~~~xml
<key>NSCameraUsageDescription</key>
<string>Cloom uses your camera to place your video over the screen recording.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Cloom uses your microphone to record your narration.</string>
<key>NSScreenCaptureUsageDescription</key>
<string>Cloom records the screen or window you select.</string>
~~~

Cloom.entitlements must include:

~~~xml
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
~~~

Write these initial tests:

~~~swift
import XCTest
@testable import Cloom

@MainActor
final class RecordingCoordinatorTests: XCTestCase {
    func testHappyPathTransitionsReachFinished() throws {
        let coordinator = RecordingCoordinator()
        let output = URL(fileURLWithPath: "/tmp/cloom.mp4")

        try coordinator.beginPreparing()
        try coordinator.beginCountdown()
        try coordinator.beginRecording()
        try coordinator.beginExporting()
        try coordinator.finish(outputURL: output)

        XCTAssertEqual(coordinator.phase, .finished(outputURL: output))
    }

    func testInvalidTransitionPreservesCurrentPhase() {
        let coordinator = RecordingCoordinator()

        XCTAssertThrowsError(try coordinator.beginRecording())
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFailureCanBeReset() {
        let coordinator = RecordingCoordinator()
        coordinator.fail(.captureFailed("Camera disconnected"))
        XCTAssertEqual(coordinator.phase, .failed(.captureFailed("Camera disconnected")))

        coordinator.reset()
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
~~~

- [x] **Step 2: Run the test and verify it fails**

Run:

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingCoordinatorTests
~~~

Expected: compilation fails because RecordingCoordinator and its value types do not exist.

- [x] **Step 3: Implement the minimal state machine**

Create these value types:

~~~swift
import Foundation

enum RecordingFailure: Error, Equatable, Sendable {
    case captureFailed(String)
    case exportFailed(String)
}

enum RecordingPhase: Equatable, Sendable {
    case idle
    case preparing
    case countdown
    case recording
    case exporting(progress: Double)
    case finished(outputURL: URL)
    case failed(RecordingFailure)
}

enum RecordingTransitionError: Error, Equatable {
    case invalid(from: RecordingPhase, action: String)
}
~~~

RecordingCoordinator is an ObservableObject with @Published private(set) var phase = RecordingPhase.idle. Each begin method accepts only its exact predecessor. updateExportProgress accepts only exporting and clamps to 0...1. reset returns any phase to idle. fail is allowed from every phase except finished.

- [x] **Step 4: Run tests and build**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingCoordinatorTests
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
~~~

Expected: three tests pass and the app target builds.

- [x] **Step 5: Commit**

~~~bash
git add .gitignore Cloom.xcodeproj Cloom/Info.plist Cloom/Cloom.entitlements Cloom/App/CloomApp.swift Cloom/Recording CloomTests/RecordingCoordinatorTests.swift
git commit -m "feat: create Cloom app foundation"
~~~

---

### Task 2: Permission Model and macOS Adapter

**Files:**
- Create: Cloom/Permissions/CapturePermission.swift
- Create: Cloom/Permissions/SystemPermissionChecker.swift
- Create: Cloom/App/AppModel.swift
- Create: CloomTests/AppModelTests.swift
- Modify: Cloom/App/CloomApp.swift
- Modify: Cloom/Recording/RecordingState.swift

**Interfaces:**
- Consumes: RecordingCoordinator from Task 1.
- Produces: CapturePermission, PermissionState, and PermissionChecking.
- Produces: SystemPermissionChecker status(for:), request(_:), and openSettings(for:).
- Produces: AppModel refreshPermissions() and request(_:).

- [x] **Step 1: Write failing permission orchestration tests**

~~~swift
import XCTest
@testable import Cloom

@MainActor
final class AppModelTests: XCTestCase {
    func testRefreshReadsEveryRequiredPermission() async {
        let checker = FakePermissionChecker(statuses: [
            .screen: .authorized,
            .camera: .denied,
            .microphone: .authorized,
        ])
        let model = AppModel(permissionChecker: checker)

        await model.refreshPermissions()

        XCTAssertEqual(model.permissions[.screen], .authorized)
        XCTAssertEqual(model.permissions[.camera], .denied)
        XCTAssertEqual(model.permissions[.microphone], .authorized)
        XCTAssertEqual(checker.statusRequests, Set(CapturePermission.allCases))
    }

    func testRequestStoresReturnedStatus() async {
        let checker = FakePermissionChecker(statuses: [.camera: .notDetermined])
        checker.requestResults[.camera] = .authorized
        let model = AppModel(permissionChecker: checker)

        await model.request(.camera)

        XCTAssertEqual(model.permissions[.camera], .authorized)
    }
}
~~~

The test target defines FakePermissionChecker conforming to PermissionChecking with mutable statuses, requestResults, and statusRequests.

- [x] **Step 2: Run the tests and verify they fail**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/AppModelTests
~~~

Expected: compilation fails because the permission types and AppModel do not exist.

- [x] **Step 3: Implement permission interfaces and system behavior**

~~~swift
enum CapturePermission: String, CaseIterable, Codable, Sendable {
    case screen
    case camera
    case microphone
}

enum PermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
protocol PermissionChecking: AnyObject {
    func status(for permission: CapturePermission) -> PermissionState
    func request(_ permission: CapturePermission) async -> PermissionState
    func openSettings(for permission: CapturePermission)
}
~~~

SystemPermissionChecker uses CGPreflightScreenCaptureAccess and CGRequestScreenCaptureAccess for screen access. It uses AVCaptureDevice.authorizationStatus and requestAccess for camera/video and microphone/audio. openSettings uses NSWorkspace with the matching Privacy & Security pane URL.

AppModel publishes a dictionary initialized to notDetermined for all permissions. refreshPermissions queries every case; request stores the returned state; openSettings delegates to the checker.

Add case permissionDenied(CapturePermission) to RecordingFailure now that CapturePermission exists.

- [x] **Step 4: Run focused and complete tests**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/AppModelTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
~~~

Expected: tests pass without displaying macOS permission prompts.

- [x] **Step 5: Commit**

~~~bash
git add Cloom/App Cloom/Permissions Cloom/Recording/RecordingState.swift CloomTests/AppModelTests.swift
git commit -m "feat: add capture permission handling"
~~~

---

### Task 3: Persisted Recording Settings

**Files:**
- Create: Cloom/Settings/RecordingSettings.swift
- Create: Cloom/Settings/SettingsStore.swift
- Create: CloomTests/SettingsStoreTests.swift
- Modify: Cloom/App/AppModel.swift

**Interfaces:**
- Consumes: AppModel from Task 2.
- Produces: OverlayShape, OverlaySize, RecordingSettings, SettingsStoring, UserDefaultsSettingsStore, and InMemorySettingsStore.

- [x] **Step 1: Write failing defaults and round-trip tests**

~~~swift
import XCTest
@testable import Cloom

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchMVPChoices() {
        let settings = RecordingSettings.default
        XCTAssertFalse(settings.includeSystemAudio)
        XCTAssertEqual(settings.overlayShape, .circle)
        XCTAssertEqual(settings.overlaySize, .medium)
        XCTAssertNil(settings.cameraDeviceID)
        XCTAssertNil(settings.microphoneDeviceID)
    }

    func testUserDefaultsStoreRoundTripsSettings() throws {
        let suiteName = "CloomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let expected = RecordingSettings(
            includeSystemAudio: true,
            overlayShape: .roundedSquare,
            overlaySize: .large,
            cameraDeviceID: "camera-1",
            microphoneDeviceID: "mic-1"
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }
}
~~~

- [x] **Step 2: Run tests and verify they fail**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/SettingsStoreTests
~~~

Expected: compilation fails because the settings types do not exist.

- [x] **Step 3: Implement settings and storage**

~~~swift
enum OverlayShape: String, Codable, CaseIterable, Sendable {
    case circle
    case roundedSquare
}

enum OverlaySize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

struct RecordingSettings: Codable, Equatable, Sendable {
    var includeSystemAudio: Bool
    var overlayShape: OverlayShape
    var overlaySize: OverlaySize
    var cameraDeviceID: String?
    var microphoneDeviceID: String?

    static let default = RecordingSettings(
        includeSystemAudio: false,
        overlayShape: .circle,
        overlaySize: .medium,
        cameraDeviceID: nil,
        microphoneDeviceID: nil
    )
}

protocol SettingsStoring: AnyObject {
    func load() -> RecordingSettings
    func save(_ settings: RecordingSettings)
}

final class InMemorySettingsStore: SettingsStoring {
    private(set) var value: RecordingSettings

    init(value: RecordingSettings = .default) {
        self.value = value
    }

    func load() -> RecordingSettings { value }
    func save(_ settings: RecordingSettings) { value = settings }
}
~~~

UserDefaultsSettingsStore JSON-encodes the whole value under recordingSettings.v1 and returns default for missing or malformed data. Change AppModel's initializer to init(permissionChecker: PermissionChecking, settingsStore: SettingsStoring = UserDefaultsSettingsStore()), publish the loaded settings, and save settings changes through the injected store.

- [x] **Step 4: Run focused and complete tests**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/SettingsStoreTests
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
~~~

Expected: all settings and earlier tests pass.

- [x] **Step 5: Commit**

~~~bash
git add Cloom/App/AppModel.swift Cloom/Settings CloomTests/SettingsStoreTests.swift
git commit -m "feat: persist recording settings"
~~~

---

### Task 4: Foundation User Interface

**Files:**
- Create: Cloom/UI/PermissionRow.swift
- Create: Cloom/UI/SetupView.swift
- Create: Cloom/UI/RecordingStatusView.swift
- Create: CloomTests/SetupReadinessTests.swift
- Modify: Cloom/App/CloomApp.swift
- Modify: Cloom/App/AppModel.swift

**Interfaces:**
- Consumes: AppModel permissions and settings plus RecordingCoordinator.phase.
- Produces: AppModel.isReadyToConfigure and the runnable setup UI used by the next plan.

- [x] **Step 1: Write failing readiness tests**

~~~swift
import XCTest
@testable import Cloom

@MainActor
final class SetupReadinessTests: XCTestCase {
    func testConfigurationRequiresAllPermissions() async {
        let checker = FakePermissionChecker(statuses: [
            .screen: .authorized,
            .camera: .authorized,
            .microphone: .denied,
        ])
        let model = AppModel(permissionChecker: checker, settingsStore: InMemorySettingsStore())
        await model.refreshPermissions()
        XCTAssertFalse(model.isReadyToConfigure)
    }

    func testAllAuthorizedPermissionsEnableConfiguration() async {
        let statuses = Dictionary(
            uniqueKeysWithValues: CapturePermission.allCases.map { ($0, PermissionState.authorized) }
        )
        let model = AppModel(
            permissionChecker: FakePermissionChecker(statuses: statuses),
            settingsStore: InMemorySettingsStore()
        )
        await model.refreshPermissions()
        XCTAssertTrue(model.isReadyToConfigure)
    }
}
~~~

- [x] **Step 2: Run tests and verify they fail**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/SetupReadinessTests
~~~

Expected: compilation fails because isReadyToConfigure does not exist.

- [x] **Step 3: Implement readiness and views**

~~~swift
var isReadyToConfigure: Bool {
    CapturePermission.allCases.allSatisfy { permissions[$0] == .authorized }
}
~~~

SetupView contains one PermissionRow each for Screen Recording, Camera, and Microphone. notDetermined rows show Grant Access; denied or restricted rows show Open Settings.

After authorization, show a Form with disabled source, camera, and microphone rows labeled Available in capture milestone; working controls for Include Mac system audio, shape, and size; and a disabled Record button labeled Choose a screen or window before recording. RecordingStatusView exhaustively renders every RecordingPhase. CloomApp creates AppModel.live and calls refreshPermissions from a task.

- [x] **Step 4: Run tests and build**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
~~~

Expected: all tests pass and the app builds without Cloom-source warnings.

- [x] **Step 5: Smoke-test a signed run from Xcode**

Verify:

- The app launches as Cloom.
- All three permission rows render.
- Grant Access triggers the corresponding macOS prompt.
- Denied permissions show Open Settings.
- Changing system audio, shape, or size survives relaunch.
- Record remains disabled because source selection belongs to the capture plan.

- [x] **Step 6: Commit**

~~~bash
git add Cloom/App Cloom/UI CloomTests/SetupReadinessTests.swift
git commit -m "feat: add Cloom setup experience"
~~~

---

### Task 5: Foundation Verification and Handoff

**Files:**
- Create: README.md
- Modify: docs/superpowers/plans/2026-09-06-cloom-foundation.md

**Interfaces:**
- Consumes: all foundation interfaces.
- Produces: verified developer commands and completion evidence for the capture-and-overlay plan.

- [x] **Step 1: Add developer instructions**

README.md must contain:

~~~markdown
# Cloom

Cloom is a local native macOS screen recorder with a configurable webcam overlay.

## Requirements

- macOS 15 or later
- Xcode 26.6 or compatible

## Build and test

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
~~~

Open Cloom.xcodeproj in Xcode for a signed local run that can request capture permissions.
~~~

Use four tildes for the outer README fence when copying this nested example so the inner bash fence remains valid.

- [x] **Step 2: Run final automated verification**

~~~bash
xcodebuild clean -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
~~~

Expected: clean succeeds, all tests pass, build succeeds, git diff --check is silent, and only README.md plus the plan-tracking change remain uncommitted.

- [x] **Step 3: Record verification evidence**

Append a Verification evidence subsection under this task containing the date, macOS version, Xcode version, number of tests executed, build result, and any baseline-only warnings. Do not record success unless current command output confirms it.

#### Verification evidence

- Date: 2026-09-06.
- Host: macOS 26.6.2 (25G83), Xcode 26.6 (17F113).
- Clean: succeeded.
- Tests: 10 executed, 0 failures, 0 unexpected failures.
- Build: succeeded for the macOS application target with code signing disabled.
- Smoke launch: the signed debug app launched and registered a 660 by 720 on-screen Cloom window. Targeted screenshot capture was unavailable because the terminal lacks Screen Recording permission.
- Baseline-only warnings: Xcode reported unavailable CoreSimulator services, skipped AppIntents metadata because the app has no AppIntents dependency, and linkd connection messages from the command-line test host. No Cloom Swift compiler warnings were reported.

- [x] **Step 4: Commit**

~~~bash
git add README.md docs/superpowers/plans/2026-09-06-cloom-foundation.md
git commit -m "docs: add Cloom development guide"
~~~

- [ ] **Step 5: Prepare the next plan**

Create docs/superpowers/plans/2026-09-06-cloom-capture-overlay.md using the writing-plans workflow. It must consume the interfaces in this plan and cover ScreenCaptureKit source selection, screen/microphone/optional-system-audio source writers, AVFoundation device discovery and camera capture, normalized overlay events, the floating NSPanel, countdown, controls, and capture-workspace manifests. Do not begin exporter work in that plan.
