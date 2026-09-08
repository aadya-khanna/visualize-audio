import AVFoundation
import CoreAudio

// Alternate audio source alongside ProcessTap — mirrors src/audioEngine.js's
// listInputDevices()/getUserMedia() device-picker path, for when a
// system-wide tap isn't available or wanted.
final class MicInputSource {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    private let engine = AVAudioEngine()
    private(set) var isRunning = false

    var onAudio: (([Float], Double) -> Void)?

    /// Lists audio *input* devices, same intent as audioEngine.js's
    /// listInputDevices() (a virtual loopback device would show up here too,
    /// if one happens to be installed, but it's no longer required).
    static func availableDevices() -> [Device] {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else {
            return []
        }
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            return Device(id: deviceID, name: name)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        return status == noErr && propertySize > 0
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { namePtr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, namePtr)
        }
        return status == noErr ? (name as String) : nil
    }

    /// Sets the AVAudioEngine input node's underlying device, then installs a
    /// tap and starts the engine. `deviceID` nil uses the system default input.
    func start(deviceID: AudioDeviceID?) throws {
        if let deviceID {
            var mutableDeviceID = deviceID
            let inputUnit = engine.inputNode.audioUnit
            guard let inputUnit else { throw NSError(domain: "MicInputSource", code: -1) }
            AudioUnitSetProperty(
                inputUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            self?.onAudio?(samples, format.sampleRate)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    deinit { stop() }
}
