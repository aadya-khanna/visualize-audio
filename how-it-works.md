# How the visualizer works

## Colors

- Signal energy depends on loudness/intensity of the audio.
- Uses a rolling window of the last 40 samples for percentile calculation.
- Current color mapping:
  - low energy / dark timbre → mellow (deep blue/purple)
  - low energy / bright timbre → calm (teal)
  - high energy / dark timbre → aggressive (red/magenta)
  - high energy / bright timbre → energetic (warm orange)

## Audio → visual pipeline

- Applies log-scaled frequency bucketing to convert FFT data into visual bars (~96 bars).
- Motion blur and attack/decay easing applied to bar movement.
- Per-bar color easing toward frequency-position or mood-derived targets.

Implementation: native Swift under `macos/Sources/VisualizeAudio/` — vDSP FFT, hand-written
energy/centroid/loudness extraction (`Audio/FeatureExtractor.swift`), system-wide Core Audio
process tap (`Audio/ProcessTap.swift`), now-playing via `MediaRemote` (`Media/`).

See `docs/adr/001-macos-only-architecture.md` for the architecture decision record.
