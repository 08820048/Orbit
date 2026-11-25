import AppKit
import OrbitCore
import SwiftUI

enum ShareTemplate: String, CaseIterable, Identifiable {
    case ranking = "排行榜", card = "卡片式", report = "年度报告"
    var id: String { rawValue }
    /// Card size in points; exported at 2x (1080 px wide).
    var size: CGSize { self == .report ? CGSize(width: 540, height: 960) : CGSize(width: 540, height: 675) }
    var ratio: String { self == .report ? "9:16 · 1080×1920" : "4:5 · 1080×1350" }
}

enum BackgroundKind: String, CaseIterable { case solid = "纯色", gradient = "渐变", glass = "毛玻璃" }

struct CardPalette: Identifiable {
    let id: Int
    let top: Color, bottom: Color
    /// Light grounds need dark text.
    let isLight: Bool

    static let all: [CardPalette] = [
        .init(id: 0, top: Color(hex: 0x0F2C66), bottom: Color(hex: 0x060E20), isLight: false),
        .init(id: 1, top: Color(hex: 0x4B2E83), bottom: Color(hex: 0x140C2A), isLight: false),
        .init(id: 2, top: Color(hex: 0x0E5F6B), bottom: Color(hex: 0x06181C), isLight: false),
        .init(id: 3, top: Color(hex: 0xEAF2FF), bottom: Color(hex: 0xB9CFF2), isLight: true),
        .init(id: 4, top: Color(hex: 0x14161C), bottom: Color(hex: 0x0B0D12), isLight: false),
        .init(id: 5, top: Color(hex: 0xF8F9FC), bottom: Color(hex: 0xF1F3F8), isLight: true),
    ]
}

struct AccentChoice: Identifiable {
    let id: Int
    let hi: Color, lo: Color
    static let all: [AccentChoice] = [
        .init(id: 0, hi: Color(hex: 0x7FB0FF), lo: Color(hex: 0x1F6BEA)),
        .init(id: 1, hi: Color(hex: 0x8DE3F0), lo: Color(hex: 0x1AA7C9)),
        .init(id: 2, hi: Color(hex: 0xC3A3FF), lo: Color(hex: 0x6A3FE0)),
        .init(id: 3, hi: Color(hex: 0xFFA9C0), lo: Color(hex: 0xE0457A)),
        .init(id: 4, hi: .white, lo: Color(hex: 0xC9D3E6)),
    ]
}

struct ShareStyle {
    var template: ShareTemplate = .ranking
    var background: BackgroundKind = .gradient
    var palette = 0
    var accent = 0
    var cornerRadius: Double = 28
    var showIcons = true
    var showRank = true
    var showHours = true
    var topN = 10
    var signature = NSFullUserName()
    var watermark = true

    var paletteValue: CardPalette { CardPalette.all[palette] }
    var accentValue: AccentChoice { AccentChoice.all[accent] }
}

struct ShareEntry: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let seconds: TimeInterval
}

struct ShareData {
    var periodTitle: String       // "2026" / "11 月" / "最近 7 天"
    var coverage: String          // "记录 20 天"
    var totalSeconds: TimeInterval
    var averageSeconds: TimeInterval
    var longestDay: DailyTotal?
    var appCount: Int
    var share: Double             // top app's share of total, 0...1
    var entries: [ShareEntry]

    var isEmpty: Bool { entries.isEmpty }

    static let placeholder = ShareData(periodTitle: "2026", coverage: "记录 0 天", totalSeconds: 0, averageSeconds: 0,
                                       longestDay: nil, appCount: 0, share: 0, entries: [])
}

/// The image that gets exported. Everything is laid out in a fixed 540-pt-wide canvas.
struct ShareCardView: View {
    let style: ShareStyle
    let data: ShareData

    private var palette: CardPalette { style.paletteValue }
    private var ink: Color { palette.isLight ? Color(hex: 0x0F1A33) : Color(hex: 0xF2F6FF) }
    private var muted: Color { palette.isLight ? Color(hex: 0x4A5C80) : Color(hex: 0x9FB4DA) }
    private var hairline: Color { palette.isLight ? Color(hex: 0x0F1A33, opacity: 0.14) : .white.opacity(0.14) }
    private var hi: Color { palette.isLight ? style.accentValue.lo : style.accentValue.hi }

    var body: some View {
        let size = style.template.size
        ZStack {
            background(size)
            Group {
                switch style.template {
                case .ranking: ranking
                case .card: card
                case .report: report
                }
            }
            .padding(.horizontal, 44)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    // MARK: Background

    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        switch style.background {
        case .solid:
            palette.top
        case .gradient:
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [style.accentValue.lo.opacity(palette.isLight ? 0.25 : 0.5), .clear],
                               center: .init(x: 0.85, y: 0), startRadius: 0, endRadius: size.width * 0.9)
                RadialGradient(colors: [style.accentValue.lo.opacity(palette.isLight ? 0.18 : 0.35), .clear],
                               center: .init(x: 0.05, y: 1), startRadius: 0, endRadius: size.width * 0.8)
            }
        case .glass:
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(style.accentValue.lo).frame(width: 320).blur(radius: 70).offset(x: 140, y: -size.height * 0.3)
                Circle().fill(style.accentValue.hi.opacity(0.7)).frame(width: 220).blur(radius: 70).offset(x: -150, y: size.height * 0.32)
                Rectangle().fill(.white.opacity(palette.isLight ? 0.35 : 0.06))
            }
        }
    }

    // MARK: Shared bits

    private func kicker(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).tracking(3.3).foregroundStyle(hi)
    }

    private var footer: some View {
        HStack {
            Text(style.signature.isEmpty ? " " : "\(style.signature) · \(Date().formatted(.dateTime.year().month(.twoDigits)))")
                .font(.system(size: 10)).tracking(1.6).foregroundStyle(muted)
            Spacer()
            if style.watermark {
                HStack(spacing: 6) {
                    GlassIcon(index: GI.orbit, size: 16)
                    Text("ORBIT").font(.system(size: 10)).tracking(1.6).foregroundStyle(muted)
                }
            }
        }
    }

    private var rankedTitle: String {
        switch data.periodTitle {
        case let t where t.hasPrefix("最近"): return "\(t)\n我最常用的 Mac 应用"
        case let t where t.hasSuffix("月"): return "\(t)我最常用的\nMac 应用"
        default: return "\(data.periodTitle) 我最常用的\nMac 应用"
        }
    }

    private func entryIcon(_ e: ShareEntry, _ size: CGFloat) -> some View {
        Image(nsImage: e.icon).resizable().frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: size * 0.2, y: size * 0.1)
    }

    // MARK: Template 1: ranking

    private var ranking: some View {
        let rows = Array(data.entries.prefix(style.topN).enumerated())
        let rowHeight: CGFloat = style.topN <= 5 ? 66 : 42
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    kicker("ORBIT / \(data.periodTitle.uppercased())")
                    Text(rankedTitle).font(.system(size: 34, weight: .bold)).lineSpacing(3).foregroundStyle(ink)
                    Text("\(data.coverage) · 共 \(Fmt.long(data.totalSeconds)) · 日均 \(Fmt.long(data.averageSeconds))")
                        .font(.system(size: 12, weight: .light)).foregroundStyle(muted)
                }
                Spacer()
                GlassIcon(index: GI.trend, size: 92).offset(x: 6, y: -4)
            }
            .padding(.top, 40)
            Rectangle().fill(hairline).frame(height: 1).padding(.top, 20)
            ForEach(rows, id: \.element.id) { i, e in
                HStack(spacing: 14) {
                    if style.showRank {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(hi).frame(width: 26, alignment: .leading)
                    }
                    if style.showIcons { entryIcon(e, style.topN <= 5 ? 38 : 28) }
                    Text(e.name).font(.system(size: style.topN <= 5 ? 17 : 14)).foregroundStyle(ink).lineLimit(1)
                    Spacer()
                    if style.showHours {
                        Text(Fmt.short(e.seconds)).font(.system(size: 13)).monospacedDigit().foregroundStyle(muted)
                    }
                }
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
            }
            Spacer(minLength: 8)
            footer.padding(.bottom, 30)
        }
    }

    // MARK: Template 2: card

    private var card: some View {
        let top = data.entries.first
        let others = Array(data.entries.dropFirst().prefix(3).enumerated())
        return VStack(spacing: 0) {
            kicker("ORBIT / \(data.periodTitle.uppercased()) · 陪伴").padding(.top, 44)
            if let top {
                Image(nsImage: top.icon).resizable().frame(width: 132, height: 132)
                    .shadow(color: style.accentValue.lo.opacity(0.7), radius: 36)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 18)
                    .padding(.top, 40)
                Text("这段时间陪我最久的是").font(.system(size: 13, weight: .light)).tracking(1).foregroundStyle(muted).padding(.top, 30)
                Text(top.name).font(.system(size: 46, weight: .bold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 6)
                if style.showHours {
                    let d = Fmt.duration(top.seconds)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(d.value).font(.system(size: 68, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient(colors: [ink, hi], startPoint: .top, endPoint: .bottom))
                        Text("\(d.unit) · 占 \(Int((data.share * 100).rounded()))%").font(.system(size: 14)).foregroundStyle(muted)
                    }
                    .padding(.top, 10)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                ForEach(others, id: \.element.id) { i, e in
                    HStack(spacing: 10) {
                        if style.showIcons { entryIcon(e, 32) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.system(size: 13, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                            Text("No.\(i + 2)" + (style.showHours ? " · \(Fmt.short(e.seconds))" : ""))
                                .font(.system(size: 11)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(.white.opacity(palette.isLight ? 0.55 : 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hairline, lineWidth: 0.5))
                }
            }
            footer.padding(.top, 24).padding(.bottom, 30)
        }
    }

    // MARK: Template 3: report

    private var report: some View {
        let icons = Array(data.entries.prefix(style.topN))
        let longest = data.longestDay
        return VStack(alignment: .leading, spacing: 0) {
            kicker("ORBIT · REPORT").padding(.top, 52)
            Text(data.periodTitle).font(.system(size: data.periodTitle.count > 4 ? 64 : 100, weight: .bold)).tracking(-2)
                .foregroundStyle(LinearGradient(colors: [ink, hi], startPoint: .top, endPoint: .bottom))
                .lineLimit(1).minimumScaleFactor(0.5).padding(.top, 14)
            Text("我在 Mac 上的这段时光").font(.system(size: 26, weight: .bold)).foregroundStyle(ink).padding(.top, 6)
            Text("\(data.coverage)，我把 \(Fmt.long(data.totalSeconds)) 交给了屏幕。")
                .font(.system(size: 13, weight: .light)).foregroundStyle(muted).lineSpacing(5).padding(.top, 12)

            Rectangle().fill(hairline).frame(height: 1).padding(.top, 30)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                stat(GI.timer, "总使用时长", Fmt.duration(data.totalSeconds))
                stat(GI.swap, "日均", Fmt.duration(data.averageSeconds))
                if let longest {
                    stat(GI.calendar, "最长的一天 · \(longest.day.formatted(.dateTime.month().day()))", Fmt.duration(longest.seconds))
                }
                stat(GI.layout, "常用应用", (String(data.appCount), "个"))
            }
            .padding(.vertical, 24)
            Rectangle().fill(hairline).frame(height: 1)

            Text("Top \(icons.count)").font(.system(size: 11)).tracking(0.9).foregroundStyle(muted).padding(.top, 28)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 22) {
                ForEach(icons) { e in
                    VStack(spacing: 8) {
                        if style.showIcons { entryIcon(e, 52) }
                        Text(e.name).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1)
                    }
                }
            }
            .padding(.top, 18)
            Spacer()
            Rectangle().fill(hairline).frame(height: 1)
            footer.padding(.top, 14).padding(.bottom, 36)
        }
    }

    private func stat(_ icon: Int, _ label: String, _ v: (value: String, unit: String)) -> some View {
        HStack(spacing: 12) {
            GlassIcon(index: icon, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 11)).tracking(0.9).foregroundStyle(muted).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.value).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(ink)
                    Text(v.unit).font(.system(size: 12)).foregroundStyle(muted)
                }
            }
        }
    }
}

enum ShareRenderer {
    /// Renders the card to PNG at 2x. Returns nil if rendering fails.
    @MainActor
    static func png(style: ShareStyle, data: ShareData, scale: CGFloat = 2) -> Data? {
        png(ShareCardView(style: style, data: data), scale: scale)
    }

    @MainActor
    static func png<V: View>(_ view: V, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        guard let cg = renderer.cgImage else { return nil }
        // SwiftUI may render into an HDR (PQ) space; exports must be plain 8-bit sRGB or colors look washed out.
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let converted = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: converted).representation(using: .png, properties: [:])
    }
}
