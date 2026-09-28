import AppKit
import Foundation

// Model for whatever MediaRemoteBridge reports. Field names are the
// (unofficial, reverse-engineered but widely used by third-party "now
// playing" utilities) MediaRemote dictionary keys — see MediaRemoteBridge.swift.
struct NowPlaying: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var bundleIdentifier: String?
    var artwork: NSImage?
    var isPlaying: Bool

    var trackIdentity: String {
        [bundleIdentifier, title, artist, album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
    }

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.trackIdentity == rhs.trackIdentity && lhs.isPlaying == rhs.isPlaying
    }

    init(
        title: String?,
        artist: String?,
        album: String?,
        isPlaying: Bool,
        bundleIdentifier: String? = nil,
        artwork: NSImage? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.bundleIdentifier = bundleIdentifier
        self.artwork = artwork
    }

    init?(info: NSDictionary, keys: MediaRemoteBridge.InfoKeys = .defaults) {
        guard info.count > 0 else { return nil }
        title = Self.string(info, keys.title)
        artist = Self.string(info, keys.artist)
        album = Self.string(info, keys.album)
        artwork = Self.data(info, keys.artworkData).flatMap { NSImage(data: $0) }
        let rate = Self.double(info, keys.playbackRate)
        isPlaying = rate > 0
        bundleIdentifier = nil

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

    private static func data(_ info: NSDictionary, _ key: String) -> Data? {
        switch info[key] {
        case let value as Data:
            return value
        case let value as NSData:
            return value as Data
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
