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
  `VisualizerView.swift`.
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
  Also confirmed while chasing that bug: **content above ~20kHz doesn't
  make it through** (20kHz reads at ~1/20th the magnitude of everything
  else; 22-23kHz drop into the noise floor) — that's consistent across
  both tap variants and is a genuine hardware/system rolloff (ultrasonic,
  inaudible anyway), not a code bug — don't try to "fix" it.
  `MediaRemoteBridge.swift`'s dlsym symbol names and dictionary keys are the
  same ones widely relied on by existing open-source "now playing"
  utilities, but are unofficial and could shift on a future OS release.
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
   (Frequency/Intensity).
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
7. If bars ever look frequency-mislabeled again (energy showing up in the
   wrong part of the spectrum), synthesize known test tones (a handful of
   fixed frequencies with a few seconds' dwell each, silence gaps between
   them so segments are unambiguous in a log) and log each frame's peak
   bin/frequency while playing them. Compare logged vs. expected frequency
   directly; a clean, consistent ratio points at a real pipeline bug, not a
   content or calibration issue.
