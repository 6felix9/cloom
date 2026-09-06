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

> **Note on Current Milestone:** This milestone records synchronized, recoverable source media. The final composited 1080p MP4 export is handled in the subsequent exporter milestone. If a recording is stopped or interrupted, source artifacts remain preserved in the workspace for export or manual recovery.
