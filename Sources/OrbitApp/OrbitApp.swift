import AppKit
import OrbitCore
import SwiftUI

/// Makes sure Orbit is a regular, active app whose window is the key window. Without this a window can be
/// visible and clickable yet never receive keyboard input (text fields look dead), e.g. when the binary is
/// started from a terminal or by a tool that does not activate it.
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Orbit lives in the menu bar: with the Dock icon hidden it is an accessory app.
        let showDock = UserDefaults.standard.object(forKey: "orbit.showDock") as? Bool ?? true
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
        // The SwiftUI window may not exist yet: make it key as soon as it does.
        DispatchQueue.main.async { Self.focusMainWindow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Self.focusMainWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { Self.focusMainWindow() }

    /// Closing the window must not quit: the shortcuts and the menu bar icon keep working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { WindowOpener.shared.showMain() } }
        return true
    }

    static func focusMainWindow() {
        // Never fight the selection overlay for the key window.
        if NSApp.windows.contains(where: { $0 is OverlayWindow && $0.isVisible }) { return }
        guard let window = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible && $0.level == .normal }), !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Brings the main window back (or opens a new one) from anywhere: the menu bar, a shortcut, a permission problem.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    /// Set by a view that has access to SwiftUI's `openWindow`.
    var open: (() -> Void)?

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeKey && $0.level == .normal && $0.styleMask.contains(.titled) && !($0 is NSPanel) }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
    }
}

/// The menu bar glyph: a planet with its orbit, drawn as a template image so it follows the menu bar colours.
enum MenuBarIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = NSBezierPath(ovalIn: NSRect(x: -8.6, y: -3.1, width: 17.2, height: 6.2))
            ring.lineWidth = 1.35
            let place = NSAffineTransform()
            place.translateX(by: 10, yBy: 9)
            place.rotate(byDegrees: 26)
            ring.transform(using: place as AffineTransform)
            ring.stroke()
            NSBezierPath(ovalIn: NSRect(x: 5.6, y: 4.6, width: 8.8, height: 8.8)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Orbit", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
                .task { await RenderCheck.runIfRequested(model); await CaptureSelfTest.runIfRequested(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { model.updater.checkForUpdates() }
            }
            CommandGroup(after: .newItem) {
                Button("刷新数据") { Task { await model.refresh() } }.keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .onAppear { WindowOpener.shared.open = { openWindow(id: "main") } }
    }
}

/// The menu under the menu bar icon.
private struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.captureSettings
        ForEach([CaptureAction.region, .window, .fullscreen], id: \.self) { action in
            item(action.title, action: action, combo: s.combo(action))
        }
        Menu("延时截图") {
            ForEach([3, 5, 10], id: \.self) { sec in
                Button("\(sec) 秒") { s.delaySeconds = sec; model.capture.perform(.delayed, fromUI: true) }
            }
        }
        Divider()
        Button("打开 Orbit") { WindowOpener.shared.showMain() }.keyboardShortcut("o")
        Button("设置…") { model.section = .settings; WindowOpener.shared.showMain() }.keyboardShortcut(",")
        Button("检查更新…") { model.updater.checkForUpdates() }
        Divider()
        Button("退出 Orbit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    @ViewBuilder
    private func item(_ title: String, action: CaptureAction, combo: KeyCombo) -> some View {
        if let shortcut = combo.shortcut {
            Button(title) { model.capture.perform(action, fromUI: true) }.keyboardShortcut(shortcut)
        } else {
            Button(title) { model.capture.perform(action, fromUI: true) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            WindowBackground()
            if model.hasOnboarded {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
    }
}

/// Page-level actions shown on the right of the top bar. A page declares them with `.topBarActions { … }`.
struct TopBarActions { let view: AnyView }

struct TopBarActionsKey: PreferenceKey {
    static var defaultValue: TopBarActions? = nil
    static func reduce(value: inout TopBarActions?, nextValue: () -> TopBarActions?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    func topBarActions<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        preference(key: TopBarActionsKey.self, value: TopBarActions(view: AnyView(content())))
    }
}

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch model.section {
                case .screenshots: ScreenshotsPage()
                case .share: ShareHubView(custom: model.custom)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlayPreferenceValue(TopBarActionsKey.self) { actions in
            HStack(spacing: 10) { Spacer(); actions?.view }
                .padding(.horizontal, 20).frame(height: 56)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        // The bar sits in the window's top strip, level with the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Top menu: the two sections centred in the window's title strip.
struct TopBar: View {
    @EnvironmentObject var model: AppModel

    private static let items: [(title: String, icon: Int, section: AppModel.Section)] = [
        ("截图", GI.capture, .screenshots), ("分享", GI.share, .share), ("设置", GI.gear, .settings),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.items, id: \.section) { item in
                let selected = model.section == item.section
                HStack(spacing: 7) {
                    GlassIcon(index: item.icon, size: 20)
                    Text(item.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                }
                .padding(.leading, 10).padding(.trailing, 14).frame(height: 30)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control) }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.section = item.section }
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 56)
    }
}

/// `Orbit --render-check <dir>`: writes the three templates as PNGs and exits. Used for verification.
@MainActor
enum RenderCheck {
    /// With `ORBIT_SAMPLE_SHOTS=1` (and `ORBIT_STORE_PATH` pointing at a throwaway index) fills the library with made-up
    /// screenshots in a temp folder, so the screenshot pages can be rendered. Returns the first one.
    static func seedSampleScreenshots(_ model: AppModel) -> ScreenshotRecord? {
        guard ProcessInfo.processInfo.environment["ORBIT_SAMPLE_SHOTS"] != nil,
              ProcessInfo.processInfo.environment["ORBIT_STORE_PATH"] != nil else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-sample-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let palettes: [(NSColor, NSColor)] = [
            (NSColor(srgbRed: 0.17, green: 0.23, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.42, green: 0.25, blue: 0.63, alpha: 1)),
            (NSColor(srgbRed: 0.06, green: 0.36, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.11, green: 0.54, blue: 0.54, alpha: 1)),
            (NSColor(srgbRed: 0.48, green: 0.23, blue: 0.37, alpha: 1), NSColor(srgbRed: 0.76, green: 0.35, blue: 0.35, alpha: 1)),
            (NSColor(srgbRed: 0.12, green: 0.16, blue: 0.27, alpha: 1), NSColor(srgbRed: 0.23, green: 0.31, blue: 0.48, alpha: 1)),
        ]
        let kinds: [CaptureKind] = [.region, .window, .region, .fullscreen, .window, .region, .window, .region, .fullscreen]
        let apps = ["Safari", "Xcode", "Figma", "Terminal"]
        var first: ScreenshotRecord?
        let now = Date()
        for i in 0..<9 {
            let size = NSSize(width: 812, height: 536)
            let (a, b) = palettes[i % palettes.count]
            let img = NSImage(size: size, flipped: false) { rect in
                NSGradient(starting: a, ending: b)?.draw(in: rect, angle: 315)
                NSColor.white.withAlphaComponent(0.14).setFill()
                for k in 0..<4 { NSBezierPath(roundedRect: NSRect(x: 28, y: rect.height - 70 - CGFloat(k) * 60, width: CGFloat(300 + (i * 40 + k * 70) % 380), height: 34), xRadius: 8, yRadius: 8).fill() }
                return true
            }
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let record = try? CaptureService.save(cg, kind: kinds[i], source: kinds[i] == .window ? apps[i % apps.count] : nil, scale: 1,
                                                        format: .png, folder: folder, date: now.addingTimeInterval(-Double(i) * 5400 - (i > 4 ? 86_400 : 0))) else { continue }
            try? model.capture.store.add(record)
            if first == nil { first = record }
        }
        model.capture.needsPermission = false
        model.capture.libraryChanged()
        return first
    }

    /// `ORBIT_LIGHT=1` renders the screens in light mode (default: dark).
    static var isLight: Bool { ProcessInfo.processInfo.environment["ORBIT_LIGHT"] != nil }
    static var scheme: ColorScheme { isLight ? .light : .dark }
    static func runIfRequested(_ model: AppModel) async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-check"), i + 1 < args.count else { return }
        NSApp.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await model.refresh()
        model.loadDock()
        guard let s = model.summary else { exit(2) }
        let entries = s.topApps.prefix(30).map {
            let info = model.catalog.info(for: $0.bundleID)
            return ShareEntry(id: $0.bundleID, name: info.name, icon: info.icon, seconds: $0.seconds)
        }
        let data = ShareData(periodTitle: model.periodTitle, coverage: "记录 \(s.daily.count) 天", totalSeconds: s.totalSeconds,
                             averageSeconds: s.averagePerActiveDay, longestDay: s.longestDay, appCount: s.appCount,
                             share: (s.topApps.first?.seconds ?? 0) / max(s.totalSeconds, 1), entries: Array(entries))
        // Whole-window renders of each screen, for visual verification without touching the desktop.
        let sampleShots = RenderCheck.seedSampleScreenshots(model)
        for (name, section) in [("share", AppModel.Section.share), ("settings", .settings), ("screenshots", .screenshots)] {
            model.hasOnboarded = true
            model.section = section
            model.custom.doc.mode = .usage
            let r = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("screen-\(name).png"))
            }
        }
        if let first = sampleShots {
            model.openShot = first
            model.section = .screenshots
            let r = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("screen-screenshot-detail.png"))
            }
            model.openShot = nil
        }
        model.hasOnboarded = false
        let ob = ImageRenderer(content: RootView().environmentObject(model).frame(width: 860, height: 580).environment(\.colorScheme, RenderCheck.scheme))
        if let cg = ob.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-onboarding.png"))
        }
        model.hasOnboarded = true
        // Custom share: real installed apps split into three groups.
        await model.custom.loadInstalledIfNeeded()
        print("installed apps found:", model.custom.installed.count)
        let top = s.topApps.map(\.bundleID)
        let originalCustomDoc = model.custom.doc   // restored at the end: the check must not touch real settings
        var doc = model.custom.doc
        doc.groups = [ShareGroup(name: "AI 与开发", bundleIDs: Array(top.prefix(5))),
                      ShareGroup(name: "写作与学习", bundleIDs: Array(top.dropFirst(5).prefix(4))),
                      ShareGroup(name: "效率与系统", bundleIDs: Array(top.dropFirst(9).prefix(6)))]
        doc.caption = "我们塑造了工具，而后工具也在塑造我们。\n—— 马歇尔·麦克卢汉"
        model.custom.doc = doc
        func resolved(_ d: CustomShareDoc) -> [ResolvedGroup] {
            d.groups.map { g in ResolvedGroup(id: g.id, name: g.name, apps: g.bundleIDs.map { model.custom.resolve($0, catalog: model.catalog) }) }
        }
        for t in CustomTemplate.allCases {
            for ratio in [CanvasRatio.landscape, .portrait] {
                var d = doc; d.template = t; d.ratio = ratio
                if let png = ShareRenderer.png(CustomShareCardView(doc: d, groups: resolved(d))) {
                    try? png.write(to: dir.appendingPathComponent("custom-\(t.rawValue)-\(ratio.rawValue).png"))
                }
            }
        }
        for (name, bg) in [("builtin:sunset-sea", "sunset-sea"), ("builtin:milkyway", "milkyway"), ("solid:0F2C66", "solid-blue")] {
            var d = doc; d.template = .fjord; d.background = name
            if let png = ShareRenderer.png(CustomShareCardView(doc: d, groups: resolved(d))) {
                try? png.write(to: dir.appendingPathComponent("custom-bg-\(bg).png"))
            }
        }
        model.hasOnboarded = true
        model.section = .share
        model.custom.doc.mode = .picked
        let ce = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
        if let cg = ce.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-custom.png"))
        }
        let pk = ImageRenderer(content: AppPickerSheet(custom: model.custom).environmentObject(model).frame(width: 900, height: 720))
        if let cg = pk.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-picker.png"))
        }
        // Usage ranking on a photo background (shared look), full screen.
        model.custom.doc.mode = .usage
        model.custom.doc.background = "builtin:fjord"
        let us = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
        us.scale = 2
        if let cg = us.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-usage-photo.png"))
        }
        model.custom.doc.background = "default"
        model.dataStyle.template = .report
        let rp = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
        rp.scale = 2
        if let cg = rp.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-usage-report.png"))
        }
        model.dataStyle.template = .ranking
        model.custom.doc.mode = .picked
        model.custom.doc.groups = []
        let rank = model.recencyScores()
        for preset in GroupPreset.all {
            model.custom.addPreset(preset, scores: rank)
            let g = model.custom.doc.groups.last!
            print("preset", preset.name, "->", g.bundleIDs.map { model.catalog.info(for: $0).name }.joined(separator: ", "))
        }
        let presetShot = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 1200).environment(\.colorScheme, RenderCheck.scheme))
        presetShot.scale = 1
        if let cg = presetShot.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-presets.png"))
        }
        // Terminal tools: what is detected here, and every catalog logo on a card.
        print("detected terminal tools:", TerminalCatalog.detect().map { "\($0.name) (\($0.commands[0]))" }.joined(separator: ", "))
        do {
            var d = originalCustomDoc
            let apps = TerminalCatalog.all.map { CustomApp.from($0) }
            d.customApps = apps
            d.groups = [ShareGroup(name: "终端工具", bundleIDs: apps.map(\.key))]
            d.template = .minimal; d.iconSize = .large; d.title = "我的终端工具"; d.caption = ""
            model.custom.doc = d
            if let png = ShareRenderer.png(CustomShareCardView(doc: d, groups: resolved(d))) {
                try? png.write(to: dir.appendingPathComponent("terminal-logos.png"))
            }
        }
        // Custom apps: full-bleed art, a transparent logo, and no picture at all.
        do {
            var d = originalCustomDoc
            var art = CustomApp(name: "Photo Art"); art.iconFile = try? CustomAppIcons.save(BackgroundStore.builtin("sunset-sea") ?? NSImage())
            var logo = CustomApp(name: "Claude Code"); logo.iconFile = try? CustomAppIcons.save(GlassIcons.image(GI.sliders)); logo.colorHex = "D97757"
            let plain = CustomApp(name: "Codex CLI", iconFile: nil, squircle: true, colorHex: "2F6BEA")
            d.customApps = [art, logo, plain]
            d.groups = [ShareGroup(name: "AI 与开发", bundleIDs: [logo.key, plain.key, art.key] + Array(top.prefix(3)))]
            d.template = .glass
            model.custom.doc = d
            if let png = ShareRenderer.png(CustomShareCardView(doc: d, groups: resolved(d))) {
                try? png.write(to: dir.appendingPathComponent("custom-apps-card.png"))
            }
            let sheet = ImageRenderer(content: CustomAppSheet(custom: model.custom, draft: logo, isNew: true).frame(width: 560, height: 420))
            if let cg = sheet.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("screen-custom-sheet.png"))
            }
            for a in [art, logo] { CustomAppIcons.delete(file: a.iconFile) }
        }
        model.custom.doc.groups = []
        let emptyShot = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, RenderCheck.scheme))
        if let cg = emptyShot.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-custom-empty.png"))
        }
        model.custom.doc = originalCustomDoc
        for kind in BackgroundKind.allCases {
            var st = ShareStyle(); st.background = kind
            if let png = ShareRenderer.png(style: st, data: data) { try? png.write(to: dir.appendingPathComponent("bg-\(kind.rawValue).png")) }
        }
        for (name, spacing, contrast, count) in [("default", 5.0, 80.0, 20), ("tight", 0.0, 80.0, 30), ("loose-even", 22.0, 30.0, 20)] {
            var st = ShareStyle(); st.template = .bubbles; st.bubbleCount = count; st.bubbleSpacing = spacing; st.bubbleContrast = contrast
            st.bg = "solid:A9A9AB"
            if let png = ShareRenderer.png(style: st, data: data) { try? png.write(to: dir.appendingPathComponent("bubbles-\(name).png")) }
        }
        for t in ShareTemplate.allCases {
            var style = ShareStyle(); style.template = t
            let start = Date()
            guard let png = ShareRenderer.png(style: style, data: data) else { print("FAIL \(t)"); exit(1) }
            try? png.write(to: dir.appendingPathComponent("\(t.rawValue).png"))
            print("\(t.rawValue): \(png.count) bytes, \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        }
        exit(0)
    }
}

/// `Orbit --capture-selftest <dir>`: takes one real full-screen capture through the same code the shortcuts use, saves it
/// into `<dir>` (never the user's library), prints what happened and exits. For verifying capture without clicking.
@MainActor
enum CaptureSelfTest {
    /// `--annotate-selftest <dir>`: draws every kind of annotation onto a made-up screenshot and saves the result, so the
    /// renderer (including the pixel-destroying blur) can be looked at without opening the editor.
    /// A made-up screenshot plus one of every annotation, for self-tests.
    static func sampleEdit() -> (CGImage, [Annotation])? {
        let size = NSSize(width: 1680, height: 1040)
        let img = NSImage(size: size, flipped: true) { rect in
            NSColor(srgbRed: 0.12, green: 0.13, blue: 0.19, alpha: 1).setFill(); rect.fill()
            NSColor(white: 1, alpha: 0.05).setFill(); NSRect(x: 0, y: 0, width: 400, height: rect.height).fill()
            let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.white]
            let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor(white: 0.8, alpha: 1)]
            ("账户信息" as NSString).draw(at: NSPoint(x: 600, y: 70), withAttributes: title)
            for (k, row) in [("用户名", "xuyi"), ("邮箱", "marshmitch884@gmail.com"), ("手机号", "138 0013 8000")].enumerated() {
                let y = 220 + CGFloat(k) * 170
                (row.0 as NSString).draw(at: NSPoint(x: 600, y: y), withAttributes: label)
                NSColor(white: 1, alpha: 0.08).setFill()
                NSBezierPath(roundedRect: NSRect(x: 600, y: y + 40, width: 840, height: 80), xRadius: 16, yRadius: 16).fill()
                (row.1 as NSString).draw(at: NSPoint(x: 630, y: y + 62), withAttributes: label)
            }
            return true
        }
        guard let base = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Double(base.width)
        func style(_ a: Annotation, _ level: LineLevel = .medium) -> Annotation {
            var a = a; a.lineWidth = AnnotationScale.lineWidth(level, imageWidth: w); return a
        }
        var items: [Annotation] = []
        var mosaic = Annotation(shape: .blur(CGRect(x: 620, y: 448, width: 330, height: 44))); mosaic.blurMode = .pixelate
        items.append(mosaic)
        var blur = Annotation(shape: .blur(CGRect(x: 620, y: 788, width: 190, height: 44))); blur.blurMode = .blur
        items.append(blur)
        items.append(style(Annotation(shape: .arrow(from: CGPoint(x: 1300, y: 260), to: CGPoint(x: 1010, y: 280)))))
        var txt = Annotation(shape: .text(origin: CGPoint(x: 1300, y: 235), string: "改成新的昵称"))
        txt.fontSize = AnnotationScale.fontSize(.medium, imageWidth: w)
        txt.textSize = AnnotationRenderer.measureText("改成新的昵称", fontSize: txt.fontSize, background: true)
        items.append(txt)
        var rect = style(Annotation(shape: .rectangle(CGRect(x: 585, y: 40, width: 880, height: 110))), .thick); rect.color = .blue
        items.append(rect)
        var ell = style(Annotation(shape: .ellipse(CGRect(x: 1180, y: 890, width: 240, height: 110)))); ell.color = .green
        items.append(ell)
        var ln = style(Annotation(shape: .line(from: CGPoint(x: 600, y: 900), to: CGPoint(x: 1100, y: 900))), .thin); ln.color = .orange
        items.append(ln)
        var plain = Annotation(shape: .text(origin: CGPoint(x: 600, y: 930), string: "无底色文字 + 阴影"))
        plain.textBackground = false; plain.color = .orange; plain.fontSize = AnnotationScale.fontSize(.large, imageWidth: w)
        plain.textSize = AnnotationRenderer.measureText("无底色文字 + 阴影", fontSize: plain.fontSize, background: false)
        items.append(plain)

        return (base, items)
    }

    /// `--editor-selftest <dir>`: opens the real editor window off screen with sample annotations and saves what it looks like.
    static func editorIfRequested(_ model: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--editor-selftest"), i + 1 < args.count, let (base, items) = sampleEdit() else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let record = try? CaptureService.save(base, kind: .region, source: "Safari", scale: 2, format: .png, folder: dir, date: Date()),
              let controller = EditorWindowController(record: record, capture: model.capture) else { return }
        let savedStyle = BeautifyStore.load()          // the self-test changes the style; put it back afterwards
        defer { BeautifyStore.save(savedStyle) }
        let window = controller.window!
        window.setFrame(NSRect(x: 100, y: 100, width: 1180, height: 820), display: true)
        window.orderFrontRegardless()
        func snap(_ name: String) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            window.contentView?.layoutSubtreeIfNeeded()
            guard let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        controller.model.commit(items: items)
        controller.model.tool = .select
        controller.model.select(items.first { if case .arrow = $0.shape { return true }; return false }?.id)
        snap("editor-select.png")
        controller.model.tool = .blur
        snap("editor-blur-tool.png")
        controller.model.tool = .crop
        controller.model.setCropRatio(16.0 / 9.0)
        snap("editor-crop.png")
        controller.model.cropRect = CGRect(x: 560, y: 180, width: 960, height: 520)
        controller.model.applyCrop()
        controller.model.tool = .text
        snap("editor-after-crop.png")
        controller.model.tool = .select
        controller.model.mode = .beautify
        snap("editor-beautify.png")
        controller.model.applyPreset(.document)
        snap("editor-beautify-document.png")
        controller.model.applyPreset(.social)
        // Save as a new screenshot and check the result like a user would.
        controller.saveAsNew()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") && $0.hasPrefix("Orbit") }.sorted()
        FileHandle.standardError.write(Data("SELFTEST files after saving: \(names)\n".utf8))
        let indexed = ((try? model.capture.store.records()) ?? []).map(\.fileName)
        FileHandle.standardError.write(Data("SELFTEST indexed: \(indexed)\n".utf8))
        if let edited = ((try? model.capture.store.records()) ?? []).first(where: { $0.fileName.contains("已编辑") }) {
            FileHandle.standardError.write(Data("SELFTEST edited image: \(edited.pixelWidth)x\(edited.pixelHeight), original untouched: \(FileManager.default.fileExists(atPath: record.path))\n".utf8))
        }
        FileHandle.standardError.write(Data("SELFTEST editor done\n".utf8))
        BeautifyStore.save(savedStyle)
        exit(0)
    }

    /// `--beautify-selftest <dir>`: renders the presets and window frames from the sample screenshot.
    static func beautifyIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--beautify-selftest"), i + 1 < args.count, let (base, items) = sampleEdit() else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let content = AnnotationRenderer.render(base: base, snapshot: EditSnapshot(items: items)) else { return }
        func save(_ cg: CGImage?, _ name: String) {
            guard let cg, let data = try? CaptureService.encode(cg, as: .png) else { return }
            try? data.write(to: dir.appendingPathComponent(name))
        }
        var mine = BeautifyStyle(); mine.title = "账户设置"; mine.signature = "徐毅"
        for p in BeautifyPreset.allCases { save(BeautifyRenderer.render(content: content, style: p.style(keeping: mine), pixelsPerPoint: 2), "preset-\(p.rawValue).png") }
        var s = BeautifyPreset.social.style(keeping: mine)
        s.background = "gradient:FF8A5B,FF4D8D"; s.frame = .window
        save(BeautifyRenderer.render(content: content, style: s, pixelsPerPoint: 2), "frame-window.png")
        s.background = "gradient:1FD1A5,2E7CF6"; s.frame = .browser; s.title = "页面标题"
        save(BeautifyRenderer.render(content: content, style: s, pixelsPerPoint: 2), "frame-browser.png")
        s.frame = .window; s.ratio = .square; s.background = "builtin:fjord"
        save(BeautifyRenderer.render(content: content, style: s, pixelsPerPoint: 2), "ratio-square-photo.png")
        FileHandle.standardError.write(Data("SELFTEST beautify done\n".utf8))
        exit(0)
    }

    static func annotateIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--annotate-selftest"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let (base, items) = sampleEdit() else { return }
        func save(_ cg: CGImage?, _ name: String) {
            guard let cg, let data = try? CaptureService.encode(cg, as: .png) else { return }
            try? data.write(to: dir.appendingPathComponent(name))
        }
        save(AnnotationRenderer.render(base: base, snapshot: EditSnapshot(items: items)), "annotated.png")
        save(AnnotationRenderer.render(base: base, snapshot: EditSnapshot(items: items, crop: CGRect(x: 560, y: 180, width: 960, height: 520))), "annotated-cropped.png")
        FileHandle.standardError.write(Data("SELFTEST annotate done\n".utf8))
        exit(0)
    }

    static func runIfRequested(_ model: AppModel) async {
        annotateIfRequested()
        beautifyIfRequested()
        editorIfRequested(model)
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capture-selftest"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        func say(_ s: String) { FileHandle.standardError.write(Data(("SELFTEST " + s + "\n").utf8)) }
        say("permission granted: \(ScreenPermission.granted)")
        say("shortcut conflicts: \(model.capture.conflicts.map(\.rawValue).sorted())")
        do {
            let screens = try await CaptureService.freezeScreens(includeCursor: false)
            say("screens captured: \(screens.count)")
            for s in screens { say("  \(s.image.width)x\(s.image.height) px, scale \(s.scale), colorspace \(s.image.colorSpace?.name as String? ?? "nil")") }
            let rec = try CaptureService.save(screens[0].image, kind: .fullscreen, source: "selftest", scale: Double(screens[0].scale), format: .png, folder: dir)
            say("saved: \(rec.path) (\(rec.byteCount) bytes)")
            let windows = try await CaptureService.windows()
            say("windows found: \(windows.count); first: \(windows.first?.title ?? "-")")
            if let w = windows.first {
                let img = try await CaptureService.captureWindow(w, includeCursor: false)
                let wr = try CaptureService.save(img, kind: .window, source: w.title, scale: 2, format: .png, folder: dir)
                say("window saved: \(wr.path) \(img.width)x\(img.height)")
            }
        } catch {
            say("FAILED: \(error.localizedDescription)")
        }
        exit(0)
    }
}
