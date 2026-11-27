import Foundation

/// How a screenshot was taken.
public enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case region, window, fullscreen

    public var label: String {
        switch self {
        case .region: "区域"
        case .window: "窗口"
        case .fullscreen: "全屏"
        }
    }
}

/// One screenshot in the library: the file on disk plus what we know about it.
public struct ScreenshotRecord: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Absolute path of the image file.
    public var path: String
    public var createdAt: Date
    public var kind: CaptureKind
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Backing scale of the screen it came from (2 on Retina).
    public var scale: Double
    public var byteCount: Int64
    /// App (or window) the screenshot is of, when known.
    public var source: String?

    public init(id: UUID = UUID(), path: String, createdAt: Date = Date(), kind: CaptureKind,
                pixelWidth: Int, pixelHeight: Int, scale: Double = 2, byteCount: Int64 = 0, source: String? = nil) {
        self.id = id; self.path = path; self.createdAt = createdAt; self.kind = kind
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.scale = scale
        self.byteCount = byteCount; self.source = source
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var fileName: String { url.lastPathComponent }
    public var folder: String { url.deletingLastPathComponent().path }
    /// Size in points: what the user saw on screen.
    public var pointSize: (width: Int, height: Int) {
        (Int((Double(pixelWidth) / max(scale, 1)).rounded()), Int((Double(pixelHeight) / max(scale, 1)).rounded()))
    }
}

/// File names for new screenshots: "Orbit 2026-11-26 21.03.12.png", with " (2)", " (3)"… when that name is taken.
public enum ScreenshotNaming {
    public static func fileName(date: Date, ext: String = "png", prefix: String = "Orbit",
                                timeZone: TimeZone = .current, exists: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(prefix) \(f.string(from: date))"
        var name = "\(base).\(ext)"
        var n = 2
        while exists(name) { name = "\(base) (\(n)).\(ext)"; n += 1 }
        return name
    }
}

extension ScreenshotNaming {
    /// "Orbit 2026-11-26 21.03.12.png" -> "Orbit 2026-11-26 21.03.12 已编辑.png" (and "(2)" when taken).
    /// Editing an already edited screenshot does not pile up suffixes.
    public static func editedName(from original: String, ext: String? = nil, exists: (String) -> Bool) -> String {
        let url = URL(fileURLWithPath: original)
        var base = url.deletingPathExtension().lastPathComponent
        if let r = base.range(of: " 已编辑") { base = String(base[..<r.lowerBound]) }
        let ext = ext ?? (url.pathExtension.isEmpty ? "png" : url.pathExtension)
        var name = "\(base) 已编辑.\(ext)"
        var n = 2
        while exists(name) { name = "\(base) 已编辑 (\(n)).\(ext)"; n += 1 }
        return name
    }
}

/// The local index behind the screenshot library. The image files live in the user's folder (default `~/Pictures/Orbit`);
/// this store remembers when and how each was taken, so the library can filter, search and show totals quickly.
///
/// All access is serialized through a lock, so one instance can be shared across tasks.
public final class ScreenshotStore: @unchecked Sendable {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Orbit/screenshots.sqlite")
    }

    /// Where screenshots are saved unless the user picks another folder.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbit", isDirectory: true)
    }

    private let db: SQLiteDatabase
    private let lock = NSLock()

    /// - Parameter url: `nil` opens an in-memory store (tests, previews).
    public init(url: URL? = ScreenshotStore.defaultURL) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(path: url.path, readOnly: false)
            try db.execute("PRAGMA journal_mode=WAL")
        } else {
            db = try SQLiteDatabase(path: ":memory:", readOnly: false)
        }
        try db.execute("""
            CREATE TABLE IF NOT EXISTS screenshots (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                created REAL NOT NULL,
                kind TEXT NOT NULL,
                px_w INTEGER NOT NULL,
                px_h INTEGER NOT NULL,
                scale REAL NOT NULL,
                bytes INTEGER NOT NULL,
                source TEXT
            );
            CREATE INDEX IF NOT EXISTS screenshots_created ON screenshots(created DESC);
            """)
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static let columns = "id, path, created, kind, px_w, px_h, scale, bytes, source"

    private static func record(_ row: SQLiteDatabase.Row) -> ScreenshotRecord {
        ScreenshotRecord(
            id: UUID(uuidString: row.text(0) ?? "") ?? UUID(), path: row.text(1) ?? "",
            createdAt: Date(timeIntervalSince1970: row.double(2)),
            kind: CaptureKind(rawValue: row.text(3) ?? "") ?? .region,
            pixelWidth: Int(row.int(4)), pixelHeight: Int(row.int(5)), scale: row.double(6),
            byteCount: row.int(7), source: row.text(8))
    }

    // MARK: Writing

    /// Adds a screenshot. A record for the same file path is replaced.
    public func add(_ r: ScreenshotRecord) throws {
        try locked {
            try db.run("""
                INSERT OR REPLACE INTO screenshots (\(Self.columns)) VALUES (?,?,?,?,?,?,?,?,?)
                """,
                [.text(r.id.uuidString), .text(r.path), .double(r.createdAt.timeIntervalSince1970), .text(r.kind.rawValue),
                 .int(Int64(r.pixelWidth)), .int(Int64(r.pixelHeight)), .double(r.scale), .int(r.byteCount),
                 r.source.map { .text($0) } ?? .null])
        }
    }

    public func remove(id: UUID) throws {
        try locked { try db.run("DELETE FROM screenshots WHERE id = ?", [.text(id.uuidString)]) }
    }

    /// Forgets every record (the files are not touched). Returns the paths that were indexed.
    @discardableResult
    public func removeAll() throws -> [String] {
        try locked {
            let paths = try db.query("SELECT path FROM screenshots") { $0.text(0) ?? "" }
            try db.run("DELETE FROM screenshots")
            return paths
        }
    }

    /// Drops records whose file is gone (deleted or moved in Finder). Returns how many were dropped.
    @discardableResult
    public func reconcile(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws -> Int {
        try locked {
            let all = try db.query("SELECT id, path FROM screenshots") { ($0.text(0) ?? "", $0.text(1) ?? "") }
            let missing = all.filter { !fileExists($0.1) }
            try db.transaction { for m in missing { try db.run("DELETE FROM screenshots WHERE id = ?", [.text(m.0)]) } }
            return missing.count
        }
    }

    // MARK: Reading

    /// Newest first. `search` matches the file name and the source app, ignoring case.
    public func records(kind: CaptureKind? = nil, search: String = "", limit: Int? = nil) throws -> [ScreenshotRecord] {
        try locked {
            var sql = "SELECT \(Self.columns) FROM screenshots"
            var clauses: [String] = [], params: [SQLiteDatabase.Value] = []
            if let kind { clauses.append("kind = ?"); params.append(.text(kind.rawValue)) }
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty {
                let escaped = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                clauses.append("(path LIKE ? ESCAPE '\\' OR source LIKE ? ESCAPE '\\')")
                params += [.text("%/%\(escaped)%"), .text("%\(escaped)%")]
            }
            if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
            sql += " ORDER BY created DESC"
            if let limit { sql += " LIMIT \(max(0, limit))" }
            return try db.query(sql, params, row: Self.record)
        }
    }

    public func record(id: UUID) throws -> ScreenshotRecord? {
        try locked {
            try db.query("SELECT \(Self.columns) FROM screenshots WHERE id = ?", [.text(id.uuidString)], row: Self.record).first
        }
    }

    /// Records taken before `date`, for automatic cleanup.
    public func records(olderThan date: Date) throws -> [ScreenshotRecord] {
        try locked {
            try db.query("SELECT \(Self.columns) FROM screenshots WHERE created < ? ORDER BY created",
                         [.double(date.timeIntervalSince1970)], row: Self.record)
        }
    }

    public func count() throws -> Int {
        try locked { try db.query("SELECT COUNT(*) FROM screenshots") { Int($0.int(0)) }.first ?? 0 }
    }

    public func totalBytes() throws -> Int64 {
        try locked { try db.query("SELECT COALESCE(SUM(bytes), 0) FROM screenshots") { $0.int(0) }.first ?? 0 }
    }
}
