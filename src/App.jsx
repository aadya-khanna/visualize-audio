import { useEffect, useRef, useState } from 'react'
import { getAccessToken, login, logout, getCurrentlyPlaying } from './spotify'
import { AudioEngine, listInputDevices } from './audioEngine'
import Visualizer from './Visualizer'
import MusicConnect from './MusicConnect'
import './App.css'

export default function App() {
  const [view, setView] = useState('landing') // 'landing' | 'source' | 'running'
  const [accessToken, setAccessToken] = useState(null)
  const [trackMeta, setTrackMeta] = useState(null)
  const [devices, setDevices] = useState([])
  const [selectedDevice, setSelectedDevice] = useState('')

  const [starting, setStarting] = useState(false)
  const [devicesLoading, setDevicesLoading] = useState(false)
  const [spotifyConnecting, setSpotifyConnecting] = useState(false)
  const [startError, setStartError] = useState(null)
  const [sourceError, setSourceError] = useState(null)
  const [spotifyError, setSpotifyError] = useState(null)

  const engineRef = useRef(null)

  useEffect(() => {
    getAccessToken().then(setAccessToken).catch((e) => setSpotifyError(e.message))
  }, [])

  // A reload/close (Cmd+R, closing the window) tears down the page before
  // React's own unmount cleanup can run, leaving the mic track and
  // AudioContext open. With a virtual loopback driver (Background Music,
  // BlackHole) that can leave its CoreAudio plugin in a corrupted state —
  // release everything explicitly the moment the page starts to go away.
  useEffect(() => {
    function releaseAudio() {
      engineRef.current?.stop()
    }
    window.addEventListener('beforeunload', releaseAudio)
    window.addEventListener('pagehide', releaseAudio)
    return () => {
      window.removeEventListener('beforeunload', releaseAudio)
      window.removeEventListener('pagehide', releaseAudio)
    }
  }, [])

  useEffect(() => {
    if (!accessToken) return
    let cancelled = false
    async function poll() {
      try {
        const data = await getCurrentlyPlaying(accessToken)
        if (!cancelled) setTrackMeta(data)
      } catch (e) {
        if (!cancelled) setSpotifyError(e.message)
      }
    }
    poll()
    const id = setInterval(poll, 3000)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [accessToken])

  async function loadDevices() {
    setDevicesLoading(true)
    setSourceError(null)
    try {
      const inputs = await listInputDevices()
      setDevices(inputs)
      // Prefer a loopback device (Background Music, BlackHole) over whatever
      // happens to be first in the list — plugging in headphones can reorder
      // this list so a headphone mic lands first, silently capturing the
      // wrong source if we just default to inputs[0].
      const loopback = inputs.find(
        (d) => /background music/i.test(d.label) && !/ui sounds/i.test(d.label),
      ) ?? inputs.find((d) => /blackhole/i.test(d.label))
      const preferred = loopback ?? inputs[0]
      if (preferred) setSelectedDevice(preferred.deviceId)
    } catch (e) {
      setSourceError(e.message)
    } finally {
      setDevicesLoading(false)
    }
  }

  useEffect(() => {
    if (view === 'source') loadDevices()
  }, [view])

  // Zero-setup path from the landing screen — falls back to the default mic
  // (AudioEngine.init tolerates an undefined deviceId) so a first-time
  // visitor can reach the visualizer without picking anything.
  async function quickStart() {
    setStarting(true)
    setStartError(null)
    try {
      const engine = new AudioEngine()
      await engine.init(undefined)
      engineRef.current = engine
      setView('running')
    } catch (e) {
      setStartError(e.message)
    } finally {
      setStarting(false)
    }
  }

  async function startVisualizer() {
    setStarting(true)
    setStartError(null)
    try {
      const engine = new AudioEngine()
      await engine.init(selectedDevice)
      engineRef.current = engine
      setView('running')
    } catch (e) {
      setStartError(e.message)
    } finally {
      setStarting(false)
    }
  }

  async function handleSpotifyLogin() {
    setSpotifyConnecting(true)
    setSpotifyError(null)
    try {
      await login()
    } catch (e) {
      setSpotifyError(e.message)
      setSpotifyConnecting(false)
    }
  }

  function handleSpotifyLogout() {
    logout()
    setAccessToken(null)
    setTrackMeta(null)
  }

  return (
    <div className="app">
      {view === 'landing' && (
        <div className="panel panel-landing">
          <h1>audio visualizer</h1>
          <p className="tagline">
            Turns sound to color-reactive visuals!
          </p>

          <button className="cta-primary" onClick={quickStart} disabled={starting}>
            {starting ? 'Starting…' : 'Start visualizer'}
          </button>
          {startError && (
            <p className="field-error" role="alert">
              {startError}
            </p>
          )}

          <p className="mic-note">
            Uses your microphone by default (your browser will ask permission). Want it to react to system/app audio instead of
            ambient mic sound?{' '}
            <button className="link-button" onClick={() => setView('source')}>
              Pick a specific audio source
            </button>
          </p>

          <div className="secondary-actions">
            <p className="music-connect-label">Connect for live music</p>
            <MusicConnect
              connected={!!accessToken}
              connecting={spotifyConnecting}
              onConnect={handleSpotifyLogin}
              onDisconnect={handleSpotifyLogout}
            />
            {spotifyError && (
              <p className="field-error" role="alert">
                {spotifyError}
              </p>
            )}
          </div>
        </div>
      )}

      {view === 'source' && (
        <div className="panel">
          <button className="link-button back-link" aria-label="Back to landing" onClick={() => setView('landing')}>
            ← Back
          </button>
          <h1>pick your audio source</h1>
          <p>
            Select the virtual loopback device routing your speaker output (e.g. BlackHole,
            Background Music). A loopback device is required for spotify/apple music/system audio. 
          </p>

          {devicesLoading && <p className="status-note">Requesting microphone permission…</p>}
          {sourceError && (
            <p className="field-error" role="alert">
              {sourceError}
            </p>
          )}

          {!devicesLoading && devices.length > 0 && (
            <select
              aria-label="Audio input device"
              value={selectedDevice}
              onChange={(e) => setSelectedDevice(e.target.value)}
            >
              {devices.map((d) => (
                <option key={d.deviceId} value={d.deviceId}>
                  {d.label || d.deviceId}
                </option>
              ))}
            </select>
          )}
          <button disabled={!selectedDevice || starting} onClick={startVisualizer}>
            {starting ? 'Starting…' : 'Start visualizer'}
          </button>
          {startError && (
            <p className="field-error" role="alert">
              {startError}
            </p>
          )}
        </div>
      )}

      {view === 'running' && (
        <Visualizer
          engineRef={engineRef}
          trackMeta={trackMeta}
          accessToken={accessToken}
          onSpotifyLogin={handleSpotifyLogin}
          onSpotifyLogout={handleSpotifyLogout}
        />
      )}
    </div>
  )
}
