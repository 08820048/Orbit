import Foundation
import OrbitCore

// Developer tool: import Screen Time into a history store and print the stats the app would show.
// Usage: orbit-cli [--store <path>] [--year 2026] [--month 11]

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let calendar = Calendar.current
let now = Date()
let year = option("--year").flatMap(Int.init) ?? calendar.component(.year, from: now)
let month = option("--month").flatMap(Int.init) ?? calendar.component(.month, from: now)
let storeURL = option("--store").map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("orbit-cli/history.sqlite")

func hours(_ s: TimeInterval) -> String { String(format: "%.1f h", s / 3600) }

do {
    let reader = ScreenTimeReader()
    print("Screen Time 访问：\(reader.checkAccess())")
    let store = try HistoryStore(url: storeURL)
    let result = try Importer(reader: reader, store: store).importScreenTime()
    print("读取 \(result.read) 条，新增 \(result.inserted) 条 → \(storeURL.path)")

    let engine = StatsEngine(calendar: calendar, hidden: try store.hiddenBundleIDs())
    for period in [StatsPeriod.year(year), .month(year: year, month: month)] {
        let interval = period.interval(in: calendar)
        let summary = engine.summary(of: try store.sessions(overlapping: interval), period: period, now: now)
        print("\n== \(period) ==")
        if let covered = summary.coveredInterval {
            print("记录自 \(covered.start.formatted(date: .abbreviated, time: .omitted))，有使用的天数 \(summary.activeDays)")
        }
        print("总计 \(hours(summary.totalSeconds))，日均 \(hours(summary.averagePerActiveDay))，应用 \(summary.appCount) 个")
        if let longest = summary.longestDay {
            print("最长的一天 \(longest.day.formatted(date: .abbreviated, time: .omitted))：\(hours(longest.seconds))")
        }
        for (i, app) in summary.topApps.enumerated() {
            print(String(format: "%2d. %-34@ %8@  %5d 次", i + 1, app.bundleID as NSString, hours(app.seconds) as NSString, app.sessions))
        }
    }
} catch {
    FileHandle.standardError.write("错误：\(error)\n".data(using: .utf8)!)
    exit(1)
}
