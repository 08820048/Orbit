import AppKit
import Foundation

/// A command-line product Orbit knows by name: how to detect it and which bundled logo to use.
struct TerminalTool: Identifiable, Hashable {
    let id: String
    let name: String
    /// Executable names to look for.
    let commands: [String]
    /// Extra words the name search should match ("claude code", "gemini cli"…).
    let aliases: [String]
    /// File in Resources/BrandLogos (without .png).
    let logo: String
    /// Tile color behind the logo; nil = the logo already is an app-icon shape, draw it as is.
    let tileHex: String?
}

enum TerminalCatalog {
    private static let light = "F7F7F5"

    static let all: [TerminalTool] = [
        .init(id: "claude", name: "Claude Code", commands: ["claude"], aliases: ["claude", "anthropic", "claude code"], logo: "claude-white", tileHex: "D97757"),
        .init(id: "codex", name: "Codex CLI", commands: ["codex"], aliases: ["codex", "openai codex"], logo: "codex-color", tileHex: light),
        .init(id: "gemini", name: "Gemini CLI", commands: ["gemini"], aliases: ["gemini", "google gemini"], logo: "geminicli-color", tileHex: nil),
        .init(id: "opencode", name: "OpenCode", commands: ["opencode"], aliases: ["opencode"], logo: "opencode", tileHex: light),
        .init(id: "qwen", name: "Qwen Code", commands: ["qwen"], aliases: ["qwen", "通义", "千问"], logo: "qwen-color", tileHex: light),
        .init(id: "cursor", name: "Cursor CLI", commands: ["cursor-agent"], aliases: ["cursor", "cursor agent"], logo: "cursor", tileHex: light),
        .init(id: "copilot", name: "GitHub Copilot CLI", commands: ["copilot"], aliases: ["copilot", "github copilot"], logo: "githubcopilot", tileHex: light),
        .init(id: "amp", name: "Amp", commands: ["amp"], aliases: ["amp", "sourcegraph"], logo: "amp-color", tileHex: light),
        .init(id: "goose", name: "Goose", commands: ["goose"], aliases: ["goose", "block goose"], logo: "goose", tileHex: light),
        .init(id: "kimi", name: "Kimi CLI", commands: ["kimi"], aliases: ["kimi", "moonshot", "月之暗面"], logo: "kimi-color", tileHex: light),
        .init(id: "ollama", name: "Ollama", commands: ["ollama"], aliases: ["ollama"], logo: "ollama", tileHex: light),
        .init(id: "openhands", name: "OpenHands", commands: ["openhands"], aliases: ["openhands", "open hands"], logo: "openhands-color", tileHex: light),
        .init(id: "cline", name: "Cline", commands: ["cline"], aliases: ["cline"], logo: "cline", tileHex: light),
        .init(id: "lmstudio", name: "LM Studio", commands: ["lms"], aliases: ["lm studio", "lmstudio", "lms"], logo: "lmstudio", tileHex: light),
        .init(id: "windsurf", name: "Windsurf", commands: ["windsurf"], aliases: ["windsurf", "codeium"], logo: "windsurf", tileHex: light),
        .init(id: "trae", name: "Trae CLI", commands: ["trae-cli", "trae"], aliases: ["trae", "字节"], logo: "trae-color", tileHex: light),
        .init(id: "codebuddy", name: "CodeBuddy", commands: ["codebuddy"], aliases: ["codebuddy", "code buddy", "腾讯"], logo: "codebuddy-color", tileHex: nil),
        .init(id: "qoder", name: "Qoder CLI", commands: ["qodercli", "qoder"], aliases: ["qoder"], logo: "qoder-color", tileHex: light),
        .init(id: "junie", name: "Junie", commands: ["junie"], aliases: ["junie", "jetbrains"], logo: "junie-color", tileHex: light),
        .init(id: "deepseek", name: "DeepSeek", commands: ["deepseek"], aliases: ["deepseek", "深度求索"], logo: "deepseek-color", tileHex: light),
    ]

    static func tool(id: String) -> TerminalTool? { all.first { $0.id == id } }

    private static var logoCache: [String: NSImage] = [:]

    static func logoImage(_ tool: TerminalTool) -> NSImage? {
        if let hit = logoCache[tool.logo] { return hit }
        guard let url = Bundle.module.url(forResource: tool.logo, withExtension: "png", subdirectory: "BrandLogos"),
              let image = NSImage(contentsOf: url) else { return nil }
        logoCache[tool.logo] = image
        return image
    }

    /// Catalog entries whose name, command or alias contains the query (for the "add custom app" name field).
    static func match(_ query: String, limit: Int = 4) -> [TerminalTool] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let scored: [(TerminalTool, Int)] = all.compactMap { t in
            let names = [t.name.lowercased()] + t.aliases.map { $0.lowercased() } + t.commands
            if names.contains(q) { return (t, 0) }
            if names.contains(where: { $0.hasPrefix(q) }) { return (t, 1) }
            if names.contains(where: { $0.contains(q) }) { return (t, 2) }
            return nil
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    // MARK: Detection

    /// Folders where CLI tools usually live. A GUI app doesn't inherit the shell's PATH, so look in the usual places.
    private static func searchDirectories() -> [String] {
        let home = NSHomeDirectory()
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home + "/.local/bin", home + "/.npm-global/bin",
                    home + "/.bun/bin", home + "/.cargo/bin", home + "/go/bin", home + "/.claude/local", home + "/.opencode/bin",
                    home + "/.volta/bin", home + "/Library/pnpm", home + "/.local/share/pnpm", home + "/.amp/bin", home + "/.codeium/windsurf/bin"]
        let fm = FileManager.default
        let nvm = home + "/.nvm/versions/node"
        for version in (try? fm.contentsOfDirectory(atPath: nvm)) ?? [] { dirs.append("\(nvm)/\(version)/bin") }
        let fnm = home + "/.local/share/fnm/node-versions"
        for version in (try? fm.contentsOfDirectory(atPath: fnm)) ?? [] { dirs.append("\(fnm)/\(version)/installation/bin") }
        return dirs
    }

    /// Catalog tools whose command exists and is executable somewhere in the usual folders.
    static func detect() -> [TerminalTool] {
        let fm = FileManager.default
        let dirs = searchDirectories()
        return all.filter { tool in
            tool.commands.contains { cmd in dirs.contains { fm.isExecutableFile(atPath: $0 + "/" + cmd) } }
        }
    }

    static func command(for tool: TerminalTool) -> String { tool.commands[0] }
}
