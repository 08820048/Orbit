import AppKit
import Foundation
import OrbitCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Section: Hashable { case overview, app, share, settings }

    enum Period: String, CaseIterable {
        case year = "年", month = "月", week = "周"
    }

    @Published var section: Section = .overview
    @Published var period: Period = .year { didSet { recompute() } }
    @Published var access: ScreenTimeReader.Access = .unavailable
    @Published var summary: PeriodSummary?
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var lastImport: Date?
    @Published var sessionCount = 0
    @Published var earliest: Date?
    @Published var selectedApp: String?
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "orbit.onboarded") }
    }

    let store: HistoryStore
    let reader = ScreenTimeReader()
    let catalog = AppCatalog()
    private(set) var monitor: ForegroundMonitor?
    private var sessions: [UsageSession] = []
    private var terminateObserver: NSObjectProtocol?

    init() {
        hasOnboarded = UserDefaults.standard.bool(forKey: "orbit.onboarded")
        do { store = try HistoryStore() } catch {
            // Disk store unavailable: keep working in memory rather than crash.
            store = try! HistoryStore(url: nil)
            lastError = "无法打开本地数据库，本次数据不会保存：\(error)"
        }
        catalog.setOverrides((try? store.displayNameOverrides()) ?? [:])
        access = reader.checkAccess()
        if hasOnboarded { startMonitor() }
        recompute()
        Task { await refresh() }
    }

    // MARK: Onboarding

    func checkAccess() {
        access = reader.checkAccess()
        if access == .granted, !hasOnboarded { finishOnboarding() }
    }

    func finishOnboarding() {
        hasOnboarded = true
        startMonitor()
        Task { await refresh() }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        let m = ForegroundMonitor(store: store)
        m.start()
        monitor = m
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak m] _ in MainActor.assumeIsolated { m?.stop() } }
    }

    // MARK: Data

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        access = reader.checkAccess()
        if access == .granted {
            let reader = reader, store = store
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Importer(reader: reader, store: store).importScreenTime()
                }.value
                lastError = nil
            } catch {
                lastError = "\(error)"
            }
        }
        recompute()
    }

    var statsPeriod: StatsPeriod {
        let cal = Calendar.current, now = Date()
        switch period {
        case .year: return .year(cal.component(.year, from: now))
        case .month: return .month(year: cal.component(.year, from: now), month: cal.component(.month, from: now))
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
            return .custom(DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!))
        }
    }

    func recompute() {
        let hidden = (try? store.hiddenBundleIDs()) ?? []
        let engine = StatsEngine(hidden: hidden)
        let interval = statsPeriod.interval(in: .current)
        sessions = (try? store.sessions(overlapping: interval)) ?? []
        summary = engine.summary(of: sessions, period: statsPeriod, topN: 200)
        lastImport = try? Importer(reader: reader, store: store).lastImportDate()
        sessionCount = (try? store.sessionCount()) ?? 0
        earliest = try? store.earliestStart()
        if selectedApp == nil { selectedApp = summary?.topApps.first?.bundleID }
    }

    func detail(for bundleID: String) -> (total: TimeInterval, daily: [DailyTotal]) {
        let d = StatsEngine(hidden: (try? store.hiddenBundleIDs()) ?? []).appDetail(
            bundleID: bundleID, sessions: sessions, period: statsPeriod)
        // Don't pad the chart back to Jan 1: start at the first day we have any data for.
        guard let start = summary?.coveredInterval?.start else { return d }
        return (d.total, d.daily.filter { $0.day >= start })
    }

    func eraseAllData() {
        try? store.eraseAll()
        selectedApp = nil
        recompute()
    }

    // MARK: Labels

    var periodTitle: String {
        let cal = Calendar.current, now = Date()
        switch period {
        case .year: return "\(cal.component(.year, from: now))"
        case .month: return "\(cal.component(.month, from: now)) 月"
        case .week: return "最近 7 天"
        }
    }

    var coverageText: String {
        guard let covered = summary?.coveredInterval else { return "还没有记录" }
        let f = Date.FormatStyle().month(.defaultDigits).day(.defaultDigits)
        let days = summary?.daily.count ?? 0
        return "记录自 \(covered.start.formatted(f))，共 \(days) 天"
    }
}

enum Fmt {
    /// "48.4" + "小时", or "36" + "分钟" when under an hour.
    static func duration(_ seconds: TimeInterval) -> (value: String, unit: String) {
        if seconds < 3600 { return (String(Int((seconds / 60).rounded())), "分钟") }
        return (String(format: "%.1f", seconds / 3600), "小时")
    }

    static func short(_ seconds: TimeInterval) -> String {
        let d = duration(seconds)
        return d.unit == "小时" ? d.value + "h" : d.value + "m"
    }

    static func long(_ seconds: TimeInterval) -> String {
        let d = duration(seconds)
        return d.value + " " + d.unit
    }
}
