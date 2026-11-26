import OrbitCore
import SwiftUI

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
