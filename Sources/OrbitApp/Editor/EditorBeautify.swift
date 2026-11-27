import AppKit
import OrbitCore
import SwiftUI

/// The beautify page: a live preview of the finished picture next to the inspector.
struct BeautifyPage: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            preview
            BeautifyInspector(model: model)
                .frame(width: 320)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.trailing, 12).padding(.bottom, 12)
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            ZStack {
                if let cg = model.beautifyPreview() {
                    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    Image(nsImage: image).resizable().scaledToFit()
                        .background { if model.style.backgroundValue == .none { Checkerboard() } }
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .padding(28)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                let l = BeautifyLayout.compute(content: model.outputSize, style: model.style, pixelsPerPoint: model.pixelsPerPoint)
                Text("\(Int(l.canvas.width)) × \(Int(l.canvas.height)) px").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Spacer()
                Text(model.style.backgroundValue == .none ? "透明背景：保存为 PNG 会保留透明，JPG 会铺成白底" : String(localized: "在这一页点「完成」，保存的就是现在看到的样子"))
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 24).frame(height: 40)
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in 0..<Int(ceil(size.height / s)) {
                for x in 0..<Int(ceil(size.width / s)) {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)),
                             with: .color((x + y) % 2 == 0 ? Color(white: 0.22) : Color(white: 0.28)))
                }
            }
        }
    }
}

struct BeautifyInspector: View {
    @ObservedObject var model: EditorModel

    private var style: BeautifyStyle { model.style }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                presets
                background
                appearance
                windowFrame
                size
                signature
            }
            .padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Presets

    private var presets: some View {
        section("一键预设") {
            HStack(spacing: 8) {
                ForEach(BeautifyPreset.allCases) { p in
                    let on = BeautifyPreset.matching(style) == p
                    VStack(spacing: 6) {
                        Group {
                            if let image = model.presetThumbnail(p) {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else {
                                Rectangle().fill(Theme.control)
                            }
                        }
                        .frame(height: 50).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(LocalizedStringKey(p.rawValue)).font(.system(size: 11)).foregroundStyle(on ? Theme.text : Theme.text2)
                    }
                    .padding(6)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2))
                    .contentShape(Rectangle())
                    .onTapGesture { model.applyPreset(p) }
                }
            }
        }
    }

    // MARK: Background

    private enum BackgroundKind: Int, CaseIterable { case gradient, image, solid
        var label: String { [String(localized: "渐变"), String(localized: "图片"), String(localized: "纯色")][rawValue] }
    }

    private var backgroundKind: BackgroundKind {
        switch style.backgroundValue {
        case .gradient: .gradient
        case .builtin, .custom: .image
        case .solid, .none: .solid
        }
    }

    private var background: some View {
        section("背景") {
            GlassSegmented(options: BackgroundKind.allCases, label: \.label,
                           selection: Binding(get: { backgroundKind }, set: { setKind($0) }), fill: true)
            switch backgroundKind {
            case .gradient: gradientSwatches
            case .image: imageChoices
            case .solid: solidChoices
            }
        }
    }

    private func setKind(_ kind: BackgroundKind) {
        guard kind != backgroundKind else { return }
        switch kind {
        case .gradient: model.style.background = BeautifyBackground.defaultGradient.string
        case .image: model.style.background = "builtin:" + (BuiltinBackground.all.first?.id ?? "fjord")
        case .solid: model.style.background = "solid:EEF1F6"
        }
    }

    private var gradientSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
            ForEach(BeautifyBackground.gradients, id: \.name) { g in
                let value = "gradient:\(g.from),\(g.to)"
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hexString: g.from), Color(hexString: g.to)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    .padding(2)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(style.background == value ? Theme.accent : .clear, lineWidth: 2))
                    .help(g.name)
                    .onTapGesture { model.style.background = value }
            }
        }
    }

    private var imageChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                ForEach(BuiltinBackground.all) { bg in
                    Group {
                        if let image = BackgroundStore.builtin(bg.id) { Image(nsImage: image).resizable().scaledToFill() } else { Color.gray }
                    }
                    .frame(width: 62, height: 40).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(style.background == "builtin:" + bg.id ? Theme.accent : .clear, lineWidth: 2))
                    .help(bg.name)
                    .onTapGesture { model.style.background = "builtin:" + bg.id }
                }
            }
            Button("选择图片…") { chooseImage() }.glassButton()
        }
    }

    private static let solidPalette = ["FFFFFF", "EEF1F6", "D9DEE8", "8FA3C8", "3B82F6", "1E2230", "0B0D12", "000000"]

    private var solidChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                // transparent
                ZStack { Checkerboard(); Image(systemName: "nosign").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)) }
                    .frame(width: 26, height: 26).clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .padding(2)
                    .overlay(Circle().strokeBorder(style.background == "none" ? Theme.accent : .clear, lineWidth: 2))
                    .help("透明")
                    .onTapGesture { model.style.background = "none" }
                ForEach(Self.solidPalette.prefix(7), id: \.self) { hex in
                    Circle().fill(Color(hexString: hex)).frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                        .padding(2)
                        .overlay(Circle().strokeBorder(style.background == "solid:" + hex ? Theme.accent : .clear, lineWidth: 2))
                        .onTapGesture { model.style.background = "solid:" + hex }
                }
            }
            ColorPicker("自定义颜色", selection: Binding(
                get: { if case let .solid(c) = style.backgroundValue { return Color(.sRGB, red: c.r, green: c.g, blue: c.b) }; return .white },
                set: { new in
                    let ns = NSColor(new).usingColorSpace(.sRGB) ?? .white
                    model.style.background = "solid:" + AnnotationColor(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)).hex
                }), supportsOpacity: false)
                .font(.system(size: 12))
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let file = try? BackgroundStore.importImage(from: url) else { return }
        model.style.background = "custom:" + file
    }

    // MARK: Look

    private var appearance: some View {
        section("外观") {
            slider(String(localized: "边距"), value: $model.style.padding, range: 0...120, format: { "\(Int($0)) px" })
            slider(String(localized: "圆角"), value: $model.style.cornerRadius, range: 0...40, format: { "\(Int($0)) pt" })
            slider(String(localized: "阴影"), value: $model.style.shadow, range: 0...1, format: { "\(Int($0 * 100))%" })
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13))
            Spacer()
            Slider(value: value, in: range).frame(width: 130)
            Text(format(value.wrappedValue)).font(.system(size: 12)).foregroundStyle(Theme.text2).monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }

    // MARK: Frame

    private var windowFrame: some View {
        section("窗口边框") {
            GlassSegmented(options: BeautifyFrame.allCases, label: \.label, selection: $model.style.frame, fill: true)
            if style.frame != .none {
                HStack(spacing: 10) {
                    Text(style.frame == .window ? "标题" : String(localized: "页面标题")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    TextField(style.frame == .window ? "例如 账户设置" : String(localized: "地址栏里显示的文字"), text: $model.style.title)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                if style.frame == .browser {
                    Text("只显示你填的文字，不会读取真实网址。").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
        }
    }

    // MARK: Size

    private var size: some View {
        section("尺寸") {
            FlowLayout(spacing: 6) {
                ForEach(BeautifyRatio.allCases, id: \.self) { r in
                    let on = style.ratio == r
                    Text(LocalizedStringKey(r.rawValue)).font(.system(size: 12)).foregroundStyle(on ? Color.white : Theme.text2)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.control), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { model.style.ratio = r }
                }
            }
        }
    }

    // MARK: Signature

    private var signature: some View {
        section("署名") {
            HStack { Text("显示署名").font(.system(size: 13)); Spacer(); GlassToggle(isOn: $model.style.showSignature) }
            if style.showSignature {
                TextField("署名", text: $model.style.signature).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            HStack { Text("Orbit 水印").font(.system(size: 13)); Spacer(); GlassToggle(isOn: $model.style.showWatermark) }
            if style.showSignature || style.showWatermark {
                Text("署名和水印画在窗口下方的空白处；边距太小放不下时会省略。").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
        }
    }
}
