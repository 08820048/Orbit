import Foundation

/// The app list that goes to the clipboard next to the share image, so people who see the picture can search the names.
/// Plain text with Markdown-style lists; reads fine anywhere it is pasted.
public enum ShareList {
    public struct Item: Equatable {
        public var name: String
        public var note: String
        public init(name: String, note: String = "") { self.name = name; self.note = note }
    }

    public struct Group: Equatable {
        public var name: String
        public var items: [Item]
        public init(name: String, items: [Item]) { self.name = name; self.items = items }
    }

    /// "Xuyi · 2026.11 · Orbit": the signature, then "Orbit" when the watermark is on. Nil when both are empty.
    static func footer(signature: String, watermark: Bool) -> String? {
        let parts = [signature.trimmingCharacters(in: .whitespacesAndNewlines), watermark ? "Orbit" : ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func assemble(_ sections: [String?]) -> String {
        sections.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Joins the closing lines (signature, hashtags) with a single newline so they read as one block.
    private static func closing(_ lines: [String?]) -> String? {
        let kept = lines.compactMap { $0 }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }

    /// Picked apps: one block per group, "- Name — note" (just "- Name" when there is no note). Empty groups are skipped.
    public static func picked(title: String, groups: [Group], signature: String, watermark: Bool, hashtags: String = "") -> String {
        let blocks = groups.filter { !$0.items.isEmpty }.map { g -> String in
            let lines = g.items.map { item -> String in
                let note = ShareNote.normalize(item.note)
                return note.isEmpty ? "- \(item.name)" : "- \(item.name) — \(note)"
            }
            return ([g.name] + lines).joined(separator: "\n")
        }
        return assemble([title.trimmingCharacters(in: .whitespacesAndNewlines)] + blocks + [closing([footer(signature: signature, watermark: watermark), hashtags.trimmingCharacters(in: .whitespacesAndNewlines)])])
    }

    /// Usage ranking: "1. Chrome — 48.4 小时" in the order given. `showDuration` off leaves just the names.
    public static func ranking(title: String, entries: [(name: String, seconds: TimeInterval)], showDuration: Bool,
                               signature: String, watermark: Bool) -> String {
        let lines = entries.enumerated().map { i, e in
            showDuration ? "\(i + 1). \(e.name) — \(duration(e.seconds))" : "\(i + 1). \(e.name)"
        }
        return assemble([title.trimmingCharacters(in: .whitespacesAndNewlines), lines.joined(separator: "\n"),
                         footer(signature: signature, watermark: watermark)])
    }

    /// "48.4 小时"; under an hour it is whole minutes ("35 分钟").
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 { return String(format: String(localized: "%.1f 小时"), seconds / 3600) }
        return String(localized: "\(max(1, Int((seconds / 60).rounded()))) 分钟")
    }
}
