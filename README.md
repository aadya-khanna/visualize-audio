# visualize-audio

A live audio visualizer that reacts to real sound. Optionally shows what's currently playing on
Spotify alongside it. Two independent ways to run it:

- **Web app** — React/Canvas, loopback/mic capture + Essentia.js feature extraction, Spotify via
  OAuth. Works in any browser.
- **macOS app** — native Swift/SwiftUI (`macos/`), a from-scratch reimplementation (not an
  Electron/WebView wrapper) that taps system audio directly via a Core Audio process tap (no
  loopback device needed) and gets Spotify now-playing info automatically via the private
  `MediaRemote` framework (no login step). Replaces the old Electron build entirely.

Spotify is entirely optional — the "Start visualizer" button on the landing screen works with
your default microphone out of the box, with no Spotify setup required. Connect Spotify (from
the landing screen or from within the running visualizer's settings panel) only if you want the
track name/art overlay.

## Getting started — web app

1. `npm install && npm run dev`, open `http://127.0.0.1:5173`.
2. (Optional, for a cleaner signal) Install a virtual loopback device so the app can capture your
   system audio instead of ambient mic sound — recommended:
   [Background Music](https://github.com/kyleneideck/BackgroundMusic)
   (`brew install --cask background-music`). BlackHole works too. Pick it via "Pick a specific
   audio source" on the landing screen.
3. (Optional, for track name/art) In your
   [Spotify developer dashboard](https://developer.spotify.com/dashboard), add redirect URI
   `http://127.0.0.1:5173/`, copy the Client ID, `cp .env.example .env` and set
   `VITE_SPOTIFY_CLIENT_ID`. Then use "Connect Spotify" in the app.

## Getting started — macOS app (native Swift)

```
open macos/Package.swift   # opens as a project in Xcode
```

Requires Xcode 15.3+ (macOS 14.4 SDK) and macOS 14.4+ to build and run — the process tap and
`MediaRemote` APIs it depends on don't exist on older systems, and there is no command-line-only
build path for this target. No Spotify setup needed: now-playing info comes from the system
automatically (works with Spotify, Music, or anything else playing), and system audio is
captured directly with no virtual loopback device required. See `macos/AGENTS.md` for
architecture notes and validation steps.

Because it uses private macOS APIs (the process tap and `MediaRemote`), this can't ship on the
App Store — same tradeoff as similar "now playing" utilities. A self-built or ad-hoc-signed
copy may need the quarantine flag cleared before macOS will open it:
```
xattr -dr com.apple.quarantine /path/to/VisualizeAudio.app
```

## Spotify user limitation (web app only)

The web app's Spotify integration is registered in Spotify's **Development Mode**, capped at 25
users total, added manually by email in the Spotify dashboard. Going beyond that requires
Spotify's Extended Quota Mode review process — not set up here. This only limits the optional
track-overlay feature; the visualizer itself has no such cap. The macOS app has no such
limitation, since it doesn't use Spotify's OAuth API at all.

## Known issues

- **Web app + virtual loopback device can cause a CoreAudio renegotiation glitch on connect**
  in some browsers/setups. Workaround: start the visualizer *before* starting playback, so any
  glitch happens on silence. Not applicable to the macOS app — it doesn't use a loopback device.
- Bluetooth output devices can add their own latency/dropout issues when combined with a
  loopback device (web app only) — wired output is more reliable if you hit stutter unrelated
  to the above.
