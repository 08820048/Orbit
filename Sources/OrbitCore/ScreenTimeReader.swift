import Foundation

/// Reads app usage from the system Screen Time store (`knowledgeC.db`).
///
/// This is a private, undocumented database. It requires Full Disk Access and only keeps
/// a few weeks of history, which is why `Importer` copies it into Orbit's own `HistoryStore`.
public struct ScreenTimeReader: Sendable {
    public enum Access: Sendable, Equatable {
        case granted
        /// The file exists but we cannot open it: Full Disk Access is missing.
        case denied
        /// No Screen Time database on this Mac (feature off, or the path moved in a new macOS).
        case unavailable
    }

    public enum ReadError: Error, CustomStringConvertible {
        case accessDenied
        case unavailable
        case schemaChanged(String)

        public var description: String {
            switch self {
            case .accessDenied: String(localized: "没有完全磁盘访问权限，无法读取屏幕使用时间。")
            case .unavailable: String(localized: "没有找到屏幕使用时间数据库。")
            case let .schemaChanged(detail): String(localized: "屏幕使用时间数据库结构和预期不一致：\(detail)")
            }
        }
    }

    /// Core Data reference date (2001-01-01) as Unix time.
    static let coreDataEpochOffset: TimeInterval = 978_307_200

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
    }

    public let databaseURL: URL

    public init(databaseURL: URL = ScreenTimeReader.defaultURL) {
        self.databaseURL = databaseURL
    }

    /// Checks whether we can read the database. Cheap enough to poll while onboarding.
    public func checkAccess() -> Access {
        do {
            let db = try SQLiteDatabase(path: databaseURL.path, readOnly: true)
            _ = try db.query("SELECT 1 FROM ZOBJECT LIMIT 1") { _ in () }
            return .granted
        } catch {
            return classifyFailure()
        }
    }

    /// Opening failed: tell "no permission" apart from "no database".
    /// Without Full Disk Access the Knowledge folder cannot be listed, so a listing error means denied.
    private func classifyFailure() -> Access {
        let fm = FileManager.default
        if fm.fileExists(atPath: databaseURL.path) { return .denied }
        let folder = databaseURL.deletingLastPathComponent().path
        do {
            _ = try fm.contentsOfDirectory(atPath: folder)
            return .unavailable
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .denied
        } catch {
            return fm.fileExists(atPath: folder) ? .denied : .unavailable
        }
    }

    /// Foreground app sessions recorded on this Mac whose end time is after `since`.
    /// Sessions synced from other devices (iPhone/iPad) are excluded.
    public func sessions(since: Date = .distantPast) throws -> [UsageSession] {
        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: databaseURL.path, readOnly: true)
            // sqlite opens lazily; touch the file so permission errors surface here, not as "schema changed".
            _ = try db.query("SELECT 1 FROM sqlite_master LIMIT 1") { _ in () }
        } catch {
            throw classifyFailure() == .unavailable ? ReadError.unavailable : ReadError.accessDenied
        }

        let sinceCD = since == .distantPast ? -Double.greatestFiniteMagnitude
            : since.timeIntervalSince1970 - Self.coreDataEpochOffset
        let sql = """
            SELECT o.Z_PK, o.ZUUID, o.ZVALUESTRING, o.ZSTARTDATE, o.ZENDDATE
            FROM ZOBJECT o
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/app/usage'
              AND o.ZVALUESTRING IS NOT NULL
              AND o.ZENDDATE > o.ZSTARTDATE
              AND o.ZENDDATE > ?
              AND (o.ZSOURCE IS NULL OR s.ZDEVICEID IS NULL)
            ORDER BY o.ZSTARTDATE
            """
        do {
            return try db.query(sql, [.double(sinceCD)]) { row in
                let start = Date(timeIntervalSince1970: row.double(3) + Self.coreDataEpochOffset)
                let end = Date(timeIntervalSince1970: row.double(4) + Self.coreDataEpochOffset)
                let key = row.text(1).map { "kc:\($0)" } ?? "kc:\(row.int(0)):\(Int64(row.double(3)))"
                return UsageSession(
                    bundleID: row.text(2) ?? "",
                    start: start, end: end,
                    source: .screenTime, sourceKey: key
                )
            }
        } catch let error as SQLiteDatabase.Error {
            throw ReadError.schemaChanged(error.description)
        }
    }
}
