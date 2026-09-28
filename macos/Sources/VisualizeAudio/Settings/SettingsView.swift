import CoreAudio
import SwiftUI

// Settings panel (gear button + display/color mode pickers). The music section is a passive
// status row — there's no login step with MediaRemote.
struct SettingsView: View {
    @Binding var displayMode: DisplayMode
    @Binding var colorMode: ColorMode
    @Binding var audioSource: AudioSource
    let availableMicDevices: [MicInputSource.Device]
    let nowPlaying: NowPlaying?

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
            musicStatusRow
        }
        .padding(16)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var musicStatusRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(nowPlaying != nil ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                if let nowPlaying {
                    Text(nowPlaying.title ?? nowPlaying.album ?? "Unknown track")
                        .font(.caption)
                        .lineLimit(2)
                    if let artist = nowPlaying.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(nowPlaying.isPlaying ? "Playing" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
