import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CustomShareView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var custom: CustomShareModel
    @State private var showPicker = false
    @State private var toast: String?
    @State private var bgTab = 0   // 0 built-in, 1 my picture, 2 solid

    private var groups: [ResolvedGroup] {
        custom.doc.groups.map { g in
            ResolvedGroup(id: g.id, name: g.name, apps: g.bundleIDs.map { custom.resolve($0, catalog: model.catalog) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "自定义分享") {
                Text("\(custom.doc.title.isEmpty ? "未命名" : custom.doc.title) · \(custom.totalApps) 个软件")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                Button("存储为 PNG…") { save() }.glassButton().disabled(custom.totalApps == 0)
                Button("拷贝图片  ⌘C") { copy() }.glassButton(primary: true)
                    .keyboardShortcut("c", modifiers: .command).disabled(custom.totalApps == 0)
            }
            HStack(spacing: 0) {
                preview
                inspector.frame(width: 340)
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(height: 32)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showPicker) { AppPickerSheet(custom: custom).environmentObject(model) }
        .task {
            await custom.loadInstalledIfNeeded()
            custom.seedIfNeeded(scores: model.recencyScores())
        }
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { geo in
            let size = custom.doc.ratio.size
            let s = min((geo.size.width - 80) / size.width, (geo.size.height - 80) / size.height, 1)
            ZStack {
                if custom.totalApps == 0 {
                    VStack(spacing: 14) {
                        GlassIcon(index: GI.layout, size: 84)
                        Text("还没有选择软件").font(.system(size: 18, weight: .bold))
                        Text("从这台 Mac 已安装的软件里挑出你想展示的，分组后生成分享图。")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Button("从已安装软件中选择…") { showPicker = true }.glassButton(primary: true)
                    }
                    .padding(.horizontal, 40)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    CustomShareCardView(doc: custom.doc, groups: groups)
                        .scaleEffect(s)
                        .frame(width: size.width * s, height: size.height * s)
                        .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
                        .shadow(color: Theme.accent.opacity(0.22), radius: 40)
                        .position(x: geo.size.width / 2, y: (geo.size.height - 20) / 2)
                    Text("\(custom.doc.ratio.label) · 可在右侧切换比例")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
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
                group(GI.docs, "文案") {
                    field("标题") { TextField("标题", text: $custom.doc.title) }
                    field("文案（可留空，可换行）") { TextField("一句话", text: $custom.doc.caption, axis: .vertical).lineLimit(1...3) }
                    field("署名") { TextField("署名", text: $custom.doc.signature) }
                }
                group(GI.stats, "软件与分组") {
                    if custom.doc.groups.isEmpty {
                        Text("还没有分组").font(.system(size: 12)).foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
                    }
                    ForEach(custom.doc.groups) { g in groupRow(g) }
                    if let note = custom.presetNote {
                        HStack(alignment: .top, spacing: 8) {
                            GlassIcon(index: GI.shield, size: 18)
                            Text(note).font(.system(size: 11)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 11).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accentHi.opacity(0.4), lineWidth: 0.5))
                        .transition(.opacity)
                    }
                    Text("快速添加常用分组").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    FlowLayout(spacing: 7) {
                        ForEach(GroupPreset.all) { preset in
                            let added = custom.hasGroup(named: preset.name)
                            PresetChip(name: preset.name, added: added)
                                .onTapGesture { if !added { withAnimation { custom.addPreset(preset, scores: model.recencyScores()) } } }
                                .help(added ? "已添加" : "添加「\(preset.name)」并按类别推荐软件")
                        }
                    }
                    HStack(spacing: 8) {
                        Button("从已安装软件中选择…") { showPicker = true }.glassButton(primary: true)
                        Button("+ 自定义分组") { custom.addGroup() }.glassButton()
                    }
                }
                group(GI.layout, "模板风格") {
                    HStack(spacing: 8) {
                        ForEach(CustomTemplate.allCases) { t in
                            Text(t.rawValue).font(.system(size: 11)).foregroundStyle(t == .paper ? Color(hex: 0x2A2620) : .white)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottomLeading).padding(7)
                                .background(thumb(t), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(custom.doc.template == t ? Theme.accentHi : Theme.line, lineWidth: custom.doc.template == t ? 2 : 0.5))
                                .onTapGesture { custom.doc.template = t }
                        }
                    }
                    Text(custom.doc.template.blurb).font(.system(size: 11)).foregroundStyle(Theme.text2)
                    row("比例") { GlassSegmented(options: CanvasRatio.allCases, label: \.rawValue, selection: $custom.doc.ratio) }
                }
                group(GI.background, "背景") {
                    GlassSegmented(options: [0, 1, 2], label: { ["内置", "我的图片", "纯色"][$0] }, selection: $bgTab, fill: true)
                    backgroundPicker
                    if custom.doc.background.hasPrefix("builtin:") || custom.doc.background.hasPrefix("custom:") || (custom.doc.background == "default" && custom.doc.template == .fjord) {
                        row("遮罩强度") { Text("\(Int(custom.doc.overlay * 100))%").foregroundStyle(Theme.text2) }
                        Slider(value: $custom.doc.overlay, in: 0...1)
                        row("背景模糊") { Text("\(Int(custom.doc.blur))").foregroundStyle(Theme.text2) }
                        Slider(value: $custom.doc.blur, in: 0...30)
                    }
                }
                group(GI.sliders, "图标与文字") {
                    row("图标大小") { GlassSegmented(options: IconSize.allCases, label: \.rawValue, selection: $custom.doc.iconSize) }
                    row("标题字体") { GlassSegmented(options: TitleFont.allCases, label: \.rawValue, selection: $custom.doc.titleFont) }
                    row("显示软件名称") { GlassToggle(isOn: $custom.doc.showNames) }
                    row("Orbit 水印") { GlassToggle(isOn: $custom.doc.watermark) }
                }
            }
        }
        .background(Theme.sidebar)
    }

    private var backgroundPicker: some View {
        Group {
            switch bgTab {
            case 0:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    bgThumb(id: "default", name: "模板默认") { Rectangle().fill(thumb(custom.doc.template)) }
                    ForEach(BuiltinBackground.all) { b in
                        bgThumb(id: "builtin:" + b.id, name: b.name) {
                            Image(nsImage: BackgroundStore.builtin(b.id) ?? NSImage()).resizable().scaledToFill()
                        }
                    }
                }
            case 1:
                VStack(alignment: .leading, spacing: 8) {
                    if custom.doc.background.hasPrefix("custom:"), let img = BackgroundStore.custom(String(custom.doc.background.dropFirst(7))) {
                        Image(nsImage: img).resizable().scaledToFill().frame(height: 90).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button("选择图片…") { chooseImage() }.glassButton()
                    Text("支持 JPG / PNG / HEIC。图片会复制到 Orbit 自己的目录，不会上传。")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            default:
                HStack(spacing: 10) {
                    ForEach(["0B0D12", "0F2C66", "2A1A4A", "0E3B2E", "F5F0E6", "FFFFFF"], id: \.self) { hex in
                        Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)).padding(2)
                            .overlay(Circle().strokeBorder(custom.doc.background == "solid:" + hex ? Theme.accentHi : .clear, lineWidth: 2))
                            .onTapGesture { custom.doc.background = "solid:" + hex }
                    }
                }
            }
        }
    }

    private func bgThumb<V: View>(id: String, name: String, @ViewBuilder _ content: () -> V) -> some View {
        let on = custom.doc.background == id
        return content().frame(height: 54).frame(maxWidth: .infinity).clipped()
            .overlay(alignment: .bottomLeading) {
                Text(name).font(.system(size: 10)).foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2).padding(.horizontal, 6).padding(.bottom, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.accentHi : Theme.line, lineWidth: on ? 2 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture { custom.doc.background = id }
    }

    private func thumb(_ t: CustomTemplate) -> some ShapeStyle {
        switch t {
        case .fjord: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3A5266), Color(hex: 0x0A121A)], startPoint: .top, endPoint: .bottom))
        case .glass: AnyShapeStyle(RadialGradient(colors: [Theme.accent.opacity(0.8), Color(hex: 0x060E20)], center: .init(x: 0.8, y: 0.1), startRadius: 0, endRadius: 80))
        case .paper: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF5F0E6), Color(hex: 0xE2D9C8)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .minimal: AnyShapeStyle(Color(hex: 0x0B0D12))
        }
    }

    private func groupRow(_ g: ShareGroup) -> some View {
        let active = custom.activeGroup == g.id
        return HStack(spacing: 8) {
            Text("⋮⋮").font(.system(size: 11)).foregroundStyle(Theme.text2)
            TextField("分组名", text: Binding(get: { g.name }, set: { custom.rename(g.id, to: $0) }))
                .textFieldStyle(.plain).font(.system(size: 13))
            Text("\(g.bundleIDs.count) 个").font(.system(size: 11)).foregroundStyle(Theme.text2)
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text2)
                .contentShape(Rectangle()).onTapGesture { custom.removeGroup(g.id) }.help("删除分组")
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(active ? Theme.accentHi : Theme.line, lineWidth: active ? 1 : 0.5))
        .shadow(color: active ? Theme.accent.opacity(0.3) : .clear, radius: 6)
        .contentShape(Rectangle())
        .onTapGesture { custom.activeGroup = g.id }
        .contextMenu {
            Button("上移") { custom.moveGroup(g.id, by: -1) }
            Button("下移") { custom.moveGroup(g.id, by: 1) }
            Button("删除分组", role: .destructive) { custom.removeGroup(g.id) }
        }
    }

    private func group<C: View>(_ icon: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) { GlassIcon(index: icon, size: 20); Text(title).font(.system(size: 12, weight: .semibold)) }
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); trailing().font(.system(size: 12)) }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
            content().textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: Actions

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            custom.doc.background = "custom:" + (try BackgroundStore.importImage(from: url))
        } catch {
            flash("无法导入图片：\(error.localizedDescription)")
        }
    }

    private func png() -> Data? {
        ShareRenderer.png(CustomShareCardView(doc: custom.doc, groups: groups))
    }

    private func copy() {
        guard let data = png() else { return flash("生成失败") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        flash("已拷贝到剪贴板")
    }

    private func save() {
        guard let data = png() else { return flash("生成失败") }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (custom.doc.title.isEmpty ? "Orbit" : custom.doc.title) + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url); flash("已保存") } catch { flash("保存失败：\(error.localizedDescription)") }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task { try? await Task.sleep(nanoseconds: 1_800_000_000); withAnimation { toast = nil } }
    }
}

// MARK: - Picker

private struct PickItem: Identifiable {
    let id: String          // bundle id, or "custom:<uuid>"
    let name: String
    var custom: CustomApp?
}

struct AppPickerSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var custom: CustomShareModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter = 0   // 0 all, 1 recent, 2 selected
    @State private var editing: CustomApp?
    @State private var editingIsNew = false

    private var recentOrder: [String: Double] { model.recencyScores() }

    private var items: [PickItem] {
        let activeIDs = Set(custom.doc.groups.first { $0.id == custom.activeGroup }?.bundleIDs ?? [])
        var customs = custom.doc.customApps.filter { $0.brand == nil || $0.iconFile != nil }.map { PickItem(id: $0.key, name: $0.name, custom: $0) }
        var installed = custom.installed.map { PickItem(id: $0.bundleID, name: $0.name, custom: nil) }
        switch filter {
        case 1:
            let scores = recentOrder
            customs = []
            installed = installed.filter { (scores[$0.id] ?? 0) > 0 }.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        case 2:
            customs = customs.filter { activeIDs.contains($0.id) }
            installed = installed.filter { activeIDs.contains($0.id) }
        default: break
        }
        let all = customs + installed
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GlassIcon(index: GI.stats, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择软件").font(.system(size: 20, weight: .bold))
                    Text("来自这台 Mac 的「应用程序」；没有图标的工具（如 Claude Code）可以自己添加")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Text("添加到").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Picker("", selection: Binding(get: { custom.activeGroup ?? UUID() }, set: { custom.activeGroup = $0 })) {
                    ForEach(custom.doc.groups) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 140)
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    GlassIcon(index: 35, size: 18)
                    TextField("搜索软件名称…", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                GlassSegmented(options: [0, 1, 2], label: { ["全部 \(custom.installed.count + custom.doc.customApps.count)", "最近常用", "已选"][$0] }, selection: $filter)
            }
            .padding(.top, 18)

            if custom.installed.isEmpty && custom.doc.customApps.isEmpty {
                ProgressView("正在读取已安装软件…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if custom.doc.groups.isEmpty {
                Text("请先添加一个分组").foregroundStyle(Theme.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if filter != 1 && (!visibleTools.isEmpty || (filter == 0 && query.isEmpty)) {
                        HStack(spacing: 8) {
                            GlassIcon(index: 2, size: 20)
                            Text("检测到的终端工具").font(.system(size: 13, weight: .semibold))
                            Text(custom.detectedTools.isEmpty
                                 ? "没有在命令行里找到常见工具，可用下方「添加自定义软件」按名称添加"
                                 : "在这台 Mac 的命令行里找到 \(custom.detectedTools.count) 个")
                                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
                        if !visibleTools.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                                ForEach(visibleTools) { tool in toolTile(tool) }
                            }
                            .padding(.top, 10)
                        }
                        HStack(spacing: 8) {
                            Text("已安装的软件").font(.system(size: 13, weight: .semibold))
                            Text("共 \(custom.installed.count) 个").font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        if filter == 0 && query.isEmpty { addTile }
                        ForEach(items) { item in tile(item) }
                    }
                    .padding(.top, 10)
                    Color.clear.frame(height: 16)
                }
            }
            HStack(spacing: 12) {
                Text("本组已选 \(custom.doc.groups.first { $0.id == custom.activeGroup }?.bundleIDs.count ?? 0) 个 · 共 \(custom.totalApps) 个　点击选中或取消；已在别的分组的软件，点击会移到当前分组")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                Spacer()
                Button("完成") { dismiss() }.glassButton(primary: true).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
        .frame(width: 900, height: 720)
        .background(WindowBackground())
        .foregroundStyle(Theme.text)
        .onAppear { if custom.activeGroup == nil { custom.activeGroup = custom.doc.groups.first?.id } }
        .sheet(item: $editing) { app in
            CustomAppSheet(custom: custom, draft: app, isNew: editingIsNew)
        }
    }

    private var visibleTools: [TerminalTool] {
        guard filter != 1 else { return [] }
        let activeIDs = Set(custom.doc.groups.first { $0.id == custom.activeGroup }?.bundleIDs ?? [])
        var tools = custom.terminalTools
        if filter == 2 { tools = tools.filter { t in custom.brandApp(for: t).map { activeIDs.contains($0.key) } ?? false } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { tools = tools.filter { $0.name.lowercased().contains(q) || $0.commands.contains { $0.contains(q) } } }
        return tools
    }

    private func toolTile(_ tool: TerminalTool) -> some View {
        let app = custom.brandApp(for: tool)
        let owner = app.flatMap { custom.groupName(containing: $0.key) }
        let inActive = app.map { custom.doc.groups.first { $0.id == custom.activeGroup }?.bundleIDs.contains($0.key) ?? false } ?? false
        let other = owner != nil && !inActive
        let detected = custom.detectedTools.contains(tool)
        return VStack(spacing: 5) {
            SharpIcon(CustomAppIcons.render(CustomApp.from(tool)), 48).shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(tool.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(TerminalCatalog.command(for: tool)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.text2).lineLimit(1)
            Text(owner ?? (detected ? "终端 · 已检测" : "终端 · 已添加")).font(.system(size: 10)).foregroundStyle(Theme.text2).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.top, 13).padding(.bottom, 9).frame(maxWidth: .infinity)
        .opacity(other ? 0.55 : 1)
        .background(inActive ? Theme.accent.opacity(0.16) : Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(inActive ? Theme.accentHi : Theme.line, lineWidth: inActive ? 1.5 : 0.5))
        .overlay(alignment: .topTrailing) {
            if inActive {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 17, height: 17).background(Circle().fill(Theme.accentGradient)).padding(7)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let g = custom.activeGroup { custom.toggleTool(tool, in: g) } }
    }

    private var addTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.accentHi)
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.accentHi.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            Text("添加自定义软件").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentHi).lineLimit(1)
            Text("终端工具 / 无图标").font(.system(size: 10)).foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 10).frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accentHi.opacity(0.5), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            editingIsNew = true
            editing = CustomApp(name: "")
        }
    }

    private func tile(_ item: PickItem) -> some View {
        let resolved = custom.resolve(item.id, catalog: model.catalog)
        let owner = custom.groupName(containing: item.id)
        let inActive = custom.doc.groups.first { $0.id == custom.activeGroup }?.bundleIDs.contains(item.id) ?? false
        let other = owner != nil && !inActive
        return VStack(spacing: 6) {
            SharpIcon(resolved.icon, 48).shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(resolved.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Text(item.custom != nil ? "自定义" + (owner.map { " · \($0)" } ?? " · 可编辑") : (owner ?? " "))
                .font(.system(size: 10)).foregroundStyle(Theme.text2).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 10).frame(maxWidth: .infinity)
        .opacity(other ? 0.55 : 1)
        .background(inActive ? Theme.accent.opacity(0.16) : Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(inActive ? Theme.accentHi : Theme.line, lineWidth: inActive ? 1.5 : 0.5))
        .overlay(alignment: .topTrailing) {
            if inActive {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(Theme.accentGradient)).padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let g = custom.activeGroup { custom.toggle(item.id, in: g) } }
        .contextMenu {
            if let app = item.custom {
                Button("编辑…") { editingIsNew = false; editing = app }
                Button("删除", role: .destructive) { custom.removeCustom(app) }
            }
        }
    }
}

// MARK: - Add / edit a custom app

struct CustomAppSheet: View {
    @ObservedObject var custom: CustomShareModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: CustomApp
    let isNew: Bool
    @State private var pending: NSImage?
    @State private var targeted = false
    @State private var error: String?
    @State private var groupID: UUID?

    init(custom: CustomShareModel, draft: CustomApp, isNew: Bool) {
        self.custom = custom
        _draft = State(initialValue: draft)
        self.isNew = isNew
        _groupID = State(initialValue: custom.activeGroup)
    }

    private var suggestions: [TerminalTool] {
        // Hide once a catalog tool has been applied (name equals it) so the list doesn't linger.
        if let id = draft.brand, let tool = TerminalCatalog.tool(id: id), tool.name == draft.name { return [] }
        return TerminalCatalog.match(draft.name)
    }

    private func apply(_ tool: TerminalTool) {
        draft.name = tool.name
        draft.brand = tool.id
        draft.squircle = tool.tileHex != nil
        draft.colorHex = tool.tileHex ?? "FFFFFF"
        draft.iconFile = nil
        pending = nil
        error = nil
    }

    private static let swatches = ["D97757", "1A1D24", "F5F5F2", "2F6BEA", "2E9B6A", "7B5CE0"]
    private var canAdd: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GlassIcon(index: GI.megaphone, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "添加自定义软件" : "编辑自定义软件").font(.system(size: 15, weight: .bold))
                    Text("图片只保存在这台 Mac 上，不上传").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    label("图标")
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accent.opacity(targeted ? 0.18 : 0.07))
                        RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.accentHi.opacity(0.5), lineWidth: 1)
                        VStack(spacing: 8) {
                            SharpIcon(CustomAppIcons.render(draft, image: pending ?? CustomAppIcons.loadFile(draft.iconFile)), 84)
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                            Text("拖入图片到这里").font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                    }
                    .frame(width: 150, height: 150)
                    .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in load(providers) }
                    Button("选择图片…") { choose() }.glassButton()
                    Button("粘贴剪贴板图片") { paste() }.glassButton()
                    if draft.iconFile != nil || pending != nil || draft.brand != nil {
                        Button("移除图片 / logo") { pending = nil; draft.iconFile = nil; draft.brand = nil }.buttonStyle(.plain).focusable(false)
                            .font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        label("名称")
                        TextField("例如 Claude Code、Gemini CLI", text: $draft.name).textFieldStyle(.plain).font(.system(size: 13))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        if !suggestions.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(suggestions) { tool in
                                    HStack(spacing: 10) {
                                        SharpIcon(CustomAppIcons.render(CustomApp.from(tool)), 28)
                                        Text(tool.name).font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Text(TerminalCatalog.command(for: tool)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text2)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                                    .onTapGesture { apply(tool) }
                                }
                            }
                            .padding(4).background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 0.5))
                            Text("点一下自动填好名称和 logo").font(.system(size: 10)).foregroundStyle(Theme.text2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        label("图标样式")
                        GlassSegmented(options: [true, false], label: { $0 ? "自动圆角方形" : "保持原样" }, selection: $draft.squircle, fill: true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        label("底色（图片带透明背景，或没有图片时使用）")
                        HStack(spacing: 10) {
                            ForEach(Self.swatches, id: \.self) { hex in
                                Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)).padding(2)
                                    .overlay(Circle().strokeBorder(draft.colorHex == hex ? Theme.accentHi : .clear, lineWidth: 2))
                                    .onTapGesture { draft.colorHex = hex }
                            }
                        }
                    }
                    if isNew {
                        VStack(alignment: .leading, spacing: 5) {
                            label("添加到分组")
                            Picker("", selection: Binding(get: { groupID ?? UUID() }, set: { groupID = $0 })) {
                                ForEach(custom.doc.groups) { Text($0.name).tag($0.id) }
                            }
                            .labelsHidden()
                        }
                    }
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 20)
            Spacer(minLength: 16)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.glassButton().keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") { commit() }.glassButton(primary: true)
                    .keyboardShortcut(.defaultAction).disabled(!canAdd)
            }
        }
        .padding(24).frame(width: 560, height: 520)
        .background(WindowBackground())
        .foregroundStyle(Theme.text)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.text2)
    }

    // MARK: Image input

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        set(NSImage(contentsOf: url))
    }

    private func paste() {
        set(NSImage(pasteboard: .general))
    }

    private func load(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                DispatchQueue.main.async { set(object as? NSImage) }
            }
            return true
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) } else if let u = item as? URL { url = u }
            DispatchQueue.main.async { set(url.flatMap { NSImage(contentsOf: $0) }) }
        }
        return true
    }

    private func set(_ image: NSImage?) {
        guard let image, image.isValid else { error = "没有读到可用的图片，请换一张（PNG / JPG / HEIC / SVG）。"; return }
        error = nil
        pending = image
        draft.brand = nil   // the user's own picture wins over a catalog logo
    }

    private func commit() {
        var app = draft
        app.name = app.name.trimmingCharacters(in: .whitespaces)
        // Typed a known name exactly and gave no picture: use its logo.
        if app.brand == nil, pending == nil, app.iconFile == nil,
           let tool = TerminalCatalog.match(app.name, limit: 1).first,
           ([tool.name.lowercased()] + tool.aliases.map({ $0.lowercased() }) + tool.commands).contains(app.name.lowercased()) {
            let a = CustomApp.from(tool)
            app.brand = a.brand; app.squircle = a.squircle; app.colorHex = a.colorHex
        }
        do {
            if let pending {
                CustomAppIcons.delete(file: custom.customApp(forKey: app.key)?.iconFile)
                app.iconFile = try CustomAppIcons.save(pending)
            }
        } catch {
            self.error = "保存图片失败：\(error.localizedDescription)"
            return
        }
        if isNew { custom.addCustom(app, to: groupID) } else { custom.updateCustom(app) }
        dismiss()
    }
}
