import Foundation

// Log-scaled frequency bucketing and bar easing logic
// (logBarValue, sampleBinLinear, and the per-frame smoothing/color-easing
// loop in draw()). Keep in sync with that file.

let barCount = 96

/// Frequency bins are linearly spaced, but music energy (and hearing) is
/// roughly logarithmic — bass would otherwise eat most of the bars while
/// treble gets crushed into the last couple. Map each bar to an
/// exponentially-growing band instead of a fixed step.
private func sampleBinLinear(_ freqData: [Float], _ idx: Double) -> Float {
    let i0 = Int(idx.rounded(.down))
    let i1 = min(i0 + 1, freqData.count - 1)
    let frac = Float(idx - Double(i0))
    return freqData[i0] * (1 - frac) + freqData[i1] * frac
}

private func logBarValue(_ freqData: [Float], _ barIndex: Int) -> Float {
    // Skip bin 0-2 (~0-45Hz on a typical 44.1kHz/2048-FFT setup) — that range
    // is mostly capture self-noise/rumble rather than real bass, and
    // log-scaling gives it disproportionate bar real estate.
    let minIndex = 3
    let maxIndex = freqData.count - 1
    let logMin = log2(Double(minIndex))
    let logMax = log2(Double(maxIndex))
    let t0 = Double(barIndex) / Double(barCount)
    let t1 = Double(barIndex + 1) / Double(barCount)
    let idx0 = pow(2, logMin + t0 * (logMax - logMin))
    let idx1 = pow(2, logMin + t1 * (logMax - logMin))

    // Low end: the band is narrower than one bin, so several consecutive
    // bars would round to the identical integer bin and read as one clumped
    // block. Interpolate a continuous fractional value instead.
    if idx1 - idx0 < 1 {
        return sampleBinLinear(freqData, (idx0 + idx1) / 2) / 255
    }

    // Wide bands (treble): still average the real bins they cover.
    var sum: Float = 0
    var count = 0
    var j = Int(idx0.rounded(.down))
    let upper = Int(idx1.rounded(.up))
    while j < upper && j < freqData.count {
        sum += freqData[j]
        count += 1
        j += 1
    }
    return count > 0 ? sum / Float(count) / 255 : 0
}

struct Bar {
    var x: Double
    var height: Double
    var r: Double
    var g: Double
    var b: Double
}

enum ColorMode {
    case frequency
    case intensity
    case album
}

private struct BarColorState {
    var r: Double = 90
    var g: Double = 90
    var b: Double = 120
    // Each bar's own easing speed — a few seconds to fully catch up.
    let rate: Double = 0.006 + Double.random(in: 0...1) * 0.014
    // Small fixed personal tint, set once — not time-varying.
    let jitter: Double = (Double.random(in: 0...1) - 0.5) * 18
}

private func clamp255(_ v: Double) -> Double {
    max(0, min(255, v))
}

/// Owns the per-bar smoothing/easing state across frames.
final class BarField {
    private var smoothed = [Float](repeating: 0, count: barCount)
    private var colorStates = (0..<barCount).map { _ in BarColorState() }

    /// Computes one frame's bars from raw frequency-domain data (0-255 byte
    /// range, matching AnalyserNode.getByteFrequencyData's convention).
    func computeBars(freqData: [Float], mood: MoodReading?, colorMode: ColorMode, albumPalette: AlbumPalette?, time: TimeInterval, width: Double, height: Double) -> [Bar] {
        let barWidth = width / Double(barCount)
        let intensityTarget = mood.map { targetColor(energyNorm: $0.energyNorm, centroidNorm: $0.centroidNorm) }
            ?? RGB(r: 90, g: 90, b: 120)

        var bars = [Bar](repeating: Bar(x: 0, height: 0, r: 0, g: 0, b: 0), count: barCount)
        for i in 0..<barCount {
            let raw = logBarValue(freqData, i)
            // Rise fast on transients, decay slower — kills the blocky/erratic
            // look from noisy low bins without dulling the visualizer's punch.
            let rate: Float = raw > smoothed[i] ? 0.5 : 0.15
            smoothed[i] += (raw - smoothed[i]) * rate
            let v = Double(smoothed[i])
            let barHeight = v * height * 0.9

            let target: RGB
            switch colorMode {
            case .intensity:
                target = intensityTarget
            case .frequency:
                target = frequencyColor(t: Double(i) / Double(barCount))
            case .album:
                if let albumPalette {
                    // Each bar is dealt one of the cover's own colors and drifts
                    // slowly in hue around it — see AlbumPalette for why this
                    // isn't a hue gradient or a spatial layout.
                    target = albumPalette.color(barIndex: i, barCount: barCount, loudness: v, time: time)
                } else {
                    target = intensityTarget
                }
            }
            // Each bar's fixed random jitter gives Frequency/Intensity mode a
            // little per-bar "personality". Album mode does its own per-bar
            // variation, in hue and tone around a real album color; this jitter
            // is a raw RGB offset that would push bars off those colors, so
            // skip it there.
            var state = colorStates[i]
            let jitter = colorMode == .album ? 0 : state.jitter
            // The slow multi-second ease is what gives Frequency/Intensity
            // their drifting-mood feel, but in Album mode it averages the
            // loudness-driven lightness away to a constant — the bars stop
            // pulsing at all. Album mode's hue is fixed per bar (it only
            // changes when the track does), so it can ease ~20x faster
            // without any risk of hue flicker: fast enough to read as beats,
            // slow enough to still smooth per-frame noise.
            let colorRate = colorMode == .album ? 0.12 : state.rate
            state.r += (target.r + jitter - state.r) * colorRate
            state.g += (target.g + jitter * 0.6 - state.g) * colorRate
            state.b += (target.b - jitter * 0.4 - state.b) * colorRate
            colorStates[i] = state

            // Album mode already bakes loudness into HSL lightness (hue-preserving);
            // stacking the flat RGB multiplier on top clips channels unevenly at
            // high v and washes the color toward white, losing the album hue right
            // when a bar gets loud. Only the other modes want the extra pop.
            let brightness = colorMode == .album ? 1.0 : 0.7 + v * 0.4
            bars[i] = Bar(
                x: Double(i) * barWidth,
                height: barHeight,
                r: clamp255(state.r * brightness),
                g: clamp255(state.g * brightness),
                b: clamp255(state.b * brightness)
            )
        }
        return bars
    }
}
