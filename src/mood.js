const HISTORY_SIZE = 40

// Tracks energy/spectral-centroid as continuous, normalized signals — no
// discrete mood buckets. Percentile rank within recent history, not min-max
// stretch: energy/centroid from mic/loopback input tend to be skewed (mostly
// quiet, occasional loud spikes), and min-max normalization puts the 0.5
// threshold above most real samples in that case. Rank-based split stays
// centered regardless of the distribution's shape.
export class MoodTracker {
  constructor() {
    this.energyHistory = []
    this.centroidHistory = []
  }

  _normalize(history, value) {
    history.push(value)
    if (history.length > HISTORY_SIZE) history.shift()
    if (history.length < 2) return 0.5
    const below = history.filter((v) => v <= value).length
    return below / history.length
  }

  update(energy, spectralCentroid) {
    const energyNorm = this._normalize(this.energyHistory, energy)
    const centroidNorm = this._normalize(this.centroidHistory, spectralCentroid)
    return { energyNorm, centroidNorm }
  }
}

// Curated corner colors on the energy x brightness plane (the palette
// aesthetic from the original mood buckets, kept — just blended continuously
// now instead of snapped between).
const CORNERS = {
  mellow: [80, 92, 168], // low energy, dark timbre — deep blue/purple
  calm: [70, 210, 210], // low energy, bright timbre — teal/blue
  aggressive: [215, 40, 145], // high energy, dark timbre — red/magenta
  energetic: [255, 155, 85], // high energy, bright timbre — warm orange
}

function lerp(a, b, t) {
  return a + (b - a) * t
}

function lerpColor(a, b, t) {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]
}

// Bilinear blend across the curated corners — continuous, so it never hard
// -snaps, but still drawn from the same palette that read well before.
export function targetColor(energyNorm, centroidNorm) {
  const lowEnergyRow = lerpColor(CORNERS.mellow, CORNERS.calm, centroidNorm)
  const highEnergyRow = lerpColor(CORNERS.aggressive, CORNERS.energetic, centroidNorm)
  return lerpColor(lowEnergyRow, highEnergyRow, energyNorm)
}

function hslToRgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = l - c / 2
  let r = 0
  let g = 0
  let b = 0
  if (h < 60) [r, g, b] = [c, x, 0]
  else if (h < 120) [r, g, b] = [x, c, 0]
  else if (h < 180) [r, g, b] = [0, c, x]
  else if (h < 240) [r, g, b] = [0, x, c]
  else if (h < 300) [r, g, b] = [x, 0, c]
  else [r, g, b] = [c, 0, x]
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255]
}

// Position-in-spectrum color: bass -> red, mids -> green, treble -> violet.
// t is a bar's fractional position (0-1) across the log-spaced frequency
// range, so color reads as "which part of the spectrum" rather than mood.
export function frequencyColor(t) {
  const hue = 300 * Math.max(0, Math.min(1, t)) // 0 (red) through 300 (violet)
  return hslToRgb(hue, 0.75, 0.55)
}
