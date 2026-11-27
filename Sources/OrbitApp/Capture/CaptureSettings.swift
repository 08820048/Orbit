import AppKit
import Carbon.HIToolbox
import OrbitCore
import SwiftUI

/// A global shortcut: Carbon key code plus Carbon modifier flags.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let control = UInt32(controlKey), shift = UInt32(shiftKey), option = UInt32(optionKey), command = UInt32(cmdKey)

    /// "⌃⇧4"
    var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// Modifier symbols and the key as separate keycaps: ["⌃", "⇧", "4"].
    var keycaps: [String] {
        var caps: [String] = []
        if modifiers & Self.control != 0 { caps.append("⌃") }
        if modifiers & Self.option != 0 { caps.append("⌥") }
        if modifiers & Self.shift != 0 { caps.append("⇧") }
        if modifiers & Self.command != 0 { caps.append("⌘") }
        return caps + [Self.keyName(keyCode)]
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= control }
        if flags.contains(.option) { m |= option }
        if flags.contains(.shift) { m |= shift }
        if flags.contains(.command) { m |= command }
        return m
    }

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G",
        kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N",
        kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
        kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6",
        kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\",
    ]
    static func keyName(_ code: UInt32) -> String { names[Int(code)] ?? "?" }

    /// For showing the shortcut next to a menu item (single-character keys only).
    var shortcut: KeyboardShortcut? {
        let name = Self.keyName(keyCode)
        guard name.count == 1, let ch = name.lowercased().first else { return nil }
        var m: SwiftUI.EventModifiers = []
        if modifiers & Self.control != 0 { m.insert(.control) }
        if modifiers & Self.option != 0 { m.insert(.option) }
        if modifiers & Self.shift != 0 { m.insert(.shift) }
        if modifiers & Self.command != 0 { m.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(ch), modifiers: m)
    }
}

/// What a global shortcut does.
enum CaptureAction: String, CaseIterable, Codable, Identifiable {
    case region, window, fullscreen, delayed, repeatLast
    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: String(localized: "区域截图")
        case .window: String(localized: "窗口截图")
        case .fullscreen: String(localized: "全屏截图")
        case .delayed: String(localized: "延时截图")
        case .repeatLast: String(localized: "重复上一次区域")
        }
    }

    /// Defaults avoid macOS's own ⌘⇧3 / ⌘⇧4 / ⌘⇧5.
    var defaultCombo: KeyCombo {
        let m = KeyCombo.control | KeyCombo.shift
        switch self {
        case .region: return KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: m)
        case .window: return KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: m)
        case .fullscreen: return KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: m)
        case .delayed: return KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: m)
        case .repeatLast: return KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: m)
        }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpg = "JPG"
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// Everything the user can tune about taking screenshots. Persisted in UserDefaults.
@MainActor
final class CaptureSettings: ObservableObject {
    private let d = UserDefaults.standard

    /// Folder every screenshot is saved to.
    @Published var folderPath: String { didSet { d.set(folderPath, forKey: "orbit.shot.folder") } }
    @Published var format: ImageFormat { didSet { d.set(format.rawValue, forKey: "orbit.shot.format") } }
    @Published var showQuickPanel: Bool { didSet { d.set(showQuickPanel, forKey: "orbit.shot.quickPanel") } }
    @Published var quickPanelSeconds: Double { didSet { d.set(quickPanelSeconds, forKey: "orbit.shot.quickSeconds") } }
    @Published var autoCopy: Bool { didSet { d.set(autoCopy, forKey: "orbit.shot.autoCopy") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "orbit.shot.sound") } }
    @Published var includeCursor: Bool { didSet { d.set(includeCursor, forKey: "orbit.shot.cursor") } }
    /// 0 = never delete automatically.
    @Published var autoCleanDays: Int { didSet { d.set(autoCleanDays, forKey: "orbit.shot.cleanDays") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "orbit.showDock"); applyActivationPolicy() } }
    @Published var combos: [CaptureAction: KeyCombo] { didSet { saveCombos() } }
    /// Seconds before a delayed screenshot (3, 5 or 10).
    @Published var delaySeconds: Int { didSet { d.set(delaySeconds, forKey: "orbit.shot.delay") } }

    init() {
        delaySeconds = d.object(forKey: "orbit.shot.delay") as? Int ?? 5
        folderPath = d.string(forKey: "orbit.shot.folder") ?? ScreenshotStore.defaultFolder.path
        format = ImageFormat(rawValue: d.string(forKey: "orbit.shot.format") ?? "") ?? .png
        showQuickPanel = d.object(forKey: "orbit.shot.quickPanel") as? Bool ?? true
        quickPanelSeconds = d.object(forKey: "orbit.shot.quickSeconds") as? Double ?? 5
        autoCopy = d.object(forKey: "orbit.shot.autoCopy") as? Bool ?? false
        playSound = d.object(forKey: "orbit.shot.sound") as? Bool ?? true
        includeCursor = d.object(forKey: "orbit.shot.cursor") as? Bool ?? false
        autoCleanDays = d.object(forKey: "orbit.shot.cleanDays") as? Int ?? 0
        showDockIcon = d.object(forKey: "orbit.showDock") as? Bool ?? true
        combos = Self.loadCombos(d)
    }

    var folderURL: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }

    func combo(_ a: CaptureAction) -> KeyCombo { combos[a] ?? a.defaultCombo }

    func resetCombos() { combos = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.defaultCombo) }) }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func saveCombos() {
        let raw = Dictionary(uniqueKeysWithValues: combos.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { d.set(data, forKey: "orbit.shot.combos") }
    }

    private static func loadCombos(_ d: UserDefaults) -> [CaptureAction: KeyCombo] {
        var out = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.defaultCombo) })
        if let data = d.data(forKey: "orbit.shot.combos"),
           let raw = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            for (k, v) in raw { if let a = CaptureAction(rawValue: k) { out[a] = v } }
        }
        return out
    }
}
