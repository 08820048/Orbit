import Foundation

/// One item in the user's Dock.
public struct DockItem: Sendable, Equatable {
    public enum Kind: Sendable { case app, folder }

    /// Label as the Dock shows it (may be localized).
    public var name: String
    public var bundleID: String?
    public var path: String?
    public var kind: Kind

    public init(name: String, bundleID: String?, path: String?, kind: Kind) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.kind = kind
    }
}

/// Reads the Dock layout from its preferences. No permission is needed.
public enum DockReader {
    /// The apps pinned in the Dock, in order.
    public static func pinnedApps() -> [DockItem] { items(from: preference("persistent-apps"), kind: .app) }

    /// Folders and stacks on the right of the Dock.
    public static func folders() -> [DockItem] { items(from: preference("persistent-others"), kind: .folder) }

    private static func preference(_ key: String) -> [[String: Any]] {
        (CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? [[String: Any]]) ?? []
    }

    /// Turns the raw preference entries into items; spacers and entries without a name are skipped.
    static func items(from entries: [[String: Any]], kind: DockItem.Kind) -> [DockItem] {
        entries.compactMap { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let label = tile["file-label"] as? String, !label.isEmpty else { return nil }
            let urlString = (tile["file-data"] as? [String: Any])?["_CFURLString"] as? String
            return DockItem(name: label,
                            bundleID: tile["bundle-identifier"] as? String,
                            path: urlString.flatMap { URL(string: $0)?.path },
                            kind: kind)
        }
    }
}
