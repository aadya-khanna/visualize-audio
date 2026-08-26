// Each renderer takes the same per-bar data (already computed: position,
// height, color) and just differs in how it paints it — swapping display
// mode never touches the audio/color logic upstream.

export function drawBarsNormal(ctx, h, bars, barWidth) {
  for (const bar of bars) {
    ctx.fillStyle = `rgb(${bar.r}, ${bar.g}, ${bar.b})`
    ctx.fillRect(bar.x, h - bar.height, barWidth * 0.8, bar.height)
  }
}

const PIXEL_GROUP = 4 // bars grouped together per chunky "pixel" column
const LEVELS = 10 // discrete height steps, like a retro LED EQ
const COLOR_STEP = 36 // quantized color depth

function quantize(v, step) {
  return Math.min(255, Math.round(v / step) * step)
}

export function drawBars8Bit(ctx, h, bars, barWidth) {
  const groupWidth = barWidth * PIXEL_GROUP
  const segmentHeight = h / LEVELS

  for (let g = 0; g < bars.length; g += PIXEL_GROUP) {
    const group = bars.slice(g, g + PIXEL_GROUP)
    if (group.length === 0) continue

    let sumHeight = 0
    let sumR = 0
    let sumG = 0
    let sumB = 0
    for (const bar of group) {
      sumHeight += bar.height
      sumR += bar.r
      sumG += bar.g
      sumB += bar.b
    }
    const avgHeight = sumHeight / group.length
    const r = quantize(sumR / group.length, COLOR_STEP)
    const gCol = quantize(sumG / group.length, COLOR_STEP)
    const b = quantize(sumB / group.length, COLOR_STEP)
    const levelCount = Math.max(0, Math.round((avgHeight / h) * LEVELS))

    ctx.fillStyle = `rgb(${r}, ${gCol}, ${b})`
    const x = group[0].x
    for (let lvl = 0; lvl < levelCount; lvl++) {
      const y = h - (lvl + 1) * segmentHeight
      ctx.fillRect(x, y + 2, groupWidth * 0.85, segmentHeight - 4)
    }
  }
}

export function drawCurveArea(ctx, w, h, bars) {
  if (bars.length === 0) return

  let sumR = 0
  let sumG = 0
  let sumB = 0
  for (const bar of bars) {
    sumR += bar.r
    sumG += bar.g
    sumB += bar.b
  }
  const n = bars.length
  const avgR = Math.round(sumR / n)
  const avgG = Math.round(sumG / n)
  const avgB = Math.round(sumB / n)

  ctx.beginPath()
  ctx.moveTo(0, h)
  ctx.lineTo(bars[0].x, h - bars[0].height)
  for (let i = 1; i < bars.length; i++) {
    const prev = bars[i - 1]
    const curr = bars[i]
    const midX = (prev.x + curr.x) / 2
    const midY = h - (prev.height + curr.height) / 2
    ctx.quadraticCurveTo(prev.x, h - prev.height, midX, midY)
  }
  const last = bars[bars.length - 1]
  ctx.lineTo(w, h - last.height)
  ctx.lineTo(w, h)
  ctx.closePath()

  const gradient = ctx.createLinearGradient(0, 0, 0, h)
  gradient.addColorStop(0, `rgba(${avgR}, ${avgG}, ${avgB}, 0.85)`)
  gradient.addColorStop(1, `rgba(${avgR}, ${avgG}, ${avgB}, 0.05)`)
  ctx.fillStyle = gradient
  ctx.fill()

  ctx.strokeStyle = `rgb(${avgR}, ${avgG}, ${avgB})`
  ctx.lineWidth = 2
  ctx.stroke()
}
