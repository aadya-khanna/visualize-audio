import Foundation

// Reads now-playing metadata from the system via the private MediaRemote framework
// (dlopen/dlsym). On macOS 15.4+ the direct MRMediaRemoteGetNowPlayingInfo call
// is often entitlement-gated and returns empty — we fall back to MRNowPlayingRequest
// through osascript/JXA in that case, and poll periodically because push
// notifications alone are unreliable across OS versions.
final class MediaRemoteBridge {
    struct InfoKeys {
        let title: String
        let artist: String
        let album: String
        let artworkData: String
        let playbackRate: String

        static let defaults = InfoKeys(
            title: "kMRMediaRemoteNowPlayingInfoTitle",
            artist: "kMRMediaRemoteNowPlayingInfoArtist",
            album: "kMRMediaRemoteNowPlayingInfoAlbum",
            artworkData: "kMRMediaRemoteNowPlayingInfoArtworkData",
            playbackRate: "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        )

        init(
            title: String,
            artist: String,
            album: String,
            artworkData: String,
            playbackRate: String
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.artworkData = artworkData
            self.playbackRate = playbackRate
        }

        init(handle: UnsafeMutableRawPointer) {
            func key(_ symbol: String, fallback: String) -> String {
                guard let ptr = dlsym(handle, symbol) else { return fallback }
                return ptr.assumingMemoryBound(to: CFString.self).pointee as String
            }
            self.init(
                title: key("kMRMediaRemoteNowPlayingInfoTitle", fallback: Self.defaults.title),
                artist: key("kMRMediaRemoteNowPlayingInfoArtist", fallback: Self.defaults.artist),
                album: key("kMRMediaRemoteNowPlayingInfoAlbum", fallback: Self.defaults.album),
                artworkData: key("kMRMediaRemoteNowPlayingInfoArtworkData", fallback: Self.defaults.artworkData),
                playbackRate: key("kMRMediaRemoteNowPlayingInfoPlaybackRate", fallback: Self.defaults.playbackRate)
            )
        }
    }

    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (NSDictionary) -> Void) -> Void
    private typealias RegisterForNotificationsFunction = @convention(c) (DispatchQueue) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let pollInterval: TimeInterval = 2
    private static let notificationSymbols = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ]
    private static let jxaScript = """
    function run() {
        var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
        if (!bundle) return '';
        bundle.load;
        var MRNowPlayingRequest = $.NSClassFromString('MRNowPlayingRequest');
        if (!MRNowPlayingRequest) return '';
        var item = MRNowPlayingRequest.localNowPlayingItem;
        if (!item) return '';
        var info = item.nowPlayingInfo;
        if (!info) return '';
        function text(key) {
            var value = info.objectForKey(key);
            return value ? String(value.js) : '';
        }
        function rate(key) {
            var value = info.objectForKey(key);
            return value ? value.doubleValue : 0;
        }
        var client = MRNowPlayingRequest.localNowPlayingPlayerPath.client;
        var bundleId = client && client.bundleIdentifier ? String(client.bundleIdentifier.js) : '';
        return [
            text('kMRMediaRemoteNowPlayingInfoTitle'),
            text('kMRMediaRemoteNowPlayingInfoArtist'),
            text('kMRMediaRemoteNowPlayingInfoAlbum'),
            rate('kMRMediaRemoteNowPlayingInfoPlaybackRate'),
            bundleId
        ].join('\\t');
    }
    """

    private var handle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetNowPlayingInfoFunction?
    private var infoKeys = InfoKeys.defaults
    private var observedNotifications: [Notification.Name] = []
    private var pollTimer: Timer?

    /// Fires on the main queue whenever now-playing info changes, `nil` when
    /// nothing is playing / detected.
    var onNowPlayingChange: ((NowPlaying?) -> Void)?

    func start() {
        if let handle = dlopen(Self.frameworkPath, RTLD_NOW) {
            self.handle = handle
            infoKeys = InfoKeys(handle: handle)

            if let getInfoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
                getNowPlayingInfo = unsafeBitCast(getInfoSymbol, to: GetNowPlayingInfoFunction.self)
            }
            if let registerSymbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
                let registerForNotifications = unsafeBitCast(registerSymbol, to: RegisterForNotificationsFunction.self)
                registerForNotifications(DispatchQueue.main)
            }

            for symbol in Self.notificationSymbols {
                guard let ptr = dlsym(handle, symbol) else { continue }
                let name = Notification.Name(ptr.assumingMemoryBound(to: CFString.self).pointee as String)
                observedNotifications.append(name)
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(nowPlayingInfoDidChange),
                    name: name,
                    object: nil
                )
            }
        } else {
            NSLog("VisualizeAudio: could not load MediaRemote — falling back to JXA polling")
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for name in observedNotifications {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        observedNotifications.removeAll()
        if let handle {
            dlclose(handle)
        }
        handle = nil
        getNowPlayingInfo = nil
    }

    @objc private func nowPlayingInfoDidChange() {
        refresh()
    }

    private func refresh() {
        guard let getNowPlayingInfo else {
            refreshViaJXA()
            return
        }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            if let nowPlaying = NowPlaying(info: info, keys: self.infoKeys) {
                self.deliver(nowPlaying)
            } else {
                self.refreshViaJXA()
            }
        }
    }

    private func refreshViaJXA() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nowPlaying = self?.fetchViaJXA()
            DispatchQueue.main.async {
                self?.deliver(nowPlaying)
            }
        }
    }

    private func deliver(_ nowPlaying: NowPlaying?) {
        onNowPlayingChange?(nowPlaying)
    }

    /// MRNowPlayingRequest via JXA still works on macOS 15.4+ when the direct
    /// MRMediaRemoteGetNowPlayingInfo callback is entitlement-gated.
    private func fetchViaJXA() -> NowPlaying? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.jxaScript]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
        else { return nil }

        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }

        let title = parts[0].isEmpty ? nil : parts[0]
        let artist = parts[1].isEmpty ? nil : parts[1]
        let album = parts[2].isEmpty ? nil : parts[2]
        let rate = Double(parts[3]) ?? 0
        let bundleIdentifier = parts.count >= 5 && !parts[4].isEmpty ? parts[4] : nil
        guard title != nil || artist != nil || album != nil else { return nil }

        return NowPlaying(
            title: title,
            artist: artist,
            album: album,
            isPlaying: rate > 0,
            bundleIdentifier: bundleIdentifier
        )
    }

    deinit { stop() }
}
