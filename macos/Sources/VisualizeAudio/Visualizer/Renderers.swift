import SwiftUI

// Direct port of src/renderers.js. Each renderer takes the same per-bar data
// (already computed: position, height, color) and just differs in how it
// paints it — swapping display mode never touches the audio/color logic
// upstream. Keep in sync with renderers.js.

enum DisplayMode: String, CaseIterable {
    case normal = "Normal"
    case eightBit = "8-Bit"
    case curve = "Curve"
}

private func color(_ bar: Bar) -> Color {
    Color(red: bar.r / 255, green: bar.g / 255, blue: bar.b / 255)
}

func drawBarsNormal(_ context: GraphicsContext, height: Double, bars: [Bar], barWidth: Double) {
    for bar in bars {
        let rect = CGRect(x: bar.x, y: height - bar.height, width: barWidth * 0.8, height: bar.height)
        context.fill(Path(rect), with: .color(color(bar)))
    }
}

private let pixelGroup = 4 // bars grouped together per chunky "pixel" column
private let levels = 10 // discrete height steps, like a retro LED EQ
private let colorStep = 36.0 // quantized color depth

private func quantize(_ v: Double, _ step: Double) -> Double {
    min(255, (v / step).rounded() * step)
}

func drawBars8Bit(_ context: GraphicsContext, height: Double, bars: [Bar], barWidth: Double) {
    let groupWidth = barWidth * Double(pixelGroup)
    let segmentHeight = height / Double(levels)

    var g = 0
    while g < bars.count {
        let group = bars[g..<min(g + pixelGroup, bars.count)]
        if group.isEmpty { g += pixelGroup; continue }

        var sumHeight = 0.0, sumR = 0.0, sumG = 0.0, sumB = 0.0
        for bar in group {
            sumHeight += bar.height
            sumR += bar.r
            sumG += bar.g
            sumB += bar.b
        }
        let count = Double(group.count)
        let avgHeight = sumHeight / count
        let r = quantize(sumR / count, colorStep)
        let gCol = quantize(sumG / count, colorStep)
        let b = quantize(sumB / count, colorStep)
        let levelCount = max(0, Int((avgHeight / height * Double(levels)).rounded()))

        let fillColor = Color(red: r / 255, green: gCol / 255, blue: b / 255)
        let x = group.first!.x
        for lvl in 0..<levelCount {
            let y = height - Double(lvl + 1) * segmentHeight
            let rect = CGRect(x: x, y: y + 2, width: groupWidth * 0.85, height: segmentHeight - 4)
            context.fill(Path(rect), with: .color(fillColor))
        }
        g += pixelGroup
    }
}

func drawCurveArea(_ context: GraphicsContext, width: Double, height: Double, bars: [Bar]) {
    guard !bars.isEmpty else { return }

    var sumR = 0.0, sumG = 0.0, sumB = 0.0
    for bar in bars {
        sumR += bar.r
        sumG += bar.g
        sumB += bar.b
    }
    let n = Double(bars.count)
    let avgR = (sumR / n).rounded()
    let avgG = (sumG / n).rounded()
    let avgB = (sumB / n).rounded()

    var path = Path()
    path.move(to: CGPoint(x: 0, y: height))
    path.addLine(to: CGPoint(x: bars[0].x, y: height - bars[0].height))
    for i in 1..<bars.count {
        let prev = bars[i - 1]
        let curr = bars[i]
        let midX = (prev.x + curr.x) / 2
        let midY = height - (prev.height + curr.height) / 2
        path.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: height - prev.height))
    }
    let last = bars[bars.count - 1]
    path.addLine(to: CGPoint(x: width, y: height - last.height))
    path.addLine(to: CGPoint(x: width, y: height))
    path.closeSubpath()

    let gradient = Gradient(stops: [
        .init(color: Color(red: avgR / 255, green: avgG / 255, blue: avgB / 255).opacity(0.85), location: 0),
        .init(color: Color(red: avgR / 255, green: avgG / 255, blue: avgB / 255).opacity(0.05), location: 1),
    ])
    context.fill(
        path,
        with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height))
    )
    context.stroke(path, with: .color(Color(red: avgR / 255, green: avgG / 255, blue: avgB / 255)), lineWidth: 2)
}
