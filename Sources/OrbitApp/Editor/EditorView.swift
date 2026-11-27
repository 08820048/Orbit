import AppKit
import OrbitCore
import SwiftUI

/// The editor window's content: title and actions, tools, the properties of the current tool, the canvas, a status line.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    let controller: EditorWindowController

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            propertiesRow
            EditorCanvas(model: model)
            statusBar
        }
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        // Hidden buttons that only carry keyboard shortcuts.
        .background(
            Group {
                Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command)
                Button("") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
                Button("") { controller.saveAsNew() }.keyboardShortcut("s", modifiers: .command)
                Button("") { controller.overwriteOriginal() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
            .opacity(0).frame(width: 0, height: 0)
        )
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(model.record.url.deletingPathExtension().lastPathComponent).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                if model.isDirty { Text("· 已编辑").font(.system(size: 12)).foregroundStyle(Theme.text2) }
            }
            .frame(width: 150, alignment: .leading)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            toolbar
            Spacer(minLength: 0)
            Button("取消") { controller.requestClose() }.glassButton()
            Button("复制") { controller.copyToClipboard() }.glassButton()
            SaveSplitButton(saveNew: { controller.saveAsNew() }, overwrite: { controller.overwriteOriginal() })
        }
        .padding(.leading, 84).padding(.trailing, 20).frame(height: 52)
    }

    // MARK: Tools

    /// One pill: the drawing tools, undo and redo, and the beautify button.
    private var toolbar: some View {
        HStack(spacing: 1) {
            ForEach(EditorModel.Tool.allCases) { tool in
                let on = model.tool == tool
                toolGlyph(tool)
                    .frame(width: 34, height: 30)
                    .foregroundStyle(on ? Theme.text : Theme.text2)
                    .background { if on { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control) } }
                    .contentShape(Rectangle())
                    .onTapGesture { model.tool = tool }
                    .help("\(tool.title)（\(tool.key.uppercased())）")
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 18).padding(.horizontal, 6)
            iconButton("arrow.uturn.backward", enabled: model.canUndo, help: String(localized: "撤销（⌘Z）")) { model.undo() }
            iconButton("arrow.uturn.forward", enabled: model.canRedo, help: String(localized: "重做（⇧⌘Z）")) { model.redo() }
            Rectangle().fill(Theme.line).frame(width: 1, height: 18).padding(.horizontal, 6)
            Image(systemName: "paintpalette").font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 30)
                .foregroundStyle(model.beautifyOn ? Color.white : Theme.text2)
                .background { if model.beautifyOn { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent) } }
                .contentShape(Rectangle())
                .onTapGesture {
                    // First click turns beautify on and opens the panel; after that the button only opens and closes the panel.
                    if !model.beautifyOn { model.beautifyOn = true; model.showBeautifyPanel = true } else { model.showBeautifyPanel.toggle() }
                }
                .help("美化：背景、边距、圆角、阴影、外框")
                .popover(isPresented: $model.showBeautifyPanel, arrowEdge: .bottom) { BeautifyPanel(model: model) }
        }
        .padding(3).background(Theme.control, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// The text tool is a plain "T": the system's text symbol turns into the word "格式" on Chinese systems.
    @ViewBuilder
    private func toolGlyph(_ tool: EditorModel.Tool) -> some View {
        if tool == .text {
            Text("T").font(.system(size: 17, weight: .semibold, design: .serif))
        } else {
            Image(systemName: tool.symbol).font(.system(size: 14, weight: .medium))
        }
    }

    private func iconButton(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 32, height: 30).foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.35).disabled(!enabled).help(help)
    }

    // MARK: Properties of the current tool (or of the selected annotation)

    private enum PropertyKind { case stroke, text, blur, crop, marker, highlight, hint }

    private var propertyKind: PropertyKind {
        if model.tool == .crop { return .crop }
        let shape: AnnotationShape? = model.tool == .select ? model.selected?.shape : nil
        switch model.tool {
        case .text: return .text
        case .blur: return .blur
        case .marker: return .marker
        case .highlight: return .highlight
        case .arrow, .rectangle, .ellipse, .line: return .stroke
        case .select:
            switch shape {
            case .text: return .text
            case .blur: return .blur
            case .marker: return .marker
            case .highlight: return .highlight
            case .some: return .stroke
            case .none: return .hint
            }
        case .crop: return .crop
        }
    }

    private var propertiesRow: some View {
        HStack(spacing: 26) {
            switch propertyKind {
            case .stroke:
                colorSwatches
                labeled("粗细") { levelPicker(LineLevel.allCases, selection: model.lineLevel, content: { level in
                    Capsule().fill(.primary).frame(width: 16, height: [2, 4, 7][level.rawValue - 1])
                }) { level in
                    model.lineLevel = level
                    model.restyleSelected { $0.lineWidth = AnnotationScale.lineWidth(level, imageWidth: model.imageSize.width) }
                } }
                labeled("阴影") { GlassToggle(isOn: Binding(get: { model.shadow }, set: { v in model.shadow = v; model.restyleSelected { $0.shadow = v } })) }
            case .text:
                colorSwatches
                labeled("字号") { levelPicker(TextLevel.allCases, selection: model.textLevel, content: { level in
                    Text("A").font(.system(size: [11, 14, 18][level.rawValue - 1], weight: .semibold))
                }) { level in
                    model.textLevel = level
                    model.restyleSelected { $0.fontSize = AnnotationScale.fontSize(level, imageWidth: model.imageSize.width) }
                } }
                labeled("底色") { GlassToggle(isOn: Binding(get: { model.textBackground }, set: { v in model.textBackground = v; model.restyleSelected { $0.textBackground = v } })) }
            case .marker:
                colorSwatches
                labeled("大小") { levelPicker(TextLevel.allCases, selection: model.textLevel, content: { level in
                    Image(systemName: "circle.fill").font(.system(size: [8, 11, 15][level.rawValue - 1]))
                }) { level in
                    model.textLevel = level
                    model.restyleSelected { $0.fontSize = AnnotationScale.fontSize(level, imageWidth: model.imageSize.width) }
                } }
                labeled("阴影") { GlassToggle(isOn: Binding(get: { model.shadow }, set: { v in model.shadow = v; model.restyleSelected { $0.shadow = v } })) }
                Text("每点一下加一个，删除后会自动重新编号").font(.system(size: 12)).foregroundStyle(Theme.text2)
            case .highlight:
                labeled("颜色") {
                    HStack(spacing: 10) {
                        ForEach(Array(AnnotationColor.highlighters.enumerated()), id: \.offset) { _, c in
                            let on = model.highlightColor == c
                            Circle().fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(on ? Color.white : .clear, lineWidth: 2))
                                .contentShape(Circle())
                                .onTapGesture { model.highlightColor = c; model.restyleSelected { $0.color = c } }
                        }
                    }
                }
                Text("拖一个矩形盖在文字上，半透明，文字依然看得清").font(.system(size: 12)).foregroundStyle(Theme.text2)
            case .blur:
                labeled("样式") {
                    GlassSegmented(options: BlurMode.allCases, label: \.label,
                                   selection: Binding(get: { model.blurMode }, set: { v in model.blurMode = v; model.restyleSelected { $0.blurMode = v } }))
                }
                labeled("强度") { levelPicker([1, 2, 3], selection: model.blurStrength, content: { Text([String(localized: "弱"), String(localized: "中"), String(localized: "强")][$0 - 1]).font(.system(size: 12)) }) { v in
                    model.blurStrength = v
                    model.restyleSelected { $0.blurStrength = v }
                } }
                Text("导出时会真正抹掉这块区域的像素，无法还原").font(.system(size: 12)).foregroundStyle(Theme.text2)
            case .crop:
                labeled("比例") { cropRatios }
                Spacer()
                Button("取消裁剪") { model.cancelCrop() }.glassButton()
                Button("应用裁剪") { model.applyCrop() }.glassButton(primary: true)
            case .hint:
                Text("点击标注选中它，拖动移动，⌫ 删除；选一个工具开始画").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            if propertyKind != .crop { Spacer() }
        }
        .padding(.horizontal, 24).frame(height: 40)
    }

    private func labeled<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.text2)
            content()
        }
    }

    private var colorSwatches: some View {
        labeled("颜色") {
            HStack(spacing: 10) {
                ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) { _, c in
                    let on = model.color == c
                    Circle().fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(on ? Color.white : .clear, lineWidth: 2))
                        .contentShape(Circle())
                        .onTapGesture { model.color = c; model.restyleSelected { $0.color = c } }
                }
            }
        }
    }

    private func levelPicker<T: Hashable, C: View>(_ options: [T], selection: T, @ViewBuilder content: @escaping (T) -> C,
                                                   onSelect: @escaping (T) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = selection == o
                content(o).foregroundStyle(on ? Color.white : Theme.text2)
                    .frame(width: 34, height: 24)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(o) }
            }
        }
        .padding(2).background(Theme.trough, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cropRatios: some View {
        let options: [(String, Double?)] = [(String(localized: "自由"), nil), ("1:1", 1), ("4:3", 4.0 / 3), ("16:9", 16.0 / 9), ("3:4", 3.0 / 4), ("9:16", 9.0 / 16)]
        return HStack(spacing: 8) {
            ForEach(options, id: \.0) { name, ratio in
                let on = model.cropRatio == ratio
                Text(name).font(.system(size: 12)).foregroundStyle(on ? Color.white : Theme.text2)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.control), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { model.setCropRatio(ratio) }
            }
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            if model.tool == .crop, let r = model.cropRect {
                Text("原图 \(Int(model.imageSize.width)) × \(Int(model.imageSize.height)) px")
                Spacer()
                Text("裁剪后 \(Int(r.width.rounded())) × \(Int(r.height.rounded())) px")
                Spacer()
                Text("拖动边和角调整 · 拖动框内移动 · 回车 应用 · Esc 取消")
            } else {
                Text("\(Int(model.outputSize.width)) × \(Int(model.outputSize.height)) px")
                Spacer()
                Text("按住 ⇧ 画正圆、正方形、水平或垂直线 · 双击文字可修改 · ⌫ 删除所选")
            }
        }
        .font(.system(size: 12)).foregroundStyle(Theme.text2)
        .padding(.horizontal, 24).frame(height: 40)
    }
}

/// "完成" with a menu for the other way to save.
private struct SaveSplitButton: View {
    let saveNew: () -> Void
    let overwrite: () -> Void

    var body: some View {
        HStack(spacing: 1) {
            Button(action: saveNew) { Text("完成").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 30) }
                .buttonStyle(.plain)
                .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
            Menu {
                Button("保存为新截图") { saveNew() }.keyboardShortcut("s", modifiers: .command)
                Button("覆盖原图") { overwrite() }.keyboardShortcut("s", modifiers: [.command, .option])
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).frame(width: 26, height: 30)
                    .background(fill, in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 9, topTrailingRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
        }
        .shadow(color: Theme.accent.opacity(0.28), radius: 8, y: 5)
        .help("完成：保存为新截图，原图保留")
    }

    private var fill: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x5C9DFF), Color(hex: 0x3B82F6), Color(hex: 0x2D6CE3)], startPoint: .top, endPoint: .bottom)
    }
}
