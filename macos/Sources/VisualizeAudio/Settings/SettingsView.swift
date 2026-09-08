import CoreAudio
import SwiftUI

// Port of Visualizer.jsx's settings panel (gear button + display/color mode
// pickers). The "Music" section replaces MusicConnect.jsx's connect/
// disconnect button — there's no login step with MediaRemote, so this is a
// passive status row instead.
struct SettingsView: View {
    @Binding var displayMode: DisplayMode
    @Binding var colorMode: ColorMode
    @Binding var audioSource: AudioSource
    let availableMicDevices: [MicInputSource.Device]
    let nowPlayingDetected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Display")
            modeRow(DisplayMode.allCases, selected: displayMode) { displayMode = $0 } label: { $0.rawValue }

            sectionTitle("Color")
            modeRow([ColorMode.frequency, .intensity], selected: colorMode) { colorMode = $0 } label: {
                $0 == .frequency ? "Frequency" : "Intensity"
            }

            sectionTitle("Audio source")
            audioSourceRow

            sectionTitle("Music")
            HStack(spacing: 6) {
                Circle()
                    .fill(nowPlayingDetected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(nowPlayingDetected ? "Now playing detected" : "Nothing playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func modeRow<T: Hashable>(_ modes: [T], selected: T, onSelect: @escaping (T) -> Void, label: @escaping (T) -> String) -> some View {
        HStack(spacing: 6) {
            ForEach(modes, id: \.self) { mode in
                Button(label(mode)) { onSelect(mode) }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mode == selected ? Color.accentColor.opacity(0.3) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .font(.caption)
            }
        }
    }

    private var audioSourceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("System audio") { audioSource = .systemTap }
                .buttonStyle(.borderless)
                .font(.caption)
                .fontWeight(isSystemTap ? .semibold : .regular)

            ForEach(availableMicDevices) { device in
                Button(device.name) { audioSource = .microphone(deviceID: device.id) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .fontWeight(isSelectedMic(device.id) ? .semibold : .regular)
            }
        }
    }

    private var isSystemTap: Bool {
        if case .systemTap = audioSource { return true }
        return false
    }

    private func isSelectedMic(_ id: AudioDeviceID) -> Bool {
        if case .microphone(let deviceID) = audioSource { return deviceID == id }
        return false
    }
}
