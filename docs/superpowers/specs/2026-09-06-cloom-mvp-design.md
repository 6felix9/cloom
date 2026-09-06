# Cloom MVP Design

## Summary

Cloom is a local, native macOS utility for recording a selected display or window with a movable webcam overlay. The webcam overlay is burned into the exported video and may change position, size, and shape while recording. Cloom records microphone audio by default and can optionally include Mac system audio.

The MVP targets macOS 15 and later, produces a 1080p 30 FPS H.264 MP4, and stores completed recordings in `~/Movies/Cloom`.

## Goals

- Record one selected display or one selected window.
- Record one selected camera and microphone.
- Let the user optionally include Mac system audio.
- Show a live, always-on-top webcam overlay while recording.
- Support circle and rounded-square webcam shapes.
- Support Small, Medium, and Large overlay sizes.
- Let the user move and resize the overlay while recording.
- Export one shareable MP4 containing the screen, webcam overlay, and chosen audio.
- Recover source media when final export fails.

## Non-goals

- Cloud uploads, share links, accounts, or collaboration.
- Transcription, captions, drawing tools, or editing timelines.
- Arbitrary overlay shapes or freeform resizing.
- Multiple simultaneous cameras, microphones, displays, or windows.
- 4K, HDR, or frame rates above 30 FPS.
- Mac App Store distribution in the MVP.

## Platform and Technology

- Language: Swift.
- UI: SwiftUI, with AppKit bridges for floating panel behavior and camera preview hosting.
- Screen and audio capture: ScreenCaptureKit.
- Camera capture: AVFoundation.
- Intermediate and final media writing: AVAssetWriter.
- Composition: Core Image for masks and transforms, rendered into pixel buffers for AVAssetWriter.
- Minimum deployment target: macOS 15.0.
- Distribution: local Developer ID or ad hoc build; App Sandbox is disabled for the MVP so Cloom can write directly to the configured recording directory.
- Development environment verified on macOS 26.6.2 with Xcode 26.6.

## User Experience

### Setup window

The setup window contains:

- A native ScreenCaptureKit sharing picker button for selecting one display or window.
- Camera and microphone selectors populated from available AVFoundation capture devices.
- An `Include Mac system audio` checkbox, off by default.
- A shape selector with Circle and Rounded Square.
- A size selector with Small, Medium, and Large.
- A Record button.

Cloom configures the picker to exclude its own bundle identifier so the setup window, floating controls, and webcam preview are not duplicated in the screen track.

### Permission flow

Before showing capture controls, Cloom explains and checks:

- Screen Recording access.
- Camera access.
- Microphone access.

The app declares `NSScreenCaptureUsageDescription`, `NSCameraUsageDescription`, and `NSMicrophoneUsageDescription`, plus the macOS camera and audio-input entitlements. A denied permission shows which capability is unavailable and an `Open System Settings` action. Cloom does not start a recording until screen, camera, and microphone access are available.

### Recording flow

1. The user selects a display or window, camera, microphone, audio mode, shape, and size.
2. Record begins a visible three-second countdown.
3. At the shared recording epoch, Cloom starts screen, camera, microphone, and optional system-audio capture.
4. A compact floating control bar shows elapsed time, camera visibility, microphone mute, size, and Stop.
5. The webcam panel remains above normal application windows. The user can drag it or choose another size preset.
6. Every overlay change is recorded against the shared recording clock.
7. Stop ends all streams and transitions to export.
8. A progress view displays `Preparing video...` while Cloom renders the final MP4.
9. Success displays `Reveal in Finder` and `Record another`.

The microphone toggle during recording changes whether microphone samples are included from that moment forward; it does not stop or reconfigure the underlying capture session. The camera toggle similarly hides the composited overlay without stopping camera capture.

## Architecture

### RecordingCoordinator

`RecordingCoordinator` is the single owner of the recording state machine:

```text
idle -> preparing -> countdown -> recording -> exporting -> finished
                            \-> failed <-/
```

It validates prerequisites, establishes the shared monotonic recording epoch, starts and stops services, publishes state to SwiftUI, and hands completed source artifacts to the exporter. Invalid state transitions fail without changing the current state.

### ScreenCaptureService

`ScreenCaptureService`:

- Presents `SCContentSharingPicker` configured for single-display and single-window selection.
- Excludes Cloom's bundle identifier from the picker and capture.
- Creates an `SCStream` from the selected `SCContentFilter`.
- Requests 1920 by 1080 output at 30 FPS using a stable pixel format.
- Receives `.screen`, `.microphone`, and, when enabled, `.audio` sample buffers on dedicated serial queues.
- Writes screen video and audio sources without compositing the camera.

For source dimensions that do not match 16:9, the exporter fits the source inside 1920 by 1080 without stretching and fills unused pixels with black.

### CameraCaptureService

`CameraCaptureService` owns one `AVCaptureSession` containing the selected `AVCaptureDeviceInput` and an `AVCaptureVideoDataOutput`. It sends frames to both:

- A live preview surface hosted in the floating panel.
- A timestamp-preserving camera source writer.

The preview is mirrored by default. The exported overlay uses the same mirrored orientation so the preview matches the result.

### CameraBubblePanel

`CameraBubblePanel` is a transparent, borderless, always-on-top `NSPanel`. It:

- Shows the live camera preview through a circular or rounded-square mask.
- Allows dragging within the selected display's visible frame.
- Applies Small, Medium, and Large presets.
- Keeps its center and diameter normalized to the selected capture area's coordinate space.
- Tracks the selected window's content rectangle when window capture is active so the panel stays aligned if that window moves or resizes.
- Sends changes to `OverlayEventStore` while recording.

Preset diameters are 12%, 18%, and 25% of the shorter output dimension. Overlay bounds are clamped so the full shape remains visible in the exported frame.

### OverlayEventStore

Overlay state is represented by normalized coordinates so it is independent of Retina scale and source resolution:

```swift
struct OverlayState: Codable, Equatable {
    var centerX: Double
    var centerY: Double
    var size: OverlaySize
    var shape: OverlayShape
    var isVisible: Bool
}

struct TimedOverlayEvent: Codable, Equatable {
    var timeSeconds: Double
    var state: OverlayState
}
```

The store writes an initial event at time zero and appends an event only when state changes. Events are also persisted incrementally to `overlay.json` in the recording's temporary working directory.

### RecordingWorkspace

Each recording receives a recoverable workspace at `~/Library/Application Support/Cloom/Recordings/<UUID>`. It contains:

```text
screen.mov
camera.mov
microphone.m4a
system-audio.m4a    # only when enabled and available
overlay.json
manifest.json
```

`manifest.json` records the recording epoch, source formats, selected devices, audio mode, intended output path, and completion state. The workspace is retained until final export succeeds. At the next launch, Cloom detects incomplete workspaces and offers to reveal or delete them.

### RecordingExporter

`RecordingExporter` runs after capture stops. It:

1. Reads the screen and camera tracks against their source timestamps.
2. Fits the screen into a 1920 by 1080 canvas without distortion.
3. Resolves the current overlay state for each output frame.
4. Crops the camera to a centered square, applies the selected mask, scales it, and places it at the normalized center.
5. Applies a 150 ms ease-in-out interpolation between size presets and uses direct position updates while dragging.
6. Mixes microphone audio and optional system audio, respecting timestamped microphone mute events. Microphone-only uses unity gain; combined mode uses -6 dB for each source to reduce clipping.
7. Writes H.264 video and AAC stereo audio to a temporary output file.
8. Atomically moves the completed file to `~/Movies/Cloom/Cloom YYYY-MM-DD at HH.mm.ss.mp4`.

The exporter reports progress from 0 to 1 using processed presentation time divided by total recording duration. It never overwrites an existing recording; duplicate names gain a numeric suffix.

## Timing and Synchronization

All capture services translate incoming presentation timestamps to a shared monotonic epoch established by `RecordingCoordinator`. Samples earlier than the epoch are discarded. Export duration ends at the last valid screen-video frame; camera or audio streams that end earlier contribute transparent video or silence for the remaining duration.

Each writer uses bounded queues. If a non-screen source cannot accept a sample, Cloom drops that source sample and records a diagnostic counter. If screen samples repeatedly cannot be written, Cloom stops with a recoverable recording error instead of producing an apparently successful corrupt video.

## Audio Modes

The setup UI exposes one checkbox:

- Off: microphone only.
- On: microphone plus Mac system audio.

Microphone capture is required for the MVP recording flow. If system-audio setup or capture fails, Cloom continues in microphone-only mode and shows a warning. If the microphone becomes unavailable after recording begins, Cloom continues with silence and shows a warning.

## Failure Handling

- Permission denied: remain idle and direct the user to the relevant System Settings page.
- Source selection cancelled: remain idle with the previous valid selection, if any.
- Selected display or window disappears before start: return to setup and request another source.
- Camera disconnects during recording: fade the latest valid frame to transparent over 250 ms, continue screen capture, and warn the user.
- Microphone disconnects: continue with silence and warn the user.
- Optional system audio fails: continue microphone-only and warn the user.
- Disk space or writer failure: stop capture, mark the workspace recoverable, and show its location.
- Export failure: retain all source artifacts and provide Retry and Reveal Files actions.
- App launch after interruption: detect incomplete manifests and offer Reveal Files or Delete.

## Persistence

UserDefaults stores the last selected camera ID, microphone ID, include-system-audio choice, overlay shape, overlay size, and save directory. Device selections fall back to the system default when the stored device is absent.

No recording content leaves the Mac. Cloom does not include analytics or networking in the MVP.

## Testing

### Unit tests

- Valid and invalid `RecordingCoordinator` state transitions.
- Overlay coordinate normalization, clamping, and output conversion.
- Overlay event coalescing and state lookup by timestamp.
- Size interpolation and camera visibility transitions.
- Audio-mode configuration and microphone mute intervals.
- Output naming and collision handling.
- Workspace manifest recovery decisions.

### Integration tests

- Start and stop with microphone-only capture using injected sample-buffer sources.
- Start and stop with microphone plus system audio.
- Camera disconnect behavior.
- System-audio failure fallback.
- Export failure retains the recording workspace.
- Successful export removes the recording workspace only after the final file exists.

### Manual verification

- Fresh permission grants and each denied-permission recovery path.
- Full-display and individual-window selection.
- Retina and non-Retina displays, plus moving the panel between displays before recording.
- Circle and rounded-square masks at every size.
- Dragging and resizing throughout a recording.
- Microphone-only and mixed-audio output in QuickTime Player.
- Camera and microphone device removal during recording.
- Long recording, low disk space, app termination during capture, and retry after export failure.

## Delivery Milestones

1. Project shell, entitlements, permissions, and tested recording state machine.
2. Source selection plus screen, microphone, and optional system-audio capture.
3. Camera capture and floating masked preview.
4. Overlay event recording and interaction controls.
5. Post-recording video composition and audio mix.
6. Recovery behavior, integration tests, and end-to-end manual verification.

## Success Criteria

On a supported Mac, a user can grant permissions, select one display or window, choose camera and microphone devices, optionally enable system audio, record while moving and resizing a circle or rounded-square face overlay, stop, and open a synchronized 1080p MP4 whose visible and audible content matches the recording controls. A failed export does not destroy the captured source media.
