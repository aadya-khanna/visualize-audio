import { useEffect, useRef, useState } from 'react'
import { getAccessToken, login, getCurrentlyPlaying } from './spotify'
import { AudioEngine, listInputDevices } from './audioEngine'
import Visualizer from './Visualizer'
import './App.css'

export default function App() {
  const [accessToken, setAccessToken] = useState(null)
  const [trackMeta, setTrackMeta] = useState(null)
  const [devices, setDevices] = useState([])
  const [selectedDevice, setSelectedDevice] = useState('')
  const [engineReady, setEngineReady] = useState(false)
  const [error, setError] = useState(null)

  const engineRef = useRef(null)

  useEffect(() => {
    getAccessToken().then(setAccessToken).catch((e) => setError(e.message))
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
        if (!cancelled) setError(e.message)
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
      setError(e.message)
    }
  }

  async function startVisualizer() {
    try {
      const engine = new AudioEngine()
      await engine.init(selectedDevice)
      engineRef.current = engine
      setEngineReady(true)
    } catch (e) {
      setError(e.message)
    }
  }

  return (
    <div className="app">
      {!accessToken && (
        <div className="panel">
          <h1>mood visualizer</h1>
          <p>Connect Spotify to show what's playing alongside the visualizer.</p>
          <button onClick={login}>Connect Spotify</button>
        </div>
      )}

      {accessToken && !engineReady && (
        <div className="panel">
          <h1>pick your audio source</h1>
          <p>
            Select the virtual loopback device routing your speaker output (e.g. BlackHole,
            Background Music) — that's what the visualizer actually analyzes.
          </p>
          <button onClick={loadDevices}>List input devices</button>
          {devices.length > 0 && (
            <select value={selectedDevice} onChange={(e) => setSelectedDevice(e.target.value)}>
              {devices.map((d) => (
                <option key={d.deviceId} value={d.deviceId}>
                  {d.label || d.deviceId}
                </option>
              ))}
            </select>
          )}
          <button disabled={!selectedDevice} onClick={startVisualizer}>
            Start visualizer
          </button>
        </div>
      )}

      {error && <div className="error">{error}</div>}

      {engineReady && <Visualizer engineRef={engineRef} trackMeta={trackMeta} />}
    </div>
  )
}
