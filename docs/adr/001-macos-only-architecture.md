# ADR 001: macOS-only architecture

**Status:** Accepted  
**Date:** 2026-09-27

## Context

The project originally shipped the same audio visualizer twice:

- A **web app** (React/Vite, Web Audio + Essentia.js, mic/loopback capture, Spotify OAuth).
- A **macOS app** (Swift/SwiftUI, Core Audio process tap, native FFT/feature extraction, MediaRemote for now-playing).

Both targets reimplemented the same algorithms independently — log-scaled frequency bucketing, mood tracking, corner-color mapping, bar easing — with no shared code. Keeping them in sync was manual and error-prone (e.g. the mono/stereo tap bug on macOS, loopback CoreAudio glitches on web).

The macOS app is the superior experience for this use case:

- **System audio capture** via a Core Audio process tap — no virtual loopback device (BlackHole, Background Music), no mic-permission workaround, no CoreAudio renegotiation glitch.
- **Now-playing info** from any app (Spotify, Music, Safari) via the private `MediaRemote` framework — no OAuth, no Spotify Development Mode 25-user cap, no client ID setup.
- **Native performance** — vDSP FFT, SwiftUI rendering, no browser sandbox or WASM load time.

The web app added maintenance surface (npm toolchain, Essentia.js WASM, PKCE auth, device-picker edge cases) without a compelling advantage once the native app existed.

## Decision

**Drop the web app entirely.** This repository is a macOS-only native application under `macos/`.

Removed:

- `src/` (React components, audio engine, Spotify client, renderers)
- Root npm toolchain (`package.json`, Vite config, `node_modules`)
- Web-specific docs (Spotify OAuth setup, loopback device instructions, Development Mode limits)

Retained:

- `macos/` — Swift Package, the sole implementation
- Algorithm documentation in `how-it-works.md` (describing the native pipeline)
- Research notes in `sources.md`

## Consequences

### Positive

- Single codebase, single build path, single set of guardrails — no algorithmic drift between targets.
- Simpler onboarding: open `macos/Package.swift` in Xcode, or run `macos/scripts/build-app.sh`.
- Better default UX: system audio and now-playing work out of the box on macOS 14.4+.
- Smaller repo: no JavaScript dependencies, no `.env` / Spotify dashboard setup.

### Negative / tradeoffs

- **Platform lock-in:** The app runs only on macOS 14.4+ with Xcode 15.3+. No browser or cross-platform access.
- **No App Store distribution:** The process tap and `MediaRemote` are private APIs. Users must build or sideload a signed copy; quarantine removal may be needed (`xattr -dr com.apple.quarantine`).
- **Lost web-specific workflows:** Users who relied on a browser tab or a loopback device on non-macOS systems no longer have a path here.

### Follow-up

- Update all documentation and agent instructions to reflect the single target.
- Remove stale comments in Swift sources that reference deleted `src/` files.
- Future visual modes and effects are implemented once, in Swift, under `macos/Sources/VisualizeAudio/`.
