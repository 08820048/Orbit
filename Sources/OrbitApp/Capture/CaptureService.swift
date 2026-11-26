import AppKit
import CoreGraphics
import ImageIO
import OrbitCore
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenPermission {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }
    /// Shows the system prompt the first time; afterwards it does nothing, so the user has to use System Settings.
    @discardableResult static func request() -> Bool { CGRequestScreenCaptureAccess() }
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}

enum CaptureError: LocalizedError {
    case noPermission, noDisplay, encoding, saving(String)
    var errorDescription: String? {
        switch self {
        case .noPermission: "Orbit 还没有屏幕录制权限"
        case .noDisplay: "没有找到要截取的显示器"
        case .encoding: "图片编码失败"
        case let .saving(why): "无法保存截图：\(why)"
        }
    }
}

/// One display, frozen at the moment the shortcut was pressed.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    /// Pixels per point.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

/// A window we can hover over and capture.
struct CapturableWindow {
    let scWindow: SCWindow
    /// Frame in AppKit screen coordinates (origin bottom-left of the primary display).
    let frame: CGRect
    var title: String {
        let app = scWindow.owningApplication?.applicationName ?? ""
        let t = scWindow.title ?? ""
        return [app, t].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}

/// Talks to ScreenCaptureKit and turns pixels into files. Nothing here shows UI.
enum CaptureService {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Every screen as one native-resolution image.
    static func freezeScreens(includeCursor: Bool) async throws -> [FrozenScreen] {
        guard ScreenPermission.granted else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var out: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen), let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int((screen.frame.width * scale).rounded())
            config.height = Int((screen.frame.height * scale).rounded())
            config.showsCursor = includeCursor
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            out.append(FrozenScreen(screen: screen, image: image))
        }
        guard !out.isEmpty else { throw CaptureError.noDisplay }
        return out
    }

    /// Normal application windows on screen, frontmost first, as of now.
    static func windows() async throws -> [CapturableWindow] {
        guard ScreenPermission.granted else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CGWindowList is ordered front to back; SCShareableContent makes no such promise.
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var out: [CapturableWindow] = []
        for item in info {
            guard let number = item[kCGWindowNumber as String] as? CGWindowID,
                  (item[kCGWindowLayer as String] as? Int) == 0,
                  let sc = byID[number], sc.frame.width >= 40, sc.frame.height >= 40 else { continue }
            if sc.owningApplication?.processID == ownPID, sc.title == nil || sc.title?.isEmpty == true { continue }
            let f = sc.frame   // Quartz coordinates: origin top-left of the primary display
            out.append(CapturableWindow(scWindow: sc, frame: CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)))
        }
        return out
    }

    /// A single window, without its shadow, regardless of what covers it.
    static func captureWindow(_ window: CapturableWindow, includeCursor: Bool) async throws -> CGImage {
        guard ScreenPermission.granted else { throw CaptureError.noPermission }
        let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)
        let config = SCStreamConfiguration()
        let scale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = includeCursor
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: Encoding and saving

    static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data {
        let type: UTType = format == .png ? .png : .jpeg
        var source = image
        if format == .jpg, image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast {
            // JPEG has no transparency: flatten onto white instead of letting it turn black.
            if let flat = flattened(image) { source = flat }
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw CaptureError.encoding }
        let options: [CFString: Any] = format == .jpg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(dest, source, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.encoding }
        return data as Data
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// Writes the image into `folder` under a fresh "Orbit …" name and returns the record to index.
    static func save(_ image: CGImage, kind: CaptureKind, source: String?, scale: Double, format: ImageFormat,
                     folder: URL, date: Date = Date()) throws -> ScreenshotRecord {
        let data = try encode(image, as: format)
        let fm = FileManager.default
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { throw CaptureError.saving(error.localizedDescription) }
        let name = ScreenshotNaming.fileName(date: date, ext: format.fileExtension) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let url = folder.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic) } catch { throw CaptureError.saving(error.localizedDescription) }
        return ScreenshotRecord(path: url.path, createdAt: date, kind: kind, pixelWidth: image.width, pixelHeight: image.height,
                                scale: scale, byteCount: Int64(data.count), source: source)
    }
}
