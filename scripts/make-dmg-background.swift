// Draws the disk image's window background (660 x 400 points) at 1x and 2x, writes a multi-resolution TIFF.
// Usage: swift scripts/make-dmg-background.swift Packaging/DMGBackground.tiff
import AppKit

let W: CGFloat = 660, H: CGFloat = 400
// Where release.sh places the icons (window coordinates, y from the top). The art is drawn around them.
let appCenter = CGPoint(x: 180, y: 196), dropCenter = CGPoint(x: 480, y: 196)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

func draw(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Flip to a top-left origin so the numbers match Finder's icon positions.
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

    // Sky
    NSGradient(colors: [rgb(8, 14, 32), rgb(14, 26, 62), rgb(24, 44, 104)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // Soft glow behind the middle
    NSGradient(colors: [rgb(70, 130, 255, 0.22), rgb(70, 130, 255, 0)])!
        .draw(fromCenter: CGPoint(x: W / 2, y: 230), radius: 0, toCenter: CGPoint(x: W / 2, y: 230), radius: 300, options: [])

    // Stars (fixed seed so the file is reproducible)
    var seed: UInt64 = 7
    func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
    for _ in 0..<70 {
        let x = rnd() * Double(W), y = rnd() * Double(H), r = 0.4 + rnd() * 1.0
        rgb(200, 220, 255, 0.25 + rnd() * 0.5).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }

    // A big faint orbit around the whole scene
    ctx.saveGState()
    ctx.translateBy(x: W / 2, y: 214); ctx.rotate(by: -12 * .pi / 180)
    rgb(150, 190, 255, 0.10).setStroke()
    let big = NSBezierPath(ovalIn: NSRect(x: -380, y: -120, width: 760, height: 240)); big.lineWidth = 1; big.stroke()
    ctx.restoreGState()

    // The path from the app to Applications: a dashed arc with a small planet and an arrow head.
    let a = CGPoint(x: appCenter.x + 86, y: appCenter.y - 6), b = CGPoint(x: dropCenter.x - 92, y: dropCenter.y - 6)
    let ctrl = CGPoint(x: (a.x + b.x) / 2, y: a.y - 44)
    let arc = NSBezierPath(); arc.move(to: a); arc.curve(to: b, controlPoint1: CGPoint(x: a.x + 60, y: ctrl.y), controlPoint2: CGPoint(x: b.x - 60, y: ctrl.y))
    arc.lineWidth = 2; arc.lineCapStyle = .round; arc.setLineDash([2, 7], count: 2, phase: 0)
    rgb(190, 215, 255, 0.55).setStroke(); arc.stroke()
    // arrow head at b, pointing along the tangent (down-right)
    let tangent = atan2(b.y - ctrl.y, 60.0)   // direction of the curve as it arrives at b
    let head = NSBezierPath()
    for side in [-1.0, 1.0] {
        let ang = tangent + .pi + side * 0.55
        let tip = CGPoint(x: b.x + 4, y: b.y + 2)
        if side < 0 { head.move(to: CGPoint(x: tip.x + 12 * cos(ang), y: tip.y + 12 * sin(ang))); head.line(to: tip) }
        else { head.line(to: CGPoint(x: tip.x + 12 * cos(ang), y: tip.y + 12 * sin(ang))) }
    }
    head.lineWidth = 2.4; head.lineCapStyle = .round; head.lineJoinStyle = .round
    rgb(210, 228, 255, 0.9).setStroke(); head.stroke()
    // planet riding the arc
    let t: CGFloat = 0.5, mt = 1 - t
    let p1 = CGPoint(x: a.x + 60, y: ctrl.y), p2 = CGPoint(x: b.x - 60, y: ctrl.y)
    let px = mt*mt*mt*a.x + 3*mt*mt*t*p1.x + 3*mt*t*t*p2.x + t*t*t*b.x
    let py = mt*mt*mt*a.y + 3*mt*mt*t*p1.y + 3*mt*t*t*p2.y + t*t*t*b.y
    NSGradient(colors: [rgb(196, 221, 255), rgb(79, 147, 255), rgb(11, 59, 168)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
        .draw(fromCenter: CGPoint(x: px - 2.5, y: py - 3), radius: 0, toCenter: CGPoint(x: px, y: py), radius: 8, options: [])
    NSGradient(colors: [rgb(79, 147, 255, 0.35), rgb(79, 147, 255, 0)])!
        .draw(fromCenter: CGPoint(x: px, y: py), radius: 0, toCenter: CGPoint(x: px, y: py), radius: 22, options: [])

    // Text
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern]
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        ctx.saveGState(); ctx.translateBy(x: 0, y: y + sz.height); ctx.scaleBy(x: 1, y: -1)   // text draws upright in a flipped context
        str.draw(at: NSPoint(x: (W - sz.width) / 2, y: 0))
        ctx.restoreGState()
    }
    text("ORBIT", size: 13, weight: .semibold, color: rgb(160, 195, 255, 0.85), y: 34, kern: 5)
    text("把 Orbit 拖到「应用程序」", size: 15, weight: .medium, color: rgb(235, 242, 255, 0.95), y: 338)
    text("Drag Orbit to Applications", size: 12, weight: .regular, color: rgb(160, 185, 230, 0.75), y: 362)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DMGBackground.tiff"
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dmgbg-\(getpid())")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for s in [1, 2] { try draw(scale: s).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("bg\(s)x.png")) }
// Keep the PNGs around for a preview; the TIFF carries both resolutions.
let tiff = NSImage(size: NSSize(width: W, height: H))
for s in [1, 2] { tiff.addRepresentation(draw(scale: s)) }
try tiff.tiffRepresentation!.write(to: URL(fileURLWithPath: out))
print("wrote \(out); previews in \(dir.path)")
