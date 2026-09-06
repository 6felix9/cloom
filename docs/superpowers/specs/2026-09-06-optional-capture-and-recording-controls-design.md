# Optional Capture and Recording Controls Design

## Summary

This change resolves GitHub issues #1 through #6 as one recording-flow update. Cloom will support screen-only recordings and every camera/microphone inclusion combination, place the live camera bubble on the display associated with the selected capture source, present readable conditional recording controls, and enter a visible stopping state on the first Stop action.

The existing local-only capture, 1920 by 1080 at 30 FPS export, crash-safe workspace, and first-party-framework constraints remain unchanged.

Where this document differs from `2026-09-06-cloom-mvp-design.md`, this document supersedes the earlier MVP requirements for mandatory camera and microphone permissions, mandatory input devices, audio modes, recording controls, and bubble display placement.

## Goals

- Let users explicitly include or exclude the camera and microphone before recording.
- Require only the permissions and selected devices needed by the enabled inputs.
- Produce a valid screen-only MP4 when both camera and microphone are disabled.
- Preserve optional Mac system audio independently of microphone capture.
- Show the live camera bubble on the display associated with the selected display or window.
- Keep bubble coordinates normalized to the selected capture canvas for export.
- Show only controls that apply to the inputs enabled when recording began.
- Replace the cramped recording control row with readable labeled rows.
- Make the first Stop action immediately visible and prevent duplicate stop requests.
- Preserve current recovery behavior if capture finalization or export fails.

## Non-goals

- Switching physical camera or microphone devices during a recording.
- Enabling an input after recording has started.
- Capturing more than one camera or microphone.
- Continuously following a captured window as it moves between displays after recording starts.
- Changing output resolution, codecs, frame rate, or destination.
- Changing the existing system-audio fallback policy.

## Settings and Compatibility

`RecordingSettings` gains two persisted booleans:

```swift
var includeCamera: Bool
var includeMicrophone: Bool
```

Both default to `true`, preserving the current behavior for new and existing users. Device IDs remain stored even when their input is disabled so re-enabling an input restores the prior device choice.

`RecordingSettings` uses explicit decoding defaults for the two new fields. A saved `recordingSettings.v1` payload created by the current app therefore decodes with both inputs enabled instead of being discarded. Existing fields retain their current values.

## Permissions and Setup

Screen Recording permission is always required. Camera and microphone permissions are required only when their corresponding input is enabled.

The setup view continues to show all permission rows, but it exposes recording configuration whenever Screen Recording permission is authorized. This avoids a deadlock in which a denied camera or microphone permission prevents the user from reaching the toggle needed to disable that input.

The Recording section contains explicit `Include camera` and `Include microphone` toggles:

- The camera device picker appears only when camera capture is enabled.
- The microphone device picker appears only when microphone capture is enabled.
- The Face overlay section appears only when camera capture is enabled.
- System audio remains independently selectable and may be recorded without a microphone.

The Record button is enabled when:

- Screen Recording permission is authorized.
- A screen or window is selected.
- If camera capture is enabled, Camera permission is authorized and a camera device ID is selected.
- If microphone capture is enabled, Microphone permission is authorized and a microphone device ID is selected.

Its help text explains the currently missing requirement rather than always demanding both devices.

## Capture Configuration

`RecordingSessionConfiguration` continues to carry an immutable `RecordingSettings` value. The controller validates only enabled inputs.

Startup behavior is:

1. Create the recoverable workspace and initial overlay event file.
2. Validate enabled device selections.
3. Complete the countdown and establish the shared epoch.
4. Start camera capture only when `includeCamera` is true.
5. Configure ScreenCaptureKit microphone capture only when `includeMicrophone` is true.
6. Start screen capture and optional system audio.
7. Enter `.recording`.

`ScreenStreamConfigurationFactory.make` accepts an optional microphone device ID plus an explicit include-microphone decision. With microphone capture disabled it sets `captureMicrophone` to false and does not set a microphone device identifier.

`ScreenCaptureService` creates and registers a microphone track only when `configuration.captureMicrophone` is true. Its receiver accepts an optional microphone track and ignores microphone callbacks when absent. The camera service is not started or stopped when camera capture is disabled.

Cleanup tracks which services were actually attempted or started. Partial startup failures still finalize every attempted service and preserve the failed workspace.

## Export Behavior

`RecordingExporter` passes a camera URL to `VideoCompositor` only when the workspace manifest says camera capture was enabled. Without a camera, the compositor renders the fitted screen directly and never attempts an overlay.

`AudioMixer` continues treating a missing microphone file as an absent track. A recording may contain:

- Microphone audio only.
- Microphone plus system audio.
- System audio only.
- No audio tracks.

The final MP4 remains valid in all four cases. Mute intervals are collected and applied only when the recording snapshot includes a microphone.

## Capture Display Resolution

ScreenCaptureKit's content rectangle is expressed in global screen points using the Core Graphics orientation, while `NSPanel` uses AppKit global screen coordinates. A small pure geometry resolver converts the selected content rectangle into AppKit coordinates using the main display's top edge:

```text
appKitY = mainDisplay.maxY - screenCaptureRect.maxY
```

It then selects the `NSScreen` with the largest intersection area:

- A display capture resolves to that display's full AppKit frame.
- A window capture resolves to the display containing the largest portion of the selected window.
- If no frame intersects because the display arrangement changed, the nearest display by center distance is used.
- If no screens are available, the converted content rectangle is used as a safe fallback.

`ScreenCaptureSelection` stores this resolved `presentationFrame`. `AppModel` passes it to `CameraBubblePanelController`, which uses it for initial placement, resizing, drag normalization, and clamping. Export coordinates remain normalized from 0 through 1 and are unaffected by display scale.

The bubble's display is resolved when the source is selected. Moving a captured window to another display after recording starts is outside this change's scope.

## Recording State and Stop Behavior

`RecordingPhase` gains `.stopping`. The state machine becomes:

```text
idle -> preparing -> countdown -> recording -> stopping -> exporting -> finished
                                         \---------------------------> failed
```

`RecordingSessionController.stop()` transitions from `.recording` to `.stopping` synchronously before its first suspension point. It then stops active capture services, finishes the overlay store, marks capture complete, and transitions to `.exporting`.

This ordering fixes the two-click symptom: SwiftUI observes `.stopping` immediately, the Stop button becomes disabled and displays `Stopping...`, and a second stop task cannot be launched while asynchronous finalization runs. Any finalization error records the failed workspace and moves to `.failed` as before.

## Recording Controls

`AppModel` stores the settings snapshot used by the active recording. The recording view derives visibility from this snapshot, not mutable setup settings.

The active controls use a vertical group of labeled rows:

- Camera toggle, Size segmented control, and Shape picker appear only when camera capture was enabled.
- Mute Microphone appears only when microphone capture was enabled.
- When neither input was enabled, only elapsed time, status, and Stop remain.
- During `.stopping`, the stop control is disabled, uses a progress indicator, and reads `Stopping...`.

No fixed-width horizontal row may force labels to wrap character by character. Controls use full-width labeled rows with consistent alignment and reasonable minimum widths.

## Error Handling

- Missing enabled camera: fail before countdown with a camera-specific selection error.
- Missing enabled microphone: fail before countdown with a microphone-specific selection error.
- Disabled input: skip its startup, stop, UI controls, and export source without warning.
- Stop failure: retain workspace, surface the error, and enter `.failed`.
- Export failure: retain workspace and preserve existing Retry Export and Reveal Source Files actions.
- Optional settings decode failure unrelated to the two new keys: retain the current fallback to `.default`.

## Automated Testing

Tests follow red-green-refactor and cover observable behavior:

- Legacy settings payloads decode with camera and microphone enabled.
- Setup readiness succeeds for screen-only configuration and ignores disabled-input permissions.
- Enabled inputs still require authorization and device IDs.
- Stream configuration disables microphone capture and clears its device ID when microphone is excluded.
- Session startup and stop skip disabled camera and microphone services.
- System audio can remain enabled without a microphone.
- Exporting without camera or audio produces a valid 1080p MP4 with no audio track.
- Capture rectangles convert to AppKit coordinates for left, right, above, and below displays.
- Window rectangles resolve to the display with the largest intersection.
- Stop enters `.stopping` before asynchronous capture teardown completes, accepts exactly one stop operation, then enters `.exporting`.
- Recording-control visibility reflects the immutable active recording settings.
- Existing capture, overlay, recovery, export, and settings tests remain green.

The final verification commands are:

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Manual Verification Notes

After automated verification, each GitHub issue receives a comment containing only the checks relevant to that issue:

- #1: secondary-display and cross-display window selection, initial bubble placement, edge clamping, and final overlay location.
- #2: camera-off recording, absent camera bubble and camera controls, valid screen-only video, and camera re-enable behavior.
- #3: microphone-off recording with system audio off and on, absent mute control, expected audio-track presence, and microphone re-enable behavior.
- #4: readable controls at the minimum window size, no wrapping or overflow, and both camera/microphone combinations.
- #5: all four camera/microphone enabled combinations and the exact controls visible for each.
- #6: one Stop click, immediate stopping feedback, disabled repeat action, automatic export transition, and failure recovery.

Comments state the automated commands that passed and clearly mark the listed hardware/UI checks as manual work still to perform.

## Success Criteria

On macOS 15 or later, a user can record a selected display or window with any camera/microphone combination, optionally include system audio, see only applicable readable recording controls, position the camera bubble on the selected source's display, and stop with one click that immediately enters a visible stopping state. The resulting 1080p MP4 contains exactly the enabled media sources, and failure never deletes the recoverable workspace.
