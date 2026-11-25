import AppKit

/// Resolves bundle identifiers to the name and icon the user recognizes.
@MainActor
public final class AppCatalog {
    public struct Info {
        public var bundleID: String
        public var name: String
        public var icon: NSImage
        /// The app is no longer installed; shown with a generic icon.
        public var isInstalled: Bool
    }

    private var cache: [String: Info] = [:]
    private var overrides: [String: String]

    public init(displayNameOverrides: [String: String] = [:]) {
        self.overrides = displayNameOverrides
    }

    public func setOverrides(_ overrides: [String: String]) {
        self.overrides = overrides
        cache.removeAll()
    }

    public func info(for bundleID: String) -> Info {
        if let hit = cache[bundleID] { return hit }
        let ws = NSWorkspace.shared
        let info: Info
        if let url = ws.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            // Finder's localized name first ("微信", not "WeChat"), then the bundle's own display name.
            let finderName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let name = overrides[bundleID]
                ?? (finderName.isEmpty ? nil : finderName)
                ?? bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundleID
            info = Info(bundleID: bundleID, name: name, icon: Self.normalized(ws.icon(forFile: url.path)), isInstalled: true)
        } else {
            let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
            info = Info(bundleID: bundleID, name: overrides[bundleID] ?? fallback,
                        icon: Self.normalized(ws.icon(for: .application)), isInstalled: false)
        }
        cache[bundleID] = info
        return info
    }

    /// Rasterizes a system icon into plain 8-bit sRGB. System icons can carry HDR / wide-gamut data that
    /// makes SwiftUI render whole share cards in an HDR color space, which exports as washed-out PNGs.
    static func normalized(_ image: NSImage, pixels: Int = 256) -> NSImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: 128, height: 128))
    }
}
