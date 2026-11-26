import OrbitCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmErase = false

    var body: some View {
        OScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置").font(.system(size: 38, weight: .bold))

                CaptureSettingsSections(settings: model.captureSettings, capture: model.capture)
                    .padding(.top, 30)

                group("数据与隐私") {
                    VStack(alignment: .leading, spacing: 12) {
                        line("数据来源", "屏幕使用时间（本机），加上 Orbit 自己的前台应用记录")
                        line("读取权限", accessText)
                        line("本地记录", "\(model.sessionCount) 条，最早 \(model.earliest?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                        line("上次导入", model.lastImport?.formatted(date: .abbreviated, time: .shortened) ?? "还没有")
                    }
                    Text("除检查更新外，Orbit 不联网。所有数据只存在这台 Mac 的 ~/Library/Application Support/Orbit。")
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
                .padding(.top, 38)

                group("更新") { UpdateSection(updater: model.updater) }
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

/// "更新" group of the settings page.
private struct UpdateSection: View {
    @ObservedObject var updater: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("当前版本") { Text(UpdateModel.versionText).font(.system(size: 13)) }
            if updater.isAvailable {
                row("自动检查") { GlassToggle(isOn: $updater.automatic) }
                Text("每天检查一次。只请求版本信息，不发送任何使用数据，也不发送你的系统信息。")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                HStack(spacing: 14) {
                    Button("检查更新…") { updater.checkForUpdates() }.glassButton().disabled(!updater.canCheck)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            } else {
                Text("这是开发版本，不会自动更新。").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
        }
    }

    private var statusText: String {
        guard let last = updater.lastCheck else { return "还没有检查过" }
        let when = last.formatted(date: .abbreviated, time: .shortened)
        return updater.lastResult.map { "上次检查：\(when)，\($0)" } ?? "上次检查：\(when)"
    }

    private func row<C: View>(_ k: String, @ViewBuilder _ v: () -> C) -> some View {
        HStack(alignment: .center) {
            Text(k).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 80, alignment: .leading)
            v()
        }
    }
}
