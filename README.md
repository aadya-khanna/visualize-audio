# mood-visualizer

Live audio visualizer, colored by feature extraction (Essentia.js), labeled with
whatever's currently playing on Spotify.

Two independent feeds, stitched together:
- **Spotify Web API** — polled for track/artist/album metadata (not audio; Spotify's stream is DRM-locked).
- **Loopback audio capture → Essentia.js** — an `AnalyserNode` drives the raw FFT bars every frame;
  Essentia (WASM) samples energy/spectral-centroid/loudness every ~150ms to drive color/mood.

## 1. Spotify app setup

You already have a Spotify developer app — reuse it:

1. Go to https://developer.spotify.com/dashboard → your app → **Settings**.
2. Under **Redirect URIs**, add: `http://127.0.0.1:5173/` (Vite's default dev URL — use
   `127.0.0.1`, not `localhost`, Spotify rejects the latter).
3. Copy the **Client ID**.
4. `cp .env.example .env` and set `VITE_SPOTIFY_CLIENT_ID`.

No client secret needed — this uses Authorization Code + PKCE, entirely client-side.

## 2. Loopback audio device (required — see below for why)

Spotify's stream is DRM-protected, so the visualizer can't read it directly. Install a
virtual loopback device that routes your speaker output back in as a "microphone":

- **macOS**: [BlackHole](https://existential.audio/blackhole/) (2ch is enough) — then in
  System Settings → Sound → Output, either switch output to BlackHole (you'll lose normal
  speaker output, use a Multi-Output Device in Audio MIDI Setup to send audio to both
  BlackHole and your speakers), or use "Aggregate/Multi-Output Device" for both.
- **Windows**: [VB-Cable](https://vb-audio.com/Cable/).

The app lists all audio *input* devices — pick the loopback one there.

## 3. Run it

```
npm install
npm run dev
```

Open http://127.0.0.1:5173, connect Spotify, pick your loopback device, hit play on Spotify.

## Notes

- `getUserMedia`/`AudioContext` require a secure context — `localhost`/`127.0.0.1` counts,
  but this won't work over plain `http://<lan-ip>`.
- Tokens live in `sessionStorage` (cleared on tab close) — re-login each session.
