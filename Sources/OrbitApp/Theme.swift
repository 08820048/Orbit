import AppKit
import OrbitCore
import SwiftUI

// Design tokens from the approved Doop canvas (Sk4PPlUPfx), Glass style. Controls (buttons, segmented, toggle) get a subtle bevel; panels and backgrounds stay flat.

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

    // Control surfaces (secondary buttons, segmented trough, toggle track). Dark values follow the approved Doop spec.
    static let glassTop = Color.dynamic(dark: (0xFFFFFF, 0.15), light: (0xFFFFFF, 0.95))
    static let glassBottom = Color.dynamic(dark: (0xFFFFFF, 0.08), light: (0xFFFFFF, 0.60))
    static let glassTopHover = Color.dynamic(dark: (0xFFFFFF, 0.20), light: (0xFFFFFF, 1.0))
    static let glassBottomHover = Color.dynamic(dark: (0xFFFFFF, 0.12), light: (0xFFFFFF, 0.78))
    static let glassPressed = Color.dynamic(dark: (0xFFFFFF, 0.05), light: (0x142868, 0.08))
    static let glassHighlight = Color.dynamic(dark: (0xFFFFFF, 0.20), light: (0xFFFFFF, 1.0))
    static let glassHairline = Color.dynamic(dark: (0xFFFFFF, 0.10), light: (0x000000, 0.10))
    static let trough = Color.dynamic(dark: (0x000000, 0.22), light: (0x142868, 0.09))
    static let troughShade = Color.dynamic(dark: (0x000000, 0.38), light: (0x000000, 0.10))
}

/// Light edge on top and shade at the bottom, drawn just inside a rounded shape.
private struct Bevel: View {
    var radius: CGFloat
    var top: Color
    var bottom: Color = .clear
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
            LinearGradient(stops: [.init(color: top, location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .clear, location: 0.7), .init(color: bottom, location: 1)],
                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }
}

private enum Blue {
    static let normal = [Color(hex: 0x5C9DFF), Color(hex: 0x3B82F6), Color(hex: 0x2D6CE3)]
    static let hover = [Color(hex: 0x6BA7FF), Color(hex: 0x4A8EFA), Color(hex: 0x3877EA)]
    static let pressed = [Color(hex: 0x2F6FE0), Color(hex: 0x2A66D6)]
    /// Hairline around blue surfaces: a faint light edge, never a dark outline.
    static let rim = Color.white.opacity(0.14)
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
    }
}

extension View {
    func glassPanel(radius: CGFloat = 20) -> some View { modifier(GlassPanel(radius: radius)) }
}

struct GlassButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, primary: primary)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed }
    private var hover: Bool { hovering && enabled && !pressed }

    private var fill: LinearGradient {
        let colors: [Color]
        if primary {
            colors = pressed ? Blue.pressed : hover ? Blue.hover : Blue.normal
        } else {
            colors = pressed ? [Theme.glassPressed, Theme.glassPressed]
                : hover ? [Theme.glassTopHover, Theme.glassBottomHover] : [Theme.glassTop, Theme.glassBottom]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Theme.text)
            .shadow(color: primary ? .black.opacity(0.18) : .clear, radius: 0, y: 1)
            .padding(.horizontal, 15).frame(height: 30)
            .background(fill, in: shape)
            .overlay {
                if pressed { Bevel(radius: 9, top: Theme.troughShade) }
                else { Bevel(radius: 9, top: primary ? .white.opacity(0.38) : Theme.glassHighlight, bottom: primary ? .black.opacity(0.14) : .clear) }
            }
            .overlay(shape.strokeBorder(primary ? Blue.rim : Theme.glassHairline, lineWidth: 0.5))
            .shadow(color: primary && !pressed ? Theme.accent.opacity(0.28) : .clear, radius: 8, y: 5)
            .offset(y: pressed ? 0.5 : 0)
            .opacity(enabled ? 1 : 0.38)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Flat window ground.
struct WindowBackground: View {
    var body: some View { Theme.window.ignoresSafeArea() }
}

/// Segmented control in the Glass style: a recessed trough with a raised blue pill for the selection.
struct GlassSegmented<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    var fill = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = selection == option
                Text(label(option))
                    .font(.system(size: 12))
                    .foregroundStyle(on ? Color.white : Theme.text2)
                    .shadow(color: on ? .black.opacity(0.18) : .clear, radius: 0, y: 1)
                    .frame(minWidth: 40, maxWidth: fill ? .infinity : nil).frame(height: 24)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: Blue.normal, startPoint: .top, endPoint: .bottom))
                                .overlay(Bevel(radius: 6, top: .white.opacity(0.38)))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Blue.rim, lineWidth: 0.5))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection = option } }
            }
        }
        .padding(3)
        .background(Theme.trough, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(Bevel(radius: 9, top: Theme.troughShade))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.glassHairline, lineWidth: 0.5))
    }
}

/// Text tabs with a thin accent underline under the selected one: a lighter second level below a segmented control.
struct TextTabs<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 22) {
            ForEach(options, id: \.self) { option in
                let on = selection == option
                Text(label(option))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Theme.text : Theme.text2)
                    .frame(height: 26)
                    .overlay(alignment: .bottom) {
                        if on { Capsule().fill(Theme.accent).frame(height: 2).offset(y: 2) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection = option } }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GlassToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        let track = Capsule()
        track.fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4F93FF), Color(hex: 0x2F74EC)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Theme.trough))
            .frame(width: 38, height: 22)
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [isOn ? Color.black.opacity(0.3) : Theme.troughShade, .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .overlay(track.strokeBorder(isOn ? Blue.rim : Theme.glassHairline, lineWidth: 0.5))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(LinearGradient(colors: [.white, Color(hex: 0xE4EAF5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 18, height: 18).padding(2)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5).frame(width: 18, height: 18))
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            }
            .contentShape(Capsule())
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

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            GlassIcon(index: GI.timer, size: 84)
            Text("这段时间还没有记录").font(.system(size: 18, weight: .bold))
            Text(model.access == .granted
                 ? "换一个时间范围，或者点「刷新」重新读取。"
                 : "没有读取屏幕使用时间的权限。Orbit 正在从现在开始记录，用一会儿再来看。")
                .font(.system(size: 13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            if model.access != .granted {
                Button("打开系统设置授权") { model.openFullDiskAccessSettings() }.glassButton(primary: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
