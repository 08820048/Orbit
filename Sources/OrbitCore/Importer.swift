import Foundation

/// Copies new Screen Time sessions into the local history store. Safe to run repeatedly:
/// sessions are keyed by their Screen Time UUID, so re-imports never double count.
public struct Importer: Sendable {
    public struct Result: Sendable, Equatable {
        public var read: Int
        public var inserted: Int
    }

    static let lastImportKey = "screentime.lastImport"
    /// Re-read a little before the newest stored session: Screen Time can finalize a session late.
    static let overlap: TimeInterval = 24 * 3600

    public let reader: ScreenTimeReader
    public let store: HistoryStore

    public init(reader: ScreenTimeReader = ScreenTimeReader(), store: HistoryStore) {
        self.reader = reader
        self.store = store
    }

    @discardableResult
    public func importScreenTime(now: Date = Date()) throws -> Result {
        let since = try store.latestEnd(source: .screenTime).map { $0.addingTimeInterval(-Self.overlap) }
        let sessions = try reader.sessions(since: since ?? .distantPast)
        let inserted = try store.insert(sessions)
        try store.setMeta(Self.lastImportKey, String(now.timeIntervalSince1970))
        return Result(read: sessions.count, inserted: inserted)
    }

    public func lastImportDate() throws -> Date? {
        try store.meta(Self.lastImportKey).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }
}
