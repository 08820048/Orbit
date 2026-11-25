import AppKit
import SwiftUI

/// A hand-made entry for things that are not installed .app bundles (Claude Code, Codex CLI, web apps…).
struct CustomApp: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// File name inside `CustomAppIcons.folder`; nil = generate a letter icon from the name.
    var iconFile: String?
    /// true: round-rect "app icon" (square art is cropped, transparent logos sit on `colorHex`); false: keep as is.
    var squircle = true
    var colorHex = "D97757"

    /// How it is referenced from a group's `bundleIDs`.
    var key: String { Self.prefix + id.uuidString }
    static let prefix = "custom:"
    static func isCustomKey(_ key: String) -> Bool { key.hasPrefix(prefix) }
}

enum CustomAppIcons {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orbit/CustomApps", isDirectory: true)
    }

    private static var cache: [String: NSImage] = [:]

    /// Stores the picture (re-encoded as PNG, at most 1024 px wide) and returns its file name.
    static func save(_ image: NSImage) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let small = BackgroundStore.normalized(image, maxWidth: 1024)
        guard let tiff = small.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = UUID().uuidString + ".png"
        try png.write(to: folder.appendingPathComponent(name))
        return name
    }

    static func delete(file: String?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }

    static func loadFile(_ file: String?) -> NSImage? {
        guard let file else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(file))
    }

    /// The finished icon (512 px, sRGB). `image` overrides the stored file (live preview in the editor).
    static func render(_ app: CustomApp, image override: NSImage? = nil) -> NSImage {
        let key = "\(app.id)|\(app.iconFile ?? "-")|\(app.squircle)|\(app.colorHex)|\(app.name.prefix(1))"
        if override == nil, let hit = cache[key] { return hit }
        let source = override ?? loadFile(app.iconFile)
        let result = draw(app, source: source)
        if override == nil { cache[key] = result }
        return result
    }

    private static func draw(_ app: CustomApp, source: NSImage?) -> NSImage {
        let px = 512
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: NSSize(width: 256, height: 256)) }
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let full = NSRect(x: 0, y: 0, width: px, height: px)
        let shape = NSBezierPath(roundedRect: full, xRadius: CGFloat(px) * 0.225, yRadius: CGFloat(px) * 0.225)
        let bg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let tint = (UInt32(app.colorHex, radix: 16)).map {
            NSColor(srgbRed: CGFloat(($0 >> 16) & 0xFF) / 255, green: CGFloat(($0 >> 8) & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
        } ?? bg

        func fit(_ image: NSImage, in rect: NSRect, fill: Bool) -> NSRect {
            let s = image.size
            guard s.width > 0, s.height > 0 else { return rect }
            let k = fill ? max(rect.width / s.width, rect.height / s.height) : min(rect.width / s.width, rect.height / s.height)
            let w = s.width * k, h = s.height * k
            return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        }

        if let image = source {
            if !app.squircle {
                image.draw(in: fit(image, in: full, fill: false), from: .zero, operation: .sourceOver, fraction: 1)
            } else if hasTransparency(image) {
                tint.setFill(); shape.fill()
                image.draw(in: fit(image, in: full.insetBy(dx: CGFloat(px) * 0.17, dy: CGFloat(px) * 0.17), fill: false),
                           from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                shape.addClip()
                image.draw(in: fit(image, in: full, fill: true), from: .zero, operation: .sourceOver, fraction: 1)
            }
        } else {
            tint.setFill(); shape.fill()
            let letter = String(app.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: CGFloat(px) * 0.5, weight: .bold), .foregroundColor: NSColor.white]
            let str = NSAttributedString(string: letter.isEmpty ? "?" : letter, attributes: attrs)
            let size = str.size()
            str.draw(at: NSPoint(x: full.midX - size.width / 2, y: full.midY - size.height / 2))
        }
        guard let cg = ctx.makeImage() else { return NSImage(size: NSSize(width: 256, height: 256)) }
        return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
    }

    /// Does the picture have see-through corners (a logo rather than full-bleed art)?
    private static func hasTransparency(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self)
        else { return false }
        ctx.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        let corners = [(0, 0), (15, 0), (0, 15), (15, 15)]
        return corners.contains { data[($0.1 * 16 + $0.0) * 4 + 3] < 200 }
    }
}
