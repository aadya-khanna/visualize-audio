import AppKit
import Foundation

/// The set of distinct colors lifted from an album cover / video thumbnail,
/// dealt out one per bar.
///
/// Deliberately **not** a hue gradient, and not a spatial layout either.
/// Interpolating *hue* between two album colors invents every hue in between —
/// a red-and-cyan cover sweeps through orange, yellow, green, blue and magenta,
/// none of which are in the artwork — so the visualizer read as a generic
/// rainbow no matter what was playing. Laying the colors out as regions
/// (contiguous bands, or scattered control points blended into each other) then
/// read as slabs: neighbouring bars in a region are near-identical, so at 96
/// bars the window looks like three or four chunks of color with visible
/// divides. So each bar instead picks one of the cover's colors outright, at
/// random, and the only thing that animates is a slow drift in that bar's own
/// hue. Across the window that reads as the album's colors shimmering
/// together; no bar is ever painted a color the cover doesn't have.
struct AlbumPalette: Equatable {
    /// One distinct color found in the artwork.
    struct Swatch: Equatable {
        var hue: Double // 0-360
        /// Colorfulness as plain RGB chroma (max channel - min channel), *not*
        /// HSL saturation. HSL inflates saturation near white and black — a
        /// cream that is 4% away from white reports 0.76 saturation — so
        /// carrying HSL saturation and re-rendering it at a lower lightness
        /// turned pale colors into vivid ones (a cover's soft pink came out
        /// crimson). Chroma stays honest at every lightness.
        var chroma: Double // 0-1
        /// The artwork's own tone for this color. Kept (rather than thrown
        /// away in favour of a fixed mid-lightness) because it is most of what
        /// makes a cover recognizable: a dark album has to render dark.
        var lightness: Double // 0-1
        /// Share of the artwork's colored pixels, 0-1. Decides how often this
        /// color comes up in the deal, so a dominant color dominates the
        /// window too.
        var weight: Double
    }

    /// How far a bar's hue wanders either side of its color, in degrees. Small
    /// on purpose: this is the album's color breathing, not a trip around the
    /// color wheel, and anything much wider starts inventing hues again.
    private static let hueDrift = 10.0

    /// The cover's colors, heaviest first.
    let swatches: [Swatch]
    /// Cumulative shares for the weighted per-bar draw.
    private let cumulativeShares: [Double]
    /// Seeds the per-bar draw and drift. Derived from the colors themselves, so
    /// a given cover always deals the same way (the bars must not reshuffle
    /// mid-track) while different covers deal differently.
    private let seed: UInt64

    init(swatches: [Swatch]) {
        let ordered = swatches.isEmpty
            ? [Swatch(hue: 220, chroma: 0.2, lightness: 0.5, weight: 1)]
            : swatches.sorted { $0.weight > $1.weight }
        self.swatches = ordered

        // Floor each share before normalizing: a color that is a genuine 5% of
        // the cover would otherwise come up on two bars out of 96 and read as
        // a stray speck rather than one of the album's colors.
        let minShare = 0.45 / Double(ordered.count)
        let shares = ordered.map { max($0.weight, minShare) }
        let total = shares.reduce(0, +)
        var running = 0.0
        cumulativeShares = shares.map { running += $0 / total; return running }

        var hash: UInt64 = 0x9E37_79B9_7F4A_7C15
        for swatch in ordered {
            hash = hash &* 6364136223846793005 &+ UInt64(bitPattern: Int64(swatch.hue * 1000)) &+ 1
            hash = hash &* 6364136223846793005 &+ UInt64(bitPattern: Int64(swatch.lightness * 1000)) &+ 1
        }
        seed = hash
    }

    /// Color for one bar: the album color this bar was dealt, at a lightness
    /// driven by its loudness (0-1) and a hue drifting slowly with `time`.
    func color(barIndex: Int, barCount: Int, loudness: Double, time: TimeInterval) -> RGB {
        let swatch = swatches[swatchIndex(forBar: barIndex)]

        // Each bar drifts at its own rate and phase, so the field shimmers
        // rather than pulsing in lockstep. Periods land between about 15 and
        // 35 seconds — slow enough to read as the color breathing rather than
        // as an effect.
        let rate = 0.18 + random(barIndex, salt: 0x2F) * 0.25
        let phase = random(barIndex, salt: 0x51) * 2 * .pi
        let drift = sin(time * rate + phase)
        let hue = (swatch.hue + drift * Self.hueDrift + 360).truncatingRemainder(dividingBy: 360)

        // A fixed per-bar tone offset plus a slow one, on a different phase to
        // the hue, so neighbouring bars dealt the same color still differ.
        let toneRate = 0.13 + random(barIndex, salt: 0x77) * 0.19
        let tone = (random(barIndex, salt: 0xC3) - 0.5) * 0.16
            + sin(time * toneRate + random(barIndex, salt: 0xA9) * 2 * .pi) * 0.045

        return render(swatch, hue: hue, tone: tone, loudness: loudness)
    }

    /// Which album color a bar was dealt. A plain weighted draw off a per-bar
    /// hash: no stored table, so it works for any bar count, and it is stable
    /// for a given cover because the hash is seeded from the colors.
    private func swatchIndex(forBar barIndex: Int) -> Int {
        guard swatches.count > 1 else { return 0 }
        let pick = random(barIndex, salt: 0x1D)
        return cumulativeShares.firstIndex { pick < $0 } ?? swatches.count - 1
    }

    /// Deterministic value in 0..<1 for a bar, per salt.
    private func random(_ barIndex: Int, salt: UInt64) -> Double {
        var state = seed &+ UInt64(bitPattern: Int64(barIndex)) &* 0x9E37_79B9_7F4A_7C15 &+ salt
        state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
        state ^= state >> 31
        return Double(state >> 11) * (1.0 / 9007199254740992.0)
    }

    /// One album color as RGB, at a drifted hue and the loudness-driven point
    /// of its tonal range.
    private func render(_ swatch: Swatch, hue: Double, tone: Double, loudness: Double) -> RGB {
        // The tonal excursion: this color at its own album lightness when the
        // bar is loud, and a few stops darker when it's quiet. Clamping the
        // anchor first keeps relative order (a cover's dark color still renders
        // darker than its light one) while guaranteeing neither end goes
        // invisible against the near-black background or blows out to white.
        let anchor = min(0.72, max(0.22, swatch.lightness))
        let lightness = min(0.94, max(0.12, anchor - 0.24 + tone + loudness * 0.30))

        // Pale covers are genuinely low-chroma, so darkening them literally
        // drains them to grey in quiet passages and the album's colors stop
        // reading at all. Compensate the way pigment does: the further below
        // its own lightness a color is rendered, the more chroma it keeps.
        // Multiplicative, so a truly achromatic (grey) swatch stays at zero.
        let darkening = max(0, swatch.lightness - lightness)
        let chroma = min(1, swatch.chroma * (0.95 + loudness * 0.3) * (1 + darkening * 1.2))

        // Rebuild the HSL saturation that reproduces that chroma *at the
        // lightness being rendered* — chroma is (1 - |2L - 1|) * saturation,
        // so invert it. This is what keeps a pale color pale and a grey cover
        // grey instead of tinting it.
        let chromaSpan = 1 - abs(2 * lightness - 1)
        let saturation = chromaSpan > 0.001 ? min(1, chroma / chromaSpan) : 0
        return hslToRgb(h: hue, s: saturation, l: lightness)
    }
}

/// Extracts a small, cached palette from now-playing artwork, off the main
/// thread. Mirrors ArtworkResolver's actor + per-track cache shape.
actor AlbumPaletteExtractor {
    private var cache: [String: AlbumPalette] = [:]

    func palette(for item: NowPlaying) async -> AlbumPalette? {
        if let cached = cache[item.trackIdentity] {
            return cached
        }
        guard let image = item.artwork, let extracted = Self.extract(from: image) else {
            return nil
        }
        cache[item.trackIdentity] = extracted
        return extracted
    }

    nonisolated private static func extract(from image: NSImage) -> AlbumPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // A small downsample is plenty to find the image's dominant colors
        // and is much cheaper than scanning full resolution.
        let side = 32
        guard let pixels = downsampledPixels(cgImage, side: side), !pixels.isEmpty else { return nil }

        // Bucket in HSL by hue *and* lightness, not in RGB. Bucketing on hue
        // alone merges a cover's navy and its sky blue into one mid blue that
        // appears nowhere in the artwork; keeping the lightness axis is what
        // lets "the same hue, lighter and darker" survive as two real colors.
        struct Bucket {
            var count = 0
            var x = 0.0 // hue as a unit vector, so 350° and 10° average to 0°
            var y = 0.0
            var chroma = 0.0
            var lightness = 0.0
        }
        var buckets: [Int: Bucket] = [:]
        var neutralLightnesses: [Double] = []
        var neutralR = 0.0, neutralG = 0.0, neutralB = 0.0

        for (r, g, b) in pixels {
            let (hue, chroma, lightness) = rgbToHCL(r: r, g: g, b: b)
            // Pixels with this little chroma, or this close to black or white,
            // carry no trustworthy hue — they're matting, paper white or
            // shadow. Set them aside rather than dropping them: a
            // black-and-white cover is made entirely of them and still
            // deserves a palette (see below). Gating on chroma rather than HSL
            // saturation is what lets pastels through: a cream's HSL
            // saturation and a near-white's are both high, but their chroma
            // is honest about which one is actually a color. The old
            // 0.15-saturation / 0.92-lightness cut discarded pastels outright,
            // so a cream-and-pink cover lost its cream entirely.
            guard chroma > 0.05, lightness > 0.04, lightness < 0.97 else {
                neutralLightnesses.append(lightness)
                neutralR += r; neutralG += g; neutralB += b
                continue
            }
            let hueBucket = Int(hue / 15) % 24
            let lightnessBucket = Int(min(0.999, lightness) * 5)
            let key = hueBucket * 10 + lightnessBucket
            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.x += cos(hue * .pi / 180)
            bucket.y += sin(hue * .pi / 180)
            bucket.chroma += chroma
            bucket.lightness += lightness
            buckets[key] = bucket
        }

        guard !buckets.isEmpty else {
            // Nothing in the cover has a usable hue — a black-and-white or
            // sepia sleeve. Return its actual tonal range at near-zero
            // saturation instead of nil, so Album mode still shows something
            // derived from the artwork rather than silently falling back to
            // the generic mood colors.
            return monochromePalette(lightnesses: neutralLightnesses, r: neutralR, g: neutralG, b: neutralB)
        }

        // Buckets still split one real color across neighbouring cells
        // (shading, anti-aliasing). Merge greedily, largest first so big
        // clusters act as attractors — but only when the two agree on *both*
        // hue and lightness, so merging can't erase a light/dark pair.
        struct Cluster {
            var hue: Double
            var chroma: Double
            var lightness: Double
            var weight: Double
        }
        var clusters: [Cluster] = []
        for bucket in buckets.values.sorted(by: { $0.count > $1.count }) {
            let count = Double(bucket.count)
            var hue = atan2(bucket.y, bucket.x) * 180 / .pi
            if hue < 0 { hue += 360 }
            let candidate = Cluster(
                hue: hue,
                chroma: bucket.chroma / count,
                lightness: bucket.lightness / count,
                weight: count
            )
            if let index = clusters.firstIndex(where: {
                hueDistance($0.hue, candidate.hue) < 18 && abs($0.lightness - candidate.lightness) < 0.20
            }) {
                var existing = clusters[index]
                let total = existing.weight + candidate.weight
                existing.hue = circularMeanHue(existing.hue, existing.weight, candidate.hue, candidate.weight)
                existing.chroma = (existing.chroma * existing.weight + candidate.chroma * candidate.weight) / total
                existing.lightness = (existing.lightness * existing.weight + candidate.lightness * candidate.weight) / total
                existing.weight = total
                clusters[index] = existing
            } else {
                clusters.append(candidate)
            }
        }

        // Drop colors too small a share of the cover to be a real "album
        // color" — a few stray anti-aliased pixels shouldn't get a band.
        let totalWeight = clusters.reduce(0.0) { $0 + $1.weight }
        var significant = clusters.filter { $0.weight / totalWeight >= 0.05 }
        if significant.isEmpty {
            significant = Array(clusters.sorted { $0.weight > $1.weight }.prefix(1))
        }
        significant.sort { $0.weight > $1.weight }
        significant = Array(significant.prefix(5))

        // Re-normalize weights over the colors that survived, so band widths
        // reflect each color's share of what's actually being painted.
        let keptWeight = significant.reduce(0.0) { $0 + $1.weight }
        var swatches = significant.map {
            AlbumPalette.Swatch(
                hue: $0.hue,
                chroma: $0.chroma,
                lightness: $0.lightness,
                weight: $0.weight / keptWeight
            )
        }

        // One dominant color would leave the field flat. Fan it out into three
        // tones of *the same hue* — the album's color, darker and lighter —
        // rather than into invented neighbouring hues, which is what made a
        // solid-orange cover paint green, blue and magenta bars.
        if swatches.count == 1 {
            let base = swatches[0]
            swatches = [-0.16, 0.0, 0.16].map {
                AlbumPalette.Swatch(
                    hue: base.hue,
                    chroma: base.chroma,
                    lightness: min(0.95, max(0.05, base.lightness + $0)),
                    weight: 1.0 / 3.0
                )
            }
        }

        return AlbumPalette(swatches: swatches)
    }

    /// Palette for artwork with no usable hue anywhere (black-and-white or
    /// heavily sepia sleeves): the cover's real tonal spread, carrying only
    /// the faint tint its average pixel has.
    nonisolated private static func monochromePalette(lightnesses: [Double], r: Double, g: Double, b: Double) -> AlbumPalette? {
        guard lightnesses.count >= 8 else { return nil }
        let count = Double(lightnesses.count)
        // Whatever faint tint the average pixel has, and no more. Carrying the
        // real (possibly zero) chroma is the point: a black-and-white sleeve
        // has to render grey, and an earlier version that floored saturation
        // instead painted it dusty red.
        let (tintHue, tintChroma, _) = rgbToHCL(r: r / count, g: g / count, b: b / count)
        let sorted = lightnesses.sorted()
        // Spread the bands across the sleeve's own tonal range rather than a
        // fixed dark-to-light ramp, so a mostly-black sleeve stays mostly dark.
        var tones: [Double] = []
        for quantile in [0.1, 0.35, 0.6, 0.85, 0.98] {
            let tone = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * quantile))]
            // A sleeve that is half solid black repeats the same tone at
            // several quantiles; two identical bands are just one wider band.
            if tones.allSatisfy({ abs($0 - tone) > 0.08 }) { tones.append(tone) }
        }
        guard tones.count > 1 else { return nil }
        let swatches = tones.sorted().map {
            AlbumPalette.Swatch(
                hue: tintHue,
                chroma: min(0.06, tintChroma),
                lightness: $0,
                weight: 1 / Double(tones.count)
            )
        }
        return AlbumPalette(swatches: swatches)
    }

    nonisolated private static func downsampledPixels(_ cgImage: CGImage, side: Int) -> [(Double, Double, Double)]? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * side
        var pixelData = [UInt8](repeating: 0, count: side * side * bytesPerPixel)
        guard let context = CGContext(
            data: &pixelData,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var pixels: [(Double, Double, Double)] = []
        pixels.reserveCapacity(side * side)
        for i in 0..<(side * side) {
            let offset = i * bytesPerPixel
            guard pixelData[offset + 3] > 200 else { continue } // skip transparent padding
            pixels.append((Double(pixelData[offset]), Double(pixelData[offset + 1]), Double(pixelData[offset + 2])))
        }
        return pixels
    }

    /// Shortest angular distance between two hues on the 0-360 color circle.
    nonisolated private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }

    /// Weighted average of two hues via their unit vectors, so e.g. 350° and
    /// 10° (both "red") merge to 0° instead of drifting to a meaningless 180°.
    nonisolated private static func circularMeanHue(_ hueA: Double, _ weightA: Double, _ hueB: Double, _ weightB: Double) -> Double {
        let radA = hueA * .pi / 180, radB = hueB * .pi / 180
        let x = cos(radA) * weightA + cos(radB) * weightB
        let y = sin(radA) * weightA + sin(radB) * weightB
        var hue = atan2(y, x) * 180 / .pi
        if hue < 0 { hue += 360 }
        return hue
    }

    /// Hue, *chroma* and lightness. Chroma (the plain max-min channel spread)
    /// rather than HSL saturation — see `Swatch.chroma` for why.
    nonisolated private static func rgbToHCL(r: Double, g: Double, b: Double) -> (h: Double, c: Double, l: Double) {
        let rN = r / 255, gN = g / 255, bN = b / 255
        let maxV = max(rN, gN, bN), minV = min(rN, gN, bN)
        let l = (maxV + minV) / 2
        let delta = maxV - minV
        guard delta > 0.0001 else { return (0, 0, l) }

        var h: Double
        if maxV == rN {
            h = 60 * (((gN - bN) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxV == gN {
            h = 60 * ((bN - rN) / delta + 2)
        } else {
            h = 60 * ((rN - gN) / delta + 4)
        }
        if h < 0 { h += 360 }
        return (h, delta, l)
    }
}
