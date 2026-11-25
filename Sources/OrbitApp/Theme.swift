import AppKit
import SwiftUI

// Design tokens from the approved Doop canvas (Sk4PPlUPfx), Glass style.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that follows the system appearance.
    static func dynamic(dark: (UInt32, Double), light: (UInt32, Double)) -> Color {
        func ns(_ v: (UInt32, Double)) -> NSColor {
            NSColor(srgbRed: CGFloat((v.0 >> 16) & 0xFF) / 255, green: CGFloat((v.0 >> 8) & 0xFF) / 255,
                    blue: CGFloat(v.0 & 0xFF) / 255, alpha: v.1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

enum Theme {
    static let window = Color.dynamic(dark: (0x0A0F1C, 1), light: (0xE8EFFA, 1))
    static let sidebar = Color.dynamic(dark: (0xFFFFFF, 0.04), light: (0xFFFFFF, 0.55))
    static let panel = Color.dynamic(dark: (0xFFFFFF, 0.06), light: (0xFFFFFF, 0.72))
    static let control = Color.dynamic(dark: (0xFFFFFF, 0.09), light: (0x142868, 0.07))
    static let text = Color.dynamic(dark: (0xEEF3FF, 1), light: (0x0F1A33, 1))
    static let text2 = Color.dynamic(dark: (0x8FA3C8, 1), light: (0x5B6B8C, 1))
    static let line = Color.dynamic(dark: (0xFFFFFF, 0.10), light: (0x142868, 0.10))
    static let edge = Color.dynamic(dark: (0xFFFFFF, 0.16), light: (0xFFFFFF, 0.95))
    static let accent = Color.dynamic(dark: (0x3B82F6, 1), light: (0x1F6BEA, 1))
    static let accentHi = Color(hex: 0x7FB0FF)
    static let accentLo = Color(hex: 0x0B47C4)

    static let accentGradient = LinearGradient(
        colors: [accentHi.opacity(0.9), accent, accentLo], startPoint: .top, endPoint: .bottom)
}

/// Indices into the Glass icon pack (file number = index). See Design/GlassIcons.
enum GI {
    static let timer = 13, trend = 14, pie = 34, calendar = 28, stats = 27, orbit = 18
    static let share = 32, gear = 39, layout = 19, shield = 10, megaphone = 16, eye = 1
    static let sliders = 30, tag = 25, background = 22, swap = 29, download = 8, docs = 15
}

enum GlassIcons {
    private static var cache: [Int: NSImage] = [:]

    static func image(_ index: Int) -> NSImage {
        if let hit = cache[index] { return hit }
        let url = Bundle.module.url(forResource: "glass-\(index)", withExtension: "png", subdirectory: "GlassIcons")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        cache[index] = image
        return image
    }
}

struct GlassIcon: View {
    let index: Int
    var size: CGFloat = 28

    var body: some View {
        SharpIcon(GlassIcons.image(index), size)
            .shadow(color: Color(hex: 0x0A3CAA, opacity: 0.28), radius: size * 0.12, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// Frosted panel used for cards.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.edge, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 20) -> some View { modifier(GlassPanel(radius: radius)) }
}

struct GlassButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Theme.text)
            .padding(.horizontal, 15).frame(height: 30)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accentGradient)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(primary ? Color.white.opacity(0.25) : Theme.line, lineWidth: 0.5))
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/// Window ground with the soft blue glows from the design.
struct WindowBackground: View {
    var body: some View {
        ZStack {
            Theme.window
            RadialGradient(colors: [Theme.accent.opacity(0.30), .clear], center: .init(x: 0.9, y: -0.05), startRadius: 0, endRadius: 600)
            RadialGradient(colors: [Color(hex: 0x1E5ADC, opacity: 0.22), .clear], center: .init(x: 0.05, y: 1.05), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// Segmented control in the Glass style.
struct GlassSegmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    var fill = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Text(label(option))
                    .font(.system(size: 12))
                    .foregroundStyle(selection == option ? Color.white : Theme.text2)
                    .frame(minWidth: 40, maxWidth: fill ? .infinity : nil).frame(height: 24)
                    .background {
                        if selection == option {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accentGradient)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection = option } }
            }
        }
        .padding(2)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct GlassToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Capsule().fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.control))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            }
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }
            .accessibilityAddTraits(.isButton)
    }
}

/// ScrollView that can be flattened for offscreen verification renders (ImageRenderer skips ScrollView content).
struct OScroll<Content: View>: View {
    static var flat: Bool { ProcessInfo.processInfo.environment["ORBIT_FLAT"] != nil }
    @ViewBuilder var content: Content
    var body: some View {
        if Self.flat { content } else { ScrollView { content } }
    }
}

extension View {
    /// Glass push button. `focusable(false)` stops macOS drawing the blue keyboard-focus ring on first launch.
    func glassButton(primary: Bool = false) -> some View {
        buttonStyle(GlassButtonStyle(primary: primary)).focusable(false)
    }
}
