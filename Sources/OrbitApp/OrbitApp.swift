import AppKit
import SwiftUI

/// Makes sure Orbit is a regular, active app whose window is the key window. Without this a window can be
/// visible and clickable yet never receive keyboard input (text fields look dead), e.g. when the binary is
/// started from a terminal or by a tool that does not activate it.
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // The SwiftUI window may not exist yet: make it key as soon as it does.
        DispatchQueue.main.async { Self.focusMainWindow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Self.focusMainWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { Self.focusMainWindow() }

    static func focusMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible }), !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Orbit") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
                .task { await RenderCheck.runIfRequested(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新数据") { Task { await model.refresh() } }.keyboardShortcut("r")
            }
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
                case .overview: OverviewView()
                case .app: AppDetailView()
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

/// Top menu: the four sections centred in the window's title strip.
struct TopBar: View {
    @EnvironmentObject var model: AppModel

    private static let items: [(title: String, icon: Int, section: AppModel.Section)] = [
        ("总览", GI.trend, .overview), ("单个应用", GI.stats, .app), ("分享图", GI.share, .share), ("设置", GI.gear, .settings),
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
    static func runIfRequested(_ model: AppModel) async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-check"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await model.refresh()
        guard let s = model.summary else { exit(2) }
        let entries = s.topApps.prefix(30).map {
            let info = model.catalog.info(for: $0.bundleID)
            return ShareEntry(id: $0.bundleID, name: info.name, icon: info.icon, seconds: $0.seconds)
        }
        let data = ShareData(periodTitle: model.periodTitle, coverage: "记录 \(s.daily.count) 天", totalSeconds: s.totalSeconds,
                             averageSeconds: s.averagePerActiveDay, longestDay: s.longestDay, appCount: s.appCount,
                             share: (s.topApps.first?.seconds ?? 0) / max(s.totalSeconds, 1), entries: Array(entries))
        // Whole-window renders of each screen, for visual verification without touching the desktop.
        for (name, section) in [("overview", AppModel.Section.overview), ("app", .app), ("share", .share), ("settings", .settings)] {
            model.hasOnboarded = true
            model.section = section
            model.custom.doc.mode = .usage
            let r = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("screen-\(name).png"))
            }
        }
        model.hasOnboarded = false
        let ob = ImageRenderer(content: RootView().environmentObject(model).frame(width: 860, height: 580).environment(\.colorScheme, .dark))
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
        let ce = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
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
        let us = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
        us.scale = 2
        if let cg = us.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("screen-usage-photo.png"))
        }
        model.custom.doc.background = "default"
        model.dataStyle.template = .report
        let rp = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
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
        let presetShot = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 1200).environment(\.colorScheme, .dark))
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
        let emptyShot = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
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
