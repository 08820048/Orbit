import OrbitCore
import SwiftUI

/// Overview: one flat page, no cards. Figures, Top 10, then the daily trend (Doop frame C1).
struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let summary = model.summary, summary.totalSeconds > 0 {
                OScroll { content(summary).padding(.horizontal, 56).padding(.top, 22).padding(.bottom, 20) }
            } else {
                EmptyStateView()
            }
        }
        .topBarActions {
            GlassSegmented(options: AppModel.Period.allCases, label: \.rawValue, selection: $model.period)
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text2).frame(width: 30, height: 30)
                    .opacity(model.isRefreshing ? 0.4 : 1)
            }
            .buttonStyle(.plain).focusable(false).disabled(model.isRefreshing).help("刷新数据")
            Button("生成分享图") { model.section = .share }.glassButton(primary: true)
        }
    }

    private func content(_ s: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.periodTitle) · 我的 Mac 时间").font(.system(size: 38, weight: .bold))
            Text(headline(s)).font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.top, 8)

            HStack(alignment: .top, spacing: 72) {
                let total = Fmt.duration(s.totalSeconds), avg = Fmt.duration(s.averagePerActiveDay)
                Figure(label: "总使用时长", value: total.value, unit: total.unit, foot: "\(s.activeDays) 天有记录")
                Figure(label: "日均", value: avg.value, unit: avg.unit, foot: "打开过 \(s.appCount) 个应用")
                if let longest = s.longestDay {
                    let d = Fmt.duration(longest.seconds)
                    Figure(label: "最长的一天", value: d.value, unit: d.unit,
                           foot: longest.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                }
                if let top = s.topApps.first {
                    Figure(label: "\(model.catalog.info(for: top.bundleID).name) 占比",
                           value: String(Int((top.seconds / s.totalSeconds * 100).rounded())), unit: "%",
                           foot: s.topApps.count > 1 ? "第二名 \(model.catalog.info(for: s.topApps[1].bundleID).name) 占 \(Int((s.topApps[1].seconds / s.totalSeconds * 100).rounded()))%" : " ")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 30)

            sectionHeader("最常用应用 Top 10", "按使用时长 · 点击查看单个应用").padding(.top, 38)
            topApps(s).padding(.top, 18)

            sectionHeader("每日时长", dailyRange(s)).padding(.top, 34)
            DailyBars(daily: s.daily, height: 66).padding(.top, 14)

            Text("数据来自屏幕使用时间 · \(model.coverageText) · 仅存于本机，不上传")
                .font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.top, 22)
        }
    }

    private func sectionHeader(_ title: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }

    private func topApps(_ s: PeriodSummary) -> some View {
        let apps = Array(s.topApps.prefix(10))
        let maxSeconds = apps.first?.seconds ?? 1
        return HStack(alignment: .top, spacing: 64) {
            column(Array(apps.enumerated()).filter { $0.offset < 5 }, maxSeconds)
            column(Array(apps.enumerated()).filter { $0.offset >= 5 }, maxSeconds)
        }
    }

    private func column(_ items: [(offset: Int, element: AppUsage)], _ maxSeconds: TimeInterval) -> some View {
        VStack(spacing: 20) {
            ForEach(items, id: \.element.bundleID) { item in
                let info = model.catalog.info(for: item.element.bundleID)
                HStack(spacing: 14) {
                    Text(String(format: "%02d", item.offset + 1)).font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Theme.text2).frame(width: 20, alignment: .trailing)
                    SharpIcon(info.icon, 34)
                    VStack(spacing: 7) {
                        HStack {
                            Text(info.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(Fmt.long(item.element.seconds)).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Theme.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.accent)
                                        .frame(width: max(4, geo.size.width * item.element.seconds / maxSeconds))
                                }
                        }
                        .frame(height: 4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectedApp = item.element.bundleID; model.section = .app }
                .help("查看 \(info.name)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dailyRange(_ s: PeriodSummary) -> String {
        guard let first = s.daily.first?.day, let last = s.daily.last?.day else { return "" }
        var text = "\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))"
        if let l = s.longestDay { text += " · 最长 \(Fmt.long(l.seconds))" }
        return text
    }

    private func headline(_ s: PeriodSummary) -> String {
        var text = "已记录 \(s.daily.count) 天，打开过 \(s.appCount) 个应用"
        if let top = s.topApps.first { text += "；时间最多的是 \(model.catalog.info(for: top.bundleID).name)。" }
        return text
    }
}

/// A figure on the overview: label, big number with unit, footnote. No card around it.
struct Figure: View {
    let label: String, value: String, unit: String, foot: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold)).monospacedDigit()
                Text(unit).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .padding(.top, 6)
            Text(foot).font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.top, 4).lineLimit(1)
        }
    }
}

struct DailyBars: View {
    let daily: [DailyTotal]
    var height: CGFloat = 150

    var body: some View {
        let maxV = max(daily.map(\.seconds).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: daily.count > 60 ? 1 : 4) {
            ForEach(daily) { d in
                let hot = d.seconds == maxV
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(hot ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.control))
                    .frame(height: max(3, height * d.seconds / maxV))
                    .help("\(d.day.formatted(.dateTime.month().day())) · \(Fmt.long(d.seconds))")
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            GlassIcon(index: GI.timer, size: 84)
            Text("这段时间还没有记录").font(.system(size: 18, weight: .bold))
            Text(model.access == .granted
                 ? "换一个时间范围，或者点「刷新」重新读取。"
                 : "没有读取屏幕使用时间的权限。Orbit 正在从现在开始记录，用一会儿再来看。")
                .font(.system(size: 13)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            if model.access != .granted {
                Button("打开系统设置授权") { model.openFullDiskAccessSettings() }.glassButton(primary: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
