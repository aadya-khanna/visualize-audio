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

    init(title: String?, artist: String?, album: String?, isPlaying: Bool, artwork: NSImage? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.artwork = artwork
    }

    init?(info: NSDictionary, keys: MediaRemoteBridge.InfoKeys = .defaults) {
        guard info.count > 0 else { return nil }
        title = Self.string(info, keys.title)
        artist = Self.string(info, keys.artist)
        album = Self.string(info, keys.album)
        if let artworkData = info[keys.artworkData] as? Data {
            artwork = NSImage(data: artworkData)
        }
        let rate = Self.double(info, keys.playbackRate)
        isPlaying = rate > 0

        guard title != nil || artist != nil || album != nil else { return nil }
    }

    private static func string(_ info: NSDictionary, _ key: String) -> String? {
        switch info[key] {
        case let value as String:
            return value.isEmpty ? nil : value
        case let value as NSString:
            let string = value as String
            return string.isEmpty ? nil : string
        default:
            return nil
        }
    }

    private static func double(_ info: NSDictionary, _ key: String) -> Double {
        switch info[key] {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        default:
            return 0
        }
    }
}
