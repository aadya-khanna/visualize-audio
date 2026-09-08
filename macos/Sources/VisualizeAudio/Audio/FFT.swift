import Accelerate
import Foundation

// Native replacement for Web Audio's AnalyserNode (src/audioEngine.js's
// `analyser.fftSize`/`getByteFrequencyData`). Computes a windowed real FFT via
// vDSP and reproduces getByteFrequencyData's byte-range/smoothing convention
// (see the Web Audio API spec's "smoothing over time" + dB-to-byte mapping)
// so BarLayout.swift's port of the bar-bucketing math sees the same shape of
// data it did in the browser.

// Raw vDSP FFT magnitudes are in an arbitrary internal scale tied to fftSize
// and the window function — not real dBFS — so converting them to dB
// requires dividing by a "zero reference" first (see Apple's
// vDSP.convert(amplitude:toDecibels:zeroReference:)). Skipping that
// reference and treating raw magnitude as if it were already dBFS was the
// actual bug behind the "way too sensitive" visualizer: a full-scale
// (amplitude 1.0) on-bin sine wave was reading as +30dB instead of ~0dBFS.
//
// fullScaleReferenceMagnitude is that missing reference: it's this exact
// pipeline's measured linear-magnitude output for a full-scale on-bin sine
// at fftSize=2048 with a normalized Hann window (see
// scripts/fft_selftest.swift, which reproduces this file's math against a
// synthetic tone). Re-run that script and update this constant if fftSize
// or the window function ever changes.
private let fullScaleReferenceMagnitude: Float = 34.37748
private let minDecibels: Float = -100
private let maxDecibels: Float = 0
private let smoothingTimeConstant: Float = 0.8

final class AudioAnalyser {
    let fftSize: Int
    let frequencyBinCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var smoothedMagnitudes: [Float]

    /// 0-255 byte range, `frequencyBinCount` bins — same convention as
    /// AnalyserNode.getByteFrequencyData.
    private(set) var freqData: [Float]

    init(fftSize: Int = 2048) {
        self.fftSize = fftSize
        self.frequencyBinCount = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.smoothedMagnitudes = [Float](repeating: 0, count: frequencyBinCount)
        self.freqData = [Float](repeating: 0, count: frequencyBinCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// `timeData` must have exactly `fftSize` samples. Also returns the raw
    /// linear magnitude spectrum (pre-dB, pre-byte-scaling) for feature
    /// extraction (see FeatureExtractor.swift), since that needs real
    /// magnitudes, not the smoothed/quantized display bytes.
    @discardableResult
    func analyze(timeData: [Float]) -> [Float] {
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

        var scale: Float = 1.0 / Float(fftSize)
        var scaledMagnitudes = [Float](repeating: 0, count: frequencyBinCount)
        vDSP_vsmul(magnitudes, 1, &scale, &scaledMagnitudes, 1, vDSP_Length(frequencyBinCount))

        var linearMagnitudes = [Float](repeating: 0, count: frequencyBinCount)
        var n = Int32(frequencyBinCount)
        vvsqrtf(&linearMagnitudes, scaledMagnitudes, &n)

        // Web Audio smooths the linear magnitude before dB conversion, not
        // the byte output — replicate that order so easing feels the same.
        for i in 0..<frequencyBinCount {
            smoothedMagnitudes[i] = smoothingTimeConstant * smoothedMagnitudes[i]
                + (1 - smoothingTimeConstant) * linearMagnitudes[i]
        }

        for i in 0..<frequencyBinCount {
            let referenced = max(smoothedMagnitudes[i], 1e-10) / fullScaleReferenceMagnitude
            let db = 20 * log10(referenced)
            let clamped = max(minDecibels, min(maxDecibels, db))
            let normalized = (clamped - minDecibels) / (maxDecibels - minDecibels)
            freqData[i] = normalized * 255
        }

        return linearMagnitudes
    }
}
