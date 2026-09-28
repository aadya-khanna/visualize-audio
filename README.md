# visualize-audio

A native macOS live audio visualizer that reacts to real system sound. Optionally shows what's
currently playing (track name, art) from Spotify, Music, or any app that publishes now-playing
info.

Built with Swift/SwiftUI. Captures system-wide audio via a Core Audio process tap (no virtual
loopback device needed) and reads now-playing metadata automatically via the private
`MediaRemote` framework (no login step).

## Getting started

```
open macos/Package.swift   # opens as a project in Xcode
```

Or from the command line:

```
cd macos && ./scripts/build-app.sh && open .build/VisualizeAudio.app
```

**Requirements:** Xcode 15.3+ (macOS 14.4 SDK) and macOS 14.4+ to build and run. The process
tap and `MediaRemote` APIs it depends on don't exist on older systems.

**First launch:** macOS prompts for the system-audio-recording permission (needed for the
process tap). Approve it once — the stable bundle identifier (`com.aadya.visualizeaudio`) lets
TCC remember the grant across rebuilds. Always run the `.app` bundle (via Xcode Run or
`build-app.sh`), not a bare `swift build` executable — see `AGENTS.md` for why.

**Distribution:** Because it uses private macOS APIs, this can't ship on the App Store. A
self-built or ad-hoc-signed copy may need the quarantine flag cleared before macOS will open
it:

```
xattr -dr com.apple.quarantine /path/to/VisualizeAudio.app
```

## Features

- System-wide audio capture (process tap) or microphone input (selectable in Settings)
- Three display modes: Normal bars, 8-Bit, Curve
- Two color modes: Frequency (spectrum-position hues) and Intensity (mood-driven)
- Automatic now-playing overlay — works with Spotify, Music, Safari, and other apps
- Mood-aware color mapping from energy, spectral centroid, and loudness

See `how-it-works.md` for the audio → visual pipeline and color logic.

## Architecture

This is a single native target under `macos/`. See `docs/adr/001-macos-only-architecture.md`
for why the earlier web app was removed.
