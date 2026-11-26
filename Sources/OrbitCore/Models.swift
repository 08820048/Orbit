import Foundation

/// Where a usage session came from.
public enum UsageSource: String, Sendable, Codable, CaseIterable {
    /// Imported from the system Screen Time database (knowledgeC.db).
    case screenTime = "screentime"
    /// Recorded by Orbit's own NSWorkspace foreground-app monitor.
    case monitor = "monitor"
}

/// One continuous stretch of an app being in the foreground.
public struct UsageSession: Sendable, Hashable, Codable {
    public var bundleID: String
    public var start: Date
    public var end: Date
    public var source: UsageSource
    /// Stable identity in the source, used to make imports idempotent.
    public var sourceKey: String

    public init(bundleID: String, start: Date, end: Date, source: UsageSource, sourceKey: String) {
        self.bundleID = bundleID
        self.start = start
        self.end = end
        self.source = source
        self.sourceKey = sourceKey
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Seconds of this session that fall inside `interval`.
    public func overlap(with interval: DateInterval) -> TimeInterval {
        let s = max(start, interval.start)
        let e = min(end, interval.end)
        return max(0, e.timeIntervalSince(s))
    }
}

/// Aggregated usage of one app over a period.
public struct AppUsage: Sendable, Hashable, Identifiable {
    public var bundleID: String
    public var seconds: TimeInterval
    /// Number of foreground sessions that started inside the period (≈ "launches"/activations).
    public var sessions: Int

    public var id: String { bundleID }
    public var hours: Double { seconds / 3600 }

    public init(bundleID: String, seconds: TimeInterval, sessions: Int) {
        self.bundleID = bundleID
        self.seconds = seconds
        self.sessions = sessions
    }
}

/// Total screen time on one calendar day.
public struct DailyTotal: Sendable, Hashable, Identifiable {
    /// Start of the day in the calendar's time zone.
    public var day: Date
    public var seconds: TimeInterval
    public var id: Date { day }

    public init(day: Date, seconds: TimeInterval) {
        self.day = day
        self.seconds = seconds
    }
}

/// Time dimension for statistics.
public enum StatsPeriod: Sendable, Hashable {
    case year(Int)
    case month(year: Int, month: Int)
    case custom(DateInterval)

    public func interval(in calendar: Calendar) -> DateInterval {
        switch self {
        case let .year(y):
            let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1))!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return DateInterval(start: start, end: end)
        case let .month(y, m):
            let start = calendar.date(from: DateComponents(year: y, month: m, day: 1))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return DateInterval(start: start, end: end)
        case let .custom(interval):
            return interval
        }
    }
}

/// Summary used by the overview screen and share cards.
public struct PeriodSummary: Sendable {
    public var period: StatsPeriod
    /// The part of the period we actually have data for (from first recorded session to now / period end).
    public var coveredInterval: DateInterval?
    public var totalSeconds: TimeInterval
    public var topApps: [AppUsage]
    public var daily: [DailyTotal]
    /// Days in `daily` with any usage.
    public var activeDays: Int { daily.filter { $0.seconds > 0 }.count }
    public var averagePerActiveDay: TimeInterval { activeDays == 0 ? 0 : totalSeconds / Double(activeDays) }
    public var longestDay: DailyTotal? { daily.max { $0.seconds < $1.seconds } }
    /// Distinct apps used in the period.
    public var appCount: Int
}
