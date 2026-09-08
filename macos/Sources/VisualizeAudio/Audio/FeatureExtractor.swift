import Foundation

// Native equivalent of src/audioEngine.js's extractFeatures(), which calls
// essentia.js's Energy/SpectralCentroidTime/Loudness on the time-domain
// buffer. Essentia isn't available in Swift, so these are reimplemented from
// their standard DSP definitions (per the plan: same formulas, not a
// reinterpretation) rather than ported line-by-line from WASM internals.

struct AudioFeatures {
    var energy: Double
    var spectralCentroid: Double
    var loudness: Double
    var mood: MoodReading?
}

enum FeatureExtractor {
    /// Essentia's Energy: sum of squared samples over the frame.
    static func energy(timeData: [Float]) -> Double {
        var sum: Double = 0
        for sample in timeData {
            sum += Double(sample) * Double(sample)
        }
        return sum
    }

    /// Standard magnitude-spectrum spectral centroid (weighted mean
    /// frequency) computed from the same linear FFT magnitudes FFT.swift
    /// already produces for the visual bars — serves the same purpose as
    /// essentia's SpectralCentroidTime (a proxy for timbral brightness)
    /// without needing essentia's specific time-domain estimator.
    static func spectralCentroid(magnitudes: [Float], sampleRate: Double, fftSize: Int) -> Double {
        var weightedSum: Double = 0
        var magnitudeSum: Double = 0
        let binHz = sampleRate / Double(fftSize)
        for (i, mag) in magnitudes.enumerated() {
            let freq = Double(i) * binHz
            weightedSum += freq * Double(mag)
            magnitudeSum += Double(mag)
        }
        return magnitudeSum > 0 ? weightedSum / magnitudeSum : 0
    }

    /// Essentia's Loudness: Stevens' power law over total frame energy
    /// (default exponent 0.67).
    static func loudness(energy: Double) -> Double {
        pow(max(energy, 0), 0.67)
    }
}
