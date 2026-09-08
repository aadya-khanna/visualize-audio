import Foundation

// Replaces src/spotify.js entirely for the native target: no OAuth/PKCE, no
// developer-dashboard registration, no 25-user cap, no login step. Instead
// this loads the private MediaRemote framework via dlopen/dlsym — the same
// technique Isle (github.com/matthewhamilton3141/isle) and other third-party
// "now playing" menu-bar utilities use, since Apple provides no public API
// for system-wide now-playing info. This is *system-wide* (whatever app is
// playing — Spotify, Music, Safari, ...), not Spotify-specific, matching how
// Isle itself works.
//
// Private-API caveat (document prominently — see macos/AGENTS.md): this
// rules out App Store distribution, same as Isle. Symbol/key names below are
// stable across recent macOS versions in practice (widely relied on by
// existing open-source "now playing" tools) but are not an Apple-documented
// contract and could change in a future OS release.
final class MediaRemoteBridge {
    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (NSDictionary) -> Void) -> Void
    private typealias RegisterForNotificationsFunction = @convention(c) (DispatchQueue) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let nowPlayingChangedNotification = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")

    private var handle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetNowPlayingInfoFunction?

    /// Fires on the main queue whenever now-playing info changes, `nil` when
    /// nothing is playing / detected.
    var onNowPlayingChange: ((NowPlaying?) -> Void)?

    func start() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
            NSLog("VisualizeAudio: could not load MediaRemote — now-playing overlay will stay empty")
            return
        }
        self.handle = handle

        guard
            let getInfoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
            let registerSymbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        else {
            NSLog("VisualizeAudio: MediaRemote symbols not found — OS version may have changed the private API")
            return
        }

        getNowPlayingInfo = unsafeBitCast(getInfoSymbol, to: GetNowPlayingInfoFunction.self)
        let registerForNotifications = unsafeBitCast(registerSymbol, to: RegisterForNotificationsFunction.self)
        registerForNotifications(DispatchQueue.main)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingInfoDidChange),
            name: Self.nowPlayingChangedNotification,
            object: nil
        )

        refresh()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: Self.nowPlayingChangedNotification, object: nil)
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
        getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            self?.onNowPlayingChange?(NowPlaying(info: info))
        }
    }

    deinit { stop() }
}
