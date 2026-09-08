## Scope

React/Vite web app: Spotify PKCE auth (`spotify.js`), audio capture + feature extraction via
Web Audio and Essentia.js (`audioEngine.js`), color/mood logic (`mood.js`), canvas rendering
(`Visualizer.jsx`, `renderers.js`), and app shell/device picker (`App.jsx`).

## Guardrails

- Token storage is `localStorage` by design (persists login across restarts, e.g. when this
  runs inside a wrapped/reopened window) — don't revert to `sessionStorage`.
- This is the browser build only. The macOS app (`macos/`) is a separate, natively reimplemented
  target — Spotify auth and audio capture here have no equivalent code path there; keep the two
  in sync only at the algorithm level (see `macos/AGENTS.md`).
- No Spotify client secret anywhere — auth is Authorization Code + PKCE, client-side only.
- Keep `renderers.js` functions pure: `(ctx, dims, bars, ...) -> draws`. Display modes must stay
  swappable without touching the audio/color pipeline upstream.
- Don't assume a loopback device is present — always support the plain-microphone fallback path.

## Validation

`npm run build` must pass cleanly. There's no test suite — audio capture and visual rendering
need to be manually verified in a browser after any change here.
