import AppKit
import Carbon.HIToolbox
import OrbitCore
import ServiceManagement
import SwiftUI

/// A titled block on the settings page.
struct SettingsGroup<C: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "label ........ control" row with a fixed label column.
private struct SettingRow<C: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: C
    var body: some View {
        HStack(spacing: 14) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 150, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }
}

private struct Hint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2) }
}

private struct LinkText: View {
    let title: LocalizedStringKey
    let action: () -> Void
    init(_ title: LocalizedStringKey, _ action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 12)).foregroundStyle(Theme.accentHi) }.buttonStyle(.plain)
    }
}

/// The screenshot part of the settings page: shortcuts, what happens after a capture, storage, startup, permission.
struct CaptureSettingsSections: View {
    enum Part { case capture, shortcuts, general }
    let part: Part
    @ObservedObject var settings: CaptureSettings
    @ObservedObject var capture: CaptureCoordinator
    @State private var confirmClear = false
    @State private var granted = ScreenPermission.granted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 38) {
            switch part {
            case .shortcuts: shortcuts
            case .capture: afterCapture; storage
            case .general: startup; permission
            }
        }
        .confirmationDialog("清空截图库？", isPresented: $confirmClear) {
            Button("全部移到废纸篓", role: .destructive) { capture.deleteAll() }
        } message: { Text("\(capture.count) 张截图会被移到废纸篓，可以从废纸篓找回。") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = ScreenPermission.granted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        SettingsGroup(title: "快捷键") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(CaptureAction.allCases) { action in
                    ShortcutRow(action: action, settings: settings, capture: capture)
                }
            }
            HStack(spacing: 6) {
                Hint("默认避开了 macOS 自带截图的 ⌘⇧3 / ⌘⇧4 / ⌘⇧5。和其他应用冲突时，这里会提示。")
                LinkText("恢复默认") { settings.resetCombos() }
            }
        }
    }

    // MARK: After a capture

    private var afterCapture: some View {
        SettingsGroup(title: "截图之后") {
            VStack(alignment: .leading, spacing: 8) {
                SettingRow(label: "显示浮窗") {
                    GlassToggle(isOn: $settings.showQuickPanel)
                    Hint("每张截图都会保存，浮窗只是方便你马上操作")
                }
                SettingRow(label: "浮窗停留") {
                    Slider(value: $settings.quickPanelSeconds, in: 2...10, step: 1).frame(width: 180)
                    Text("\(Int(settings.quickPanelSeconds)) 秒").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                .disabled(!settings.showQuickPanel).opacity(settings.showQuickPanel ? 1 : 0.4)
                SettingRow(label: "自动复制") {
                    GlassToggle(isOn: $settings.autoCopy)
                    Hint("截完后同时复制到剪贴板")
                }
                SettingRow(label: "截图声音") { GlassToggle(isOn: $settings.playSound) }
                SettingRow(label: "包含鼠标指针") { GlassToggle(isOn: $settings.includeCursor) }
            }
        }
    }

    // MARK: Storage

    private var storage: some View {
        SettingsGroup(title: "截图存储") {
            VStack(alignment: .leading, spacing: 8) {
                SettingRow(label: "保存位置") {
                    Text(Self.short(settings.folderPath)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).frame(width: 260, height: 30, alignment: .leading)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    LinkText("选择…") { chooseFolder() }
                    LinkText("在 Finder 中显示") { NSWorkspace.shared.open(settings.folderURL) }
                }
                SettingRow(label: "格式") { GlassSegmented(options: ImageFormat.allCases, label: \.rawValue, selection: $settings.format) }
                SettingRow(label: "文件名") {
                    Text(ScreenshotNaming.fileName(date: Date(), ext: settings.format.fileExtension, exists: { _ in false }))
                        .font(.system(size: 12)).padding(.horizontal, 10).frame(width: 260, height: 30, alignment: .leading)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Hint("以「Orbit」开头，后面是日期和时间")
                }
                SettingRow(label: "已保存") {
                    Text("\(capture.count) 张，\(ByteCountFormatter.string(fromByteCount: capture.totalBytes, countStyle: .file))").font(.system(size: 13))
                }
                SettingRow(label: "自动清理") {
                    GlassSegmented(options: [0, 30, 90, 365], label: { $0 == 0 ? String(localized: "从不") : $0 == 365 ? String(localized: "1 年") : String(localized: "\($0) 天") }, selection: $settings.autoCleanDays)
                }
                SettingRow(label: "清空截图库") {
                    Button("清空…") { confirmClear = true }.glassButton().disabled(capture.count == 0)
                    Hint("文件移到废纸篓，可以找回")
                }
            }
        }
    }

    // MARK: Startup

    private var startup: some View {
        SettingsGroup(title: "菜单栏与启动") {
            VStack(alignment: .leading, spacing: 8) {
                SettingRow(label: "开机启动") {
                    GlassToggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                }
                SettingRow(label: "Dock 图标") {
                    GlassToggle(isOn: $settings.showDockIcon)
                    Hint("关闭后只留菜单栏图标")
                }
            }
        }
    }

    // MARK: Permission

    private var permission: some View {
        SettingsGroup(title: "权限") {
            SettingRow(label: "屏幕录制") {
                Text(granted ? "已授权" : String(localized: "未授权")).font(.system(size: 13))
                if !granted { Button("打开系统设置") { ScreenPermission.request(); ScreenPermission.openSettings() }.glassButton(primary: true) }
            }
        }
    }

    // MARK: Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.folderURL
        panel.prompt = String(localized: "选择")
        if panel.runModal() == .OK, let url = panel.url { settings.folderPath = url.path }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// One shortcut: its keycaps and a "修改" link that records the next key combination.
private struct ShortcutRow: View {
    let action: CaptureAction
    @ObservedObject var settings: CaptureSettings
    @ObservedObject var capture: CaptureCoordinator
    @State private var recording = false
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        HStack(spacing: 14) {
            Text(action.title).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 150, alignment: .leading)
            if recording {
                Text("按下新的快捷键…（Esc 取消）").font(.system(size: 12)).foregroundStyle(Theme.accentHi)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(settings.combo(action).keycaps.enumerated()), id: \.offset) { _, cap in
                        Text(cap).font(.system(size: 13)).frame(minWidth: 26, minHeight: 26).padding(.horizontal, 3)
                            .background(Theme.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.glassHairline, lineWidth: 0.5))
                    }
                }
                Button { startRecording() } label: { Text("修改").font(.system(size: 12)).foregroundStyle(Theme.accentHi) }.buttonStyle(.plain)
            }
            if let warning { Text(warning).font(.system(size: 12)).foregroundStyle(.orange) }
            else if capture.conflicts.contains(action) { Text("这个快捷键已被其他应用占用").font(.system(size: 12)).foregroundStyle(.orange) }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        warning = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }   // Esc
            let mods = KeyCombo.carbonModifiers(from: event.modifierFlags)
            let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            // A global shortcut needs ⌃, ⌥ or ⌘, and a key we can name.
            guard mods & (KeyCombo.control | KeyCombo.option | KeyCombo.command) != 0, KeyCombo.keyName(combo.keyCode) != "?" else {
                warning = String(localized: "请至少带上 ⌃、⌥ 或 ⌘")
                NSSound.beep()
                return nil
            }
            if let other = CaptureAction.allCases.first(where: { $0 != action && settings.combo($0) == combo }) {
                warning = String(localized: "已用于「\(other.title)」")
                NSSound.beep()
                return nil
            }
            settings.combos[action] = combo
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
