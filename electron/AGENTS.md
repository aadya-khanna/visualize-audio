## Scope

Electron main process (`main.cjs`): serves the built `dist/` over a local static HTTP server
and opens a `BrowserWindow` pointed at it.

## Guardrails

- The server must bind `127.0.0.1:5173` — this has to exactly match the Spotify redirect URI
  registered in the developer dashboard. Changing host/port breaks OAuth and needs a README
  update too.
- `main.cjs` must stay CommonJS (`.cjs` extension) — the package is `"type": "module"`.
- Don't add navigation/reload paths that bypass the renderer's `beforeunload`/`pagehide`
  cleanup — skipping it can leave a virtual audio device (Background Music/BlackHole) in a
  corrupted state (see README known issues).

## Validation

`npm run build && npx electron .` should open a window and serve the app with no console
errors. If relaunching quickly after a previous run, check for `EADDRINUSE` on port 5173 first.
