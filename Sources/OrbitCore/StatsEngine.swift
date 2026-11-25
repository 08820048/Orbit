import Foundation

/// Turns raw sessions into the numbers shown in the app and on share cards. Pure and synchronous.
public struct StatsEngine: Sendable {
    /// System processes that are "in front" without being used: never counted.
    public static let defaultExcluded: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.UserNotificationCenter",
    ]

    public var calendar: Calendar
    public var excluded: Set<String>

    public init(calendar: Calendar = .current, hidden: Set<String> = []) {
        self.calendar = calendar
        self.excluded = Self.defaultExcluded.union(hidden)
    }

    /// Summary of `period`, using only time up to `now`.
    public func summary(of sessions: [UsageSession], period: StatsPeriod, now: Date = Date(), topN: Int = 10) -> PeriodSummary {
        let full = period.interval(in: calendar)
        let window = DateInterval(start: full.start, end: max(full.start, min(full.end, now)))
        let used = resolve(sessions, in: window)

        var byApp: [String: AppUsage] = [:]
        for s in used {
            let secs = s.overlap(with: window)
            guard secs > 0 else { continue }
            var entry = byApp[s.bundleID] ?? AppUsage(bundleID: s.bundleID, seconds: 0, sessions: 0)
            entry.seconds += secs
            if window.contains(s.start) { entry.sessions += 1 }
            byApp[s.bundleID] = entry
        }
        let ranked = byApp.values.sorted { ($0.seconds, $1.bundleID) > ($1.seconds, $0.bundleID) }
        let daily = dailyTotals(used, in: window)
        let firstDay = daily.first { $0.seconds > 0 }?.day

        return PeriodSummary(
            period: period,
            coveredInterval: firstDay.map { DateInterval(start: $0, end: window.end) },
            totalSeconds: ranked.reduce(0) { $0 + $1.seconds },
            topApps: Array(ranked.prefix(topN)),
            daily: firstDay.map { start in daily.filter { $0.day >= start } } ?? [],
            appCount: ranked.count)
    }

    /// Total and per-day usage of one app over `period`.
    public func appDetail(bundleID: String, sessions: [UsageSession], period: StatsPeriod, now: Date = Date()) -> (total: TimeInterval, daily: [DailyTotal]) {
        let full = period.interval(in: calendar)
        let window = DateInterval(start: full.start, end: max(full.start, min(full.end, now)))
        let used = resolve(sessions, in: window).filter { $0.bundleID == bundleID }
        let daily = dailyTotals(used, in: window)
        return (daily.reduce(0) { $0 + $1.seconds }, daily)
    }

    /// Hour-of-day and weekday profile plus session lengths of one app over `period`.
    /// - Parameter from: first day we have data for; days before it are not counted in the weekday averages.
    public func appInsights(bundleID: String, sessions: [UsageSession], period: StatsPeriod, now: Date = Date(), from: Date? = nil) -> AppInsights {
        let full = period.interval(in: calendar)
        let window = DateInterval(start: full.start, end: max(full.start, min(full.end, now)))
        let used = resolve(sessions, in: window).filter { $0.bundleID == bundleID }

        var hourly = [TimeInterval](repeating: 0, count: 24)
        var total: TimeInterval = 0, longest: TimeInterval = 0, count = 0
        for s in used {
            let secs = s.overlap(with: window)
            guard secs > 0 else { continue }
            count += 1; total += secs; longest = max(longest, secs)
            var cursor = max(s.start, window.start)
            let end = min(s.end, window.end)
            while cursor < end {
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? end
                let sliceEnd = min(end, max(hourEnd, cursor.addingTimeInterval(1)))
                hourly[calendar.component(.hour, from: cursor)] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }

        var sums = [TimeInterval](repeating: 0, count: 7), days = [Int](repeating: 0, count: 7)
        for d in dailyTotals(used, in: window) where from.map({ d.day >= $0 }) ?? true {
            let index = (calendar.component(.weekday, from: d.day) + 5) % 7   // Sunday = 1 → 6, Monday = 2 → 0
            sums[index] += d.seconds; days[index] += 1
        }
        let weekday = (0..<7).map { days[$0] == 0 ? 0 : sums[$0] / Double(days[$0]) }
        return AppInsights(hourly: hourly, weekdayAverage: weekday, sessionCount: count,
                           averageSession: count == 0 ? 0 : total / Double(count), longestSession: longest)
    }

    // MARK: Internals

    /// Drops excluded apps and picks one source per day: Screen Time where it has data
    /// for that day, Orbit's own monitor otherwise. The two overlap, so they must never be summed.
    func resolve(_ sessions: [UsageSession], in window: DateInterval) -> [UsageSession] {
        let relevant = sessions.filter { !excluded.contains($0.bundleID) && $0.overlap(with: window) > 0 }
        let screenTimeDays = Set(relevant.lazy.filter { $0.source == .screenTime }.map { calendar.startOfDay(for: $0.start) })
        return relevant.filter { s in
            s.source == .screenTime || !screenTimeDays.contains(calendar.startOfDay(for: s.start))
        }
    }

    /// Seconds per calendar day across `window`, splitting sessions that cross midnight.
    func dailyTotals(_ sessions: [UsageSession], in window: DateInterval) -> [DailyTotal] {
        guard window.duration > 0 else { return [] }
        var totals: [Date: TimeInterval] = [:]
        for s in sessions {
            var cursor = max(s.start, window.start)
            let end = min(s.end, window.end)
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                let sliceEnd = min(end, next)
                totals[day, default: 0] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }
        var out: [DailyTotal] = []
        var day = calendar.startOfDay(for: window.start)
        while day < window.end {
            out.append(DailyTotal(day: day, seconds: totals[day] ?? 0))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
