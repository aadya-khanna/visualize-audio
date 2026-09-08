import SwiftUI

// Port of src/Visualizer.jsx: a Canvas draw loop driven by TimelineView
// (native equivalent of requestAnimationFrame), the gear-button settings
// panel, and the now-playing track overlay (fed by MediaRemote instead of
// Spotify OAuth polling).
struct VisualizerView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var mediaRemote = MediaRemoteBridgeStore()

    @State private var displayMode: DisplayMode = .normal
    @State private var colorMode: ColorMode = .frequency
    @State private var audioSource: AudioSource = .systemTap
    @State private var settingsOpen = false
    @State private var availableMicDevices: [MicInputSource.Device] = []
    // @State (not a plain `let`) so the class instance — and its per-bar
    // smoothing state — survives view re-creation, not just view identity.
    @State private var barField = BarField()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 8 / 255, green: 8 / 255, blue: 16 / 255).ignoresSafeArea()

            TimelineView(.animation) { _ in
                Canvas { context, size in
                    // Fade trail instead of hard clear — reads as "mood" smoothing.
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(red: 8 / 255, green: 8 / 255, blue: 16 / 255).opacity(0.25))
                    )

                    let width = Double(size.width)
                    let height = Double(size.height)
                    let barWidth = width / Double(barCount)
                    let bars = barField.computeBars(
                        freqData: audioEngine.freqData,
                        mood: audioEngine.features.mood,
                        colorMode: colorMode,
                        width: width,
                        height: height
                    )

                    switch displayMode {
                    case .normal:
                        drawBarsNormal(context, height: height, bars: bars, barWidth: barWidth)
                    case .eightBit:
                        drawBars8Bit(context, height: height, bars: bars, barWidth: barWidth)
                    case .curve:
                        drawCurveArea(context, width: width, height: height, bars: bars)
                    }
                }
            }

            if let nowPlaying = mediaRemote.nowPlaying {
                trackOverlay(nowPlaying)
                    .padding(16)
            }

            VStack(alignment: .trailing, spacing: 8) {
                Button(action: { settingsOpen.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                if settingsOpen {
                    SettingsView(
                        displayMode: $displayMode,
                        colorMode: $colorMode,
                        audioSource: $audioSource,
                        availableMicDevices: availableMicDevices,
                        nowPlayingDetected: mediaRemote.nowPlaying != nil
                    )
                }
            }
            .padding(16)
        }
        .onAppear {
            availableMicDevices = MicInputSource.availableDevices()
            audioEngine.start(source: audioSource)
            mediaRemote.start()
        }
        .onDisappear {
            audioEngine.stop()
            mediaRemote.stop()
        }
        .onChange(of: audioSource) { _, newSource in
            audioEngine.start(source: newSource)
        }
    }

    private func trackOverlay(_ nowPlaying: NowPlaying) -> some View {
        HStack(spacing: 10) {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(nowPlaying.artist ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(10)
        .background(.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Thin ObservableObject wrapper so MediaRemoteBridge's callback can publish
/// SwiftUI-observable state.
final class MediaRemoteBridgeStore: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    private let bridge = MediaRemoteBridge()

    func start() {
        bridge.onNowPlayingChange = { [weak self] nowPlaying in
            self?.nowPlaying = nowPlaying
        }
        bridge.start()
    }

    func stop() {
        bridge.stop()
    }
}
