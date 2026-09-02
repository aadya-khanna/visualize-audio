# visualize-audio

A live audio visualizer that reacts to real sound (via loopback capture + Essentia.js feature
extraction). Optionally shows what's currently playing on Spotify alongside it. Runs as a web
app or a desktop app via Electron.

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

## Getting started — desktop app (Electron)

```
npm run electron
```

This builds the app and opens it in a native window. No separate packaging step yet — this
runs from source via `npx electron .`. Same optional Spotify `.env` setup as above (the desktop
app reuses the exact same redirect URI) if you want the track overlay.

## Spotify user limitation

The app is registered in Spotify's **Development Mode**, capped at 25 users total, added
manually by email in the Spotify dashboard. Going beyond that requires Spotify's Extended Quota
Mode review process — not set up here. This only limits the optional track-overlay feature; the
visualizer itself has no such cap.

## Known issues

- **Electron + virtual audio device causes a ~15s glitch on connect.** The first time the app
  opens a stream to a loopback device (Background Music/BlackHole) inside the Electron build,
  CoreAudio renegotiates that device's format, briefly glitching anything already playing
  through it. It self-resolves after ~15 seconds. Not present in the web app (regular Chrome
  handles this negotiation more gracefully than Electron's bundled Chromium). Workaround: start
  the visualizer *before* starting playback, so the glitch happens on silence.
- Bluetooth output devices can add their own latency/dropout issues when combined with a
  loopback device — wired output is more reliable if you hit stutter unrelated to the above.
