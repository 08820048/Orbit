import AppKit
import Foundation
import OrbitCore
import SwiftUI

// MARK: - Document

enum ShareMode: String, Codable, CaseIterable, Identifiable {
    case usage = "数据排行", picked = "自选软件"
    var id: String { rawValue }
}

enum CustomTemplate: String, Codable, CaseIterable, Identifiable {
    case fjord = "峡湾", glass = "玻璃", paper = "纸感", minimal = "极简"
    var id: String { rawValue }
    var blurb: String {
        switch self {
        case .fjord: "照片背景 + 宋体标题，左侧分组名"
        case .glass: "蓝色玻璃卡片，每个分组一块毛玻璃"
        case .paper: "浅色纸张底，适合白天分享"
        case .minimal: "纯黑底，不分组，只有图标阵列"
        }
    }
}

enum CanvasRatio: String, Codable, CaseIterable, Identifiable {
    case landscape = "横版", square = "方形", portrait = "竖版"
    case xiaohongshu = "小红书", wide = "X / 横幅", story = "手机壁纸"
    var id: String { rawValue }

    /// The three plain shapes, then the social-platform presets.
    static let basic: [CanvasRatio] = [.landscape, .square, .portrait]
    static let platforms: [CanvasRatio] = [.xiaohongshu, .wide, .story]

    /// Points; exported at 2x.
    var size: CGSize {
        switch self {
        case .landscape: CGSize(width: 800, height: 512)
        case .square: CGSize(width: 640, height: 640)
        case .portrait: CGSize(width: 640, height: 800)
        case .xiaohongshu: CGSize(width: 600, height: 800)
        case .wide: CGSize(width: 800, height: 450)
        case .story: CGSize(width: 540, height: 960)
        }
    }
    /// Wider than tall: the card lays groups out side by side.
    var isWide: Bool { size.width > size.height }

    var shape: String {
        switch self {
        case .landscape: "25:16"
        case .square: "1:1"
        case .portrait: "4:5"
        case .xiaohongshu: "3:4"
        case .wide: "16:9"
        case .story: "9:16"
        }
    }
    var pixels: String { "\(Int(size.width * 2))×\(Int(size.height * 2))" }
    var label: String { "\(shape) · \(pixels)" }
}

enum IconSize: String, Codable, CaseIterable, Identifiable {
    case small = "小", medium = "中", large = "大"
    var id: String { rawValue }
    var points: CGFloat { self == .small ? 30 : self == .medium ? 36 : 44 }
}

enum TitleFont: String, Codable, CaseIterable, Identifiable {
    case song = "宋体", hei = "黑体", round = "圆体"
    var id: String { rawValue }
    func font(_ size: CGFloat) -> Font {
        switch self {
        case .song: .custom("Songti SC", size: size).weight(.bold)
        case .hei: .system(size: size, weight: .bold)
        case .round: .system(size: size, weight: .bold, design: .rounded)
        }
    }
}

struct ShareGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var bundleIDs: [String] = []
}

struct CustomShareDoc: Codable, Equatable {
    var title = "2026 我的 Mac 常用软件"
    var caption = ""
    var signature = NSFullUserName()
    var groups: [ShareGroup] = []
    var template: CustomTemplate = .fjord
    var ratio: CanvasRatio = .landscape
    /// "default" (the template's own), "builtin:<name>", "custom:<file>", "solid:<RRGGBB>"
    var background = "default"
    var overlay = 0.6
    var blur = 0.0
    var iconSize: IconSize = .medium
    var titleFont: TitleFont = .song
    var showNames = true
    var watermark = true
    /// The first-run suggestion (top used apps) has been applied; don't redo it after the user clears groups.
    var seeded = false
    var customApps: [CustomApp] = []
    var mode: ShareMode = .usage
    var cornerRadius = 24.0
    /// Title override for the usage-ranking card; empty = automatic.
    var usageTitle = ""
    /// Hashtags added as the last line of the copied app list; empty = none.
    var hashtags = "#我的Mac软件 #Mac"
    /// Lay the card out as "icon + name + one-line note" and show `notes`.
    var showNotes = false
    /// Apps the user added from outside the usual folders, by path (they would not be found by scanning).
    var extraApps: [String] = []
    /// One-line comments by app key (bundle id or custom-app key). Kept even if the app leaves every group.
    var notes: [String: String] = [:]

    init() {}

    // Missing keys fall back to defaults, so adding a field never wipes a user's saved card.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CustomShareDoc()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? d.title
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? d.caption
        signature = try c.decodeIfPresent(String.self, forKey: .signature) ?? d.signature
        groups = try c.decodeIfPresent([ShareGroup].self, forKey: .groups) ?? d.groups
        template = try c.decodeIfPresent(CustomTemplate.self, forKey: .template) ?? d.template
        ratio = try c.decodeIfPresent(CanvasRatio.self, forKey: .ratio) ?? d.ratio
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        overlay = try c.decodeIfPresent(Double.self, forKey: .overlay) ?? d.overlay
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
        iconSize = try c.decodeIfPresent(IconSize.self, forKey: .iconSize) ?? d.iconSize
        titleFont = try c.decodeIfPresent(TitleFont.self, forKey: .titleFont) ?? d.titleFont
        showNames = try c.decodeIfPresent(Bool.self, forKey: .showNames) ?? d.showNames
        watermark = try c.decodeIfPresent(Bool.self, forKey: .watermark) ?? d.watermark
        seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? d.seeded
        customApps = try c.decodeIfPresent([CustomApp].self, forKey: .customApps) ?? d.customApps
        mode = try c.decodeIfPresent(ShareMode.self, forKey: .mode) ?? d.mode
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        usageTitle = try c.decodeIfPresent(String.self, forKey: .usageTitle) ?? d.usageTitle
        hashtags = try c.decodeIfPresent(String.self, forKey: .hashtags) ?? d.hashtags
        extraApps = try c.decodeIfPresent([String].self, forKey: .extraApps) ?? d.extraApps
        showNotes = try c.decodeIfPresent(Bool.self, forKey: .showNotes) ?? d.showNotes
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? d.notes
    }
}

// MARK: - Installed apps

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    /// Mac App Store category without the "public.app-category." prefix ("developer-tools"), or "".
    var category = ""
    var id: String { bundleID }
}

enum InstalledApps {
    /// The folders apps are installed into, in the order they win when the same bundle id appears twice.
    static var defaultRoots: [String] {
        ["/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications", NSHomeDirectory() + "/Applications"]
    }

    /// Finds installed apps, looking up to `maxDepth` folders down (so "/Applications/Utilities/…" and vendor folders like
    /// "/Applications/Setapp/…" are covered). Apps without a Dock icon (`LSUIElement`: menu bar tools, Windows App…) are
    /// real apps people use and share, so they are included; only `LSBackgroundOnly` helpers are left out.
    static func scan(roots: [String] = defaultRoots, maxDepth: Int = 3, extraPaths: [String] = []) -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [InstalledApp] = []

        func add(_ url: URL) {
            guard let app = app(at: url), !seen.contains(app.bundleID) else { return }
            seen.insert(app.bundleID)
            out.append(app)
        }

        for root in roots {
            guard let walker = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            while let url = walker.nextObject() as? URL {
                if url.pathExtension == "app" { add(url); walker.skipDescendants(); continue }
                if walker.level >= maxDepth { walker.skipDescendants() }
            }
        }
        for path in extraPaths where fm.fileExists(atPath: path) { add(URL(fileURLWithPath: path)) }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One app bundle as the picker lists it, or nil for background-only helpers and things that are not apps.
    /// An app without a bundle identifier gets a path-based key instead of being dropped.
    static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
        if (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool) == true { return nil }
        let id = bundle.bundleIdentifier ?? AppCatalog.pathKey(url)
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let category = ((bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String) ?? "")
            .replacingOccurrences(of: "public.app-category.", with: "").lowercased()
        return InstalledApp(bundleID: id, name: name, category: category)
    }
}

// MARK: - Backgrounds

struct BuiltinBackground: Identifiable {
    let id: String
    let name: String
    static let all: [BuiltinBackground] = [
        .init(id: "fjord", name: "峡湾暮色"), .init(id: "mist-lake", name: "云雾湖山"),
        .init(id: "dark-lake", name: "暗色湖面"), .init(id: "milkyway", name: "银河山脊"),
        .init(id: "alps-night", name: "雪山星夜"), .init(id: "horizon", name: "海平线"),
        .init(id: "sunset-sea", name: "红霞海面"), .init(id: "fluid-blue", name: "蓝绿流体"),
    ]
}

enum BackgroundStore {
    private static var cache: [String: NSImage] = [:]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orbit/Backgrounds", isDirectory: true)
    }

    static func builtin(_ id: String) -> NSImage? {
        load(key: "b:" + id) {
            Bundle.module.url(forResource: id, withExtension: "jpg", subdirectory: "Backgrounds")
        }
    }

    static func custom(_ file: String) -> NSImage? {
        load(key: "c:" + file) { folder.appendingPathComponent(file) }
    }

    /// Copies a user-chosen picture into Orbit's own folder so it keeps working if the original moves.
    static func importImage(from url: URL) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
        return name
    }

    private static func load(key: String, url: () -> URL?) -> NSImage? {
        if let hit = cache[key] { return hit }
        guard let u = url(), let raw = NSImage(contentsOf: u) else { return nil }
        let image = normalized(raw, maxWidth: 2400)
        cache[key] = image
        return image
    }

    /// Redraws into 8-bit sRGB (see AppCatalog.normalized: HDR/wide-gamut sources wash out exported PNGs).
    static func normalized(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
        guard let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }), rep.pixelsWide > 0 else { return image }
        let scale = min(1, maxWidth / CGFloat(rep.pixelsWide))
        let w = max(1, Int(CGFloat(rep.pixelsWide) * scale)), h = max(1, Int(CGFloat(rep.pixelsHigh) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}

// MARK: - Model

@MainActor
final class CustomShareModel: ObservableObject {
    private static let key = "orbit.customShare.v1"

    @Published var doc: CustomShareDoc { didSet { if doc != oldValue { save() } } }
    @Published var installed: [InstalledApp] = []
    /// Known command-line products found on this Mac.
    @Published var detectedTools: [TerminalTool] = []
    @Published var activeGroup: UUID?
    private var scanned = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(CustomShareDoc.self, from: data) {
            doc = saved
        } else {
            doc = CustomShareDoc()
        }
        activeGroup = doc.groups.first?.id
    }

    private func save() {
        if let data = try? JSONEncoder().encode(doc) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func loadInstalledIfNeeded() async {
        guard !scanned else { return }
        scanned = true
        let extra = doc.extraApps
        installed = await Task.detached(priority: .userInitiated) { InstalledApps.scan(extraPaths: extra) }.value
        detectedTools = await Task.detached(priority: .userInitiated) { TerminalCatalog.detect() }.value
    }

    /// First run: put the user's most-used (recently) apps into one group so the card is never empty.
    func seedIfNeeded(scores: [String: Double]) {
        guard !doc.seeded else { return }
        doc.seeded = true
        guard doc.groups.isEmpty, !installed.isEmpty else { return }
        let top = AppRecommender.pick(from: installed.filter(AppRecommender.isRecommendable), scores: scores, limit: 12, minimum: 0)
        guard !top.isEmpty else { return }
        let group = ShareGroup(name: "常用软件", bundleIDs: top.map(\.bundleID))
        doc.groups = [group]
        activeGroup = group.id
    }

    var totalApps: Int { doc.groups.reduce(0) { $0 + $1.bundleIDs.count } }

    // MARK: Groups

    /// Adds apps picked from anywhere on disk to the list and to `group`. Returns how many were not on the list before.
    @discardableResult
    func addExternalApps(_ urls: [URL], to group: UUID?) -> Int {
        var added = 0
        for url in urls {
            guard let app = InstalledApps.app(at: url) else { continue }
            if !installed.contains(where: { $0.bundleID == app.bundleID }) {
                installed.append(app)
                installed.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                added += 1
            }
            if !doc.extraApps.contains(url.path) { doc.extraApps.append(url.path) }
            if let group, !(doc.groups.first { $0.id == group }?.bundleIDs.contains(app.bundleID) ?? false) { toggle(app.bundleID, in: group) }
        }
        return added
    }

    func addGroup() {
        let group = ShareGroup(name: "分组 \(doc.groups.count + 1)")
        doc.groups.append(group)
        activeGroup = group.id
    }

    func removeGroup(_ id: UUID) {
        doc.groups.removeAll { $0.id == id }
        if activeGroup == id { activeGroup = doc.groups.first?.id }
    }

    func moveGroup(_ id: UUID, by offset: Int) {
        guard let i = doc.groups.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard doc.groups.indices.contains(j) else { return }
        doc.groups.swapAt(i, j)
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = doc.groups.firstIndex(where: { $0.id == id }) else { return }
        doc.groups[i].name = name
    }

    /// Selecting an app that is in another group moves it here; selecting one that is already here removes it.
    func toggle(_ bundleID: String, in groupID: UUID) {
        guard let target = doc.groups.firstIndex(where: { $0.id == groupID }) else { return }
        if doc.groups[target].bundleIDs.contains(bundleID) {
            doc.groups[target].bundleIDs.removeAll { $0 == bundleID }
            return
        }
        for i in doc.groups.indices { doc.groups[i].bundleIDs.removeAll { $0 == bundleID } }
        doc.groups[target].bundleIDs.append(bundleID)
    }

    // MARK: Notes

    func note(for key: String) -> String { doc.notes[key] ?? "" }

    func setNote(_ text: String, for key: String) {
        let limited = ShareNote.limit(text)
        if ShareNote.normalize(limited).isEmpty { doc.notes.removeValue(forKey: key) } else { doc.notes[key] = limited }
    }

    /// Apps currently on the card that have a note.
    var notedCount: Int {
        doc.groups.flatMap(\.bundleIDs).filter { !ShareNote.normalize(doc.notes[$0] ?? "").isEmpty }.count
    }

    func clearNotes() { doc.notes.removeAll() }

    // MARK: Custom apps

    func customApp(forKey key: String) -> CustomApp? { doc.customApps.first { $0.key == key } }

    func addCustom(_ app: CustomApp, to group: UUID?) {
        doc.customApps.append(app)
        if let group { toggle(app.key, in: group) }
    }

    /// The custom entry created for a catalog tool, if the user already used it.
    func brandApp(for tool: TerminalTool) -> CustomApp? {
        doc.customApps.first { $0.brand == tool.id && $0.iconFile == nil }
    }

    /// Tools shown in the picker: found on this Mac, plus ones added earlier (even if since uninstalled).
    var terminalTools: [TerminalTool] {
        var list = detectedTools
        for app in doc.customApps {
            if let id = app.brand, app.iconFile == nil, let tool = TerminalCatalog.tool(id: id), !list.contains(tool) { list.append(tool) }
        }
        return list
    }

    func toggleTool(_ tool: TerminalTool, in group: UUID) {
        if let app = brandApp(for: tool) { toggle(app.key, in: group) } else { addCustom(CustomApp.from(tool), to: group) }
    }

    func updateCustom(_ app: CustomApp) {
        guard let i = doc.customApps.firstIndex(where: { $0.id == app.id }) else { return }
        doc.customApps[i] = app
    }

    func removeCustom(_ app: CustomApp) {
        doc.customApps.removeAll { $0.id == app.id }
        for i in doc.groups.indices { doc.groups[i].bundleIDs.removeAll { $0 == app.key } }
        doc.notes.removeValue(forKey: app.key)
        CustomAppIcons.delete(file: app.iconFile)
    }

    private func noteText(_ key: String) -> String { ShareNote.normalize(doc.notes[key] ?? "") }

    /// Name and icon for a group entry, whether it is an installed app or a custom one.
    func resolve(_ key: String, catalog: AppCatalog) -> ResolvedApp {
        if let custom = customApp(forKey: key) {
            return ResolvedApp(id: key, name: custom.name, icon: CustomAppIcons.render(custom), note: noteText(key))
        }
        let info = catalog.info(for: key)
        return ResolvedApp(id: key, name: info.name, icon: info.icon, note: noteText(key))
    }

    // MARK: Presets

    /// Shown under the groups after a preset was added ("recommended 5 apps…"); clears itself.
    @Published var presetNote: String?

    func hasGroup(named name: String) -> Bool { doc.groups.contains { $0.name == name } }

    /// Adds a group with the apps pinned in the Dock, in Dock order. Apps already in another group stay where they are.
    func addDockGroup(_ dock: [String]) {
        guard !hasGroup(named: "Dock") else { return }
        let taken = Set(doc.groups.flatMap(\.bundleIDs))
        let ids = dock.filter { !taken.contains($0) }
        let group = ShareGroup(name: "Dock", bundleIDs: ids)
        doc.groups.append(group)
        activeGroup = group.id
        presetNote = ids.isEmpty ? "Dock 里的软件都已经在其他分组里了。" : nil
    }

    /// Adds a built-in group and fills it with installed apps that fit it, best recent usage first (at most 6).
    /// `scores` is `AppRecommender.recencyScores`. System tools are never recommended.
    func addPreset(_ preset: GroupPreset, scores: [String: Double]) {
        guard !hasGroup(named: preset.name) else { return }
        let taken = Set(doc.groups.flatMap(\.bundleIDs))
        let candidates = installed.filter { !taken.contains($0.bundleID) && AppRecommender.isRecommendable($0) && preset.fits($0) }
        let picks = AppRecommender.pick(from: candidates, scores: scores, limit: 6).map(\.bundleID)
        let group = ShareGroup(name: preset.name, bundleIDs: Array(picks))
        doc.groups.append(group)
        activeGroup = group.id
        presetNote = picks.isEmpty
            ? "没有找到适合「\(preset.name)」的已安装软件，请点「从已安装软件中选择」手动添加。"
            : "已按软件类别为「\(preset.name)」推荐了 \(picks.count) 个，可在「选择软件」里增减。"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.presetNote = nil
        }
    }

    func groupName(containing bundleID: String) -> String? {
        doc.groups.first { $0.bundleIDs.contains(bundleID) }?.name
    }
}
