## Scope

Native Swift/SwiftUI macOS app (`macos/Sources/VisualizeAudio/`). This is the sole
implementation — the earlier React/Vite web app was removed (see
`docs/adr/001-macos-only-architecture.md`).

- `Audio/` — `ProcessTap.swift` (Core Audio system-wide tap, macOS 14.4+,
  no loopback device), `MicInputSource.swift` (AVAudioEngine mic/device
  picker, the alternate source), `FFT.swift` (vDSP real FFT, reproduces
  AnalyserNode's byte-range/smoothing convention), `FeatureExtractor.swift`
  (energy/spectral-centroid/loudness), `MoodTracker.swift`,
  `AudioEngine.swift` (coordinator).
- `Media/` — `MediaRemoteBridge.swift` (private `MediaRemote` framework via
  dlopen/dlsym), `NowPlaying.swift`.
- `Visualizer/` — `ColorMapping.swift`, `BarLayout.swift`, `Renderers.swift`,
  `AlbumPalette.swift` (album-cover colors -> per-bar colors, for the "Album"
  color mode), `VisualizerView.swift`.
- `Settings/SettingsView.swift` — gear-button panel. The music section is a
  passive status row, not a connect button — there is no login step with
  MediaRemote.

## Guardrails

- **Verified working** against Xcode 26.6 (macOS 26.5 SDK): the process tap,
  aggregate device, IOProc, and `MediaRemote` bridge all build and run —
  system audio capture and now-playing info both confirmed live. Three real
  issues turned up in that process, all fixed and worth knowing about:
  1. **A raw `swift build` executable can't get the system-audio-recording
     TCC permission.** No Info.plist means no usage-description string, and
     its ad-hoc code signature is a hash of the binary — a different
     identity every rebuild — so TCC has nothing stable to prompt for or
     remember a grant against. It doesn't error; it silently hands the tap
     zeroed buffers instead, which looks exactly like "the tap works but
     there's no audio." Fix: `scripts/build-app.sh` assembles a real `.app`
     bundle (binds `Info.plist`, ad-hoc signs with a **stable**
     `--identifier com.aadya.visualizeaudio`) — use it (or Xcode's own Run,
     which does the equivalent) instead of running the bare SPM binary.
     First launch of the bundle prompts for the permission; approve it once
     and it persists across rebuilds because the identifier is now stable.
  2. **Raw vDSP FFT magnitudes are an arbitrary internal scale, not dBFS** —
     converting them to dB needs a "zero reference" divisor (see Apple's
     `vDSP.convert(amplitude:toDecibels:zeroReference:)`); treating the raw
     magnitude as if it were already calibrated dB made the visualizer
     wildly over-sensitive (a full-scale test tone read as +30dB instead of
     ~0dBFS). `FFT.swift`'s `fullScaleReferenceMagnitude` constant is that
     reference, empirically measured via `scripts/fft_selftest.swift`
     (which reproduces this file's exact FFT pipeline against a synthetic
     full-scale tone) — re-run that script and update the constant if
     `fftSize` or the window function ever changes.
  3. **`ProcessTap` used a stereo tap (`CATapDescription(stereoGlobalTapButExcludeProcesses:)`)
     but `handle()` read its interleaved `[L0,R0,L1,R1,...]` buffer as if it
     were one sequence of mono samples** — for content correlated across
     channels (most music, and any test tone played on both channels), this
     measures every frequency at almost exactly half its true value.
     Fixed by switching to `CATapDescription(monoGlobalTapButExcludeProcesses:)`,
     which has CoreAudio itself mix down to mono before delivery.
  Also confirmed while chasing the tap bug: **content above ~20kHz doesn't
  make it through** (20kHz reads at ~1/20th the magnitude of everything
  else; 22-23kHz drop into the noise floor) — that's consistent across
  both tap variants and is a genuine hardware/system rolloff (ultrasonic,
  inaudible anyway), not a code bug — don't try to "fix" it.
  `MediaRemoteBridge.swift`'s dlsym symbol names and dictionary keys are the
  same ones widely relied on by existing open-source "now playing"
  utilities, but are unofficial and could shift on a future OS release.
- **Album color mode must not interpolate hue between the cover's colors, and
  must not lay them out as regions either.** Two rewrites, two different
  wrong-looking results, both worth not repeating:
  1. *A circular hue gradient through the extracted hues.* With only two or
     three stops that gradient covers the whole color wheel — a red-and-cyan
     cover painted orange, yellow, green, blue and magenta bars — so every
     album looked like the same generic rainbow. It also discarded each color's
     lightness and its share of the cover, so a dark album rendered bright and
     an 8% accent color got half the window.
  2. *Laying the colors out spatially* — first a contiguous band per color,
     then scattered control points blended into each other. Both read as slabs:
     neighbouring bars within a region are near-identical, so at 96 bars the
     window is three or four chunks of color with visible divides. Blending
     between regions also goes muddy where two cover colors are near
     complementary, because their midpoint is grey.
  What works: **each bar draws one of the cover's colors outright**, by a
  weighted per-bar random deal (weighted by each color's share of the artwork),
  and the only animation is a slow drift of that bar's *own* hue — ±10°, over
  15-35s, on a per-bar phase. No bar is ever painted a color the cover doesn't
  have, and at 96 bars the deal reads as the album's colors shimmering together
  rather than as any kind of layout. Things that look like details but aren't:
  - Swatches carry **chroma, not HSL saturation.** HSL reports a cream that is
    4% off white at 0.76 saturation, so re-rendering it at a lower lightness
    turned a cover's soft pink into a vivid crimson and tinted a
    black-and-white sleeve dusty red.
  - Keep the hue drift **small.** It is the album's color breathing, not a trip
    around the wheel; widen it much past ±10° and the mode starts inventing
    hues again, which is failure mode 1 by another route.
  - Album mode uses a **much faster per-bar color ease** than the other modes
    in `BarLayout.swift`. The slow multi-second ease that gives Frequency and
    Intensity their drifting-mood feel averages the loudness-driven lightness
    away to a constant, and the bars stop pulsing entirely. It's safe here
    because each bar's color changes only by that slow drift.
  - The drift needs a clock, so `computeBars` takes a `time`, fed from the
    `TimelineView` in `VisualizerView.swift` — not read from a global inside
    the color code, which would make the pipeline untestable.
- **Private APIs mean no App Store distribution** — distribute as a
  signed-but-not-notarized (or self-signed) build; users may need the
  `xattr -dr com.apple.quarantine` workaround.
- **Don't enable App Sandbox** on this target — the process tap and
  MediaRemote don't work under the sandbox restrictions required for
  App Store apps.
- **This is a Swift Package (`Package.swift`), not a hand-built `.xcodeproj`.**
  Open `macos/Package.swift` directly in Xcode ("File > Open…") — Xcode
  treats it as a project, and its own Run/Debug handles bundling and signing
  for you. From the command line, always use `scripts/build-app.sh` (not a
  bare `swift build`) — see guardrail 1 above for why.
- Keep `Renderers.swift` functions pure: `(ctx, dims, bars, ...) -> draws`.
  Display modes must stay swappable without touching the audio/color pipeline
  upstream.

## Validation

No CI — this needs Xcode (15.3+, macOS 14.4 SDK) to build and a real
macOS 14.4+ Mac to run, since neither the process tap nor MediaRemote can be
exercised from the command line alone:

1. `./scripts/build-app.sh && open .build/VisualizeAudio.app` (or Xcode's
   Run). First launch prompts for the system-audio-recording permission —
   approve it.
2. Verify each display mode (Normal/8-Bit/Curve) and color mode
   (Frequency/Intensity/Album).
3. Play audio from an arbitrary app (not just Spotify) with **no** loopback
   device installed — bars should react with real dynamic range (quiet
   passages low, transients tall, not everything pinned near max).
4. Switch to the microphone source in Settings and confirm that path still
   works.
5. Play/pause/change tracks in Spotify (or Music, or Safari) while the app
   is running — the track overlay should update with no connect/login step.
6. If `fftSize` or the window function in `FFT.swift` ever changes, re-run
   `swift scripts/fft_selftest.swift` and update `fullScaleReferenceMagnitude`
   from its output.
7. Album color mode is the one part of the visual pipeline that *is* testable
   from the command line — image to palette is a pure function, needing no tap,
   no permission and nothing playing. Run `./scripts/palette_selftest.sh` after
   touching `AlbumPalette.swift`; pass it image paths to check real covers.
   It sweeps a full drift cycle and flags any hue that lands further from every
   cover color than the drift allows; a two-color cover that paints red ->
   orange -> yellow -> green -> cyan -> blue is the rainbow regression described
   in the album-color guardrail above. `--png <dir>` also renders mocks of the
   bar field at several times, which is much faster to judge than reading hue
   names — and chunking (the other failure mode) is *only* visible that way.
8. If bars ever look frequency-mislabeled again (energy showing up in the
   wrong part of the spectrum), synthesize known test tones (a handful of
   fixed frequencies with a few seconds' dwell each, silence gaps between
   them so segments are unambiguous in a log) and log each frame's peak
   bin/frequency while playing them. Compare logged vs. expected frequency
   directly; a clean, consistent ratio points at a real pipeline bug, not a
   content or calibration issue.
