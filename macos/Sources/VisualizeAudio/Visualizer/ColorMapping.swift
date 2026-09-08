import Foundation

// Direct port of src/mood.js's color logic. Keep in sync with that file —
// this is the native target's copy of the same palette/formulas, not a
// reinterpretation.

struct RGB {
    var r: Double
    var g: Double
    var b: Double
}

// Curated corner colors on the energy x brightness plane.
private let mellow = RGB(r: 80, g: 92, b: 168) // low energy, dark timbre
private let calm = RGB(r: 70, g: 210, b: 210) // low energy, bright timbre
private let aggressive = RGB(r: 215, g: 40, b: 145) // high energy, dark timbre
private let energetic = RGB(r: 255, g: 155, b: 85) // high energy, bright timbre

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

private func lerpColor(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    RGB(r: lerp(a.r, b.r, t), g: lerp(a.g, b.g, t), b: lerp(a.b, b.b, t))
}

/// Bilinear blend across the curated corners, driven by normalized energy and
/// spectral-centroid percentile ranks (see MoodTracker).
func targetColor(energyNorm: Double, centroidNorm: Double) -> RGB {
    let lowEnergyRow = lerpColor(mellow, calm, centroidNorm)
    let highEnergyRow = lerpColor(aggressive, energetic, centroidNorm)
    return lerpColor(lowEnergyRow, highEnergyRow, energyNorm)
}

private func hslToRgb(h: Double, s: Double, l: Double) -> RGB {
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    var r = 0.0, g = 0.0, b = 0.0
    if h < 60 { (r, g, b) = (c, x, 0) }
    else if h < 120 { (r, g, b) = (x, c, 0) }
    else if h < 180 { (r, g, b) = (0, c, x) }
    else if h < 240 { (r, g, b) = (0, x, c) }
    else if h < 300 { (r, g, b) = (x, 0, c) }
    else { (r, g, b) = (c, 0, x) }
    return RGB(r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255)
}

/// Position-in-spectrum color: bass -> red, mids -> green, treble -> violet.
/// `t` is a bar's fractional position (0-1) across the log-spaced frequency range.
func frequencyColor(t: Double) -> RGB {
    let hue = 300 * max(0, min(1, t))
    return hslToRgb(h: hue, s: 0.75, l: 0.55)
}
