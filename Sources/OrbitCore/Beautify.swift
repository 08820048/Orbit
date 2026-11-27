import CoreGraphics
import Foundation

// MARK: - Colours and backgrounds

extension AnnotationColor {
    /// "7F5AF0" (with or without a leading #).
    public init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    public var hex: String {
        func c(_ x: Double) -> Int { max(0, min(255, Int((x * 255).rounded()))) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// What sits behind the screenshot. Stored as a string so the same forms ("builtin:", "custom:", "solid:") work for the
/// share editor and for beautified screenshots.
public enum BeautifyBackground: Equatable, Sendable {
    case none
    case solid(AnnotationColor)
    case gradient(AnnotationColor, AnnotationColor)
    case builtin(String)
    case custom(String)

    public init(string: String) {
        if string == "none" { self = .none; return }
        if string.hasPrefix("solid:"), let c = AnnotationColor(hex: String(string.dropFirst(6))) { self = .solid(c); return }
        if string.hasPrefix("gradient:") {
            let parts = string.dropFirst(9).split(separator: ",").map(String.init)
            if parts.count == 2, let a = AnnotationColor(hex: parts[0]), let b = AnnotationColor(hex: parts[1]) { self = .gradient(a, b); return }
        }
        if string.hasPrefix("builtin:") { self = .builtin(String(string.dropFirst(8))); return }
        if string.hasPrefix("custom:") { self = .custom(String(string.dropFirst(7))); return }
        self = Self.defaultGradient
    }

    public var string: String {
        switch self {
        case .none: "none"
        case let .solid(c): "solid:\(c.hex)"
        case let .gradient(a, b): "gradient:\(a.hex),\(b.hex)"
        case let .builtin(n): "builtin:\(n)"
        case let .custom(f): "custom:\(f)"
        }
    }

    public static let defaultGradient = BeautifyBackground.gradient(AnnotationColor(hex: "7F5AF0")!, AnnotationColor(hex: "2CB1F5")!)

    /// The gradient swatches offered in the inspector.
    public static let gradients: [(name: String, from: String, to: String)] = [
        (String(localized: "极光"), "7F5AF0", "2CB1F5"), (String(localized: "日落"), "FF8A5B", "FF4D8D"), (String(localized: "薄荷"), "1FD1A5", "2E7CF6"), (String(localized: "暖阳"), "F9D423", "FF4E50"),
        (String(localized: "深海"), "0F2027", "2C5364"), (String(localized: "石墨"), "232526", "414345"), (String(localized: "云白"), "FDFBFB", "EBEDEE"), (String(localized: "糖果"), "FBC2EB", "A6C1EE"),
    ]

    /// Perceived brightness 0...1 of the background (images count as dark): decides signature and title colours.
    public var luminance: Double {
        switch self {
        case let .solid(c): c.luminance
        case let .gradient(a, b): (a.luminance + b.luminance) / 2
        case .none, .builtin, .custom: 0.2
        }
    }
}

// MARK: - Style

public enum BeautifyFrame: String, Codable, CaseIterable, Sendable {
    case none, window, browser
    public var label: String { self == .none ? String(localized: "无") : self == .window ? String(localized: "窗口") : String(localized: "浏览器") }
    /// Height of the title bar in points.
    public var chromePoints: Double { self == .none ? 0 : self == .window ? 30 : 38 }
}

public enum BeautifyRatio: String, Codable, CaseIterable, Sendable {
    case auto = "自动", square = "1:1", portrait45 = "4:5", portrait34 = "3:4", wide = "16:9", tall = "9:16"
    /// width / height, or nil to fit the content.
    public var value: Double? {
        switch self {
        case .auto: nil
        case .square: 1
        case .portrait45: 4.0 / 5
        case .portrait34: 3.0 / 4
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        }
    }
}

/// How a screenshot is dressed up: background, spacing, corners, shadow, window frame, size, signature.
public struct BeautifyStyle: Equatable, Codable, Sendable {
    public var background: String = BeautifyBackground.defaultGradient.string
    /// Space around the window, in points.
    public var padding: Double = 48
    /// Corner radius in points.
    public var cornerRadius: Double = 14
    /// 0...1
    public var shadow: Double = 0.62
    public var frame: BeautifyFrame = .window
    /// Text in the title bar (window) or address pill (browser).
    public var title: String = ""
    public var ratio: BeautifyRatio = .auto
    public var showSignature = true
    public var signature: String = ""
    public var showWatermark = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BeautifyStyle()
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? d.padding
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? d.shadow
        frame = try c.decodeIfPresent(BeautifyFrame.self, forKey: .frame) ?? d.frame
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? d.title
        ratio = try c.decodeIfPresent(BeautifyRatio.self, forKey: .ratio) ?? d.ratio
        showSignature = try c.decodeIfPresent(Bool.self, forKey: .showSignature) ?? d.showSignature
        signature = try c.decodeIfPresent(String.self, forKey: .signature) ?? d.signature
        showWatermark = try c.decodeIfPresent(Bool.self, forKey: .showWatermark) ?? d.showWatermark
    }

    public var backgroundValue: BeautifyBackground { BeautifyBackground(string: background) }
}

public enum BeautifyPreset: String, CaseIterable, Identifiable, Sendable {
    case social = "社交媒体", document = "文档", clean = "纯净"
    public var id: String { rawValue }

    /// The preset's look. Title and signature text are kept from `base`, because they belong to the user, not the look.
    public func style(keeping base: BeautifyStyle = BeautifyStyle()) -> BeautifyStyle {
        var s = BeautifyStyle()
        s.title = base.title
        s.signature = base.signature
        s.ratio = base.ratio
        switch self {
        case .social:
            s.background = BeautifyBackground.defaultGradient.string
            s.padding = 48; s.cornerRadius = 14; s.shadow = 0.62; s.frame = .window
            s.showSignature = true; s.showWatermark = true
        case .document:
            s.background = "solid:EEF1F6"
            s.padding = 20; s.cornerRadius = 6; s.shadow = 0.18; s.frame = .none
            s.showSignature = false; s.showWatermark = false
        case .clean:
            s.background = "none"
            s.padding = 14; s.cornerRadius = 10; s.shadow = 0.35; s.frame = .none
            s.showSignature = false; s.showWatermark = false
        }
        return s
    }

    /// The preset a style still matches (ignoring title, signature text and size), for highlighting it.
    public static func matching(_ style: BeautifyStyle) -> BeautifyPreset? {
        allCases.first { $0.style(keeping: style) == style }
    }
}

// MARK: - Layout

/// Where everything goes on the finished canvas. Sizes are pixels, origin top-left.
public struct BeautifyLayout: Equatable, Sendable {
    public var canvas: CGSize
    /// The window: title bar (if any) plus the screenshot.
    public var window: CGRect
    /// Height of the title bar in pixels.
    public var chrome: Double
    /// The screenshot itself.
    public var content: CGRect
    public var padding: Double
    public var cornerRadius: Double

    public static func compute(content: CGSize, style: BeautifyStyle, pixelsPerPoint ppp: Double) -> BeautifyLayout {
        let chrome = style.frame.chromePoints * ppp
        let pad = max(0, style.padding) * ppp
        let w = content.width, h = content.height + chrome
        var cw = w + 2 * pad, ch = h + 2 * pad
        if let ratio = style.ratio.value {
            if cw / ch > ratio { ch = cw / ratio } else { cw = ch * ratio }
        }
        let window = CGRect(x: ((cw - w) / 2).rounded(), y: ((ch - h) / 2).rounded(), width: w, height: h)
        let contentRect = CGRect(x: window.minX, y: window.minY + chrome, width: content.width, height: content.height)
        return BeautifyLayout(canvas: CGSize(width: cw.rounded(), height: ch.rounded()), window: window, chrome: chrome,
                              content: contentRect, padding: pad, cornerRadius: max(0, style.cornerRadius) * ppp)
    }
}
