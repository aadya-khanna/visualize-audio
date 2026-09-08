import Combine
import CoreAudio
import Foundation

// Native equivalent of src/audioEngine.js's AudioEngine class: owns whichever
// source is active (system tap or mic), runs the analyser continuously, and
// extracts mood features on a timer (matching Visualizer.jsx's 150ms
// cadence) — same shape as the JS class, just split across the source
// abstractions above.

enum AudioSource: Equatable {
    case systemTap
    case microphone(deviceID: AudioDeviceID?)
}

final class AudioEngine: ObservableObject {
    private let analyser = AudioAnalyser(fftSize: 2048)
    private let moodTracker = MoodTracker()

    private var sampleRate: Double = 44100
    private var sampleBuffer: [Float] = []
    private var latestMagnitudes: [Float] = []

    private var processTap: ProcessTap?
    private var micSource: MicInputSource?
    private var featureTimer: Timer?

    @Published private(set) var freqData: [Float] = Array(repeating: 0, count: 1024)
    @Published private(set) var features = AudioFeatures(energy: 0, spectralCentroid: 0, loudness: 0, mood: nil)
    @Published private(set) var activeSource: AudioSource?
    @Published private(set) var lastError: String?

    func start(source: AudioSource) {
        stop()
        do {
            switch source {
            case .systemTap:
                let tap = ProcessTap()
                tap.onAudio = { [weak self] samples, rate in self?.ingest(samples, rate) }
                try tap.start()
                processTap = tap
            case .microphone(let deviceID):
                let mic = MicInputSource()
                mic.onAudio = { [weak self] samples, rate in self?.ingest(samples, rate) }
                try mic.start(deviceID: deviceID)
                micSource = mic
            }
            activeSource = source
            lastError = nil
        } catch {
            lastError = "\(error)"
            activeSource = nil
            NSLog("VisualizeAudio: failed to start audio source \(source): \(error)")
        }

        featureTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.extractFeatures()
        }
    }

    // Mirrors audioEngine.js's stop(): release everything explicitly rather
    // than waiting on deinit, so the app quitting/switching sources doesn't
    // leave a device or tap dangling.
    func stop() {
        processTap?.stop()
        processTap = nil
        micSource?.stop()
        micSource = nil
        featureTimer?.invalidate()
        featureTimer = nil
        activeSource = nil
    }

    // Called on the source's real-time audio thread.
    private func ingest(_ samples: [Float], _ rate: Double) {
        sampleRate = rate
        sampleBuffer.append(contentsOf: samples)

        let fftSize = analyser.fftSize
        guard sampleBuffer.count >= fftSize else { return }
        let window = Array(sampleBuffer.suffix(fftSize))
        if sampleBuffer.count > fftSize * 4 {
            sampleBuffer.removeAll(keepingCapacity: true) // avoid unbounded growth if analysis falls behind
        }

        let magnitudes = analyser.analyze(timeData: window)
        let bytes = analyser.freqData

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestMagnitudes = magnitudes
            self.freqData = bytes
        }
    }

    private func extractFeatures() {
        guard !latestMagnitudes.isEmpty else { return }
        let timeData = sampleBuffer.suffix(analyser.fftSize)
        guard timeData.count == analyser.fftSize else { return }

        let energy = FeatureExtractor.energy(timeData: Array(timeData))
        let centroid = FeatureExtractor.spectralCentroid(
            magnitudes: latestMagnitudes,
            sampleRate: sampleRate,
            fftSize: analyser.fftSize
        )
        let loudness = FeatureExtractor.loudness(energy: energy)
        let mood = moodTracker.update(energy: energy, spectralCentroid: centroid)

        DispatchQueue.main.async { [weak self] in
            self?.features = AudioFeatures(energy: energy, spectralCentroid: centroid, loudness: loudness, mood: mood)
        }
    }

    deinit { stop() }
}
