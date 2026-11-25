import AppKit
import SwiftUI

/// Pre-scales icons to the exact pixel size they are drawn at.
///
/// Letting SwiftUI shrink a 256–384 px icon to 20–40 pt in one step aliases (jagged edges, "noise").
/// Here the source is halved repeatedly with high-quality interpolation and then resampled to
/// `points × backing scale` pixels, so it is drawn 1:1. Results are cached per (image, size).
enum IconRaster {
    private static var cache: [String: NSImage] = [:]
    private static var sources: [NSImage] = []   // keeps ObjectIdentifier keys valid

    private static var scale: CGFloat { max(2, NSScreen.main?.backingScaleFactor ?? 2) }

    static func image(_ source: NSImage, points: CGFloat) -> NSImage {
        let key = "\(ObjectIdentifier(source).hashValue)@\(Int(points.rounded()))@\(Int(scale))"
        if let hit = cache[key] { return hit }
        guard var cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        let target = max(1, Int((points * scale).rounded()))
        while cg.width >= target * 2, cg.height >= target * 2, let half = resample(cg, width: cg.width / 2, height: cg.height / 2) { cg = half }
        guard cg.width != target || cg.height != target else { return store(key, source, NSImage(cgImage: cg, size: NSSize(width: points, height: points))) }
        guard let out = resample(cg, width: target, height: target) else { return source }
        return store(key, source, NSImage(cgImage: out, size: NSSize(width: points, height: points)))
    }

    private static func store(_ key: String, _ source: NSImage, _ image: NSImage) -> NSImage {
        if !sources.contains(where: { $0 === source }) { sources.append(source) }
        cache[key] = image
        return image
    }

    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// An app or glass icon drawn crisply at `size` points.
struct SharpIcon: View {
    let image: NSImage
    let size: CGFloat

    init(_ image: NSImage, _ size: CGFloat) { self.image = image; self.size = size }

    var body: some View {
        Image(nsImage: IconRaster.image(image, points: size))
            .resizable().interpolation(.high).antialiased(true)
            .frame(width: size, height: size)
    }
}
