import AppKit

// Draws the Tab Groups app icon at 1024pt: a window with a tab bar on top, on a blue rounded square.
let size: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // top-left origin

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func rounded(_ rect: CGRect, tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
    p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
    p.closeSubpath()
    return p
}
func fill(_ path: CGPath, _ c: CGColor) { ctx.addPath(path); ctx.setFillColor(c); ctx.fillPath() }
func pill(_ rect: CGRect, _ c: CGColor) { fill(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil), c) }

// Plate with the standard macOS icon margins and a soft shadow.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
fill(platePath, color(0x2F6BEA))
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(platePath); ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(0x5AA2FF), color(0x2350D8)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
// A soft highlight across the top, like light on glass.
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.minY + 330), options: [])
ctx.restoreGState()

// The tab bar: a frosted strip with two tabs.
let left: CGFloat = 212, right: CGFloat = 812
let barTop: CGFloat = 318, barHeight: CGFloat = 104
let bar = CGRect(x: left, y: barTop, width: right - left, height: barHeight + 40)
fill(rounded(bar, tl: 44, tr: 44, br: 0, bl: 0), color(0xFFFFFF, 0.30))

// The window, sitting under the bar.
let windowRect = CGRect(x: left, y: barTop + barHeight, width: right - left, height: 300)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x0B1E66, 0.35))
fill(rounded(windowRect, tl: 0, tr: 40, br: 44, bl: 44), color(0xFFFFFF))
ctx.restoreGState()

// Selected tab: white, joined to the window. Second tab: a quiet pill.
let tabHeight: CGFloat = barHeight - 16
let selected = CGRect(x: left, y: barTop + 16, width: 290, height: tabHeight + 2)
fill(rounded(selected, tl: 36, tr: 36, br: 0, bl: 0), color(0xFFFFFF))
let other = CGRect(x: left + 306, y: barTop + 22, width: 270, height: tabHeight - 14)
fill(CGPath(roundedRect: other, cornerWidth: 30, cornerHeight: 30, transform: nil), color(0xFFFFFF, 0.28))

// Tab contents: an app dot and a title line each.
func dot(_ x: CGFloat, _ y: CGFloat, _ c: CGColor) { fill(CGPath(ellipseIn: CGRect(x: x, y: y, width: 44, height: 44), transform: nil), c) }
dot(selected.minX + 30, selected.midY - 22, color(0xFF8A3D))
pill(CGRect(x: selected.minX + 92, y: selected.midY - 10, width: 150, height: 20), color(0x1B2A4A, 0.30))
dot(other.minX + 26, other.midY - 22, color(0x34D17A))
pill(CGRect(x: other.minX + 88, y: other.midY - 10, width: 140, height: 20), color(0xFFFFFF, 0.75))

// Window contents: a sidebar and a few lines.
let sidebar = CGRect(x: windowRect.minX, y: windowRect.minY, width: 170, height: windowRect.height)
fill(rounded(sidebar, tl: 0, tr: 0, br: 0, bl: 44), color(0xEEF2FA))
for (i, w) in [96.0, 78.0, 104.0].enumerated() {
    pill(CGRect(x: sidebar.minX + 34, y: sidebar.minY + 50 + CGFloat(i) * 52, width: w, height: 20), color(0x1B2A4A, 0.18))
}
for (i, w) in [330.0, 270.0, 300.0, 190.0].enumerated() {
    pill(CGRect(x: sidebar.maxX + 46, y: windowRect.minY + 56 + CGFloat(i) * 56, width: w, height: 22),
         color(0x1B2A4A, i == 0 ? 0.34 : 0.14))
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
