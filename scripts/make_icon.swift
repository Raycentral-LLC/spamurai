// Renders the 1024×1024 app icon: a crimson shield split by a katana slash.
// Usage: swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so y grows downward, like design tools.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background: deep ink with a warm glow behind the shield.
let bg = CGGradient(colorsSpace: space, colors: [color(0x1A0A10), color(0x07060A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(0xE6293D, 0.55), color(0xE6293D, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 500), endRadius: 470, options: [])

// Shield outline.
let shield = CGMutablePath()
shield.move(to: CGPoint(x: 512, y: 180))
shield.addCurve(to: CGPoint(x: 790, y: 290), control1: CGPoint(x: 600, y: 245), control2: CGPoint(x: 700, y: 280))
shield.addCurve(to: CGPoint(x: 512, y: 860), control1: CGPoint(x: 800, y: 560), control2: CGPoint(x: 700, y: 760))
shield.addCurve(to: CGPoint(x: 234, y: 290), control1: CGPoint(x: 324, y: 760), control2: CGPoint(x: 224, y: 560))
shield.addCurve(to: CGPoint(x: 512, y: 180), control1: CGPoint(x: 324, y: 280), control2: CGPoint(x: 424, y: 245))
shield.closeSubpath()

// The cut runs from upper right to lower left; each half shifts away from it.
let from = CGPoint(x: 830, y: 215), to = CGPoint(x: 190, y: 835)
let len = hypot(to.x - from.x, to.y - from.y)
let dir = CGPoint(x: (to.x - from.x) / len, y: (to.y - from.y) / len)
let normal = CGPoint(x: -dir.y, y: dir.x) // points to the lower-right half

func halfPlane(_ side: CGFloat) -> CGPath {
    // A big quad covering one side of the cut line.
    let far: CGFloat = 3000
    let p = CGMutablePath()
    let a = CGPoint(x: from.x - dir.x * far, y: from.y - dir.y * far)
    let b = CGPoint(x: from.x + dir.x * far, y: from.y + dir.y * far)
    p.move(to: a)
    p.addLine(to: b)
    p.addLine(to: CGPoint(x: b.x + normal.x * far * side, y: b.y + normal.y * far * side))
    p.addLine(to: CGPoint(x: a.x + normal.x * far * side, y: a.y + normal.y * far * side))
    p.closeSubpath()
    return p
}

let fill = CGGradient(colorsSpace: space, colors: [color(0xFF7340), color(0xE6293D), color(0x9E0F24)] as CFArray,
                      locations: [0, 0.55, 1])!
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
let gap: CGFloat = 13

for side in [CGFloat(-1), 1] {
    ctx.saveGState()
    ctx.translateBy(x: normal.x * gap * side, y: normal.y * gap * side)
    ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: color(0x000000, 0.6))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(halfPlane(side))
    ctx.clip()
    ctx.addPath(shield)
    ctx.clip()
    ctx.drawLinearGradient(fill, start: CGPoint(x: 300, y: 180), end: CGPoint(x: 720, y: 860), options: [])
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 260, y: 200), end: CGPoint(x: 520, y: 520), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// The blade: a tapered streak of light, widest in the middle, fading past the shield.
func streak(width: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    p.move(to: from)
    p.addQuadCurve(to: to, control: CGPoint(x: mid.x + normal.x * width, y: mid.y + normal.y * width))
    p.addQuadCurve(to: from, control: CGPoint(x: mid.x - normal.x * width, y: mid.y - normal.y * width))
    p.closeSubpath()
    return p
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: color(0xFF9A6A, 1))
ctx.setFillColor(color(0xFFE2D4, 0.9))
ctx.addPath(streak(width: 16))
ctx.fillPath()
ctx.restoreGState()
ctx.setFillColor(color(0xFFFFFF))
ctx.addPath(streak(width: 7))
ctx.fillPath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
