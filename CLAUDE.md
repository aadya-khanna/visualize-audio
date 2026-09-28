See README.md for setup, running, and distribution notes.

## macOS-native audio visualizer

This repo is a **macOS-only** Swift/SwiftUI app under `macos/`. It captures system-wide audio
via a Core Audio process tap (no loopback device needed) and gets now-playing info automatically
via the private `MediaRemote` framework (no OAuth/login).

The audio → visual pipeline — log-scaled frequency bucketing, energy/spectral-centroid/loudness
mood tracking, corner-color palette, bar easing — lives entirely in Swift under
`macos/Sources/VisualizeAudio/`.

Read `AGENTS.md` before making changes. For the decision to drop the web app, see
`docs/adr/001-macos-only-architecture.md`.
