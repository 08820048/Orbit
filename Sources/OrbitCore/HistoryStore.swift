import Foundation

/// Orbit's own local usage history. Screen Time keeps only a few weeks, so everything we
/// read is copied here; this file is what makes yearly statistics possible.
///
/// All access is serialized through a lock, so one instance can be shared across tasks.
public final class HistoryStore: @unchecked Sendable {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orbit/history.sqlite")
    }

    private let db: SQLiteDatabase
    private let lock = NSLock()

    /// - Parameter url: `nil` opens an in-memory store (tests, previews).
    public init(url: URL? = HistoryStore.defaultURL) throws {
        if let url {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(path: url.path, readOnly: false)
            try db.execute("PRAGMA journal_mode=WAL")
        } else {
            db = try SQLiteDatabase(path: ":memory:", readOnly: false)
        }
        try migrate()
    }

    private func migrate() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY,
                bundle_id TEXT NOT NULL,
                start REAL NOT NULL,
                end REAL NOT NULL,
                source TEXT NOT NULL,
                source_key TEXT NOT NULL UNIQUE
            );
            CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);
            CREATE INDEX IF NOT EXISTS sessions_end ON sessions(end);
            CREATE TABLE IF NOT EXISTS app_prefs (
                bundle_id TEXT PRIMARY KEY,
                hidden INTEGER NOT NULL DEFAULT 0,
                display_name TEXT
            );
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Sessions

    /// Inserts sessions, skipping any whose `sourceKey` is already stored. Returns the number inserted.
    @discardableResult
    public func insert(_ sessions: [UsageSession]) throws -> Int {
        guard !sessions.isEmpty else { return 0 }
        return try locked {
            try db.transaction {
                var inserted = 0
                for s in sessions where s.end > s.start && !s.bundleID.isEmpty {
                    try db.run(
                        "INSERT OR IGNORE INTO sessions (bundle_id, start, end, source, source_key) VALUES (?,?,?,?,?)",
                        [.text(s.bundleID), .double(s.start.timeIntervalSince1970),
                         .double(s.end.timeIntervalSince1970), .text(s.source.rawValue), .text(s.sourceKey)])
                    inserted += db.changes
                }
                return inserted
            }
        }
    }

    /// Sessions that overlap `interval` (not clipped).
    public func sessions(overlapping interval: DateInterval) throws -> [UsageSession] {
        try locked {
            try db.query(
                "SELECT bundle_id, start, end, source, source_key FROM sessions WHERE start < ? AND end > ? ORDER BY start",
                [.double(interval.end.timeIntervalSince1970), .double(interval.start.timeIntervalSince1970)]
            ) { row in
                UsageSession(
                    bundleID: row.text(0) ?? "",
                    start: Date(timeIntervalSince1970: row.double(1)),
                    end: Date(timeIntervalSince1970: row.double(2)),
                    source: UsageSource(rawValue: row.text(3) ?? "") ?? .monitor,
                    sourceKey: row.text(4) ?? "")
            }
        }
    }

    /// End time of the newest stored session from `source`.
    public func latestEnd(source: UsageSource) throws -> Date? {
        try locked {
            try db.query("SELECT MAX(end) FROM sessions WHERE source = ?", [.text(source.rawValue)]) { row in
                row.isNull(0) ? nil : Date(timeIntervalSince1970: row.double(0))
            }.first ?? nil
        }
    }

    /// Start of the oldest stored session: "records since …".
    public func earliestStart() throws -> Date? {
        try locked {
            try db.query("SELECT MIN(start) FROM sessions") { row in
                row.isNull(0) ? nil : Date(timeIntervalSince1970: row.double(0))
            }.first ?? nil
        }
    }

    public func sessionCount() throws -> Int {
        try locked { try db.query("SELECT COUNT(*) FROM sessions") { Int($0.int(0)) }.first ?? 0 }
    }

    /// Erases all recorded history and preferences (privacy reset).
    public func eraseAll() throws {
        try locked { try db.execute("DELETE FROM sessions; DELETE FROM app_prefs; DELETE FROM meta;") }
    }

    // MARK: App preferences

    public func hiddenBundleIDs() throws -> Set<String> {
        try locked { Set(try db.query("SELECT bundle_id FROM app_prefs WHERE hidden = 1") { $0.text(0) ?? "" }) }
    }

    public func setHidden(_ hidden: Bool, bundleID: String) throws {
        try locked {
            try db.run("""
                INSERT INTO app_prefs (bundle_id, hidden) VALUES (?, ?)
                ON CONFLICT(bundle_id) DO UPDATE SET hidden = excluded.hidden
                """, [.text(bundleID), .int(hidden ? 1 : 0)])
        }
    }

    public func displayNameOverrides() throws -> [String: String] {
        try locked {
            Dictionary(uniqueKeysWithValues: try db.query(
                "SELECT bundle_id, display_name FROM app_prefs WHERE display_name IS NOT NULL"
            ) { ($0.text(0) ?? "", $0.text(1) ?? "") })
        }
    }

    /// `nil` clears the override.
    public func setDisplayName(_ name: String?, bundleID: String) throws {
        try locked {
            try db.run("""
                INSERT INTO app_prefs (bundle_id, display_name) VALUES (?, ?)
                ON CONFLICT(bundle_id) DO UPDATE SET display_name = excluded.display_name
                """, [.text(bundleID), name.map { .text($0) } ?? .null])
        }
    }

    // MARK: Meta

    public func meta(_ key: String) throws -> String? {
        try locked { try db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) }.first ?? nil }
    }

    public func setMeta(_ key: String, _ value: String) throws {
        try locked {
            try db.run("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
        }
    }
}
