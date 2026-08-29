import { useEffect, useRef, useState } from 'react'
import { frequencyColor, targetColor } from './mood.js'
import { drawBarsNormal, drawBars8Bit, drawCurveArea } from './renderers.js'

const DISPLAY_MODES = [
  { key: 'normal', label: 'Normal' },
  { key: '8bit', label: '8-Bit' },
  { key: 'curve', label: 'Curve' },
]

const COLOR_MODES = [
  { key: 'freq', label: 'Frequency' },
  { key: 'intensity', label: 'Intensity' },
]

function clamp255(v) {
  return Math.max(0, Math.min(255, v))
}

const BAR_COUNT = 96

function sampleBinLinear(freqData, idx) {
  const i0 = Math.floor(idx)
  const i1 = Math.min(i0 + 1, freqData.length - 1)
  const frac = idx - i0
  return freqData[i0] * (1 - frac) + freqData[i1] * frac
}

// Frequency bins from getByteFrequencyData are linearly spaced, but music
// energy (and hearing) is roughly logarithmic — bass would otherwise eat
// most of the bars while treble gets crushed into the last couple. Map each
// bar to an exponentially-growing band instead of a fixed step.
function logBarValue(freqData, barIndex) {
  // Skip bin 0-2 (~0-45Hz on a typical 44.1kHz/2048-FFT setup) — that range is
  // mostly mic self-noise/rumble rather than real bass, and log-scaling gives
  // it disproportionate bar real estate, making the low end look erratic.
  const minIndex = 3
  const maxIndex = freqData.length - 1
  const logMin = Math.log2(minIndex)
  const logMax = Math.log2(maxIndex)
  const t0 = barIndex / BAR_COUNT
  const t1 = (barIndex + 1) / BAR_COUNT
  const idx0 = 2 ** (logMin + t0 * (logMax - logMin))
  const idx1 = 2 ** (logMin + t1 * (logMax - logMin))

  // Low end: the band is narrower than one bin, so several consecutive bars
  // would round to the identical integer bin and read as one clumped block.
  // Interpolate a continuous fractional value instead — every bar gets a
  // distinct, smoothly varying reading even where the raw FFT has no
  // resolution to back it up.
  if (idx1 - idx0 < 1) {
    return sampleBinLinear(freqData, (idx0 + idx1) / 2) / 255
  }

  // Wide bands (treble): still average the real bins they cover.
  let sum = 0
  let count = 0
  for (let j = Math.floor(idx0); j < Math.ceil(idx1) && j < freqData.length; j++) {
    sum += freqData[j]
    count++
  }
  return count ? sum / count / 255 : 0
}

// Bars driven by live FFT data (log-spaced buckets). Color target depends on
// colorMode: "freq" fixes each bar's target by its position in the spectrum
// (bass -> red, treble -> violet); "intensity" shares one mood-derived target
// (energy/centroid) across all bars. Either way bars ease toward their target
// at their own fixed, gentle pace so color settles in smoothly, never snaps.
export default function Visualizer({ engineRef, trackMeta }) {
  const canvasRef = useRef(null)
  const rafRef = useRef(null)
  const featuresRef = useRef({ energy: 0, spectralCentroid: 0, loudness: -60, mood: null })
  const smoothedBarsRef = useRef(new Float32Array(BAR_COUNT))
  const barColorStateRef = useRef(
    Array.from({ length: BAR_COUNT }, () => ({
      r: 90,
      g: 90,
      b: 120,
      rate: 0.006 + Math.random() * 0.014, // each bar's own easing speed — a few seconds to fully catch up
      jitter: (Math.random() - 0.5) * 18, // small fixed personal tint, set once — not time-varying
    })),
  )
  const displayModeRef = useRef('normal')
  const [displayMode, setDisplayMode] = useState('normal')
  const colorModeRef = useRef('freq')
  const [colorMode, setColorMode] = useState('freq')
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [gearRotation, setGearRotation] = useState(0)

  useEffect(() => {
    displayModeRef.current = displayMode
  }, [displayMode])

  useEffect(() => {
    colorModeRef.current = colorMode
  }, [colorMode])

  function toggleSettings() {
    setSettingsOpen((open) => !open)
    setGearRotation((r) => r + 90)
  }

  useEffect(() => {
    const featureInterval = setInterval(() => {
      const engine = engineRef.current
      if (!engine) return
      featuresRef.current = engine.extractFeatures()
    }, 150)
    return () => clearInterval(featureInterval)
  }, [engineRef])

  useEffect(() => {
    const canvas = canvasRef.current
    const ctx = canvas.getContext('2d')

    function resize() {
      canvas.width = canvas.clientWidth * devicePixelRatio
      canvas.height = canvas.clientHeight * devicePixelRatio
    }
    resize()
    window.addEventListener('resize', resize)

    function draw() {
      rafRef.current = requestAnimationFrame(draw)
      const engine = engineRef.current
      if (!engine) return

      const { freqData } = engine.getVisualData()
      const { mood } = featuresRef.current

      const w = canvas.width
      const h = canvas.height

      // fade trail instead of hard clear — reads as "mood" smoothing
      ctx.fillStyle = 'rgba(8, 8, 16, 0.25)'
      ctx.fillRect(0, 0, w, h)

      const barWidth = w / BAR_COUNT
      const smoothed = smoothedBarsRef.current
      const colorStates = barColorStateRef.current
      const colorMode = colorModeRef.current
      const intensityTarget = mood ? targetColor(mood.energyNorm, mood.centroidNorm) : [90, 90, 120]

      const bars = new Array(BAR_COUNT)
      for (let i = 0; i < BAR_COUNT; i++) {
        const raw = logBarValue(freqData, i)
        // rise fast on transients, decay slower — kills the blocky/erratic look
        // from noisy low bins without dulling the visualizer's punch
        const rate = raw > smoothed[i] ? 0.5 : 0.15
        smoothed[i] += (raw - smoothed[i]) * rate
        const v = smoothed[i]
        const barHeight = v * h * 0.9

        const [tr, tg, tb] = colorMode === 'intensity' ? intensityTarget : frequencyColor(i / BAR_COUNT)
        const state = colorStates[i]
        state.r += (tr + state.jitter - state.r) * state.rate
        state.g += (tg + state.jitter * 0.6 - state.g) * state.rate
        state.b += (tb - state.jitter * 0.4 - state.b) * state.rate

        const brightness = 0.7 + v * 0.4 // louder bins pop brighter
        bars[i] = {
          x: i * barWidth,
          height: barHeight,
          r: clamp255(state.r * brightness),
          g: clamp255(state.g * brightness),
          b: clamp255(state.b * brightness),
        }
      }

      const mode = displayModeRef.current
      if (mode === '8bit') {
        drawBars8Bit(ctx, h, bars, barWidth)
      } else if (mode === 'curve') {
        drawCurveArea(ctx, w, h, bars)
      } else {
        drawBarsNormal(ctx, h, bars, barWidth)
      }
    }
    draw()

    return () => {
      cancelAnimationFrame(rafRef.current)
      window.removeEventListener('resize', resize)
    }
  }, [engineRef])

  return (
    <div className="visualizer-wrap">
      <canvas ref={canvasRef} className="visualizer-canvas" />
      {trackMeta && (
        <div className="track-meta">
          {trackMeta.albumArt && <img src={trackMeta.albumArt} alt="" />}
          <div>
            <div className="track-name">{trackMeta.name}</div>
            <div className="track-artist">{trackMeta.artists}</div>
          </div>
        </div>
      )}

      <button
        className="gear-button"
        style={{ transform: `rotate(${gearRotation}deg)` }}
        onClick={toggleSettings}
        aria-label="Display settings"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
        </svg>
      </button>

      {settingsOpen && (
        <div className="settings-panel">
          <div className="settings-title">Display</div>
          {DISPLAY_MODES.map((mode) => (
            <button
              key={mode.key}
              className={displayMode === mode.key ? 'active' : ''}
              onClick={() => setDisplayMode(mode.key)}
            >
              {mode.label}
            </button>
          ))}
          <div className="settings-title">Color</div>
          {COLOR_MODES.map((mode) => (
            <button
              key={mode.key}
              className={colorMode === mode.key ? 'active' : ''}
              onClick={() => setColorMode(mode.key)}
            >
              {mode.label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
