import AppKit
import SwiftUI

@main
struct OrbitApp: App {
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

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView().frame(width: 220)
            Group {
                switch model.section {
                case .overview: OverviewView()
                case .app: AppDetailView()
                case .share: ShareEditorView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                GlassIcon(index: GI.orbit, size: 30)
                Text("Orbit").font(.system(size: 15, weight: .bold)).tracking(0.3)
            }
            .padding(.horizontal, 8).padding(.top, 34).padding(.bottom, 18)

            sectionLabel("统计")
            row("年度总览", GI.trend, .overview, meta: model.summary.map { _ in model.periodTitle })
            row("单个应用", GI.stats, .app)
            sectionLabel("分享").padding(.top, 14)
            row("生成分享图", GI.share, .share)

            Spacer()
            HStack(alignment: .top, spacing: 10) {
                GlassIcon(index: GI.shield, size: 28)
                Text("数据来源：屏幕使用时间\n\(model.coverageText)\n仅存于本机，不上传")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2).lineSpacing(3)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: 14)
            .padding(.horizontal, 4).padding(.bottom, 8)
            row("设置", GI.gear, .settings)
        }
        .padding(.horizontal, 10).padding(.bottom, 16)
        .background(Theme.sidebar)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func row(_ title: String, _ icon: Int, _ section: AppModel.Section, meta: String? = nil) -> some View {
        let selected = model.section == section
        return HStack(spacing: 10) {
            GlassIcon(index: icon, size: 22)
            Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
            Spacer()
            if let meta { Text(meta).font(.system(size: 11)).foregroundStyle(Theme.text2) }
        }
        .padding(.horizontal, 8).frame(height: 34)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.section = section }
        .accessibilityAddTraits(.isButton)
    }
}

/// Header bar shared by the main screens.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 24).padding(.top, 14).frame(height: 62, alignment: .center)
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
        let entries = s.topApps.prefix(10).map {
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
            let r = ImageRenderer(content: RootView().environmentObject(model).frame(width: 1280, height: 800).environment(\.colorScheme, .dark))
            r.scale = 1
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
        for kind in BackgroundKind.allCases {
            var st = ShareStyle(); st.background = kind
            if let png = ShareRenderer.png(style: st, data: data) { try? png.write(to: dir.appendingPathComponent("bg-\(kind.rawValue).png")) }
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
