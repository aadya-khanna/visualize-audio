import SwiftUI

// Main visualizer view: a Canvas draw loop driven by TimelineView, the gear-button settings
// panel, and the now-playing track overlay (fed by MediaRemote).
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

            TimelineView(.animation) { timeline in
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
                        albumPalette: mediaRemote.albumPalette,
                        time: timeline.date.timeIntervalSinceReferenceDate,
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .allowsHitTesting(false)
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
                        availableMicDevices: availableMicDevices
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
            NowPlayingArtwork(artwork: nowPlaying.artwork, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title ?? nowPlaying.album ?? "Unknown track")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let artist = nowPlaying.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
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
    @Published private(set) var albumPalette: AlbumPalette?
    private let bridge = MediaRemoteBridge()
    private let artworkResolver = ArtworkResolver()
    private let paletteExtractor = AlbumPaletteExtractor()
    private var artworkTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?

    func start() {
        bridge.onNowPlayingChange = { [weak self] nowPlaying in
            DispatchQueue.main.async {
                self?.handleNowPlaying(nowPlaying)
            }
        }
        bridge.start()
    }

    func stop() {
        artworkTask?.cancel()
        artworkTask = nil
        paletteTask?.cancel()
        paletteTask = nil
        bridge.stop()
    }

    private func handleNowPlaying(_ incoming: NowPlaying?) {
        artworkTask?.cancel()
        paletteTask?.cancel()

        guard var incoming else {
            nowPlaying = nil
            albumPalette = nil
            return
        }

        if let current = nowPlaying,
           current.trackIdentity == incoming.trackIdentity,
           incoming.artwork == nil {
            incoming.artwork = current.artwork
        }

        if nowPlaying?.trackIdentity != incoming.trackIdentity {
            albumPalette = nil
        }

        nowPlaying = incoming
        resolveArtwork(for: incoming)
        if incoming.artwork != nil {
            resolvePalette(for: incoming)
        }
    }

    private func resolveArtwork(for item: NowPlaying) {
        guard item.artwork == nil else { return }

        artworkTask = Task {
            guard let artwork = await artworkResolver.resolve(for: item) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard nowPlaying?.trackIdentity == item.trackIdentity else { return }
                var updated = nowPlaying!
                updated.artwork = artwork
                nowPlaying = updated
                resolvePalette(for: updated)
            }
        }
    }

    private func resolvePalette(for item: NowPlaying) {
        paletteTask?.cancel()
        paletteTask = Task {
            guard let palette = await paletteExtractor.palette(for: item) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard nowPlaying?.trackIdentity == item.trackIdentity else { return }
                albumPalette = palette
            }
        }
    }
}
