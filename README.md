# visualize-audio

A live audio visualizer that reacts to real sound (via loopback capture + Essentia.js feature
extraction) and shows what's currently playing on Spotify alongside it. Runs as a web app or
a desktop app via Electron.

## Getting started — web app

1. In your [Spotify developer dashboard](https://developer.spotify.com/dashboard), add redirect
   URI `http://127.0.0.1:5173/`, then copy the Client ID.
2. `cp .env.example .env` and set `VITE_SPOTIFY_CLIENT_ID`.
3. Install a virtual loopback device so the app can capture your system audio — recommended:
   [Background Music](https://github.com/kyleneideck/BackgroundMusic)
   (`brew install --cask background-music`). BlackHole works too. Or skip this and just use
   your microphone — lower quality, zero setup.
4. `npm install && npm run dev`, open `http://127.0.0.1:5173`.

## Getting started — desktop app (Electron)

Same Spotify/`.env` setup as above (the desktop app reuses the exact same redirect URI). Then:

```
npm run electron
```

This builds the app and opens it in a native window. No separate packaging step yet — this
runs from source via `npx electron .`.

## Spotify user limitation

The app is registered in Spotify's **Development Mode**, capped at 25 users total, added
manually by email in the Spotify dashboard. Going beyond that requires Spotify's Extended Quota
Mode review process — not set up here.

## Known issues

- **Electron + virtual audio device causes a ~15s glitch on connect.** The first time the app
  opens a stream to a loopback device (Background Music/BlackHole) inside the Electron build,
  CoreAudio renegotiates that device's format, briefly glitching anything already playing
  through it. It self-resolves after ~15 seconds. Not present in the web app (regular Chrome
  handles this negotiation more gracefully than Electron's bundled Chromium). Workaround: start
  the visualizer *before* starting playback, so the glitch happens on silence.
- Bluetooth output devices can add their own latency/dropout issues when combined with a
  loopback device — wired output is more reliable if you hit stutter unrelated to the above.
