import OrbitCore
import SwiftUI

/// "我的 Mac": the home page. One card per kind of content that can be shared.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)

    var body: some View {
        OScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("我的 Mac").font(.system(size: 38, weight: .bold))
                Text("选一种内容，做成可以分享的图。所有内容都只在这台 Mac 上处理，不会上传。")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(ShareSource.allCases) { card($0) }
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, 56).padding(.top, 22).padding(.bottom, 24)
        }
        .task { await model.loadMacFacts() }
    }

    private func card(_ source: ShareSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GlassIcon(index: source.icon, size: 30)
                Text(source.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(source.permission ?? "无需权限").font(.system(size: 11)).foregroundStyle(Theme.text2)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Theme.control, in: Capsule())
            }
            preview(source).frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading).padding(.top, 16)
            Spacer(minLength: 12)
            HStack {
                if source == .usage {
                    Button("查看详情") { model.section = .overview }.buttonStyle(.plain).focusable(false)
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
                Spacer()
                if source.isAvailable {
                    Button("做成分享图") { model.start(source) }.glassButton(primary: true)
                } else {
                    Text(source == .screenshot ? "阶段 2" : "即将推出").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
        }
        .padding(18).frame(height: 216)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(source.isAvailable ? 1 : 0.55)
    }

    @ViewBuilder
    private func preview(_ source: ShareSource) -> some View {
        switch source {
        case .usage:
            if let s = model.summary, s.totalSeconds > 0 {
                let total = Fmt.duration(s.totalSeconds)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(total.value).font(.system(size: 28, weight: .bold)).monospacedDigit()
                        Text("\(total.unit) · \(model.periodTitle)").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    icons(s.topApps.prefix(7).map(\.bundleID))
                }
            } else {
                note("还没有使用记录")
            }
        case .stack:
            if model.dockApps.isEmpty { note(source.blurb) } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dock 里有 \(model.dockApps.count) 个软件").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    icons(model.dockApps.prefix(8).compactMap(\.bundleID))
                }
            }
        case .gear:
            if let g = model.macProfile {
                VStack(alignment: .leading, spacing: 5) {
                    Text(g.modelName).font(.system(size: 20, weight: .bold))
                    Text([g.chip, g.memoryLabel, g.storageLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    Text(g.system).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            } else { note("正在读取…") }
        default:
            note(source.blurb)
        }
    }

    private func icons(_ bundleIDs: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(bundleIDs, id: \.self) { SharpIcon(model.catalog.info(for: $0).icon, 30) }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2).lineSpacing(3)
    }
}
