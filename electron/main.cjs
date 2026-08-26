const { app, BrowserWindow } = require('electron')
const http = require('http')
const fs = require('fs')
const path = require('path')

// Electron's bundled Chromium has been observed failing to negotiate audio
// input with virtual/aggregate CoreAudio devices (Background Music, BlackHole)
// via its out-of-process audio service on macOS — surfaces as
// kAudioUnitErr_CannotDoInCurrentContext and garbled/glitching playback.
// Forcing the audio service in-process avoids that negotiation path.
app.commandLine.appendSwitch('disable-features', 'AudioServiceOutOfProcess')

// Must match the Spotify redirect URI exactly — that's already registered as
// http://127.0.0.1:5173/, so the local static server has to serve on that
// same host/port for the OAuth redirect to land somewhere real.
const HOST = '127.0.0.1'
const PORT = 5173
const DIST_DIR = path.join(__dirname, '..', 'dist')

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
}

function startServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      let filePath = path.join(DIST_DIR, decodeURIComponent(req.url.split('?')[0]))
      if (filePath.endsWith('/') || !path.extname(filePath)) {
        filePath = path.join(DIST_DIR, 'index.html') // SPA fallback for client-side routes
      }

      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404)
          res.end('Not found')
          return
        }
        res.writeHead(200, { 'Content-Type': MIME_TYPES[path.extname(filePath)] || 'application/octet-stream' })
        res.end(data)
      })
    })

    server.listen(PORT, HOST, () => resolve(server))
    server.on('error', reject)
  })
}

async function createWindow() {
  if (!fs.existsSync(DIST_DIR)) {
    console.error(`No build found at ${DIST_DIR} — run "npm run build" first.`)
    app.quit()
    return
  }

  try {
    await startServer()
  } catch (err) {
    if (err.code === 'EADDRINUSE') {
      // Another instance (or a leftover from a previous run) is already
      // serving on this port — just point the window at it instead of
      // crashing. If nothing is actually serving a valid app there, the
      // window will show a load error instead of the app silently quitting.
      console.warn(`Port ${PORT} already in use — reusing whatever is already serving there.`)
    } else {
      console.error('Failed to start local server:', err)
      app.quit()
      return
    }
  }

  const win = new BrowserWindow({
    width: 1000,
    height: 700,
    backgroundColor: '#08080f',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  win.loadURL(`http://${HOST}:${PORT}/`)
}

app.whenReady().then(createWindow)

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})
