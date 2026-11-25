import Foundation
import Testing
@testable import OrbitCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    return f.date(from: s)!
}

private func session(_ id: String, _ start: String, _ end: String, _ source: UsageSource = .screenTime, key: String? = nil) -> UsageSession {
    UsageSession(bundleID: id, start: date(start), end: date(end), source: source, sourceKey: key ?? "\(source):\(id):\(start)")
}

@Suite struct StatsEngineTests {
    let engine = StatsEngine(calendar: utc)

    @Test func ranksAppsByTimeAndClipsToPeriod() {
        let sessions = [
            session("chrome", "2026-11-01T10:00:00Z", "2026-11-01T12:00:00Z"),
            session("zed", "2026-11-02T09:00:00Z", "2026-11-02T10:00:00Z"),
            // Starts in October: only the November half counts.
            session("zed", "2026-10-31T23:00:00Z", "2026-11-01T01:00:00Z"),
        ]
        let s = engine.summary(of: sessions, period: .month(year: 2026, month: 11), now: date("2026-11-25T00:00:00Z"))
        #expect(s.topApps.map(\.bundleID) == ["chrome", "zed"])
        #expect(s.topApps[0].seconds == 7200)
        #expect(s.topApps[1].seconds == 3600 + 3600)
        #expect(s.topApps[1].sessions == 1, "session started in October is not a November launch")
        #expect(s.totalSeconds == 14400)
        #expect(s.appCount == 2)
    }

    @Test func splitsSessionsAcrossMidnight() {
        let sessions = [session("a", "2026-11-01T23:00:00Z", "2026-11-02T02:00:00Z")]
        let s = engine.summary(of: sessions, period: .month(year: 2026, month: 11), now: date("2026-11-03T00:00:00Z"))
        #expect(s.daily.map(\.seconds) == [3600, 7200])
        #expect(s.longestDay?.day == date("2026-11-02T00:00:00Z"))
    }

    @Test func coverageStartsAtFirstRecordedDay() {
        let sessions = [session("a", "2026-11-06T08:00:00Z", "2026-11-06T09:00:00Z")]
        let s = engine.summary(of: sessions, period: .year(2026), now: date("2026-11-08T12:00:00Z"))
        #expect(s.coveredInterval?.start == date("2026-11-06T00:00:00Z"))
        #expect(s.daily.count == 3, "Nov 6, 7, 8 — not padded back to Jan 1")
        #expect(s.activeDays == 1)
    }

    @Test func prefersScreenTimeOverMonitorOnTheSameDay() {
        let sessions = [
            session("a", "2026-11-01T10:00:00Z", "2026-11-01T11:00:00Z", .screenTime),
            session("a", "2026-11-01T10:00:00Z", "2026-11-01T11:00:00Z", .monitor),
            // Only the monitor saw Nov 2 (e.g. no Full Disk Access yet): keep it.
            session("a", "2026-11-02T10:00:00Z", "2026-11-02T10:30:00Z", .monitor),
        ]
        let s = engine.summary(of: sessions, period: .month(year: 2026, month: 11), now: date("2026-11-03T00:00:00Z"))
        #expect(s.totalSeconds == 3600 + 1800)
    }

    @Test func excludesSystemAndHiddenApps() {
        let engine = StatsEngine(calendar: utc, hidden: ["secret"])
        let sessions = [
            session("com.apple.loginwindow", "2026-11-01T10:00:00Z", "2026-11-01T11:00:00Z"),
            session("secret", "2026-11-01T11:00:00Z", "2026-11-01T12:00:00Z"),
            session("ok", "2026-11-01T12:00:00Z", "2026-11-01T12:10:00Z"),
        ]
        let s = engine.summary(of: sessions, period: .year(2026), now: date("2026-12-01T00:00:00Z"))
        #expect(s.topApps.map(\.bundleID) == ["ok"])
    }

    @Test func ignoresTimeAfterNow() {
        let sessions = [session("a", "2026-11-01T10:00:00Z", "2026-11-01T12:00:00Z")]
        let s = engine.summary(of: sessions, period: .year(2026), now: date("2026-11-01T11:00:00Z"))
        #expect(s.totalSeconds == 3600)
    }

    @Test func appDetailTotalsOneApp() {
        let sessions = [
            session("a", "2026-11-01T10:00:00Z", "2026-11-01T11:00:00Z"),
            session("b", "2026-11-01T11:00:00Z", "2026-11-01T12:00:00Z"),
            session("a", "2026-11-03T10:00:00Z", "2026-11-03T10:30:00Z"),
        ]
        let d = engine.appDetail(bundleID: "a", sessions: sessions, period: .month(year: 2026, month: 11), now: date("2026-11-04T00:00:00Z"))
        #expect(d.total == 5400)
        #expect(d.daily.map(\.seconds) == [3600, 0, 1800], "Nov 1–3; the window ends at Nov 4 00:00")
    }

    @Test func appInsightsProfilesHoursWeekdaysAndSessions() {
        // 2026-11-02 is a Monday, 2026-11-04 a Wednesday.
        let sessions = [
            session("a", "2026-11-02T09:30:00Z", "2026-11-02T10:30:00Z"),   // crosses an hour boundary
            session("a", "2026-11-02T14:00:00Z", "2026-11-02T14:20:00Z"),
            session("a", "2026-11-04T09:00:00Z", "2026-11-04T09:10:00Z"),
            session("b", "2026-11-03T09:00:00Z", "2026-11-03T12:00:00Z"),   // other apps are ignored
        ]
        let i = engine.appInsights(bundleID: "a", sessions: sessions, period: .month(year: 2026, month: 11), now: date("2026-11-05T00:00:00Z"))
        #expect(i.hourly[9] == 1800 + 600)
        #expect(i.hourly[10] == 1800)
        #expect(i.hourly[14] == 1200)
        #expect(i.hourly.reduce(0, +) == 5400)
        #expect(i.peakHour == 9)
        #expect(i.sessionCount == 3)
        #expect(i.longestSession == 3600)
        #expect(i.averageSession == 1800)
        #expect(i.weekdayAverage[0] == 4800, "one Monday in range")
        #expect(i.weekdayAverage[2] == 600)
        #expect(i.weekdayAverage[1] == 0)
        #expect(i.peakWeekday == 0)
        let later = engine.appInsights(bundleID: "a", sessions: sessions, period: .month(year: 2026, month: 11),
                                       now: date("2026-11-05T00:00:00Z"), from: date("2026-11-03T00:00:00Z"))
        #expect(later.weekdayAverage[0] == 0, "days before `from` are not counted")
    }
}

@Suite struct HistoryStoreTests {
    @Test func insertIsIdempotentBySourceKey() throws {
        let store = try HistoryStore(url: nil)
        let s = session("a", "2026-11-01T10:00:00Z", "2026-11-01T11:00:00Z", key: "kc:1")
        #expect(try store.insert([s]) == 1)
        #expect(try store.insert([s, s]) == 0)
        #expect(try store.sessionCount() == 1)
    }

    @Test func queriesOverlappingSessions() throws {
        let store = try HistoryStore(url: nil)
        try store.insert([
            session("a", "2026-10-31T23:00:00Z", "2026-11-01T01:00:00Z"),
            session("b", "2026-12-01T00:00:00Z", "2026-12-01T01:00:00Z"),
        ])
        let nov = StatsPeriod.month(year: 2026, month: 11).interval(in: utc)
        #expect(try store.sessions(overlapping: nov).map(\.bundleID) == ["a"])
        #expect(try store.earliestStart() == date("2026-10-31T23:00:00Z"))
    }

    @Test func appPreferences() throws {
        let store = try HistoryStore(url: nil)
        try store.setHidden(true, bundleID: "x")
        try store.setDisplayName("微信", bundleID: "com.tencent.xinWeChat")
        #expect(try store.hiddenBundleIDs() == ["x"])
        #expect(try store.displayNameOverrides() == ["com.tencent.xinWeChat": "微信"])
        try store.setHidden(false, bundleID: "x")
        try store.setDisplayName(nil, bundleID: "com.tencent.xinWeChat")
        #expect(try store.hiddenBundleIDs().isEmpty)
        #expect(try store.displayNameOverrides().isEmpty)
    }
}

@Suite struct ScreenTimeImportTests {
    /// Builds a file shaped like knowledgeC.db with the columns Orbit reads.
    func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kc-\(UUID().uuidString).db")
        let db = try SQLiteDatabase(path: url.path, readOnly: false)
        try db.execute("""
            CREATE TABLE ZSOURCE (Z_PK INTEGER PRIMARY KEY, ZDEVICEID TEXT);
            CREATE TABLE ZOBJECT (Z_PK INTEGER PRIMARY KEY, ZUUID TEXT, ZSTREAMNAME TEXT, ZVALUESTRING TEXT,
                                  ZSTARTDATE REAL, ZENDDATE REAL, ZSOURCE INTEGER);
            INSERT INTO ZSOURCE VALUES (1, 'iphone-device-id');
            -- 2026-11-01T00:00:00Z = 1793491200 unix = 815184000 core data
            INSERT INTO ZOBJECT VALUES (1, 'u1', '/app/usage', 'com.google.Chrome', 815184000, 815187600, NULL);
            INSERT INTO ZOBJECT VALUES (2, 'u2', '/app/usage', 'dev.zed.Zed', 815187600, 815189400, NULL);
            INSERT INTO ZOBJECT VALUES (3, 'u3', '/app/usage', 'com.phone.app', 815184000, 815187600, 1);
            INSERT INTO ZOBJECT VALUES (4, 'u4', '/app/webUsage', 'example.com', 815184000, 815187600, NULL);
            INSERT INTO ZOBJECT VALUES (5, 'u5', '/app/usage', 'broken', 815187600, 815184000, NULL);
            """)
        return url
    }

    @Test func readsOnlyLocalAppUsage() throws {
        let reader = ScreenTimeReader(databaseURL: try makeFixture())
        #expect(reader.checkAccess() == .granted)
        let sessions = try reader.sessions()
        #expect(sessions.map(\.bundleID) == ["com.google.Chrome", "dev.zed.Zed"])
        #expect(sessions[0].start == date("2026-11-01T00:00:00Z"))
        #expect(sessions[0].duration == 3600)
        #expect(sessions[0].sourceKey == "kc:u1")
    }

    @Test func importIsIncrementalAndIdempotent() throws {
        let url = try makeFixture()
        let store = try HistoryStore(url: nil)
        let importer = Importer(reader: ScreenTimeReader(databaseURL: url), store: store)
        #expect(try importer.importScreenTime() == .init(read: 2, inserted: 2))
        #expect(try importer.importScreenTime().inserted == 0)

        let db = try SQLiteDatabase(path: url.path, readOnly: false)
        try db.execute("INSERT INTO ZOBJECT VALUES (6, 'u6', '/app/usage', 'com.apple.finder', 815270400, 815274000, NULL);")
        #expect(try importer.importScreenTime().inserted == 1)
        #expect(try store.sessionCount() == 3)
        #expect(try importer.lastImportDate() != nil)
    }

    @Test func missingDatabaseIsUnavailable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reader = ScreenTimeReader(databaseURL: dir.appendingPathComponent("knowledgeC.db"))
        #expect(reader.checkAccess() == .unavailable)
        #expect(throws: ScreenTimeReader.ReadError.self) { try reader.sessions() }
    }
}

@Suite @MainActor struct ForegroundMonitorTests {
    @Test func recordsSessionOnSwitchAndSkipsBlips() throws {
        let store = try HistoryStore(url: nil)
        var t = date("2026-11-01T10:00:00Z")
        let monitor = ForegroundMonitor(store: store, now: { t })
        monitor.switchTo("a")
        t += 600
        monitor.switchTo("b")
        t += 0.3 // too short to count
        monitor.switchTo("c")
        t += 60
        monitor.switchTo("c") // same app: no new session
        t += 60
        monitor.switchTo(nil) // sleep
        let all = try store.sessions(overlapping: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(all.map(\.bundleID) == ["a", "c"])
        #expect(all.map(\.duration) == [600, 120])
        #expect(all.allSatisfy { $0.source == .monitor })
    }
}

@Suite struct BubblePackingTests {
    private let area = CGSize(width: 492, height: 400)

    @Test func circlesNeverOverlapAndStayInsideTheArea() {
        let weights = (0..<30).map { 50_000 / Double($0 + 1) }   // a steep, realistic usage curve
        let circles = BubblePacking.pack(weights: weights, in: area)
        #expect(circles.count == 30)
        for (i, a) in circles.enumerated() {
            #expect(a.x - a.r >= -0.5 && a.x + a.r <= area.width + 0.5, "circle \(i) inside horizontally")
            #expect(a.y - a.r >= -0.5 && a.y + a.r <= area.height + 0.5, "circle \(i) inside vertically")
            for b in circles[(i + 1)...] {
                #expect(hypot(a.x - b.x, a.y - b.y) >= a.r + b.r, "circles must not overlap")
            }
        }
    }

    @Test func biggestIsLargestAndNearTheMiddle() {
        let circles = BubblePacking.pack(weights: [9000, 4000, 2000, 900, 400, 100], in: area)
        #expect(circles[0].r == circles.map(\.r).max())
        #expect(zip(circles, circles.dropFirst()).allSatisfy { $0.r >= $1.r }, "radius follows usage order")
        let centre = CGPoint(x: area.width / 2, y: area.height / 2)
        let distances = circles.map { hypot($0.x - centre.x, $0.y - centre.y) }
        #expect(distances[0] == distances.min(), "the most used app sits closest to the middle")
    }

    @Test func spacingAndSizeContrastAreAdjustable() {
        let weights = [9000.0, 4000, 2000, 900, 400, 100]
        let tight = BubblePacking.pack(weights: weights, in: area, gap: 0)
        let loose = BubblePacking.pack(weights: weights, in: area, gap: 40)
        #expect(loose[0].r < tight[0].r, "more spacing leaves less room, so icons shrink to fit")
        for circles in [tight, loose] {
            for (i, a) in circles.enumerated() {
                for b in circles[(i + 1)...] { #expect(hypot(a.x - b.x, a.y - b.y) >= a.r + b.r, "never overlap, even at zero spacing") }
            }
        }
        let flat = BubblePacking.pack(weights: weights, in: area, exponent: 0)
        #expect(Set(flat.map { ($0.r * 100).rounded() }).count == 1, "contrast 0 makes every icon the same size")
        let steep = BubblePacking.pack(weights: weights, in: area, exponent: 0.5)
        let mild = BubblePacking.pack(weights: weights, in: area, exponent: 0.2)
        #expect(steep[5].r / steep[0].r < mild[5].r / mild[0].r, "higher contrast widens the gap between biggest and smallest")
    }

    @Test func emptyOrZeroWeightsGiveNothing() {
        #expect(BubblePacking.pack(weights: [], in: area).isEmpty)
        #expect(BubblePacking.pack(weights: [0, 0], in: area).isEmpty)
    }
}
