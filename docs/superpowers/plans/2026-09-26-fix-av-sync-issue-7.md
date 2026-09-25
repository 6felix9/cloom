# Fix Issue #7 — Exported MP4 A/V Desync and Leading Black

**Goal:** Exported MP4s start on real content, with microphone and system audio in sync with screen and camera video for the whole clip.

**Issue:** https://github.com/6felix9/cloom/issues/7

## Root Cause

The recording epoch is sampled before the camera and ScreenCaptureKit pipelines are started, so each stream's first sample arrives at a different `epoch + warm-up` (1–3 s). Every capture writer calls `startSession(atSourceTime: epoch)`, and AVAssetWriter inserts a leading empty edit when the first sample is later than the session start. Verified with probes against the real `MediaSampleWriter`:

| Artifact | Leading warm-up gap | Effect at export (before fix) |
|---|---|---|
| `screen.mov` | kept as an empty edit | The decoding `AVAssetReaderTrackOutput` emits a **black placeholder frame at t=0** for the empty edit, so `VideoCompositor`'s "rebase to the first frame" was a no-op and the render opened on black for the whole screen warm-up. **This is the black head.** |
| `camera.mov` | kept as an empty edit | Same placeholder behaviour; the camera happened to stay on the epoch timeline. |
| `microphone.m4a`, `system-audio.m4a` | **dropped by the M4A container** | Audio started at t=0 with its first real sample, while real video only started at the screen's warm-up offset. **This is the desync**, and it made epoch-relative mute intervals land in the wrong place. |

Overlay events and mute intervals are recorded relative to the epoch.

## Fix

1. **Keep the audio offset:** raw microphone and system audio are now written as QuickTime (`microphone.mov`, `system-audio.mov`), which keeps the leading empty edit like the video files do.
2. **`RecordingTimeline`** (`Cloom/Export/RecordingTimeline.swift`) reads each stream's first real sample from the first non-empty track segment. It sets `anchor` = the latest start among screen, camera (if enabled) and microphone (if enabled). System audio is optional and may start late, so it is aligned but never moves the anchor.
3. **`VideoCompositor.render(anchor:)`** keeps screen, camera and overlay events on the shared epoch-relative source timeline and emits `sourceTime − anchor`. Frames before the anchor (including the empty-edit placeholder) are skipped. The latest real screen frame before the anchor is held at t=0, because ScreenCaptureKit only delivers frames when content changes.
4. **`AudioMixer.mux(anchor:)`** inserts each audio source from the anchor onward at `sourceStart − anchor`, and rebases mute intervals with `AudioMixer.rebased(_:anchor:)`.
5. **`RecordingExporter`** resolves the timeline, passes the anchor to both stages, and logs the per-stream starts (`com.tzefoong.Cloom` / `Export`).

The epoch is still sampled before the pipelines start, so no stream drops early samples. Output t=0 lines up with the moment all essential streams are live, which is roughly when the UI switches to "Recording".

## Tests

- `RecordingTimelineTests`: capture files keep per-stream start offsets; anchor selection; missing optional streams; missing screen.
- `VideoCompositorTests`: warm-up trimmed with the first frame non-black; the latest pre-anchor frame is held; a single pre-anchor frame still renders; camera frames and overlay events share the screen timeline.
- `AudioMixerTests`: microphone onset aligned to t=0; late system audio keeps its offset; mute interval rebasing.
- `RecordingExporterTests.testExportStartsOnRealContentWithAudioAlignedWhenStreamsWarmUpAtDifferentTimes`: end to end, with camera, screen and microphone starting at +0.1/+0.2/+0.4 s. Against the previous code it fails with a black first frame and audio ending 0.39 s before video.

## Follow-ups (out of scope)

- Static-screen tail: video ends at the last delivered screen frame and audio is clamped to the video duration, so a static screen at the end of a recording truncates audio. Repeat the last frame up to the stop time.
- Camera auto-exposure warm-up may show a dark bubble for the first few hundred milliseconds.
