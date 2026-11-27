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

@Suite struct DockReaderTests {
    @Test func readsAppsInOrderAndSkipsSpacers() {
        let entries: [[String: Any]] = [
            ["tile-type": "file-tile", "tile-data": ["file-label": "Safari浏览器", "bundle-identifier": "com.apple.Safari",
                                                      "file-data": ["_CFURLString": "file:///Applications/Safari.app/"]]],
            ["tile-type": "spacer-tile", "tile-data": [String: Any]()],
            ["tile-type": "file-tile", "tile-data": ["file-label": "Zed", "bundle-identifier": "dev.zed.Zed",
                                                      "file-data": ["_CFURLString": "file:///Applications/Zed.app/"]]],
            ["tile-type": "file-tile", "tile-data": ["file-label": ""]],
        ]
        let items = DockReader.items(from: entries, kind: .app)
        #expect(items.map(\.name) == ["Safari浏览器", "Zed"])
        #expect(items.map(\.bundleID) == ["com.apple.Safari", "dev.zed.Zed"])
        #expect(items[0].path == "/Applications/Safari.app")
    }
}

@Suite struct ShareNoteTests {
    @Test func limitsLengthAndKeepsOneLine() {
        #expect(ShareNote.limit(String(repeating: "字", count: 30)).count == ShareNote.maxLength)
        #expect(ShareNote.limit("写代码\n不卡") == "写代码 不卡")
    }

    @Test func keepsInnerSpacesWhileTypingButTrimsForTheCard() {
        #expect(ShareNote.limit("Mac ") == "Mac ")
        #expect(ShareNote.normalize("  Mac 瘦身 ") == "Mac 瘦身")
        #expect(ShareNote.normalize("   ").isEmpty)
    }
}

@Suite struct ShareListTests {
    @Test func pickedListsGroupsWithNotesAndSkipsEmptyOnes() {
        let text = ShareList.picked(
            title: "我的 Mac 常用软件",
            groups: [
                .init(name: "AI 与开发", items: [.init(name: "Alma", note: "日常对话的主力"), .init(name: "Zed")]),
                .init(name: "空分组", items: []),
            ],
            signature: "Xuyi · 2026.11", watermark: true)
        #expect(text == "我的 Mac 常用软件\n\nAI 与开发\n- Alma — 日常对话的主力\n- Zed\n\nXuyi · 2026.11 · Orbit")
    }

    @Test func hashtagsGoOnTheLastLineAndAreSkippedWhenEmpty() {
        let groups: [ShareList.Group] = [.init(name: "G", items: [.init(name: "A")])]
        #expect(ShareList.picked(title: "T", groups: groups, signature: "Xuyi", watermark: true, hashtags: " #Mac ")
                == "T\n\nG\n- A\n\nXuyi · Orbit\n#Mac")
        #expect(ShareList.picked(title: "T", groups: groups, signature: "", watermark: false, hashtags: "#Mac")
                == "T\n\nG\n- A\n\n#Mac")
        #expect(ShareList.picked(title: "T", groups: groups, signature: "", watermark: false, hashtags: "  ") == "T\n\nG\n- A")
    }

    @Test func footerFollowsSignatureAndWatermark() {
        #expect(ShareList.footer(signature: "", watermark: false) == nil)
        #expect(ShareList.footer(signature: " Xuyi ", watermark: false) == "Xuyi")
        #expect(ShareList.footer(signature: "", watermark: true) == "Orbit")
        #expect(!ShareList.picked(title: "T", groups: [], signature: "", watermark: false).contains("Orbit"))
    }

    @Test func rankingNumbersEntriesAndFormatsDuration() {
        let text = ShareList.ranking(title: "2026 我最常用的 Mac 应用",
                                     entries: [(name: "Chrome", seconds: 48.4 * 3600), (name: "Zed", seconds: 20.0 * 60)],
                                     showDuration: true, signature: "", watermark: true)
        #expect(text == "2026 我最常用的 Mac 应用\n\n1. Chrome — 48.4 小时\n2. Zed — 20 分钟\n\nOrbit")
        let bare = ShareList.ranking(title: "T", entries: [(name: "Chrome", seconds: 3600.0)], showDuration: false, signature: "", watermark: false)
        #expect(bare == "T\n\n1. Chrome")
    }
}

@Suite struct ScreenshotLibraryTests {
    private func record(_ name: String, at t: TimeInterval, kind: CaptureKind = .region, source: String? = nil, bytes: Int64 = 100) -> ScreenshotRecord {
        ScreenshotRecord(path: "/tmp/Orbit/\(name)", createdAt: Date(timeIntervalSince1970: t), kind: kind,
                         pixelWidth: 1624, pixelHeight: 1072, scale: 2, byteCount: bytes, source: source)
    }

    @Test func namesStartWithTheProductAndNeverCollide() {
        let utc = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_795_000_000)   // fixed instant
        let first = ScreenshotNaming.fileName(date: date, timeZone: utc, exists: { _ in false })
        #expect(first.hasPrefix("Orbit 20") && first.hasSuffix(".png"))
        #expect(first.contains(" ") && !first.contains(":") && !first.contains("/"))
        let second = ScreenshotNaming.fileName(date: date, timeZone: utc, exists: { $0 == first })
        #expect(second == first.replacingOccurrences(of: ".png", with: " (2).png"))
        let third = ScreenshotNaming.fileName(date: date, timeZone: utc, exists: { $0 == first || $0 == second })
        #expect(third.hasSuffix("(3).png"))
        #expect(ScreenshotNaming.fileName(date: date, ext: "jpg", timeZone: utc, exists: { _ in false }).hasSuffix(".jpg"))
    }

    @Test func listsNewestFirstAndFiltersByKindAndSearch() throws {
        let store = try ScreenshotStore(url: nil)
        try store.add(record("Orbit A.png", at: 100, kind: .region, source: "Safari"))
        try store.add(record("Orbit B.png", at: 300, kind: .window, source: "Xcode"))
        try store.add(record("Orbit C.png", at: 200, kind: .fullscreen))
        #expect(try store.records().map(\.fileName) == ["Orbit B.png", "Orbit C.png", "Orbit A.png"])
        #expect(try store.records(kind: .window).map(\.fileName) == ["Orbit B.png"])
        #expect(try store.records(search: "xcode").map(\.fileName) == ["Orbit B.png"])
        #expect(try store.records(search: "orbit c").map(\.fileName) == ["Orbit C.png"])
        #expect(try store.records(search: "100%").isEmpty)          // % is literal, not a wildcard
        #expect(try store.records(limit: 2).count == 2)
    }

    @Test func totalsRemovalAndOlderThan() throws {
        let store = try ScreenshotStore(url: nil)
        let a = record("a.png", at: 100, bytes: 10), b = record("b.png", at: 200, bytes: 32)
        try store.add(a); try store.add(b)
        #expect(try store.count() == 2)
        #expect(try store.totalBytes() == 42)
        #expect(try store.records(olderThan: Date(timeIntervalSince1970: 150)).map(\.fileName) == ["a.png"])
        try store.remove(id: a.id)
        #expect(try store.record(id: a.id) == nil)
        #expect(try store.count() == 1)
        #expect(try store.removeAll() == [b.path])
        #expect(try store.count() == 0)
    }

    @Test func reconcileDropsRecordsWhoseFileIsGone() throws {
        let store = try ScreenshotStore(url: nil)
        try store.add(record("kept.png", at: 1)); try store.add(record("gone.png", at: 2))
        let dropped = try store.reconcile(fileExists: { $0.hasSuffix("kept.png") })
        #expect(dropped == 1)
        #expect(try store.records().map(\.fileName) == ["kept.png"])
    }

    @Test func pointSizeFollowsTheBackingScale() {
        #expect(record("x.png", at: 0).pointSize == (812, 536))
    }

    @Test func recordsSurviveReopeningTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-shots-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = record("persist.png", at: 5, kind: .window, source: "Safari")
        do { try ScreenshotStore(url: url).add(r) }
        #expect(try ScreenshotStore(url: url).record(id: r.id) == r)
    }
}

@Suite struct AnnotationGeometryTests {
    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    @Test func rectFromDragNormalisesAndCanBeSquare() {
        #expect(GeometryTools.rect(from: pt(100, 80), to: pt(40, 20), square: false) == CGRect(x: 40, y: 20, width: 60, height: 60))
        let sq = GeometryTools.rect(from: pt(10, 10), to: pt(70, 40), square: true)
        #expect(sq.width == sq.height && sq.width == 60)
        let sqUpLeft = GeometryTools.rect(from: pt(100, 100), to: pt(70, 40), square: true)
        #expect(sqUpLeft == CGRect(x: 40, y: 40, width: 60, height: 60))
    }

    @Test func lineEndpointsSnapToFortyFiveDegrees() {
        let h = GeometryTools.endpoint(from: pt(0, 0), to: pt(100, 8), snap: true)
        #expect(abs(h.y) < 0.001 && abs(h.x - hypot(100, 8)) < 0.001)
        let v = GeometryTools.endpoint(from: pt(0, 0), to: pt(6, 90), snap: true)
        #expect(abs(v.x) < 0.001)
        let d = GeometryTools.endpoint(from: pt(0, 0), to: pt(50, 40), snap: true)
        #expect(abs(d.x - d.y) < 0.001)
        #expect(GeometryTools.endpoint(from: pt(0, 0), to: pt(50, 40), snap: false) == pt(50, 40))
    }

    @Test func hitTestingFindsOutlinesAndLines() {
        var rect = Annotation(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100)))
        rect.lineWidth = 6
        #expect(rect.hit(pt(100, 150), tolerance: 4))        // on the edge
        #expect(!rect.hit(pt(200, 150), tolerance: 4))       // the empty middle stays click-through
        #expect(!rect.hit(pt(10, 10), tolerance: 4))
        var arrow = Annotation(shape: .arrow(from: pt(0, 0), to: pt(100, 0)))
        arrow.lineWidth = 6
        #expect(arrow.hit(pt(50, 5), tolerance: 4))
        #expect(!arrow.hit(pt(50, 40), tolerance: 4))
        let blur = Annotation(shape: .blur(CGRect(x: 0, y: 0, width: 50, height: 50)))
        #expect(blur.hit(pt(25, 25), tolerance: 4))          // regions are hit anywhere inside
    }

    @Test func movingShiftsEveryPoint() {
        let a = Annotation(shape: .arrow(from: pt(1, 2), to: pt(3, 4))).moved(by: CGVector(dx: 10, dy: 20))
        #expect(a.shape == .arrow(from: pt(11, 22), to: pt(13, 24)))
        let t = Annotation(shape: .text(origin: pt(5, 5), string: "hi")).moved(by: CGVector(dx: -5, dy: 1))
        #expect(t.shape == .text(origin: pt(0, 6), string: "hi"))
    }

    @Test func resizingDragsOneHandleAndKeepsTheOppositeCorner() {
        let r = CGRect(x: 100, y: 100, width: 100, height: 50)
        #expect(RectGeometry.resize(r, handle: .bottomRight, to: pt(250, 220)) == CGRect(x: 100, y: 100, width: 150, height: 120))
        #expect(RectGeometry.resize(r, handle: .left, to: pt(60, 999)) == CGRect(x: 60, y: 100, width: 140, height: 50))
        // dragging past the opposite edge flips instead of producing a negative size
        #expect(RectGeometry.resize(r, handle: .right, to: pt(50, 0)) == CGRect(x: 50, y: 100, width: 50, height: 50))
        let sq = RectGeometry.resize(r, handle: .bottomRight, to: pt(260, 160), square: true)
        #expect(sq.width == sq.height)
        let arrow = Annotation(shape: .arrow(from: pt(0, 0), to: pt(10, 0))).resized(.end, to: pt(30, 40), constrain: false)
        #expect(arrow.shape == .arrow(from: pt(0, 0), to: pt(30, 40)))
    }

    @Test func cropRespectsBoundsMinimumSizeAndRatio() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let start = CGRect(x: 100, y: 100, width: 400, height: 300)
        let grown = CropMath.resize(start, handle: .bottomRight, to: pt(2000, 2000), bounds: bounds, ratio: nil)
        #expect(grown == CGRect(x: 100, y: 100, width: 700, height: 500))
        let tiny = CropMath.resize(start, handle: .bottomRight, to: pt(101, 101), bounds: bounds, ratio: nil)
        #expect(tiny.width >= 24 && tiny.height >= 24)
        let locked = CropMath.resize(start, handle: .bottomRight, to: pt(500, 500), bounds: bounds, ratio: 1)
        #expect(abs(locked.width - locked.height) < 0.001)
        let fitted = CropMath.fit(CGRect(x: 0, y: 0, width: 800, height: 600), ratio: 16.0 / 9.0)
        #expect(abs(fitted.width / fitted.height - 16.0 / 9.0) < 0.001 && fitted.midX == 400 && fitted.midY == 300)
        #expect(GeometryTools.clamp(CGRect(x: 700, y: -20, width: 200, height: 100), in: bounds) == CGRect(x: 600, y: 0, width: 200, height: 100))
    }

    @Test func historyUndoesRedoesAndTracksDirty() {
        var h = EditHistory()
        #expect(!h.canUndo && !h.isDirty)
        let a = Annotation(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        h.commit(EditSnapshot(items: [a]))
        #expect(h.canUndo && !h.canRedo && h.isDirty)
        h.commit(EditSnapshot(items: [a], crop: CGRect(x: 0, y: 0, width: 5, height: 5)))
        #expect(h.undo() && h.current.crop == nil && h.current.items.count == 1)
        #expect(h.canRedo)
        #expect(h.redo() && h.current.crop != nil)
        h.undo(); h.undo()
        #expect(!h.isDirty && !h.canUndo)
        h.commit(EditSnapshot(items: [a]))
        h.undo()
        h.commit(EditSnapshot(items: []))      // an identical state is not a new step
        #expect(!h.canUndo)
        h.commit(EditSnapshot(items: [a]))
        h.undo()
        h.commit(EditSnapshot(items: [Annotation(shape: .line(from: pt(0, 0), to: pt(1, 1)))]))
        #expect(!h.canRedo)                    // a new edit clears redo
    }

    @Test func scalingAndEditedNames() {
        #expect(AnnotationScale.factor(forImageWidth: 600) == 1)
        #expect(AnnotationScale.factor(forImageWidth: 2400) == 2)
        #expect(AnnotationScale.factor(forImageWidth: 10_000) == 4)
        #expect(AnnotationScale.lineWidth(.thick, imageWidth: 1200) > AnnotationScale.lineWidth(.thin, imageWidth: 1200))
        let n1 = ScreenshotNaming.editedName(from: "Orbit 2026-11-26 21.03.12.png", exists: { _ in false })
        #expect(n1 == "Orbit 2026-11-26 21.03.12 已编辑.png")
        let n2 = ScreenshotNaming.editedName(from: n1, exists: { $0 == n1 })
        #expect(n2 == "Orbit 2026-11-26 21.03.12 已编辑 (2).png")
        #expect(ScreenshotNaming.editedName(from: "/a/b/Orbit x.jpg", exists: { _ in false }) == "Orbit x 已编辑.jpg")
    }
}
