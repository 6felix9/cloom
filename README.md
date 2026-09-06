# Cloom

Cloom is a local native macOS screen recorder with a configurable webcam overlay.

## Requirements

- macOS 15 or later
- Xcode 26.6 or compatible

## Build and test

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Open `Cloom.xcodeproj` in Xcode for a signed local run that can request capture permissions.

## Permissions and Signed Runs

Cloom requires three macOS privacy permissions before recording can begin:
- **Screen Recording** (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`)
- **Camera** (`AVCaptureDevice.requestAccess(for: .video)`)
- **Microphone** (`AVCaptureDevice.requestAccess(for: .audio)`)

For testing with live hardware devices, launch Cloom directly from Xcode with code signing enabled so macOS can grant and persist these permissions.

## Recoverable Recording Workspace

During recording, source media is streamed incrementally into a unique workspace located at:
`~/Library/Application Support/Cloom/Recordings/<UUID>/`

The workspace contains:
- `screen.mov`: Captured screen or window video (H.264, 1920x1080 at 30 FPS, BGRA).
- `camera.mov`: Captured webcam video (H.264, synchronized to the host-time epoch).
- `microphone.m4a`: Audio recorded from the selected microphone (AAC, 48 kHz).
- `system-audio.m4a`: Optional system audio stream (AAC, present when enabled).
- `overlay.json`: Timestamped log of webcam overlay positions, shapes, and sizes.
- `manifest.json`: Recording metadata, device IDs, audio mode, and capture state.
## Video Composition and Output

When you stop recording, Cloom automatically renders and mixes the final video:
- **Output location**: `~/Movies/Cloom/Cloom YYYY-MM-DD at HH.mm.ss.mp4`
- **Collision resolution**: If a file with the same timestamp exists, Cloom appends an incrementing suffix (` 2`, ` 3`, etc.).
- **Visual composition**:
  - Fits any display or window dimension inside a 1920x1080 canvas without distortion.
  - Crops and mirrors the webcam feed, applying circular or rounded-square masks.
  - Places the webcam at its normalized coordinates and applies 150 ms ease-in-out size transitions.
- **Audio mixing**:
  - Blends microphone narration and optional Mac system audio (-6 dB each in combined mode).
  - Respects in-recording mute toggles by silencing microphone audio during muted intervals.
- **Safety and recovery**:
  - Raw source files are cleaned up only after the final MP4 has been successfully rendered and verified.
  - If export fails, source media is retained in `~/Library/Application Support/Cloom/Recordings/<UUID>/` with "Retry export" and "Reveal source files" actions.
