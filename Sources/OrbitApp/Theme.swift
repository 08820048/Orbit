import AppKit
import OrbitCore
import SwiftUI

// Design tokens from the approved Doop canvas (Sk4PPlUPfx), Glass style; flat fills, no gradients in the UI chrome.

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
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Theme.text)
            .padding(.horizontal, 15).frame(height: 30)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control)
                }
            }
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/// Flat window ground.
struct WindowBackground: View {
    var body: some View { Theme.window.ignoresSafeArea() }
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
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent)
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
        Capsule().fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.control))
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
