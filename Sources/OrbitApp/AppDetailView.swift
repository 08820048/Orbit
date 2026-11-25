import OrbitCore
import SwiftUI

/// One app's total time and daily trend (PRD 5.2 "单应用使用时长").
struct AppDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "单个应用") {
                GlassSegmented(options: AppModel.Period.allCases, label: \.rawValue, selection: $model.period)
            }
            if let summary = model.summary, !summary.topApps.isEmpty {
                HStack(spacing: 0) {
                    list(summary).frame(width: 280).background(Theme.sidebar)
                    detail(summary)
                }
            } else {
                EmptyStateView()
            }
        }
    }

    private func list(_ s: PeriodSummary) -> some View {
        OScroll {
            VStack(spacing: 2) {
                ForEach(s.topApps) { app in
                    let info = model.catalog.info(for: app.bundleID)
                    HStack(spacing: 10) {
                        SharpIcon(info.icon, 26)
                        Text(info.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text(Fmt.short(app.seconds)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 10).frame(height: 40)
                    .background {
                        if model.selectedApp == app.bundleID {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedApp = app.bundleID }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func detail(_ s: PeriodSummary) -> some View {
        if let id = model.selectedApp, let usage = s.topApps.first(where: { $0.bundleID == id }) {
            let info = model.catalog.info(for: id)
            let d = model.detail(for: id)
            let total = Fmt.duration(d.total)
            OScroll {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        SharpIcon(info.icon, 64)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.name).font(.system(size: 26, weight: .bold))
                            Text(id).font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                    }
                    HStack(spacing: 14) {
                        StatTile(icon: GI.timer, label: "总时长", value: total.value, unit: total.unit, foot: model.periodTitle)
                        StatTile(icon: GI.swap, label: "打开次数", value: "\(usage.sessions)", unit: "次", foot: "前台切换")
                        let active = d.daily.filter { $0.seconds > 0 }.count
                        let avg = Fmt.duration(active == 0 ? 0 : d.total / Double(active))
                        StatTile(icon: GI.calendar, label: "使用日均", value: avg.value, unit: avg.unit, foot: "\(active) 天用过")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            GlassIcon(index: GI.trend, size: 24)
                            Text("每日时长").font(.system(size: 13, weight: .semibold))
                        }
                        DailyBars(daily: d.daily, height: 180)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16).glassPanel()
                }
                .padding(28)
            }
        } else {
            Text("选择左侧的应用").foregroundStyle(Theme.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmErase = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "设置") { EmptyView() }
            OScroll {
                VStack(alignment: .leading, spacing: 16) {
                    group(GI.shield, "数据与隐私") {
                        line("数据来源", "屏幕使用时间（本机），加上 Orbit 自己的前台应用记录")
                        line("读取权限", accessText)
                        line("本地记录", "\(model.sessionCount) 条，最早 \(model.earliest?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                        line("上次导入", model.lastImport?.formatted(date: .abbreviated, time: .shortened) ?? "还没有")
                        Text("Orbit 不联网，所有数据只存在这台 Mac 的 ~/Library/Application Support/Orbit。")
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        if let err = model.lastError {
                            Text(err).font(.system(size: 12)).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("刷新数据") { Task { await model.refresh() } }.glassButton()
                            if model.access != .granted {
                                Button("打开系统设置授权") { model.openFullDiskAccessSettings() }.glassButton(primary: true)
                            }
                            Button("清除所有记录…") { confirmErase = true }.glassButton()
                        }
                    }
                    group(GI.sliders, "关于数据准确性") {
                        Text("屏幕使用时间的统计规则由 macOS 决定，可能与你的直觉有出入（例如后台播放、全屏睡眠）。系统只保留约 3 周的数据，Orbit 会把读到的记录存下来，之后才能做年度统计。")
                            .font(.system(size: 12)).foregroundStyle(Theme.text2).lineSpacing(4)
                    }
                }
                .padding(28).frame(maxWidth: 640, alignment: .leading)
            }
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

    private func group<C: View>(_ icon: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { GlassIcon(index: icon, size: 24); Text(title).font(.system(size: 13, weight: .semibold)) }
            content()
        }
        .padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).glassPanel()
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 80, alignment: .leading)
            Text(v).font(.system(size: 13))
        }
    }
}
