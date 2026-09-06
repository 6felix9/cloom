# AGENTS.md — Cloom Engineering Guidelines & Agent Runbook

## Overview

Cloom is a native macOS application (Swift 6, macOS 15+) that provides a local, high-performance screen recorder with an interactive, floating webcam overlay inspired by Loom.

All capture, streaming, rendering, and mixing pipelines run entirely locally using first-party Apple frameworks with **zero external dependencies**.

---

## Architectural Principles & Rules

1. **Native Apple Frameworks Only**:
   - Do NOT add third-party SPM packages or CocoaPods.
   - Core stack: `ScreenCaptureKit`, `AVFoundation`, `CoreImage`, `AppKit`, `SwiftUI`.
2. **Swift 6 Strict Concurrency**:
   - Whole-module strict concurrency is enabled.
   - All async methods and closures must satisfy `Sendable` guarantees.
   - Use actors (e.g., `AppModel` is `@MainActor`) or thread-safe reference types (`@unchecked Sendable` with `NSLock`) when crossing concurrency boundaries.
3. **Canvas & Export Standards**:
   - Master composition output resolution: **1920×1080 @ 30 FPS**, H.264 video (`.mp4`), AAC stereo audio @ 48 kHz.
   - Screen capture is aspect-fitted without stretching or distortion.
   - Webcam feed is centered, squared, horizontally mirrored, masked (circle or rounded rectangle), and animated (150 ms size interpolation).
4. **Non-Destructive Crash Safety**:
   - Capture writes raw synchronized media streams into an isolated workspace (`~/Library/Application Support/Cloom/Recordings/<UUID>/`).
   - Workspace artifacts are deleted **only** after post-processing export succeeds and output file integrity is verified.
   - If export fails, workspace files remain preserved with UI options to retry export or reveal raw files in Finder.
5. **App Sandbox**:
   - Disabled for local MVP to allow direct hardware device discovery, ScreenCaptureKit system audio capture, and saving to `~/Movies/Cloom/`.

---

## Codebase Map

```
Cloom/
├── App/
│   ├── CloomApp.swift                # App entry point
│   └── AppModel.swift                # Root @MainActor coordinator binding UI, Capture, and Export
├── Capture/
│   ├── CaptureDeviceDiscovery.swift  # Enumerates cameras, microphones, and screens
│   ├── CaptureDeviceOption.swift     # Device models and identifiers
│   ├── CaptureSourceSelection.swift  # Selected source state model
│   ├── CameraCaptureService.swift    # AVCaptureSession camera pipeline
│   ├── ScreenCaptureService.swift    # ScreenCaptureKit display & window capture
│   ├── ScreenSourcePicker.swift      # System display/window picker integration
│   ├── ScreenStreamConfigurationFactory.swift # Audio mode stream configuration
│   └── MediaSampleWriter.swift       # AVAssetWriter wrapper for synchronized source streams
├── Overlay/
│   ├── CameraBubblePanel.swift       # Floating borderless NSPanel with edge clamping
│   ├── CameraPreviewView.swift       # Metal / AVCaptureVideoPreviewLayer wrapper
│   ├── OverlayState.swift            # Normalized coordinates (0...1), sizes (S/M/L), shapes
│   └── OverlayEventStore.swift       # Thread-safe JSON logger for overlay movement timestamps
├── Recording/
│   ├── RecordingCoordinator.swift    # State machine (.idle, .countdown, .recording, .exporting, .finished, .failed)
│   ├── RecordingSessionController.swift # Starts/stops screen & camera capture with single epoch
│   ├── RecordingWorkspace.swift      # Directory manager for UUID-based raw recordings
│   ├── RecordingManifest.swift       # JSON metadata tracking capture session details
│   └── RecordingState.swift          # Session state enum
├── Export/
│   ├── VideoCompositor.swift         # Core Image pipeline compositing screen + masked camera overlay
│   ├── AudioMixer.swift              # AVMutableComposition multi-track mixer (-6 dB attenuation & muting)
│   ├── RecordingOutputNamer.swift    # Formats destination path: "Cloom YYYY-MM-DD at HH.mm.ss.mp4"
│   └── RecordingExporter.swift       # Pipeline orchestrating render, audio mux, and workspace cleanup
├── Permissions/
│   ├── CapturePermission.swift       # Permission state tracking
│   └── SystemPermissionChecker.swift # Screen recording, Camera, and Mic permission queries & prompts
├── Settings/
│   ├── RecordingSettings.swift       # User preferences model
│   └── SettingsStore.swift           # UserDefaults persistence
└── UI/
    ├── SetupView.swift               # Pre-recording setup, device selection, and export progress view
    ├── PermissionRow.swift           # Individual permission status and deep-links
    ├── RecordingControlsView.swift   # Hover controls on camera bubble (size, shape, mute, stop)
    └── RecordingStatusView.swift     # Countdown and status indicators
```

---

## Verification & Testing

Always verify changes with the project's test suite and build command before asserting completion:

### Run Full Test Suite
```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
```

### Run Specific Test Suite
```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -only-testing:CloomTests/<SuiteName>
```

### Build App Target
```bash
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

---

## Development Guidelines for Agents

- **Modifying Capture or Export**: Always update or add corresponding unit tests in `CloomTests/`. Synthetic audio/video fixtures should be short (e.g., 0.1–0.5 seconds) to keep test execution fast.
- **Modifying Overlay**: Position coordinates must remain normalized (`0.0 ... 1.0`) relative to the primary display to ensure accurate mapping to the 1920×1080 canvas during post-export.
- **Git Hygiene**: When working on features or bug fixes, keep implementation test-driven, maintain zero compiler warnings, and clean up temporary worktrees upon completion.
