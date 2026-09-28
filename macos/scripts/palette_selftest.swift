// Standalone diagnostic for the album color pipeline: feeds synthetic covers
// with known colors (and, given file paths, real artwork) through the real
// AlbumPaletteExtractor and prints what each bar would be painted, as ANSI
// color blocks. Unlike the audio path, image -> palette is a pure function, so
// it can be checked from the command line with no tap, no permissions and no
// music playing.
//
// Run with (it needs the real Visualizer sources compiled alongside it):
//   ./scripts/palette_selftest.sh              # synthetic covers
//   ./scripts/palette_selftest.sh cover.jpg    # a real cover, by path
//
// What a correct run looks like: for every case, the "hues painted" line lists
// only hues that appear in the input. Seeing a full red -> orange -> yellow ->
// green -> cyan -> blue -> violet spread from a two-color cover is the
// rainbow-gradient bug this pipeline was rewritten to remove — the bars must
// show the album's own colors going lighter and darker, never invented hues.

import AppKit
import Foundation

// MARK: - reporting helpers

func hsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
    let rN = r / 255, gN = g / 255, bN = b / 255
    let maxV = max(rN, gN, bN), minV = min(rN, gN, bN)
    let l = (maxV + minV) / 2
    let delta = maxV - minV
    guard delta > 0.0001 else { return (0, 0, l) }
    let s = l > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)
    var h: Double
    if maxV == rN { h = 60 * ((gN - bN) / delta) }
    else if maxV == gN { h = 60 * ((bN - rN) / delta + 2) }
    else { h = 60 * ((rN - gN) / delta + 4) }
    if h < 0 { h += 360 }
    return (h, s, l)
}

func hueName(_ h: Double, _ s: Double) -> String {
    guard s > 0.12 else { return "grey" }
    let names: [(Double, String)] = [
        (15, "red"), (45, "orange"), (70, "yellow"), (160, "green"),
        (200, "cyan"), (255, "blue"), (290, "violet"), (340, "magenta"), (361, "red"),
    ]
    for (bound, name) in names where h < bound { return name }
    return "red"
}

func swatchBlock(_ r: Double, _ g: Double, _ b: Double) -> String {
    String(format: "\u{1B}[48;2;%d;%d;%dm  \u{1B}[0m", Int(r), Int(g), Int(b))
}

/// Collapses a run-length sequence of hue names for the summary line.
func distinctRun(_ names: [String]) -> [String] {
    var out: [String] = []
    for name in names where out.last != name { out.append(name) }
    return out
}

// MARK: - synthetic covers

/// Builds a cover from proportional horizontal color blocks.
func makeCover(_ blocks: [(NSColor, Double)], side: Int = 300) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let total = blocks.reduce(0.0) { $0 + $1.1 }
    var y = 0.0
    for (color, share) in blocks {
        color.setFill()
        let height = Double(side) * share / total
        NSRect(x: 0, y: y, width: Double(side), height: height).fill()
        y += height
    }
    image.unlockFocus()
    return image
}

func rgb255(_ color: NSColor) -> (Double, Double, Double) {
    let c = color.usingColorSpace(.deviceRGB)!
    return (c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
}

/// Shortest angular distance between two hues.
func hueGap(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
}

/// Every bar is painted one of the cover's own colors, drifted at most
/// `AlbumPalette.hueDrift` degrees either way, so any painted hue further than
/// that from every album hue is an invented one. Near-grey pixels are skipped —
/// their hue is meaningless at that little chroma.
let driftTolerance = 14.0

func strayHues(painted: [(h: Double, s: Double)], album: [Double]) -> [Double] {
    var stray: [Double] = []
    for (hue, saturation) in painted where saturation > 0.12 {
        guard !album.contains(where: { hueGap($0, hue) <= driftTolerance }) else { continue }
        if !stray.contains(where: { hueGap($0, hue) < 8 }) { stray.append(hue) }
    }
    return stray
}

/// Renders a mock of the actual bar field to a PNG — the same per-bar colors
/// the app would draw, over the app's background, with a plausible spectrum
/// shape for bar heights. Much faster to judge than reading hue names.
func writePreview(_ palette: AlbumPalette, to path: String, label: String, time: TimeInterval) {
    let width = 960, height = 260, bars = barCountForReport
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(calibratedRed: 8 / 255, green: 8 / 255, blue: 16 / 255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: Double(width), height: Double(height)).fill()

    let barWidth = Double(width) / Double(bars)
    for i in 0..<bars {
        // A plausible spectrum: loud low end rolling off, plus some jitter, so
        // the loudness-driven lightness varies bar to bar like it does live.
        let t = Double(i) / Double(bars)
        let envelope = pow(1 - t, 1.3) * 0.75 + 0.12
        let wobble = 0.12 * sin(Double(i) * 1.9) + 0.08 * sin(Double(i) * 0.7)
        let loudness = min(1, max(0.02, envelope + wobble))

        let c = palette.color(barIndex: i, barCount: bars, loudness: loudness, time: time)
        NSColor(calibratedRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1).setFill()
        NSRect(x: Double(i) * barWidth, y: 0, width: barWidth - 1, height: loudness * Double(height) * 0.9).fill()
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("    preview: \(path)  (\(label))")
}

// MARK: - the report

let barCountForReport = 96
let extractor = AlbumPaletteExtractor()
/// Set by `--png <dir>`: where to drop rendered previews of the bar field.
var previewDirectory: String?

func report(_ label: String, artwork: NSImage, inputs: [(NSColor, Double)]) async {
    print("\n\u{1B}[1m\(label)\u{1B}[0m")

    if !inputs.isEmpty {
        print("  input colors:")
        for (color, share) in inputs {
            let (r, g, b) = rgb255(color)
            let (h, s, l) = hsl(r, g, b)
            let chroma = (max(r, g, b) - min(r, g, b)) / 255
            print(String(format: "    %3.0f%%  %@ hue %6.1f  chroma %.2f  light %.2f  (%@)",
                         share * 100, swatchBlock(r, g, b), h, chroma, l, hueName(h, s)))
        }
    }

    let item = NowPlaying(title: label, artist: nil, album: nil, isPlaying: true, artwork: artwork)
    guard let palette = await extractor.palette(for: item) else {
        print("  \u{1B}[31m-> no palette extracted\u{1B}[0m")
        return
    }

    print("  extracted album colors (\(palette.swatches.count), in band order):")
    for swatch in palette.swatches {
        let c = hslPreview(swatch)
        let (_, s, _) = hsl(c.0, c.1, c.2)
        print(String(format: "    %@ hue %6.1f  chroma %.2f  light %.2f  share %4.1f%%  (%@)",
                     swatchBlock(c.0, c.1, c.2), swatch.hue, swatch.chroma,
                     swatch.lightness, swatch.weight * 100, hueName(swatch.hue, s)))
    }

    if let dir = previewDirectory {
        let safe = String(label.prefix(40).map { $0.isLetter || $0.isNumber ? $0 : "_" })
        // A few seconds apart, to show the drift actually moving.
        for (index, time) in [0.0, 6.0, 13.0].enumerated() {
            writePreview(palette, to: "\(dir)/\(safe)_t\(index).png", label: "\(label) @ t=\(time)s", time: time)
        }
    }

    // Every painted hue must be one of the album's own, or sit between two of
    // them on the short way round (an RGB blend of two album colors). A hue
    // outside that set is an invented one — the rainbow regression.
    let albumHues = palette.swatches.map(\.hue)

    // Two loudness snapshots: silence, and a loud frame. The hues must be
    // identical between them — only the tone should move.
    for (caption, loudness) in [("quiet (loudness 0.05)", 0.05), ("loud  (loudness 0.85)", 0.85)] {
        var line = ""
        var names: [String] = []
        var paintedHues: [(h: Double, s: Double)] = []
        for i in 0..<barCountForReport {
            let c = palette.color(barIndex: i, barCount: barCountForReport, loudness: loudness, time: 0)
            if i % 2 == 0 { line += swatchBlock(c.r, c.g, c.b) }
            let (h, s, _) = hsl(c.r, c.g, c.b)
            names.append(hueName(h, s))
            paintedHues.append((h, s))
            // Sweep a full drift cycle so the check covers every hue the bar
            // will ever be painted, not just the one at t=0.
            for step in 0..<24 {
                let t = Double(step) * 1.7
                let drifted = palette.color(barIndex: i, barCount: barCountForReport, loudness: loudness, time: t)
                let (dh, ds, _) = hsl(drifted.r, drifted.g, drifted.b)
                paintedHues.append((dh, ds))
            }
        }
        print("  \(caption):")
        print("    \(line)")
        print("    hues painted: \(distinctRun(names).joined(separator: " -> "))")
        if loudness > 0.5 {
            // How far each bar's hue actually travels over a drift cycle, and
            // how far the whole field ever strays from an album color.
            var travels: [Double] = []
            var worstStray = 0.0
            for i in 0..<barCountForReport {
                var seen: [Double] = []
                for step in 0..<40 {
                    let c = palette.color(barIndex: i, barCount: barCountForReport, loudness: loudness, time: Double(step) * 1.1)
                    let (h, sat, _) = hsl(c.r, c.g, c.b)
                    guard sat > 0.12 else { continue }
                    seen.append(h)
                    worstStray = max(worstStray, albumHues.map { hueGap($0, h) }.min() ?? 0)
                }
                if seen.count > 1 {
                    let reference = seen[0]
                    let offsets = seen.map { hue -> Double in
                        var d = hue - reference
                        if d > 180 { d -= 360 }; if d < -180 { d += 360 }
                        return d
                    }
                    travels.append((offsets.max() ?? 0) - (offsets.min() ?? 0))
                }
            }
            if !travels.isEmpty {
                let mean = travels.reduce(0, +) / Double(travels.count)
                print(String(format: "    drift: each bar sweeps %.1f° on average (max %.1f°); never more than %.1f° from an album color",
                             mean, travels.max() ?? 0, worstStray))
            }
        }
        let invented = strayHues(painted: paintedHues, album: albumHues)
        if invented.isEmpty {
            print("    \u{1B}[32mok\u{1B}[0m — every painted hue is one of the album's colors")
        } else {
            let list = invented.map { String(format: "%.0f°", $0) }.joined(separator: ", ")
            print("    \u{1B}[31mINVENTED HUES: \(list)\u{1B}[0m")
        }
    }
}

/// Renders a swatch at its own album lightness, just for the printed preview.
func hslPreview(_ swatch: AlbumPalette.Swatch) -> (Double, Double, Double) {
    let span = 1 - abs(2 * swatch.lightness - 1)
    let saturation = span > 0.001 ? min(1, swatch.chroma / span) : 0
    let c = hslToRgb(h: swatch.hue, s: saturation, l: swatch.lightness)
    return (c.r, c.g, c.b)
}

@main
enum PaletteSelfTest {
    static func main() async {
        var files = Array(CommandLine.arguments.dropFirst())
        if let flag = files.firstIndex(of: "--png"), flag + 1 < files.count {
            previewDirectory = files[flag + 1]
            files.removeSubrange(flag...(flag + 1))
        }

        if files.isEmpty {
            let cases: [(String, [(NSColor, Double)])] = [
                ("A. Two distinct colors — red cover with cyan accent", [
                    (NSColor(calibratedRed: 0.85, green: 0.12, blue: 0.10, alpha: 1), 0.75),
                    (NSColor(calibratedRed: 0.10, green: 0.75, blue: 0.80, alpha: 1), 0.25),
                ]),
                ("B. Dark moody cover — deep navy + muted crimson", [
                    (NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.28, alpha: 1), 0.70),
                    (NSColor(calibratedRed: 0.45, green: 0.10, blue: 0.16, alpha: 1), 0.30),
                ]),
                ("C. Pastel cover — soft pink + cream + mint", [
                    (NSColor(calibratedRed: 0.97, green: 0.78, blue: 0.83, alpha: 1), 0.40),
                    (NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.86, alpha: 1), 0.30),
                    (NSColor(calibratedRed: 0.80, green: 0.94, blue: 0.87, alpha: 1), 0.30),
                ]),
                ("D. Single strong hue — solid orange", [
                    (NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.10, alpha: 1), 1.0),
                ]),
                ("E. Dominant + tiny accent — 92% purple, 8% yellow", [
                    (NSColor(calibratedRed: 0.42, green: 0.15, blue: 0.70, alpha: 1), 0.92),
                    (NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.15, alpha: 1), 0.08),
                ]),
                ("F. One hue, two tones — navy + sky blue (must stay two colors)", [
                    (NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.35, alpha: 1), 0.55),
                    (NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.96, alpha: 1), 0.45),
                ]),
                ("G. Near-monochrome cover — black + white + grey", [
                    (NSColor(calibratedWhite: 0.02, alpha: 1), 0.5),
                    (NSColor(calibratedWhite: 0.98, alpha: 1), 0.3),
                    (NSColor(calibratedWhite: 0.50, alpha: 1), 0.2),
                ]),
                ("H. Hue-circle neighbours — crimson (350°) + orange (20°)", [
                    (NSColor(calibratedRed: 0.80, green: 0.08, blue: 0.22, alpha: 1), 0.5),
                    (NSColor(calibratedRed: 0.90, green: 0.45, blue: 0.15, alpha: 1), 0.5),
                ]),
            ]
            for (label, blocks) in cases {
                await report(label, artwork: makeCover(blocks), inputs: blocks)
            }
        } else {
            for path in files {
                guard let image = NSImage(contentsOfFile: path) else {
                    print("\n\u{1B}[31mcould not read \(path)\u{1B}[0m")
                    continue
                }
                await report((path as NSString).lastPathComponent, artwork: image, inputs: [])
            }
        }

        print("")
    }
}
