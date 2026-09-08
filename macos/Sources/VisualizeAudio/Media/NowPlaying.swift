import AppKit
import Foundation

// Model for whatever MediaRemoteBridge reports. Field names are the
// (unofficial, reverse-engineered but widely used by third-party "now
// playing" utilities) MediaRemote dictionary keys — see MediaRemoteBridge.swift.
struct NowPlaying: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album && lhs.isPlaying == rhs.isPlaying
    }

    init?(info: NSDictionary) {
        guard info.count > 0 else { return nil }
        title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: artworkData)
        }
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        isPlaying = rate > 0

        guard title != nil || artist != nil else { return nil }
    }
}
