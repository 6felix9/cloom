# Cloom

A lightweight, native macOS screen recorder with an interactive floating webcam bubble — inspired by Loom, built purely with Swift 6, SwiftUI, and ScreenCaptureKit.

---

## Features

- **Interactive Camera Bubble**: Draggable floating webcam overlay on top of all windows with edge-clamping across multiple displays.
- **Customizable Overlay**: Switch between 3 bubble sizes (Small 160pt, Medium 220pt, Large 300pt) with smooth 150 ms animations, and toggle between Circle and Rounded Square shapes.
- **Screen & Window Recording**: Capture entire displays or specific application windows with high fidelity.
- **Multi-Track Audio**: Record your microphone and optionally include Mac system audio (mixed at balanced -6 dB levels).
- **Quick Mute**: Mute and unmute your narration directly from the floating overlay during recording.
- **Automatic 1080p Export**: Automatically renders and mixes your recording into a 1920×1080 @ 30 FPS MP4 saved directly to `~/Movies/Cloom/`.
- **Fail-Safe & Recoverable**: Source audio and video are streamed safely to an isolated workspace. Raw files are only cleaned up after export is successfully verified.
- **100% Private & Native**: Zero external dependencies, no cloud subscriptions, no Electron — everything runs locally on your Mac.

---

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Xcode 16+** (with Swift 6)

---

## Quick Start & Setup

### 1. Open in Xcode
Clone the repository and open the project:
```bash
open Cloom.xcodeproj
```

Select your development team under **Signing & Capabilities** (required by macOS to remember privacy permissions across launches), select **My Mac** as the destination, and press **Cmd + R** to run.

### 2. Or Run from Command Line
```bash
# Build the application
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO

# Launch the built app
open build/Build/Products/Debug/Cloom.app
```

---

## How to Use

1. **Grant Permissions**:
   On the first launch, Cloom checks for **Screen Recording**, **Camera**, and **Microphone** access. Click the buttons in the setup screen to grant any missing permissions in macOS System Settings.
2. **Choose Sources**:
   - Select your target screen or window.
   - Choose your camera (with live preview) and microphone.
   - Select your audio mode: **Microphone Only** or **Microphone + System Audio**.
3. **Start Recording**:
   Click **Start Recording**. A 3-second countdown will appear before recording begins.
4. **Control the Floating Bubble**:
   - Drag the camera bubble to any position on your screen.
   - Hover over the bubble to access quick controls: resize (S / M / L), toggle shape, mute/unmute microphone, or stop recording.
5. **Stop & Export**:
   Click **Stop Recording** (from either the floating controls or the main window). Cloom will automatically composite the 1080p video, mix audio tracks, and present a **Reveal in Finder** button once complete.

---

## Output & Storage

- **Finished Videos**:
  Exported to `~/Movies/Cloom/Cloom YYYY-MM-DD at HH.mm.ss.mp4`. If a video already exists at the same timestamp, an incrementing suffix (` 2`, ` 3`) is appended.
- **Raw Recording Workspaces**:
  While recording is active, raw streams are stored at:
  `~/Library/Application Support/Cloom/Recordings/<UUID>/`
  If an export ever fails, source media is retained safely with options to **Retry export** or **Reveal source files**.

---

## Development & Testing

Run the full test suite (55 unit & integration tests):
```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
```

For developer architecture guidelines and module breakdowns, see [AGENTS.md](AGENTS.md).
