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

- **This was written without access to the macOS 14.4 SDK** (the sandbox
  building this only has Command Line Tools with SDK 14.2) — `ProcessTap.swift`
  in particular (the `CATapDescription`/`AudioHardwareCreateProcessTap`/
  aggregate-device sequence) has not been compiled or run. Treat it as a
  first draft to validate against real API docs in Xcode 15.3+, not
  verified-working code. `MediaRemoteBridge.swift`'s dlsym symbol names and
  dictionary keys are the same ones widely relied on by existing open-source
  "now playing" utilities, but are unofficial and could shift on a future OS
  release — if now-playing info silently stops working after an OS update,
  check those string constants first.
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
  treats it as a project. `Info.plist` at `macos/Info.plist` documents the
  required keys (`NSMicrophoneUsageDescription`,
  `NSAudioCaptureUsageDescription`, min system version 14.4); wire it into
  the target's build settings (`INFOPLIST_FILE`) or copy its keys into
  whatever Info.plist Xcode generates for the target — a bare `swift build`
  will compile the code but won't produce a real signed `.app` with TCC
  permissions working correctly.
- Keep the algorithms in `Visualizer/` and `Audio/FeatureExtractor.swift`
  numerically in sync with `src/mood.js`, `src/Visualizer.jsx`, and
  `src/audioEngine.js` — the whole point of "two-way" is that both targets
  look and feel like the same visualizer, not two different apps that
  happen to share a name.

## Validation

No CI here — this needs Xcode (15.3+, macOS 14.4 SDK) to build and a real
macOS 14.4+ Mac to run, since neither the process tap nor MediaRemote can be
exercised from the command line alone:

1. Open `macos/Package.swift` in Xcode, resolve/build, run.
2. Compare each display mode (Normal/8-Bit/Curve) and color mode
   (Frequency/Intensity) against the web app side by side.
3. Play audio from an arbitrary app (not just Spotify) with **no** loopback
   device installed — bars should react. This is the actual fix for the old
   Electron glitch.
4. Switch to the microphone source in Settings and confirm that path still
   works.
5. Play/pause/change tracks in Spotify (or Music, or Safari) while the app
   is running — the track overlay should update with no connect/login step.
