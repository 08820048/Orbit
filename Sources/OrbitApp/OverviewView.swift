import OrbitCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: model.period == .year ? "年度总览" : model.period == .month ? "本月总览" : "近 7 天") {
                GlassSegmented(options: AppModel.Period.allCases, label: \.rawValue, selection: $model.period)
                Button(model.isRefreshing ? "刷新中…" : "刷新") { Task { await model.refresh() } }
                    .glassButton().disabled(model.isRefreshing)
                Button("生成分享图") { model.section = .share }.glassButton(primary: true)
            }
            if let summary = model.summary, summary.totalSeconds > 0 {
                OScroll { content(summary).padding(.horizontal, 32).padding(.vertical, 24) }
            } else {
                EmptyStateView()
            }
        }
    }

    private func content(_ s: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.periodTitle) · 我的 Mac 时间").font(.system(size: 38, weight: .bold))
                Text(headline(s)).font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            .padding(.bottom, 6)

            HStack(spacing: 14) {
                let total = Fmt.duration(s.totalSeconds), avg = Fmt.duration(s.averagePerActiveDay)
                StatTile(icon: GI.timer, label: "总使用时长", value: total.value, unit: total.unit,
                         foot: "\(s.activeDays) 天有记录")
                StatTile(icon: GI.stats, label: "日均", value: avg.value, unit: avg.unit,
                         foot: "打开过 \(s.appCount) 个应用")
                if let longest = s.longestDay {
                    let d = Fmt.duration(longest.seconds)
                    StatTile(icon: GI.calendar, label: "最长的一天", value: d.value, unit: d.unit,
                             foot: longest.day.formatted(.dateTime.month().day().weekday(.abbreviated)))
                }
                if let top = s.topApps.first {
                    StatTile(icon: GI.pie, label: "\(model.catalog.info(for: top.bundleID).name) 占比",
                             value: String(Int((top.seconds / s.totalSeconds * 100).rounded())), unit: "%",
                             foot: s.topApps.count > 1 ? "第二名 \(model.catalog.info(for: s.topApps[1].bundleID).name) 占 \(Int((s.topApps[1].seconds / s.totalSeconds * 100).rounded()))%" : " ")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                TopAppsPanel(summary: s).frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    DailyPanel(summary: s)
                    ShareCTA()
                }
                .frame(width: 400)
            }
        }
    }

    private func headline(_ s: PeriodSummary) -> String {
        var text = "\(model.coverageText)，打开过 \(s.appCount) 个应用"
        if let top = s.topApps.first { text += "；时间最多的是 \(model.catalog.info(for: top.bundleID).name)。" }
        return text
    }
}

struct StatTile: View {
    let icon: Int, label: String, value: String, unit: String, foot: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold)).monospacedDigit()
                Text(unit).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            .padding(.top, 8)
            Text(foot).font(.system(size: 11)).foregroundStyle(Theme.text2).padding(.top, 4).lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { GlassIcon(index: icon, size: 40).padding(.top, 12).padding(.trailing, 14) }
        .glassPanel()
    }
}

struct TopAppsPanel: View {
    @EnvironmentObject var model: AppModel
    let summary: PeriodSummary

    var body: some View {
        let apps = Array(summary.topApps.prefix(10))
        let maxSeconds = apps.first?.seconds ?? 1
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GlassIcon(index: GI.stats, size: 24)
                Text("最常用应用 Top 10").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("按使用时长").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .top, spacing: 28) {
                column(Array(apps.enumerated()).filter { $0.offset < 5 }, maxSeconds)
                column(Array(apps.enumerated()).filter { $0.offset >= 5 }, maxSeconds)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .glassPanel()
    }

    private func column(_ items: [(offset: Int, element: AppUsage)], _ maxSeconds: TimeInterval) -> some View {
        VStack(spacing: 18) {
            ForEach(items, id: \.element.bundleID) { item in
                let info = model.catalog.info(for: item.element.bundleID)
                HStack(spacing: 14) {
                    Text(String(format: "%02d", item.offset + 1)).font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Theme.text2).frame(width: 22, alignment: .trailing)
                    SharpIcon(info.icon, 34)
                    VStack(spacing: 7) {
                        HStack {
                            Text(info.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(Fmt.long(item.element.seconds)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Theme.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(LinearGradient(colors: [Theme.accentLo, Theme.accent, Theme.accentHi], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(4, geo.size.width * item.element.seconds / maxSeconds))
                                        .shadow(color: Theme.accent.opacity(0.45), radius: 5)
                                }
                        }
                        .frame(height: 6)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectedApp = item.element.bundleID; model.section = .app }
            }
        }
        .frame(maxWidth: .infinity)
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
                    .fill(hot ? AnyShapeStyle(LinearGradient(colors: [Theme.accentHi, Theme.accentLo], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.control))
                    .frame(height: max(3, height * d.seconds / maxV))
                    .shadow(color: hot ? Theme.accent.opacity(0.6) : .clear, radius: 6)
                    .help("\(d.day.formatted(.dateTime.month().day())) · \(Fmt.long(d.seconds))")
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

struct DailyPanel: View {
    let summary: PeriodSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                GlassIcon(index: GI.trend, size: 24)
                Text("每日时长").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let first = summary.daily.first?.day, let last = summary.daily.last?.day {
                    Text("\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            DailyBars(daily: summary.daily)
            HStack {
                if let l = summary.longestDay {
                    Text("最长 · \(l.day.formatted(.dateTime.month().day())) · \(Fmt.long(l.seconds))")
                }
                Spacer()
                Text("日均 \(Fmt.long(summary.averagePerActiveDay))")
            }
            .font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .glassPanel()
    }
}

struct ShareCTA: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("把这段时间做成一张图").font(.system(size: 20, weight: .bold))
                Text("3 个模板，背景、圆角、主题色都能调，拷贝后直接发朋友圈。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineSpacing(3).padding(.trailing, 80)
                Button("开始制作") { model.section = .share }
                    .buttonStyle(.plain).focusable(false).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x0B3AA0))
                    .padding(.horizontal, 16).frame(height: 30)
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GlassIcon(index: GI.megaphone, size: 84).offset(x: 8, y: -6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(LinearGradient(colors: [Color(hex: 0x1D5FE0), Color(hex: 0x0B2C7A)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
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
