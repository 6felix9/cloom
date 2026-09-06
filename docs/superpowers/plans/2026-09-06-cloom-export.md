# Cloom Export and Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Transform the raw source media from a completed Cloom recording workspace (`screen.mov`, `camera.mov`, `microphone.m4a`, `system-audio.m4a`, `overlay.json`) into a single, synchronized, high-quality 1080p 30 FPS H.264/AAC MP4 video saved to `~/Movies/Cloom/`.

**Architecture:** A standalone, Sendable `RecordingExporter` consumes a `RecordingWorkspace` and produces a final `.mp4` file. It delegates video compositing to `VideoCompositor` (using Core Image filters, transforms, and `AVAssetWriterInputPixelBufferAdaptor` on a 1920x1080 canvas) and audio mixing to `AudioMixer` (using `AVMutableComposition` and `AVMutableAudioMix` with -6 dB per-track attenuation when system audio is present, and volume ducking/silence during mute intervals). `AppModel` drives export upon capture completion, publishes progress to `SetupView`, reveals the output in Finder, and ensures workspaces are preserved on failure.

**Tech Stack:** Swift 6, AVFoundation, CoreImage, CoreMedia, AppKit, SwiftUI, XCTest, Xcode 26.6

**Spec:** docs/superpowers/specs/2026-09-06-cloom-mvp-design.md

## Global Constraints

- Target resolution: 1920 by 1080 pixels at 30 FPS.
- Video format: H.264 progressive (`AVVideoCodecType.h264`), 8 Mbps target bitrate, 32BGRA pixel format.
- Audio format: AAC stereo (`kAudioFormatMPEG4AAC`), 48 kHz, 192 kbps.
- Container: QuickTime MP4 (`AVFileType.mp4`).
- Output directory: `~/Movies/Cloom/`.
- Naming format: `Cloom YYYY-MM-DD at HH.mm.ss.mp4` with collision resolution appending ` 2`, ` 3`, etc.
- Aspect ratio: Non-16:9 source screens are aspect-fitted inside 1920x1080 with black bars; no stretching or distortion.
- Webcam overlay: Horizontally mirrored, centered square crop, masked to circle or rounded square, scaled to small (12%), medium (18%), or large (25%) of 1080p height, placed at normalized center `(centerX, centerY)`.
- Smooth transitions: 150 ms ease-in-out interpolation when size changes.
- Audio balance: Microphone only at 0 dB (unity gain); combined microphone + system audio at -6 dB (`0.501187`) each to prevent clipping.
- Mute intervals: Silence applied during recorded mute intervals.
- Fault tolerance: Workspace is retained on failure; deleted only after export successfully verifies.

---

### Task 1: Collision-Safe Output Naming

**Files:**
- Create: Cloom/Export/RecordingOutputNamer.swift
- Create: CloomTests/RecordingOutputNamerTests.swift

**Interfaces:**
- Produces: `RecordingOutputNamer.availableURL(in:date:fileManager:) -> URL`.
- Consumes: Foundation `URL`, `Date`, `FileManager`.

- [ ] **Step 1: Write failing output namer tests**

~~~swift
import Foundation
import XCTest
@testable import Cloom

final class RecordingOutputNamerTests: XCTestCase {
    func testNameUsesTimestampAndDoesNotOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: first)
        let second = RecordingOutputNamer.availableURL(in: directory, date: date)

        XCTAssertEqual(first.pathExtension, "mp4")
        XCTAssertEqual(
            second.deletingPathExtension().lastPathComponent,
            first.deletingPathExtension().lastPathComponent + " 2"
        )
    }

    func testMultipleCollisionsIncrementSuffix() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: first)
        let second = RecordingOutputNamer.availableURL(in: directory, date: date)
        try Data().write(to: second)
        let third = RecordingOutputNamer.availableURL(in: directory, date: date)

        XCTAssertEqual(
            third.deletingPathExtension().lastPathComponent,
            first.deletingPathExtension().lastPathComponent + " 3"
        )
    }
}
~~~

- [ ] **Step 2: Run test and verify it fails (RED)**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingOutputNamerTests
~~~

- [ ] **Step 3: Implement RecordingOutputNamer**

~~~swift
import Foundation

enum RecordingOutputNamer {
    static func availableURL(
        in directory: URL,
        date: Date = .now,
        fileManager: FileManager = .default
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Cloom \(formatter.string(from: date))"
        var candidate = directory.appending(path: stem).appendingPathExtension("mp4")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(stem) \(suffix)").appendingPathExtension("mp4")
            suffix += 1
        }
        return candidate
    }
}
~~~

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingOutputNamerTests
git add Cloom/Export/RecordingOutputNamer.swift CloomTests/RecordingOutputNamerTests.swift
git commit -m "feat: add collision-safe recording output namer"
~~~

---

### Task 2: Core Image Video Composition and Overlay Masking

**Files:**
- Create: Cloom/Export/VideoCompositor.swift
- Create: CloomTests/VideoCompositorTests.swift

**Interfaces:**
- Produces: `VideoCompositor.render(screenURL:cameraURL:events:outputURL:progress:) throws`.
- Consumes: Core Image, AVAssetReader, AVAssetWriter, `TimedOverlayEvent`.

- [ ] **Step 1: Write failing video compositing tests**

Create synthetic sample test videos for screen and camera, and verify compositing succeeds, preserves duration, renders 1920x1080 video, and invokes progress callbacks.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/VideoCompositorTests
~~~

- [ ] **Step 3: Implement VideoCompositor**

Implement aspect-fit screen scaling, centered square camera crop, horizontal mirror transform, circle and rounded-rectangle masks using `CIFilter.roundedRectangleGenerator()`, normalized coordinate placement, and 150 ms size interpolation. Render with `CIContext` into `CVPixelBufferPool` buffers and append to `AVAssetWriterInputPixelBufferAdaptor`.

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/VideoCompositorTests
git add Cloom/Export/VideoCompositor.swift CloomTests/VideoCompositorTests.swift
git commit -m "feat: add Core Image video compositor"
~~~

---

### Task 3: Multi-Track Audio Mixing and Muting

**Files:**
- Create: Cloom/Export/AudioMixer.swift
- Create: CloomTests/AudioMixerTests.swift

**Interfaces:**
- Produces: `AudioMixer.mux(videoURL:microphoneURL:systemAudioURL:includeSystemAudio:muteIntervals:outputURL:) async throws`.
- Consumes: `AVMutableComposition`, `AVMutableAudioMix`, `AVAssetExportSession`.

- [ ] **Step 1: Write failing audio mixing tests**

Verify microphone-only mode maintains unity gain, combined mode applies -6 dB to both tracks, and mute intervals apply 0.0 volume parameters.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/AudioMixerTests
~~~

- [ ] **Step 3: Implement AudioMixer**

Construct `AVMutableComposition` containing video and audio tracks. Configure `AVMutableAudioMixInputParameters` with volume ramp or stepped volume to zero during mute intervals, and export using `AVAssetExportPresetHighestQuality` to MP4.

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/AudioMixerTests
git add Cloom/Export/AudioMixer.swift CloomTests/AudioMixerTests.swift
git commit -m "feat: add audio mixer with system audio and mute support"
~~~

---

### Task 4: RecordingExporter Pipeline and Progress

**Files:**
- Create: Cloom/Export/RecordingExporter.swift
- Create: CloomTests/RecordingExporterTests.swift
- Modify: Cloom/Recording/RecordingWorkspace.swift (ensure Sendable or safe path passing)

**Interfaces:**
- Produces: `protocol RecordingExporting: Sendable`, `struct RecordingExporter: RecordingExporting`.
- Consumes: `RecordingWorkspace`, `VideoCompositor`, `AudioMixer`, `RecordingOutputNamer`.

- [ ] **Step 1: Write failing export pipeline tests**

Verify end-to-end export from mock or synthetic workspace produces output MP4 in `~/Movies/Cloom`, removes temporary intermediate artifacts, updates progress from 0 to 1, and retains workspace on injected failure.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingExporterTests
~~~

- [ ] **Step 3: Implement RecordingExporter**

Coordinate destination URL generation, temporary render file, compositor execution (progress 0.0 to 0.9), audio mixing (progress 0.9 to 1.0), atomic destination placement, and workspace retention logic.

- [ ] **Step 4: Verify green and commit**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/RecordingExporterTests
git add Cloom/Export/RecordingExporter.swift Cloom/Recording/RecordingWorkspace.swift CloomTests/RecordingExporterTests.swift
git commit -m "feat: implement recording export pipeline"
~~~

---

### Task 5: App Integration and Export UI

**Files:**
- Modify: Cloom/App/AppModel.swift
- Modify: Cloom/UI/SetupView.swift
- Create: CloomTests/ExportIntegrationTests.swift

**Interfaces:**
- Consumes: `RecordingExporter`, `RecordingCoordinator`, `AppModel`.
- Produces: User-facing export progress bar, completion view with "Reveal in Finder", failure view with "Retry export" and "Reveal source files".

- [ ] **Step 1: Write failing UI / AppModel export integration tests**

Verify that `AppModel.stopRecording()` automatically triggers `exporter.export`, updates coordinator export progress, transitions to `.finished` with output URL on success, and transitions to `.failed` on error.

- [ ] **Step 2: Verify red**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/ExportIntegrationTests
~~~

- [ ] **Step 3: Wire AppModel and SetupView**

Inject `RecordingExporting` into `AppModel`. Update `stopRecording()` to initiate export. Render `ProgressView` during `.exporting`, success actions during `.finished`, and retry actions during `.failed`.

- [ ] **Step 4: Verify green and run full test suite**

~~~bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Cloom/App/AppModel.swift Cloom/UI/SetupView.swift CloomTests/ExportIntegrationTests.swift
git commit -m "feat: integrate export pipeline into app lifecycle"
~~~

---

### Task 6: Exporter Verification and Release Polish

**Files:**
- Modify: README.md
- Modify: docs/superpowers/plans/2026-09-06-cloom-export.md

**Interfaces:**
- Consumes: Complete export pipeline.
- Produces: Verified end-to-end recording and export evidence.

- [ ] **Step 1: Document export workflow and settings in README.md**
- [ ] **Step 2: Clean verification run across all suites**
- [ ] **Step 3: Record verification evidence and close milestone**
- [ ] **Step 4: Commit**
