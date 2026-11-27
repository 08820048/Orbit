import SwiftUI

/// A built-in group the user can add with one tap. Apps are suggested from their Mac App Store category
/// (`LSApplicationCategoryType`) plus name / bundle-id keywords for things the store has no category for (AI, chat…).
struct GroupPreset: Identifiable {
    let name: String
    let categories: Set<String>
    let keywords: [String]
    var id: String { name }

    /// Name / bundle-id keywords. Short ones ("arc", "line") must match a whole word, or "Unarchiver" would count as "arc".
    func keywordMatch(_ app: InstalledApp) -> Bool {
        let haystack = (app.bundleID + " " + app.name).lowercased()
        let words = Set(haystack.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return keywords.contains { $0.count <= 4 ? words.contains($0) : haystack.contains($0) }
    }

    func categoryMatch(_ app: InstalledApp) -> Bool {
        categories.contains(app.category) || (name == String(localized: "游戏娱乐") && Self.isGameCategory(app.category))
    }

    static let all: [GroupPreset] = [
        .init(name: String(localized: "AI 与开发"), categories: [],
              keywords: ["claude", "chatgpt", "openai", "codex", "anthropic", "cursor", "copilot", "gemini", "deepseek", "ollama",
                         "lmstudio", "lm studio", "windsurf", "perplexity", "kimi", "doubao", "豆包", "通义", "alma", "antigravity", "trae"]),
        .init(name: String(localized: "开发工具"), categories: ["developer-tools"],
              keywords: ["xcode", "vscode", "visual studio", "jetbrains", "zed", "iterm", "terminal", "warp", "docker", "postman", "sublime", "termius", "github", "unity"]),
        .init(name: String(localized: "写作与学习"), categories: ["education", "reference"],
              keywords: ["typora", "obsidian", "notion", "bear", "ulysses", "thymer", "logseq", "ibooks", "books", "anki", "notes", "备忘录", "pages", "marginnote"]),
        .init(name: String(localized: "办公"), categories: ["business", "productivity", "finance"],
              keywords: ["microsoft.word", "microsoft.excel", "microsoft.powerpoint", "microsoft.outlook", "iwork", "numbers", "keynote", "wps", "office", "calendar", "日历"]),
        .init(name: String(localized: "影像与设计"), categories: ["graphics-design", "photography"],
              keywords: ["figma", "sketch", "pixelmator", "photoshop", "illustrator", "affinity", "blender", "preview", "snipaste", "eagle", "pixel"]),
        .init(name: String(localized: "音乐与视频"), categories: ["music", "video"],
              keywords: ["music", "quicktime", "iina", "vlc", "spotify", "netease", "音乐", "tv", "podcast", "infuse"]),
        .init(name: String(localized: "效率与系统"), categories: ["utilities"],
              keywords: ["finder", "raycast", "alfred", "bartender", "cleanmymac", "mole", "clash", "activity monitor", "keychain", "1password", "hush", "owlsort", "runnock"]),
        .init(name: String(localized: "社交与通讯"), categories: ["social-networking"],
              keywords: ["wechat", "xinwechat", "tencent.qq", "telegram", "whatsapp", "slack", "discord", "feishu", "lark", "dingtalk", "messages", "mail", "line", "zoom", "teams"]),
        .init(name: String(localized: "上网与媒体"), categories: ["news"],
              keywords: ["chrome", "safari", "firefox", "microsoft.edgemac", "arc", "brave", "opera", "browser", "reeder", "newsblur"]),
        .init(name: String(localized: "游戏娱乐"), categories: ["entertainment"],
              keywords: ["steam", "epic", "game", "minecraft", "battle.net"]),
    ]

    /// Categories like "action-games" / "games".
    static func isGameCategory(_ c: String) -> Bool { c == "games" || c.hasSuffix("-games") }
}

extension GroupPreset {
    /// Each app belongs to exactly one preset: a keyword hit wins over its store category
    /// (so QQ lands in 社交 even though its category says developer tools).
    static func owner(of app: InstalledApp) -> String? {
        all.first { $0.keywordMatch(app) }?.name ?? all.first { $0.categoryMatch(app) }?.name
    }

    func fits(_ app: InstalledApp) -> Bool { Self.owner(of: app) == name }
}

/// Wraps its children onto new lines (macOS 13 `Layout`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), origins)
    }
}

struct PresetChip: View {
    let name: String
    let added: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(added ? "✓" : "+").font(.system(size: added ? 11 : 14)).foregroundStyle(added ? Theme.text2 : Theme.accentHi)
            Text(name).font(.system(size: 12)).foregroundStyle(Theme.text)
        }
        .padding(.leading, 8).padding(.trailing, 10).frame(height: 26)
        .background(Theme.control, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 0.5))
        .opacity(added ? 0.5 : 1)
        .contentShape(Capsule())
    }
}
