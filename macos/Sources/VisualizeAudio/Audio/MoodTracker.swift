import Foundation

// Direct port of src/mood.js's MoodTracker. Tracks energy/spectral-centroid
// as continuous, normalized signals via percentile rank within a rolling
// window, not min-max stretch — mic/tap input tends to be skewed (mostly
// quiet, occasional loud spikes), and min-max normalization puts the 0.5
// threshold above most real samples in that case. Rank-based split stays
// centered regardless of the distribution's shape.

private let historySize = 40

struct MoodReading {
    var energyNorm: Double
    var centroidNorm: Double
}

final class MoodTracker {
    private var energyHistory: [Double] = []
    private var centroidHistory: [Double] = []

    private func normalize(_ history: inout [Double], _ value: Double) -> Double {
        history.append(value)
        if history.count > historySize { history.removeFirst() }
        if history.count < 2 { return 0.5 }
        let below = history.filter { $0 <= value }.count
        return Double(below) / Double(history.count)
    }

    func update(energy: Double, spectralCentroid: Double) -> MoodReading {
        let energyNorm = normalize(&energyHistory, energy)
        let centroidNorm = normalize(&centroidHistory, spectralCentroid)
        return MoodReading(energyNorm: energyNorm, centroidNorm: centroidNorm)
    }
}
