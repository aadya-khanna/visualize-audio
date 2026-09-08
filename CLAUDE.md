See README.md for setup, running, and known issues.

## Two implementations, one visualizer

This repo ships the same audio visualizer twice, as independent targets that share no code:

- **Web app** (`src/`, root `package.json`) — React/Vite, Web Audio + Essentia.js for feature
  extraction, mic/loopback-device capture, Spotify via OAuth/PKCE. Runs in any browser.
- **macOS app** (`macos/`) — native Swift/SwiftUI, built from scratch (not an Electron/WebView
  wrapper). Captures system-wide audio via a Core Audio process tap (no loopback device needed)
  and gets Spotify now-playing info automatically via the private `MediaRemote` framework (no
  OAuth/login). Fully replaced the old `electron/` shell.

Each reimplements the same algorithms — log-scaled frequency bucketing, the energy/spectral-
centroid/loudness mood tracking, the corner-color palette and bar easing — independently in its
own language. Keep the two in sync at the *algorithm* level when either one's math changes;
don't try to share code between them, and don't assume a fix in one automatically applies to
the other.

Each directory has its own AGENTS.md — read the one for whatever you're touching before making
changes.
