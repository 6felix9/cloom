# Fix Issue #13 — Recording Countdown Stays on "3"

**Goal:** Pressing Start Recording shows a large 3 → 2 → 1, one step per second, before recording starts.

**Issue:** https://github.com/6felix9/cloom/issues/13

## Root Cause

- `RecordingPhase.countdown` carried no remaining value, so the UI had nothing to show except a constant.
- `ThreeSecondCountdownSleeper` slept once for 3 s, so the coordinator never had a moment to publish 2 or 1.
- `RecordingStatusView` hard-coded "Starting in 3…", and `RecordingControlsView` showed the red record icon and `00:00` timer in every phase, so the countdown looked like a recording already in progress.

## Fix

1. `RecordingPhase.countdown(remaining: Int)`.
2. `RecordingCoordinator.beginCountdown(seconds:)` enters the countdown at `seconds`. The new `tickCountdown()` steps it down and refuses to go below 1. `beginRecording()` accepts any countdown phase.
3. `CountdownSleeping` stays as the test injection point, but now sleeps one tick (`sleepForCountdownTick()`, `OneSecondCountdownSleeper`). `RecordingSessionController.start` sleeps `countdownSeconds` (3) ticks and ticks the coordinator between them. The epoch is still sampled after the countdown.
4. `RecordingStatusView` shows "Starting in N…".
5. During the countdown, `RecordingControlsView` shows the remaining seconds as a large number, in place of the record icon and timer.

## Tests

- `RecordingCoordinatorTests`: countdown goes 3 → 2 → 1, then `.recording`. Ticking past 1, ticking outside the countdown, and a zero-second countdown are all rejected.
- `RecordingSessionControllerTests.testCountdownTicksThreeTwoOneBeforeStartingCapture`: the controlled sleeper checks the phase at each tick and that no capture starts before the countdown ends.
