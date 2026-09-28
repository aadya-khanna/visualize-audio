import AppKit
import Foundation

/// Resolves album art / video thumbnails for the current now-playing item.
/// JXA cannot return artwork on macOS 15.4+, so we layer fallbacks:
/// embedded MediaRemote bytes (when available) → YouTube thumbnail from browser URL
/// → iTunes Search artwork for music → playing app's icon.
actor ArtworkResolver {
    private var cache: [String: NSImage] = [:]

    func resolve(for item: NowPlaying) async -> NSImage? {
        if let artwork = item.artwork {
            cache[item.trackIdentity] = artwork
            return artwork
        }

        if let cached = cache[item.trackIdentity] {
            return cached
        }

        if let artwork = await fetchYouTubeThumbnail(bundleIdentifier: item.bundleIdentifier) {
            cache[item.trackIdentity] = artwork
            return artwork
        }

        if let artwork = await fetchITunesArtwork(title: item.title, artist: item.artist, album: item.album) {
            cache[item.trackIdentity] = artwork
            return artwork
        }

        if let artwork = appIcon(for: item.bundleIdentifier) {
            cache[item.trackIdentity] = artwork
            return artwork
        }

        return nil
    }

    private func fetchYouTubeThumbnail(bundleIdentifier: String?) async -> NSImage? {
        guard let bundleIdentifier,
              let browser = Self.browserScripts[bundleIdentifier],
              let pageURL = runAppleScript(browser.script),
              let videoID = Self.youtubeVideoID(from: pageURL),
              let thumbnailURL = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
        else { return nil }

        return await downloadImage(from: thumbnailURL)
    }

    private func fetchITunesArtwork(title: String?, artist: String?, album: String?) async -> NSImage? {
        let query = [artist, title, album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let results = json["results"] as? [[String: Any]],
                let first = results.first,
                let artworkURLString = first["artworkUrl100"] as? String,
                let artworkURL = URL(string: artworkURLString.replacingOccurrences(of: "100x100", with: "600x600"))
            else { return nil }
            return await downloadImage(from: artworkURL)
        } catch {
            return nil
        }
    }

    private func appIcon(for bundleIdentifier: String?) -> NSImage? {
        guard
            let bundleIdentifier,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func downloadImage(from url: URL) async -> NSImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let url = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url, !url.isEmpty, url.hasPrefix("http") else { return nil }
        return url
    }

    private static func youtubeVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first
            return id?.isEmpty == false ? id : nil
        }

        guard host.contains("youtube.com") || host.contains("youtube-nocookie.com") else { return nil }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let id = items.first(where: { $0.name == "v" })?.value,
           !id.isEmpty {
            return id
        }
        return nil
    }

    private struct BrowserScript {
        let script: String
    }

    private static let browserScripts: [String: BrowserScript] = [
        "com.google.Chrome": BrowserScript(script: """
            tell application "Google Chrome"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """),
        "com.apple.Safari": BrowserScript(script: """
            tell application "Safari"
                if (count of windows) = 0 then return ""
                return URL of current tab of front window
            end tell
            """),
        "company.thebrowser.Browser": BrowserScript(script: """
            tell application "Arc"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """),
        "org.mozilla.firefox": BrowserScript(script: """
            tell application "Firefox"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """),
        "com.brave.Browser": BrowserScript(script: """
            tell application "Brave Browser"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """),
        "com.microsoft.edgemac": BrowserScript(script: """
            tell application "Microsoft Edge"
                if (count of windows) = 0 then return ""
                return URL of active tab of front window
            end tell
            """),
    ]
}
