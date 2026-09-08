// Standalone diagnostic: feeds a known full-scale (amplitude 1.0) sine wave
// through the exact same vDSP pipeline as Audio/FFT.swift and reports the
// resulting magnitude/dB at that tone's bin. A correctly scaled real FFT
// should report a full-scale tone at (or a few dB below, from window
// coherent-gain loss) 0 dBFS — not +14dB, which is what live capture showed.
// Run with: swift scripts/fft_selftest.swift

import Accelerate
import Foundation

let fftSize = 2048
let sampleRate = 48000.0
let toneFreq = 1000.0
let toneAmplitude: Float = 1.0

var timeData = [Float](repeating: 0, count: fftSize)
for n in 0..<fftSize {
    timeData[n] = toneAmplitude * Float(sin(2 * Double.pi * toneFreq * Double(n) / sampleRate))
}

let frequencyBinCount = fftSize / 2
let log2n = vDSP_Length(log2(Double(fftSize)))
let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

var window = [Float](repeating: 0, count: fftSize)
vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

var windowed = [Float](repeating: 0, count: fftSize)
vDSP_vmul(timeData, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

var realp = [Float](repeating: 0, count: frequencyBinCount)
var imagp = [Float](repeating: 0, count: frequencyBinCount)
var magnitudes = [Float](repeating: 0, count: frequencyBinCount)

realp.withUnsafeMutableBufferPointer { realPtr in
    imagp.withUnsafeMutableBufferPointer { imagPtr in
        var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
        windowed.withUnsafeBufferPointer { windowedPtr in
            windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frequencyBinCount) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(frequencyBinCount))
            }
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(frequencyBinCount))
    }
}

// Current FFT.swift scaling: magnitude / fftSize, then sqrt.
var scale: Float = 1.0 / Float(fftSize)
var scaledMagnitudes = [Float](repeating: 0, count: frequencyBinCount)
vDSP_vsmul(magnitudes, 1, &scale, &scaledMagnitudes, 1, vDSP_Length(frequencyBinCount))

var linearMagnitudes = [Float](repeating: 0, count: frequencyBinCount)
var n = Int32(frequencyBinCount)
vvsqrtf(&linearMagnitudes, scaledMagnitudes, &n)

let binHz = sampleRate / Double(fftSize)
let expectedBin = Int((toneFreq / binHz).rounded())
let peakBin = linearMagnitudes.indices.max(by: { linearMagnitudes[$0] < linearMagnitudes[$1] })!
let peakMag = linearMagnitudes[peakBin]
let peakDb = 20 * log10(max(peakMag, 1e-10))

print("Full-scale \(toneFreq)Hz tone (amplitude \(toneAmplitude))")
print("Expected bin ~\(expectedBin) (\(Double(expectedBin) * binHz)Hz)")
print("Peak bin: \(peakBin) (\(Double(peakBin) * binHz)Hz), magnitude=\(peakMag), raw dB (no reference)=\(peakDb)")

// FFT.swift's fullScaleReferenceMagnitude is exactly this measured value —
// so referencing against it should now read ~0dBFS by construction. This is
// a regression check: if it drifts from ~0, the pipeline (fftSize, window)
// changed and FFT.swift's constant needs updating from the value above.
let fullScaleReferenceMagnitude: Float = 34.37748
let referencedDb = 20 * log10(peakMag / fullScaleReferenceMagnitude)
print("Referenced against FFT.swift's fullScaleReferenceMagnitude: dB=\(referencedDb) (expect ~0)")

vDSP_destroy_fftsetup(fftSetup)
