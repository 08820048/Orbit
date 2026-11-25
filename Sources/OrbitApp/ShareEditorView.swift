import AppKit
import OrbitCore
import SwiftUI
import UniformTypeIdentifiers

struct ShareEditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var style = ShareStyle()
    @State private var toast: String?

    private var data: ShareData {
        guard let s = model.summary else { return .placeholder }
        let entries = s.topApps.prefix(10).map { app -> ShareEntry in
            let info = model.catalog.info(for: app.bundleID)
            return ShareEntry(id: app.bundleID, name: info.name, icon: info.icon, seconds: app.seconds)
        }
        return ShareData(
            periodTitle: model.periodTitle,
            coverage: "记录 \(s.daily.count) 天",
            totalSeconds: s.totalSeconds, averageSeconds: s.averagePerActiveDay,
            longestDay: s.longestDay, appCount: s.appCount,
            share: s.totalSeconds > 0 ? (s.topApps.first?.seconds ?? 0) / s.totalSeconds : 0,
            entries: Array(entries))
    }

    var body: some View {
        let data = data
        VStack(spacing: 0) {
            ScreenHeader(title: "生成分享图") {
                Text("\(model.periodTitle) · Top \(style.topN)").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Button("存储为 PNG…") { save(data) }.glassButton().disabled(data.isEmpty)
                Button("拷贝图片  ⌘C") { copy(data) }
                    .glassButton(primary: true).keyboardShortcut("c", modifiers: .command).disabled(data.isEmpty)
            }
            HStack(spacing: 0) {
                preview(data)
                inspector.frame(width: 300)
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(height: 32)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: Preview

    private func preview(_ data: ShareData) -> some View {
        GeometryReader { geo in
            let size = style.template.size
            let s = min((geo.size.width - 80) / size.width, (geo.size.height - 90) / size.height, 1)
            ZStack {
                if data.isEmpty {
                    EmptyStateView().frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ShareCardView(style: style, data: data)
                        .scaleEffect(s, anchor: .center)
                        .frame(width: size.width * s, height: size.height * s)
                        .shadow(color: .black.opacity(0.5), radius: 40, y: 24)
                        .shadow(color: Theme.accent.opacity(0.25), radius: 40)
                        .animation(.easeOut(duration: 0.18), value: style.cornerRadius)
                        .position(x: geo.size.width / 2, y: (geo.size.height - 24) / 2)
                    Text("\(style.template.ratio) · 适合朋友圈 / 小红书").font(.system(size: 11)).foregroundStyle(Theme.text2)
                        .position(x: geo.size.width / 2, y: geo.size.height - 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Inspector

    private var inspector: some View {
        OScroll {
            VStack(spacing: 0) {
                group(GI.layout, "模板") {
                    HStack(spacing: 8) {
                        ForEach(ShareTemplate.allCases) { t in
                            Text(t.rawValue).font(.system(size: 11)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 84, alignment: .bottomLeading).padding(8)
                                .background(templateThumb(t), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(style.template == t ? Theme.accentHi : Theme.line, lineWidth: style.template == t ? 2 : 0.5))
                                .onTapGesture { style.template = t }
                        }
                    }
                    row("尺寸") { Text(style.template.ratio).foregroundStyle(Theme.text2) }
                }
                group(GI.background, "背景") {
                    GlassSegmented(options: BackgroundKind.allCases, label: \.rawValue, selection: $style.background, fill: true)
                    HStack(spacing: 10) {
                        ForEach(CardPalette.all) { p in
                            Circle().fill(LinearGradient(colors: [p.top, p.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                                .padding(2)
                                .overlay(Circle().strokeBorder(style.palette == p.id ? Theme.accentHi : .clear, lineWidth: 2))
                                .onTapGesture { style.palette = p.id }
                        }
                    }
                }
                group(GI.sliders, "圆角与主题色") {
                    row("圆角") { Text("\(Int(style.cornerRadius)) pt").foregroundStyle(Theme.text2).monospacedDigit() }
                    Slider(value: $style.cornerRadius, in: 0...56, step: 2)
                    row("主题色") {
                        HStack(spacing: 9) {
                            ForEach(AccentChoice.all) { a in
                                Circle().fill(LinearGradient(colors: [a.hi, a.lo], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 18, height: 18).padding(2)
                                    .overlay(Circle().strokeBorder(style.accent == a.id ? Theme.accentHi : .clear, lineWidth: 2))
                                    .onTapGesture { style.accent = a.id }
                            }
                        }
                    }
                }
                group(GI.eye, "显示内容") {
                    row("应用图标") { GlassToggle(isOn: $style.showIcons) }
                    row("排名序号") { GlassToggle(isOn: $style.showRank) }
                    row("具体时长") { GlassToggle(isOn: $style.showHours) }
                    row("显示数量") {
                        GlassSegmented(options: [5, 10], label: { "Top \($0)" }, selection: $style.topN)
                    }
                }
                group(GI.tag, "签名") {
                    row("署名") {
                        TextField("", text: $style.signature).textFieldStyle(.plain).font(.system(size: 12))
                            .padding(.horizontal, 8).frame(width: 140, height: 24)
                            .background(Theme.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    row("Orbit 水印") { GlassToggle(isOn: $style.watermark) }
                }
            }
        }
        .background(Theme.sidebar)
    }

    private func templateThumb(_ t: ShareTemplate) -> some ShapeStyle {
        switch t {
        case .ranking: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0F2C66), Color(hex: 0x060E20)], startPoint: .top, endPoint: .bottom))
        case .card: AnyShapeStyle(RadialGradient(colors: [Theme.accent.opacity(0.7), Color(hex: 0x060E20)], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 60))
        case .report: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0F2C66), Color(hex: 0x0A1B44)], startPoint: .topTrailing, endPoint: .bottomLeading))
        }
    }

    private func group<C: View>(_ icon: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) { GlassIcon(index: icon, size: 20); Text(title).font(.system(size: 12, weight: .semibold)) }
                .padding(.bottom, 1)
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); trailing().font(.system(size: 12)) }
    }

    // MARK: Export

    private func copy(_ data: ShareData) {
        guard let png = ShareRenderer.png(style: style, data: data) else { return flash("生成失败") }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        flash("已拷贝到剪贴板")
    }

    private func save(_ data: ShareData) {
        guard let png = ShareRenderer.png(style: style, data: data) else { return flash("生成失败") }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Orbit \(model.periodTitle).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try png.write(to: url); flash("已保存") } catch { flash("保存失败：\(error.localizedDescription)") }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
