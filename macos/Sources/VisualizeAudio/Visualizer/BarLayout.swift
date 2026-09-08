import Foundation

// Direct port of src/Visualizer.jsx's bar bucketing/easing logic
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

/// Owns the per-bar smoothing/easing state across frames — mirrors
/// smoothedBarsRef/barColorStateRef in Visualizer.jsx.
final class BarField {
    private var smoothed = [Float](repeating: 0, count: barCount)
    private var colorStates = (0..<barCount).map { _ in BarColorState() }

    /// Computes one frame's bars from raw frequency-domain data (0-255 byte
    /// range, matching AnalyserNode.getByteFrequencyData's convention).
    func computeBars(freqData: [Float], mood: MoodReading?, colorMode: ColorMode, width: Double, height: Double) -> [Bar] {
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

            let target = colorMode == .intensity ? intensityTarget : frequencyColor(t: Double(i) / Double(barCount))
            var state = colorStates[i]
            state.r += (target.r + state.jitter - state.r) * state.rate
            state.g += (target.g + state.jitter * 0.6 - state.g) * state.rate
            state.b += (target.b - state.jitter * 0.4 - state.b) * state.rate
            colorStates[i] = state

            let brightness = 0.7 + v * 0.4 // louder bins pop brighter
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
