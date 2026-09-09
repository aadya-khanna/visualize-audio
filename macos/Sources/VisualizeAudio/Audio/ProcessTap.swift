import AudioToolbox
import CoreAudio
import Foundation

// System-wide audio capture via a macOS 14.4+ Core Audio *process tap* — no
// virtual loopback device (Background Music/BlackHole), no mic permission,
// and none of the CoreAudio renegotiation glitch documented in the Electron
// build's README known issues, because the signal never passes through a
// virtual device at all.
//
// Pattern follows Apple's WWDC23 "Meet Core Audio taps" session and the
// open-source AudioCap reference project (github.com/insidegui/AudioCap).
// Requires the macOS 14.4 SDK (Xcode 15.3+). Verified working against Xcode
// 26.6 — see macos/AGENTS.md for the two real issues that turned up in that
// process (TCC permission bundling, FFT dB scaling) and how they were fixed.
// Run via scripts/build-app.sh, not a bare `swift build` — see AGENTS.md.
final class ProcessTap {
    enum TapError: Error {
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case ioProcFailed(OSStatus)
    }

    private var tapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var isRunning = false
    private var sampleRate: Double = 48000

    /// Called on a real-time audio thread with mono samples (CoreAudio mixes
    /// down to mono itself, per the mono tap description below — the
    /// visualizer only needs level/spectrum, not stereo separation) and the
    /// device's sample rate.
    var onAudio: (([Float], Double) -> Void)?

    /// Sets up a system-wide tap (excludes no processes, i.e. captures
    /// everything currently playing) wrapped in a private aggregate device so
    /// we can register an IO proc and pull buffers out of it.
    func start() throws {
        // Mono, not stereo: handle() reads the IOProc buffer as one sequence
        // of samples. A stereo tap delivers interleaved [L0,R0,L1,R1,...]
        // floats — reading that as if it were mono treats each L/R pair as
        // two separate time samples, which measures every frequency at half
        // its true value for any content correlated across channels. Found
        // by playing known test tones (1-23kHz) through the old stereo tap:
        // every one measured at almost exactly half its true frequency
        // (5kHz->2.5kHz, 20kHz->10kHz, etc — see macos/AGENTS.md).
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "VisualizeAudio System Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID: AudioObjectID = .unknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else { throw TapError.tapCreationFailed(tapStatus) }
        tapID = newTapID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VisualizeAudio Tap Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapDescription.uuid.uuidString]
            ],
        ]

        var newAggregateID: AudioObjectID = .unknown
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else { throw TapError.aggregateDeviceCreationFailed(aggregateStatus) }
        aggregateDeviceID = newAggregateID

        sampleRate = Self.nominalSampleRate(of: aggregateDeviceID) ?? sampleRate

        var newProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateDeviceID, nil) { [weak self] _, inputData, _, _, _ in
            self?.handle(inputData)
        }
        guard ioStatus == noErr, let newProcID else { throw TapError.ioProcFailed(ioStatus) }
        ioProcID = newProcID

        let startStatus = AudioDeviceStart(aggregateDeviceID, newProcID)
        guard startStatus == noErr else { throw TapError.ioProcFailed(startStatus) }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if aggregateDeviceID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        isRunning = false
        tapID = .unknown
        aggregateDeviceID = .unknown
        ioProcID = nil
        sampleRate = 48000
    }

    // Real-time audio thread. Allocating here (Array(...)) isn't strictly
    // realtime-safe, but this is a visualizer, not a low-latency audio
    // pipeline — occasional jitter is invisible in the rendered bars.
    private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let buffer = list.first, let data = buffer.mData else { return }
        let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard frameCount > 0 else { return }
        let samples = UnsafeBufferPointer<Float>(start: data.assumingMemoryBound(to: Float.self), count: frameCount)
        onAudio?(Array(samples), sampleRate)
    }

    deinit { stop() }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double? {
        var rate: Float64 = 0
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &rate)
        return status == noErr && rate > 0 ? rate : nil
    }
}

extension AudioObjectID {
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}
