import Foundation
import OrbitCore

/// Decides which installed apps are worth *recommending* for a share card, and in what order.
/// (The manual picker still lists everything.)
enum AppRecommender {
    /// Apple apps people actually show off. Every other `com.apple.*` app is a system tool
    /// (System Settings, App Store, Activity Monitor, Migration Assistant, Dictionary, Tips, Print Center…) and is skipped.
    private static let appleShowcase: [String] = [
        "com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.apple.Notes", "com.apple.Music",
        "com.apple.Photos", "com.apple.podcasts", "com.apple.TV", "com.apple.iCal", "com.apple.reminders",
        "com.apple.Maps", "com.apple.FaceTime", "com.apple.iWork.", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.apple.QuickTimePlayerX", "com.apple.iMovieApp", "com.apple.garageband",
    ]

    static func isRecommendable(_ app: InstalledApp) -> Bool {
        guard app.bundleID.hasPrefix("com.apple.") else { return true }
        return appleShowcase.contains { app.bundleID == $0 || ($0.hasSuffix(".") && app.bundleID.hasPrefix($0)) }
    }

    /// Recency-weighted usage per app: each session counts for its length, halved for every `halfLifeDays`
    /// since it ended. So an app used heavily this week outranks one used a lot a month ago.
    static func recencyScores(_ sessions: [UsageSession], now: Date = Date(), halfLifeDays: Double = 7) -> [String: Double] {
        var scores: [String: Double] = [:]
        for s in sessions {
            let ageDays = max(0, now.timeIntervalSince(s.end)) / 86_400
            scores[s.bundleID, default: 0] += s.duration * pow(0.5, ageDays / halfLifeDays)
        }
        return scores
    }

    /// Candidates ordered by score (best first). Apps with no recorded use only fill up to `minimum`,
    /// so a group isn't padded with things the user never opens.
    static func pick(from candidates: [InstalledApp], scores: [String: Double], limit: Int, minimum: Int = 3) -> [InstalledApp] {
        let used = candidates.filter { (scores[$0.bundleID] ?? 0) > 0 }
            .sorted { (scores[$0.bundleID] ?? 0) > (scores[$1.bundleID] ?? 0) }
        var result = Array(used.prefix(limit))
        if result.count < minimum {
            let unused = candidates.filter { (scores[$0.bundleID] ?? 0) <= 0 }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result += unused.prefix(minimum - result.count)
        }
        return result
    }
}
