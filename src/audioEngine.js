import { EssentiaWASM } from 'essentia.js/dist/essentia-wasm.es.js'
import Essentia from 'essentia.js/dist/essentia.js-core.es.js'
import { MoodTracker } from './mood.js'

const FFT_SIZE = 2048

// The WASM binary loads async (fetch + compile) even though the glue module
// object exists synchronously on import — wait for Emscripten's runtime hook
// before touching it, or algorithm calls will fail on an uninitialized heap.
function waitForWasmReady() {
  return new Promise((resolve) => {
    if (EssentiaWASM.calledRun) {
      resolve()
      return
    }
    const prev = EssentiaWASM.onRuntimeInitialized
    EssentiaWASM.onRuntimeInitialized = () => {
      prev?.()
      resolve()
    }
  })
}

// Lists audio *input* devices. A virtual loopback device (BlackHole, VB-Cable)
// shows up here just like a microphone — pick it in the UI to visualize
// whatever's playing through your speakers (e.g. Spotify).
export async function listInputDevices() {
  await navigator.mediaDevices.getUserMedia({ audio: true }) // triggers permission + labels
  const devices = await navigator.mediaDevices.enumerateDevices()
  return devices.filter((d) => d.kind === 'audioinput')
}

export class AudioEngine {
  constructor() {
    this.essentia = null
    this.audioContext = null
    this.analyser = null
    this.source = null
    this.stream = null
    this.moodTracker = new MoodTracker()
    this.features = { energy: 0, spectralCentroid: 0, loudness: -60, mood: null }
  }

  async init(deviceId) {
    await waitForWasmReady()
    this.essentia = new Essentia(EssentiaWASM)

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: deviceId ? { deviceId: { exact: deviceId } } : true,
    })

    this.audioContext = new AudioContext()
    this.source = this.audioContext.createMediaStreamSource(this.stream)

    this.analyser = this.audioContext.createAnalyser()
    this.analyser.fftSize = FFT_SIZE
    this.analyser.smoothingTimeConstant = 0.8
    this.source.connect(this.analyser)

    this.freqData = new Uint8Array(this.analyser.frequencyBinCount)
    this.timeData = new Float32Array(this.analyser.fftSize)
  }

  // Call every animation frame. Cheap: just reads the analyser's buffers.
  getVisualData() {
    this.analyser.getByteFrequencyData(this.freqData)
    this.analyser.getFloatTimeDomainData(this.timeData)
    return { freqData: this.freqData, timeData: this.timeData }
  }

  // Call periodically (e.g. every 150-200ms), not every frame — essentia's
  // JS/WASM feature extraction is heavier than reading the analyser.
  extractFeatures() {
    if (!this.essentia) return this.features
    const vector = this.essentia.arrayToVector(this.timeData)
    const energy = this.essentia.Energy(vector).energy
    const centroid = this.essentia.SpectralCentroidTime(vector, this.audioContext.sampleRate).centroid
    const loudness = this.essentia.Loudness(vector).loudness
    const mood = this.moodTracker.update(energy, centroid)

    this.features = { energy, spectralCentroid: centroid, loudness, mood }
    return this.features
  }

  stop() {
    this.stream?.getTracks().forEach((t) => t.stop())
    this.audioContext?.close()
  }
}
