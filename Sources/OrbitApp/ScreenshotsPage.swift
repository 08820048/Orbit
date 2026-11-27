import AppKit
import ImageIO
import OrbitCore
import SwiftUI

/// Small cached thumbnails, decoded off the main thread.
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path)@\(maxPixel)@\(modified)" as NSString
    }

    private static func decode(_ url: URL, _ maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Already decoded, or (only in the offscreen render check, which never runs `.task`) decoded right now.
    static func ready(for url: URL, maxPixel: Int) -> NSImage? {
        let key = key(url, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        guard OScroll<EmptyView>.flat, let image = decode(url, maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func image(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = key(url, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        let image: NSImage? = await Task.detached(priority: .utility) { decode(url, maxPixel) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// The "截图" page: every screenshot, or the permission guide when Orbit cannot capture yet.
struct ScreenshotsPage: View {
    @EnvironmentObject var model: AppModel
    var body: some View { ScreenshotsContent(capture: model.capture) }
}

private struct ReloadKey: Hashable {
    var version: Int
    var kind: CaptureKind?
    var search: String
}

private struct ScreenshotsContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var capture: CaptureCoordinator
    @State private var kind: CaptureKind?
    @State private var search = ""
    @State private var records: [ScreenshotRecord] = []
    @State private var total: Int
    @State private var bytes: Int64

    /// Starts with the data already loaded, so the page never flashes the empty state before the first reload.
    init(capture: CaptureCoordinator) {
        _capture = ObservedObject(wrappedValue: capture)
        _records = State(initialValue: capture.records(kind: nil, search: ""))
        _total = State(initialValue: capture.count)
        _bytes = State(initialValue: capture.totalBytes)
    }

    private var settings: CaptureSettings { model.captureSettings }

    var body: some View {
        Group {
            if let open = model.openShot {
                ScreenshotDetail(record: open, all: records, capture: capture) { model.openShot = nil }
            } else if capture.needsPermission && total == 0 {
                PermissionGuide(capture: capture)
            } else {
                library
            }
        }
        .task(id: ReloadKey(version: capture.libraryVersion, kind: kind, search: search)) {
            records = capture.records(kind: kind, search: search)
            total = capture.count
            bytes = capture.totalBytes
        }
        .onAppear { capture.reconcile() }
    }

    // MARK: Library

    private var library: some View {
        OScroll {
            VStack(alignment: .leading, spacing: 0) {
                toolbarRow
                if capture.needsPermission { permissionBanner.padding(.top, 18) }
                if records.isEmpty { empty.padding(.top, 60) } else { groups }
            }
            .padding(.horizontal, 56).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One row at the top: filter and totals on the left, search, Finder and the capture button on the right.
    private var toolbarRow: some View {
        HStack(spacing: 14) {
            GlassSegmented(options: [CaptureKind?.none, .region, .window, .fullscreen], label: { $0?.label ?? String(localized: "全部") }, selection: $kind)
            Text("\(total) 张 · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.text2)
                if CommandLine.arguments.contains("--render-check") {
                    Text("搜索文件名、应用").font(.system(size: 12)).foregroundStyle(Theme.text2)   // offscreen renders cannot draw a text field
                } else {
                    TextField("搜索文件名、应用", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10).frame(width: 220, height: 30)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Button("在 Finder 中显示") { NSWorkspace.shared.open(settings.folderURL) }
                .glassButton().help(Text(verbatim: Self.shortPath(settings.folderPath)))
            Button { capture.startFromMenu() } label: {
                Image(systemName: "camera.viewfinder").font(.system(size: 15, weight: .semibold)).frame(width: 22, height: 18)
            }
            .glassButton(primary: true).help(Text("截图"))
        }
    }

    private var groups: some View {
        let sections = Self.sections(records)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(sections, id: \.title) { section in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(section.title).font(.system(size: 15, weight: .semibold))
                    Text("\(section.items.count) 张").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                .padding(.top, 26).padding(.bottom, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(section.items) { r in
                        ShotTile(record: r, capture: capture) { model.openShot = r }
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").font(.system(size: 34)).foregroundStyle(Theme.accentHi)
            Text(total == 0 ? "还没有截图" : String(localized: "没有符合条件的截图")).font(.system(size: 15, weight: .semibold))
            Text(total == 0 ? "按 \(settings.combo(.region).display) 截第一张。截图会保存在 \(Self.shortPath(settings.folderPath))。" : String(localized: "换一个筛选条件或搜索词试试。"))
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Orbit 还没有屏幕录制权限，现在无法截图。").font(.system(size: 13))
            Spacer()
            Button("打开系统设置") { ScreenPermission.request(); ScreenPermission.openSettings() }.glassButton(primary: true)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Helpers

    struct DaySection { let title: String; let items: [ScreenshotRecord] }

    /// "今天", "昨天", then one section per calendar day.
    static func sections(_ records: [ScreenshotRecord]) -> [DaySection] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = .app
        f.dateFormat = String(localized: "M月d日 EEEE")
        var out: [DaySection] = []
        var current: (day: Date, items: [ScreenshotRecord])?
        func flush() {
            guard let c = current else { return }
            let title = cal.isDateInToday(c.day) ? String(localized: "今天") : cal.isDateInYesterday(c.day) ? String(localized: "昨天") : f.string(from: c.day)
            out.append(DaySection(title: title, items: c.items))
        }
        for r in records {
            let day = cal.startOfDay(for: r.createdAt)
            if current?.day == day { current?.items.append(r) } else { flush(); current = (day, [r]) }
        }
        flush()
        return out
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: Tile

private struct ShotTile: View {
    let record: ScreenshotRecord
    @ObservedObject var capture: CaptureCoordinator
    let open: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    init(record: ScreenshotRecord, capture: CaptureCoordinator, open: @escaping () -> Void) {
        self.record = record; self.capture = capture; self.open = open
        _image = State(initialValue: Thumbnails.ready(for: record.url, maxPixel: 520))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The picture sits in an overlay so a very wide or tall screenshot can never stretch the tile (and crowd its neighbours).
            Rectangle().fill(Theme.control)
                .frame(height: 116).frame(maxWidth: .infinity)
                .overlay {
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                }
                .overlay {
                if hovering {
                    Color.black.opacity(0.5)
                    HStack(spacing: 8) {
                        tileButton("doc.on.doc", primary: true) { capture.copy(record) }
                        tileButton("pencil.tip.crop.circle") { capture.edit(record) }
                        ShareLink(item: record.url) { tileIcon("square.and.arrow.up", primary: false) }.buttonStyle(.plain)
                        tileButton("trash") { capture.delete(record) }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .onHover { hovering = $0 }
            .onTapGesture(perform: open)
            .onDrag { NSItemProvider(contentsOf: record.url) ?? NSItemProvider() }
            .contextMenu {
                Button("编辑") { capture.edit(record) }
                Button("美化") { capture.edit(record, beautify: true) }
                Button("复制") { capture.copy(record) }
                Button("在 Finder 中显示") { capture.reveal(record) }
                Divider()
                Button("移到废纸篓", role: .destructive) { capture.delete(record) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.url.deletingPathExtension().lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(meta).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
        }
        .task(id: record.id) { image = await Thumbnails.image(for: record.url, maxPixel: 520) }
    }

    private var meta: String {
        if record.kind == .window, let s = record.source, !s.isEmpty { return String(localized: "窗口 · \(s)") }
        return "\(record.kind.label) · \(record.pointSize.width) × \(record.pointSize.height)"
    }

    private func tileIcon(_ name: String, primary: Bool) -> some View {
        Image(systemName: name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 30, height: 30)
            .background(primary ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.18)), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func tileButton(_ name: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileIcon(name, primary: primary) }.buttonStyle(.plain)
    }
}

// MARK: Detail

private struct ScreenshotDetail: View {
    let record: ScreenshotRecord
    let all: [ScreenshotRecord]
    @ObservedObject var capture: CaptureCoordinator
    let close: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var image: NSImage?

    init(record: ScreenshotRecord, all: [ScreenshotRecord], capture: CaptureCoordinator, close: @escaping () -> Void) {
        self.record = record; self.all = all; self.capture = capture; self.close = close
        _image = State(initialValue: Thumbnails.ready(for: record.url, maxPixel: 2400))
    }

    private var index: Int? { all.firstIndex(where: { $0.id == record.id }) }

    var body: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(spacing: 14) {
                HStack {
                    Button { close() } label: { Text("‹ 全部截图").font(.system(size: 13)).foregroundStyle(Theme.accentHi) }.buttonStyle(.plain)
                    Spacer()
                    if let i = index { Text("\(i + 1) / \(all.count)").font(.system(size: 13)).foregroundStyle(Theme.text2) }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel)
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().padding(30).shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                            .onTapGesture(count: 2) { capture.edit(record) }
                    }
                    HStack {
                        arrow("chevron.left", enabled: (index ?? 0) > 0) { step(-1) }
                        Spacer()
                        arrow("chevron.right", enabled: index.map { $0 < all.count - 1 } ?? false) { step(1) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            info.frame(width: 300)
        }
        .padding(.horizontal, 40).padding(.top, 8).padding(.bottom, 24)
        .task(id: record.id) { image = nil; image = await Thumbnails.image(for: record.url, maxPixel: 2400) }
        .focusable()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.delete) { trash(); return .handled }
        .onKeyPress("e") { capture.edit(record); return .handled }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.url.deletingPathExtension().lastPathComponent).font(.system(size: 15, weight: .semibold)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 40)
            Text(record.url.pathExtension.uppercased()).font(.system(size: 12)).foregroundStyle(Theme.text2).padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                line("时间", Self.time(record.createdAt))
                line("方式", record.kind.label)
                if let s = record.source, !s.isEmpty { line("来源", s) }
                line("尺寸", "\(record.pixelWidth) × \(record.pixelHeight)（\(Int(record.scale))x）")
                line("文件大小", ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                line("位置", Self.short(record.folder))
            }
            .padding(.top, 26)
            VStack(alignment: .leading, spacing: 10) {
                Button("复制") { capture.copy(record) }.glassButton(primary: true)
                HStack(spacing: 10) {
                    Button("编辑") { capture.edit(record) }.glassButton()
                    Button("美化") { capture.edit(record, beautify: true) }.glassButton()
                }
                HStack(spacing: 10) {
                    ShareLink(item: record.url) { Text("分享…") }.buttonStyle(GlassButtonStyle()).focusable(false)
                    Button("在 Finder 中显示") { capture.reveal(record) }.glassButton()
                }
                Button("移到废纸篓") { trash() }.glassButton()
            }
            .padding(.top, 28)
            Text("键盘：← → 切换，E 编辑，⌫ 移到废纸篓，Esc 返回").font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.top, 26)
            Spacer()
        }
    }

    private func line(_ k: LocalizedStringKey, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 70, alignment: .leading)
            Text(v).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .bold)).frame(width: 36, height: 36)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.25).disabled(!enabled)
    }

    private func step(_ d: Int) {
        guard let i = index, all.indices.contains(i + d) else { return }
        model.openShot = all[i + d]
    }

    private func trash() {
        let next = index.flatMap { i in all.indices.contains(i + 1) ? all[i + 1] : (i > 0 ? all[i - 1] : nil) }
        capture.delete(record)
        model.openShot = next
    }

    static func time(_ date: Date) -> String {
        let cal = Calendar.current, f = DateFormatter()
        f.locale = .app
        if cal.isDateInToday(date) { f.dateFormat = String(localized: "'今天' HH:mm") }
        else if cal.isDateInYesterday(date) { f.dateFormat = String(localized: "'昨天' HH:mm") }
        else { f.dateFormat = String(localized: "yyyy年M月d日 HH:mm") }
        return f.string(from: date)
    }

    static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: Permission

struct PermissionGuide: View {
    @ObservedObject var capture: CaptureCoordinator

    var body: some View {
        OScroll {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("允许 Orbit 截取屏幕").font(.system(size: 30, weight: .bold)).padding(.top, 22)
                Text("macOS 要求你明确同意，Orbit 才能截图。只需要做一次。")
                    .font(.system(size: 15)).foregroundStyle(Theme.text2).padding(.top, 10)
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "点击下面的「打开系统设置」", nil)
                    step(2, "在「隐私与安全性 → 屏幕录制」里，打开 Orbit 旁边的开关", "系统会要求输入密码或用触控 ID 确认。列表里没有 Orbit 的话，点列表左下角的「+」，选择 Orbit 应用")
                    step(3, "回到 Orbit，按提示重新打开", "macOS 授权后需要重启应用才会生效，Orbit 会帮你重新打开")
                }
                .padding(.top, 34)
                HStack(spacing: 12) {
                    Button("打开系统设置") { ScreenPermission.request(); ScreenPermission.openSettings() }.glassButton(primary: true)
                    Button("我已授权，重新打开 Orbit") { Self.relaunch() }.glassButton()
                    HStack(spacing: 7) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("当前状态：未授权").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    .padding(.leading, 10)
                }
                .padding(.top, 36)
                Text("Orbit 只在你按下快捷键时截图。截图只保存在这台 Mac 上，不会上传。")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).padding(.top, 34)
            }
            .padding(.horizontal, 64).padding(.top, 40).frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            capture.needsPermission = !ScreenPermission.granted
        }
    }

    private func step(_ n: Int, _ title: LocalizedStringKey, _ sub: LocalizedStringKey?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentHi)
                .frame(width: 24, height: 24).background(Theme.control, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let sub { Text(sub).font(.system(size: 12)).foregroundStyle(Theme.text2) }
            }
        }
    }

    /// Starts a fresh copy of this app and quits this one: the permission only applies to a new process.
    /// A packaged app is reopened by its bundle; a bare development binary (no .app around it) is started again directly.
    static func relaunch() {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let exe = Bundle.main.executableURL {
            let p = Process()
            p.executableURL = exe
            p.arguments = Array(CommandLine.arguments.dropFirst())
            do { try p.run(); NSApp.terminate(nil) } catch { NSSound.beep() }
        }
    }
}
