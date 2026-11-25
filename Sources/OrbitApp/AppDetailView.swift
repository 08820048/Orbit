import OrbitCore
import SwiftUI

/// One app's total time and daily trend (PRD 5.2 "单应用使用时长").
/// The app is chosen from the name at the top (searchable list) or stepped through by rank with the arrows.
struct AppDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var showPicker = false
    @State private var query = ""

    var body: some View {
        Group {
            if let summary = model.summary, !summary.topApps.isEmpty {
                page(summary)
            } else {
                EmptyStateView()
            }
        }
        .topBarActions {
            GlassSegmented(options: AppModel.Period.allCases, label: \.rawValue, selection: $model.period)
        }
    }

    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private func page(_ s: PeriodSummary) -> some View {
        // Falls back to the top app when the selection is not in this period's ranking.
        let index = s.topApps.firstIndex { $0.bundleID == model.selectedApp } ?? 0
        let usage = s.topApps[index]
        let info = model.catalog.info(for: usage.bundleID)
        let d = model.detail(for: usage.bundleID)
        let insights = model.insights(for: usage.bundleID)
        let total = Fmt.duration(d.total)
        let active = d.daily.filter { $0.seconds > 0 }.count
        let avg = Fmt.duration(active == 0 ? 0 : d.total / Double(active))
        let share = s.totalSeconds > 0 ? Int((usage.seconds / s.totalSeconds * 100).rounded()) : 0
        let avgSession = Fmt.duration(insights.averageSession), longestSession = Fmt.duration(insights.longestSession)
        return OScroll {
            VStack(alignment: .leading, spacing: 0) {
                UsageNav()
                header(s, index: index, info: info, id: usage.bundleID)

                HStack(alignment: .top, spacing: 48) {
                    Figure(label: "总时长", value: total.value, unit: total.unit, foot: model.periodTitle)
                    Figure(label: "占总时长", value: "\(share)", unit: "%", foot: "第 \(index + 1) 名")
                    Figure(label: "打开次数", value: "\(usage.sessions)", unit: "次", foot: "前台切换")
                    Figure(label: "平均每次", value: avgSession.value, unit: avgSession.unit, foot: "共 \(insights.sessionCount) 段使用")
                    Figure(label: "最长一次", value: longestSession.value, unit: longestSession.unit, foot: "连续在前台")
                    Figure(label: "使用日均", value: avg.value, unit: avg.unit, foot: "\(active) 天用过")
                    Spacer(minLength: 0)
                }
                .padding(.top, 32)

                HStack(alignment: .top, spacing: 64) {
                    chart("一天中的时段", note: hourNote(insights)) {
                        MiniBars(values: insights.hourly, height: 132, spacing: 3,
                                 labels: [0: "0", 6: "6", 12: "12", 18: "18"],
                                 tip: { "\(Self.hourRange($0)) · \(Fmt.long(insights.hourly[$0]))" })
                    }
                    chart("每周分布", note: weekNote(insights)) {
                        MiniBars(values: insights.weekdayAverage, height: 132, spacing: 10,
                                 labels: Dictionary(uniqueKeysWithValues: Self.weekdayNames.enumerated().map { ($0.offset, String($0.element.dropFirst())) }),
                                 tip: { "\(Self.weekdayNames[$0]) · 日均 \(Fmt.long(insights.weekdayAverage[$0]))" })
                    }
                }
                .padding(.top, 38)

                chart("每日时长", note: dailyNote(d.daily)) {
                    DailyBars(daily: d.daily, height: 170)
                }
                .padding(.top, 38)
            }
            .padding(.horizontal, 56).padding(.top, 22).padding(.bottom, 24)
        }
    }

    private func chart<C: View>(_ title: String, note: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func hourRange(_ h: Int) -> String { String(format: "%02d:00–%02d:00", h, (h + 1) % 24) }

    private func hourNote(_ i: AppInsights) -> String {
        i.peakHour.map { "最常在 \(Self.hourRange($0))" } ?? "还没有足够的记录"
    }

    private func weekNote(_ i: AppInsights) -> String {
        guard let day = i.peakWeekday else { return "还没有足够的记录" }
        return "\(Self.weekdayNames[day])最多 · 日均 \(Fmt.long(i.weekdayAverage[day]))"
    }

    private func dailyNote(_ daily: [DailyTotal]) -> String {
        guard let first = daily.first?.day, let last = daily.last?.day else { return "" }
        var text = "\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))"
        if let top = daily.max(by: { $0.seconds < $1.seconds }), top.seconds > 0 {
            text += " · 最长 \(top.day.formatted(.dateTime.month().day())) · \(Fmt.long(top.seconds))"
        }
        return text
    }

    // MARK: Header and app switcher

    private func header(_ s: PeriodSummary, index: Int, info: AppCatalog.Info, id: String) -> some View {
        HStack(spacing: 10) {
            Button { showPicker = true } label: {
                HStack(spacing: 16) {
                    SharpIcon(info.icon, 64).shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(info.name).font(.system(size: 26, weight: .bold))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.text2)
                        }
                        Text("第 \(index + 1) 名 · \(id)").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false).help("切换应用")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) { picker(s) }
            HStack(spacing: 0) {
                step("chevron.left", enabled: index > 0, help: "上一名") { model.selectedApp = s.topApps[index - 1].bundleID }
                step("chevron.right", enabled: index < s.topApps.count - 1, help: "下一名") { model.selectedApp = s.topApps[index + 1].bundleID }
            }
            .padding(.leading, 6)
            Spacer()
        }
    }

    private func step(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false).disabled(!enabled).opacity(enabled ? 1 : 0.3).help(help)
    }

    private func picker(_ s: PeriodSummary) -> some View {
        let apps = query.isEmpty ? s.topApps : s.topApps.filter {
            model.catalog.info(for: $0.bundleID).name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        return VStack(spacing: 8) {
            TextField("搜索应用", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(apps) { app in
                        let info = model.catalog.info(for: app.bundleID)
                        HStack(spacing: 10) {
                            SharpIcon(info.icon, 26)
                            Text(info.name).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            Text(Fmt.short(app.seconds)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                        .padding(.horizontal, 10).frame(height: 38)
                        .background {
                            if model.selectedApp == app.bundleID {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedApp = app.bundleID; showPicker = false; query = "" }
                    }
                    if apps.isEmpty {
                        Text("没有匹配的应用").font(.system(size: 12)).foregroundStyle(Theme.text2).padding(.top, 20)
                    }
                }
            }
        }
        .padding(12).frame(width: 300, height: 400)
    }
}

/// Flat bar chart with sparse axis labels; the tallest bar is highlighted.
struct MiniBars: View {
    let values: [Double]
    var height: CGFloat = 104
    var spacing: CGFloat = 4
    /// Axis labels by bar index.
    var labels: [Int: String] = [:]
    var tip: (Int) -> String = { _ in "" }

    var body: some View {
        let maxV = max(values.max() ?? 0, 1)
        let peak = values.max().flatMap { $0 > 0 ? values.firstIndex(of: $0) : nil }
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(i == peak ? Theme.accent : Theme.control)
                        .frame(height: max(3, height * values[i] / maxV))
                        .help(tip(i))
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: spacing) {
                ForEach(values.indices, id: \.self) { i in
                    Text(labels[i] ?? "").font(.system(size: 10)).foregroundStyle(Theme.text2)
                        .fixedSize().frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmErase = false

    var body: some View {
        OScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置").font(.system(size: 38, weight: .bold))

                group("数据与隐私") {
                    VStack(alignment: .leading, spacing: 12) {
                        line("数据来源", "屏幕使用时间（本机），加上 Orbit 自己的前台应用记录")
                        line("读取权限", accessText)
                        line("本地记录", "\(model.sessionCount) 条，最早 \(model.earliest?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                        line("上次导入", model.lastImport?.formatted(date: .abbreviated, time: .shortened) ?? "还没有")
                    }
                    Text("Orbit 不联网，所有数据只存在这台 Mac 的 ~/Library/Application Support/Orbit。")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    if let err = model.lastError {
                        Text(err).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    HStack(spacing: 10) {
                        Button("刷新数据") { Task { await model.refresh() } }.glassButton()
                        if model.access != .granted {
                            Button("打开系统设置授权") { model.openFullDiskAccessSettings() }.glassButton(primary: true)
                        }
                        Button("清除所有记录…") { confirmErase = true }.glassButton()
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 30)

                group("关于数据准确性") {
                    Text("屏幕使用时间的统计规则由 macOS 决定，可能与你的直觉有出入（例如后台播放、全屏睡眠）。系统只保留约 3 周的数据，Orbit 会把读到的记录存下来，之后才能做年度统计。")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).lineSpacing(4)
                }
                .padding(.top, 38)
            }
            .padding(.horizontal, 56).padding(.top, 22).padding(.bottom, 24)
            .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("清除 Orbit 里的所有使用记录？", isPresented: $confirmErase) {
            Button("清除", role: .destructive) { model.eraseAllData() }
        } message: { Text("不会影响系统的屏幕使用时间。此操作无法撤销。") }
    }

    private var accessText: String {
        switch model.access {
        case .granted: "已授权"
        case .denied: "未授权（完全磁盘访问权限）"
        case .unavailable: "没有找到屏幕使用时间数据库"
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 80, alignment: .leading)
            Text(v).font(.system(size: 13))
        }
    }
}
