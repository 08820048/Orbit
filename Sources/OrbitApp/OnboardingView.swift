import OrbitCore
import SwiftUI

/// First-launch flow: get Full Disk Access, or fall back to recording from today.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: 470)
            right.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 580)
        .task {
            // Poll while this screen is showing; cancelled automatically when onboarding ends.
            while !Task.isCancelled {
                model.checkAccess()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkAccess()
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GlassIcon(index: GI.shield, size: 56)
                Text("第 2 步，共 3 步").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            .padding(.top, 44)
            Text("让 Orbit 读取\n你的屏幕使用时间")
                .font(.system(size: 30, weight: .bold)).lineSpacing(4).padding(.top, 16)
            Text("macOS 把应用使用记录保存在系统目录里，Orbit 需要「完全磁盘访问权限」才能读取。数据只在这台 Mac 上处理，Orbit 不联网。")
                .font(.system(size: 13)).foregroundStyle(Theme.text2).lineSpacing(5).padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                step(1, "点下面的按钮，打开「系统设置 › 隐私与安全性」", done: true)
                step(2, "在「完全磁盘访问权限」列表里打开 Orbit", done: false)
                step(3, "回到这里，Orbit 会自动检测并开始读取（系统可能会要求重新打开 Orbit）", done: false)
            }
            .padding(.top, 22)

            Spacer()
            HStack(spacing: 12) {
                Button("打开系统设置") { model.openFullDiskAccessSettings() }
                    .glassButton(primary: true)
                HStack(spacing: 7) {
                    Circle().fill(Theme.accentHi).frame(width: 7, height: 7).shadow(color: Theme.accent, radius: 4)
                    Text(model.access == .unavailable ? "没有找到屏幕使用时间数据" : "正在等待授权…")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            HStack(spacing: 0) {
                Text("暂不授权？").foregroundStyle(Theme.text2)
                Button("先从今天开始记录") { model.finishOnboarding() }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Theme.accentHi)
                Text("：只能统计之后的使用。").foregroundStyle(Theme.text2)
            }
            .font(.system(size: 12)).padding(.top, 14).padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
    }

    private func step(_ n: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(done ? Color.white : Theme.text2)
                .frame(width: 20, height: 20)
                .background(Circle().fill(done ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.control)))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A mock of the System Settings list the user is about to see.
    private var right: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0F2C66), Color(hex: 0x060E20)], startPoint: .topTrailing, endPoint: .bottomLeading)
            RadialGradient(colors: [Theme.accent.opacity(0.45), .clear], center: .init(x: 0.6, y: 0.2), startRadius: 0, endRadius: 320)
            GlassIcon(index: GI.shield, size: 110).offset(x: -110, y: -150)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.25)).frame(width: 10, height: 10) }
                    Text("完全磁盘访问权限").font(.system(size: 12, weight: .semibold)).padding(.leading, 10)
                    Spacer()
                }
                .padding(.horizontal, 12).frame(height: 38)
                mockRow(icon: AnyView(Image(systemName: "chevron.left.forwardslash.chevron.right").frame(width: 22, height: 22)), name: "Zed", on: false)
                mockRow(icon: AnyView(GlassIcon(index: GI.orbit, size: 26)), name: "Orbit", on: true, highlight: true)
                mockRow(icon: AnyView(Image(systemName: "hammer.fill").frame(width: 22, height: 22)), name: "Xcode", on: false)
            }
            .foregroundStyle(Color(hex: 0xEAF1FF))
            .frame(width: 330)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
            .offset(y: 50)
        }
    }

    private func mockRow(icon: AnyView, name: String, on: Bool, highlight: Bool = false) -> some View {
        HStack(spacing: 10) {
            icon
            Text(name).font(.system(size: 13, weight: highlight ? .semibold : .regular))
            Spacer()
            GlassToggle(isOn: .constant(on)).allowsHitTesting(false)
        }
        .padding(.horizontal, 12).frame(height: 46)
        .background {
            if highlight {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accentHi.opacity(0.6), lineWidth: 1))
                    .padding(.horizontal, 4)
            }
        }
    }
}
