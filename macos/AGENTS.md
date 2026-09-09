## Scope

Native Swift/SwiftUI macOS app (`Sources/VisualizeAudio/`) that fully
replaces the old `electron/` shell. It reimplements the web app's audio
pipeline and Spotify integration natively rather than embedding the web
build — see the file-by-file "what gets ported" table in the plan this was
built from. The web app (`src/`, `index.html`, top-level `package.json`
scripts) is a separate, untouched target; keep the two in sync only at the
*algorithm* level (color mapping, bar bucketing, easing), not by sharing code.

- `Audio/` — `ProcessTap.swift` (Core Audio system-wide tap, macOS 14.4+,
  no loopback device), `MicInputSource.swift` (AVAudioEngine mic/device
  picker, the alternate source), `FFT.swift` (vDSP real FFT, reproduces
  AnalyserNode's byte-range/smoothing convention), `FeatureExtractor.swift`
  (energy/spectral-centroid/loudness — native reimplementation of
  essentia.js's algorithms, not a WASM port), `MoodTracker.swift`,
  `AudioEngine.swift` (coordinator).
- `Media/` — `MediaRemoteBridge.swift` (private `MediaRemote` framework via
  dlopen/dlsym), `NowPlaying.swift`.
- `Visualizer/` — `ColorMapping.swift`, `BarLayout.swift`, `Renderers.swift`,
  `VisualizerView.swift` — direct ports of `src/mood.js`, `src/Visualizer.jsx`,
  `src/renderers.js`. Keep these three in sync with their JS counterparts if
  either one's algorithm changes; don't let the two visual pipelines drift
  into different behavior.
- `Settings/SettingsView.swift` — port of `Visualizer.jsx`'s gear-button
  panel. The music section is a passive status row, not a connect button —
  there is no login step with MediaRemote.

## Guardrails

- **Verified working** against Xcode 26.6 (macOS 26.5 SDK): the process tap,
  aggregate device, IOProc, and `MediaRemote` bridge all build and run —
  system audio capture and now-playing info both confirmed live. Two real
  issues turned up in that process, both fixed and worth knowing about:
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
     Diagnosed by playing known tones (1-23kHz, 2s dwell each — synthesized
     with `numpy`/`wave`, no repo script for this one, just reproduce
     inline) through the app while logging each frame's peak bin/frequency:
     every tone from 1-19kHz measured at ~50% of its true frequency (5kHz
     read as 2.5kHz, 20kHz as 10kHz, etc — a clean, consistent 2x error, not
     noise). Fixed by switching to `CATapDescription(monoGlobalTapButExcludeProcesses:)`,
     which has CoreAudio itself mix down to mono before delivery — re-ran
     the same tone test afterward and every frequency 1-19kHz now measures
     correctly. This was very likely the dominant cause of any "some
     frequencies just don't show up" symptom, since real content was being
     relabeled at the wrong bin rather than simply missing.
  Also confirmed while chasing that bug: **content above ~20kHz doesn't
  make it through** (20kHz reads at ~1/20th the magnitude of everything
  else; 22-23kHz drop into the noise floor) — that's consistent across
  both tap variants and is a genuine hardware/system rolloff (ultrasonic,
  inaudible anyway), not a code bug — don't try to "fix" it.
  `MediaRemoteBridge.swift`'s dlsym symbol names and dictionary keys are the
  same ones widely relied on by existing open-source "now playing"
  utilities, but are unofficial and could shift on a future OS release.
- **Private APIs mean no App Store distribution** — same tradeoff Isle
  documents in its own README. Distribute as a signed-but-not-notarized (or
  self-signed) build; users may need the `xattr -dr com.apple.quarantine`
  workaround Isle's README describes.
- **Don't enable App Sandbox** on this target — the process tap and
  MediaRemote don't work under the sandbox restrictions required for
  App Store apps. If sandboxing is added later for some other reason, that's
  a real feature loss to flag, not a checkbox to just turn on.
- **This is a Swift Package (`Package.swift`), not a hand-built `.xcodeproj`.**
  Open `macos/Package.swift` directly in Xcode ("File > Open…") — Xcode
  treats it as a project, and its own Run/Debug handles bundling and signing
  for you. From the command line, always use `scripts/build-app.sh` (not a
  bare `swift build`) — see guardrail 1 above for why.
- Keep the algorithms in `Visualizer/` and `Audio/FeatureExtractor.swift`
  numerically in sync with `src/mood.js`, `src/Visualizer.jsx`, and
  `src/audioEngine.js` — the whole point of "two-way" is that both targets
  look and feel like the same visualizer, not two different apps that
  happen to share a name.

## Validation

No CI here — this needs Xcode (15.3+, macOS 14.4 SDK) to build and a real
macOS 14.4+ Mac to run, since neither the process tap nor MediaRemote can be
exercised from the command line alone:

1. `./scripts/build-app.sh && open .build/VisualizeAudio.app` (or Xcode's
   Run). First launch prompts for the system-audio-recording permission —
   approve it.
2. Compare each display mode (Normal/8-Bit/Curve) and color mode
   (Frequency/Intensity) against the web app side by side.
3. Play audio from an arbitrary app (not just Spotify) with **no** loopback
   device installed — bars should react with real dynamic range (quiet
   passages low, transients tall, not everything pinned near max). This is
   the actual fix for the old Electron glitch.
4. Switch to the microphone source in Settings and confirm that path still
   works.
5. Play/pause/change tracks in Spotify (or Music, or Safari) while the app
   is running — the track overlay should update with no connect/login step.
6. If `fftSize` or the window function in `FFT.swift` ever changes, re-run
   `swift scripts/fft_selftest.swift` and update `fullScaleReferenceMagnitude`
   from its output.
7. If bars ever look frequency-mislabeled again (energy showing up in the
   wrong part of the spectrum), don't guess from a real song — synthesize
   known test tones (a handful of fixed frequencies with a few seconds'
   dwell each, silence gaps between them so segments are unambiguous in a
   log) and log each frame's peak bin/frequency while playing them. Compare
   logged vs. expected frequency directly; a clean, consistent ratio (like
   the 2x from guardrail 3 above) points at a real pipeline bug, not a
   content or calibration issue.
