import AppKit
import OrbitCore
import SwiftUI

struct ResolvedApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    /// One-line comment; empty when the user wrote none.
    var note = ""
}

struct ResolvedGroup: Identifiable {
    let id: UUID
    let name: String
    let apps: [ResolvedApp]
}

/// The exported "my apps" card. Laid out in a fixed-size canvas; if the content is too tall it is
/// shrunk uniformly (and re-flowed to use the extra width) rather than clipped.
struct CustomShareCardView: View {
    let doc: CustomShareDoc
    let groups: [ResolvedGroup]
    /// Editor preview only: tapping an app opens its note popover, and empty notes show a hint.
    var editing: NoteEditing? = nil

    private let pad: CGFloat = 40
    private let topPad: CGFloat = 34
    private let footerReserve: CGFloat = 46

    private var size: CGSize { doc.ratio.size }
    private var icon: CGFloat { doc.iconSize.points }
    private var visibleGroups: [ResolvedGroup] { groups.filter { !$0.apps.isEmpty } }

    // MARK: Colors

    private var lightSurface: Bool {
        if doc.background.hasPrefix("solid:") { return Self.isLight(hex: String(doc.background.dropFirst(6))) }
        return doc.template == .paper && doc.background == "default"
    }
    private var ink: Color { lightSurface ? Color(hex: 0x2A2620) : .white }
    private var muted: Color { lightSurface ? Color(hex: 0x6B6254) : Color(hex: 0xC9D5DF) }
    private var hairline: Color { lightSurface ? Color(hex: 0x2A2620, opacity: 0.15) : .white.opacity(0.16) }
    private var accent: Color { lightSurface ? Color(hex: 0x1F6BEA) : Theme.accentHi }

    static func isLight(hex: String) -> Bool {
        guard let v = UInt32(hex, radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 160
    }

    // MARK: Body

    var body: some View {
        let s = fitScale()
        let w = size.width / s, h = size.height / s
        ZStack(alignment: .topLeading) {
            background
            content(width: w, height: h)
                .frame(width: w, height: h, alignment: .topLeading)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: doc.cornerRadius, style: .continuous))
    }

    private func content(width w: CGFloat, height h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if doc.showNotes {
                header(width: w, centered: false); noteLayout(width: w)
            } else {
                switch doc.template {
                case .fjord, .paper: header(width: w, centered: false); labeledRows(width: w)
                case .glass: header(width: w, centered: false); panels(width: w)
                case .minimal: header(width: w, centered: true); iconField(width: w)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, pad).padding(.top, topPad)
        .overlay(alignment: .bottom) { footer.padding(.horizontal, pad).padding(.bottom, 16) }
    }

    // MARK: Pieces

    private var titleSize: CGFloat { doc.ratio == .landscape ? 32 : 28 }

    private func header(width: CGFloat, centered: Bool, title: String? = nil, caption: String? = nil) -> some View {
        let title = title ?? doc.title, caption = caption ?? doc.caption
        return VStack(alignment: centered ? .center : .leading, spacing: 8) {
            if centered {
                Text("MY MAC").font(.system(size: 11)).tracking(4).foregroundStyle(muted)
            }
            Text(title.isEmpty ? " " : title)
                .font(doc.template == .minimal ? doc.titleFont.font(titleSize * 0.7) : doc.titleFont.font(titleSize))
                .foregroundStyle(ink).shadow(color: .black.opacity(lightSurface ? 0 : 0.5), radius: 10, y: 2)
                .multilineTextAlignment(centered ? .center : .leading)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 12.5, weight: .light)).tracking(0.6).lineSpacing(3)
                    .foregroundStyle(muted).multilineTextAlignment(centered ? .center : .leading)
                    .shadow(color: .black.opacity(lightSurface ? 0 : 0.5), radius: 6, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        HStack {
            Text(doc.signature).font(.system(size: 10)).tracking(1.6).foregroundStyle(muted.opacity(0.85))
            Spacer()
            if doc.watermark {
                HStack(spacing: 6) {
                    GlassIcon(index: GI.orbit, size: 14)
                    Text("ORBIT").font(.system(size: 10)).tracking(1.6).foregroundStyle(muted.opacity(0.85))
                }
            }
        }
    }

    private func tile(_ app: ResolvedApp, cellW: CGFloat) -> some View {
        VStack(spacing: 7) {
            SharpIcon(app.icon, icon)
                .shadow(color: .black.opacity(lightSurface ? 0.22 : 0.5), radius: icon * 0.22, y: icon * 0.14)
            if doc.showNames {
                Text(app.name).font(.system(size: 10.5)).tracking(0.2).lineLimit(2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(height: 26, alignment: .top)
                    .foregroundStyle(lightSurface ? ink : Color(hex: 0xE6EEF5))
                    .shadow(color: .black.opacity(lightSurface ? 0 : 0.7), radius: 3, y: 1)
            }
        }
        .frame(width: cellW)
    }

    private static func chunks<T>(_ items: [T], _ n: Int) -> [[T]] {
        guard n > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: n).map { Array(items[$0 ..< min($0 + n, items.count)]) }
    }

    private var cellHeight: CGFloat { icon + (doc.showNames ? 33 : 0) }

    // fjord / paper: group label on the left, icons on the right
    private let labelW: CGFloat = 104
    /// Between groups, and between icon rows inside one group.
    private let rowGap: CGFloat = 8
    private let appRowGap: CGFloat = 6

    /// Icons per row. Starts at 6 (landscape) / 4, but grows to fit the biggest group on one row, as far as the width allows;
    /// only then does a group wrap onto a second row.
    private func columns(forGridWidth gw: CGFloat) -> Int {
        let base = doc.ratio == .landscape ? 6 : 4
        let widest = visibleGroups.map(\.apps.count).max() ?? 0
        let fit = max(1, Int(gw / (icon + 22)))
        return max(1, min(max(base, widest), fit))
    }

    private func labeledRows(width w: CGFloat) -> some View {
        let gw = w - 2 * pad - labelW
        let cols = columns(forGridWidth: gw)
        let cellW = gw / CGFloat(cols)
        return VStack(alignment: .leading, spacing: rowGap) {
            ForEach(visibleGroups) { g in
                HStack(alignment: .top, spacing: 0) {
                    Text(g.name).font(.system(size: 15, weight: .medium)).tracking(1.5).foregroundStyle(ink)
                        .shadow(color: .black.opacity(lightSurface ? 0 : 0.6), radius: 6, y: 1)
                        .frame(width: labelW, alignment: .leading).padding(.top, max(0, icon / 2 - 10))
                    VStack(alignment: .leading, spacing: appRowGap) {
                        ForEach(Array(Self.chunks(g.apps, cols).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 0) { ForEach(row) { tile($0, cellW: cellW) } }
                        }
                    }
                }
            }
        }
    }

    // glass: one frosted panel per group
    private func panelColumns() -> Int { doc.ratio == .landscape ? 3 : 2 }

    private func panels(width w: CGFloat) -> some View {
        let pc = panelColumns(), gap: CGFloat = 12
        let panelW = (w - 2 * pad - CGFloat(pc - 1) * gap) / CGFloat(pc)
        let inner = max(1, Int((panelW - 28) / (icon + 14)))
        let cellW = (panelW - 28) / CGFloat(inner)
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(Self.chunks(visibleGroups, pc).enumerated()), id: \.offset) { _, rowGroups in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(rowGroups) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(g.name).font(.system(size: 12, weight: .medium)).tracking(1).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(Self.chunks(g.apps, inner).enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 0) { ForEach(row) { tile($0, cellW: cellW) } }
                                }
                            }
                        }
                        .padding(14).frame(width: panelW, alignment: .leading)
                        .background(.white.opacity(lightSurface ? 0.5 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hairline, lineWidth: 0.5))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // minimal: every icon in one centered field
    private func fieldColumns() -> Int { doc.ratio == .landscape ? 8 : 6 }

    private func iconField(width w: CGFloat) -> some View {
        let all = visibleGroups.flatMap(\.apps)
        let cols = min(fieldColumns(), max(1, Int((w - 2 * pad) / (icon + 22))))
        let cellW = min((w - 2 * pad) / CGFloat(cols), icon + 40)
        return VStack(spacing: 14) {
            ForEach(Array(Self.chunks(all, cols).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) { ForEach(row) { tile($0, cellW: cellW) } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // notes: one column per group, each app as "icon + name + one-line note"
    private var noteRowHeight: CGFloat { icon + 12 }
    private let noteGap: CGFloat = 20
    private let notePanelPad: CGFloat = 14

    private var noteColumnCount: Int { doc.ratio == .landscape ? 3 : 2 }

    /// Groups as they appear in note mode. The minimal template has no groups, so its apps are split evenly into unnamed columns.
    private var noteSections: [ResolvedGroup] {
        guard doc.template == .minimal else { return visibleGroups }
        let all = visibleGroups.flatMap(\.apps)
        let cols = min(noteColumnCount, max(1, all.count))
        let per = Int(ceil(Double(all.count) / Double(cols)))
        return Self.chunks(all, max(1, per)).map { ResolvedGroup(id: UUID(), name: "", apps: $0) }
    }

    private func noteColumnWidth(width w: CGFloat) -> CGFloat {
        let cols = min(noteColumnCount, max(1, noteSections.count))
        let gap = doc.template == .glass ? 12 : noteGap
        return (w - 2 * pad - CGFloat(cols - 1) * gap) / CGFloat(cols)
    }

    private func noteLayout(width w: CGFloat) -> some View {
        let colW = noteColumnWidth(width: w)
        let gap = doc.template == .glass ? CGFloat(12) : noteGap
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(Self.chunks(noteSections, noteColumnCount).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, g in noteColumn(g, width: colW) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func noteColumn(_ g: ResolvedGroup, width: CGFloat) -> some View {
        let column = VStack(alignment: .leading, spacing: 6) {
            if !g.name.isEmpty {
                Text(g.name).font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.bottom, 4)
            }
            ForEach(g.apps) { noteRow($0) }
        }
        if doc.template == .glass {
            column.padding(notePanelPad).frame(width: width, alignment: .leading)
                .background(.white.opacity(lightSurface ? 0.5 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hairline, lineWidth: 0.5))
        } else {
            column.frame(width: width, alignment: .leading)
        }
    }

    private func noteRow(_ app: ResolvedApp) -> some View {
        let isEditing = editing?.editingKey == app.id
        return HStack(spacing: 10) {
            SharpIcon(app.icon, icon)
                .shadow(color: .black.opacity(lightSurface ? 0.22 : 0.5), radius: icon * 0.18, y: icon * 0.1)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).foregroundStyle(ink)
                if !app.note.isEmpty {
                    Text(app.note).font(.system(size: 11)).lineLimit(1).foregroundStyle(muted)
                } else if editing != nil {
                    Text("加一句短评").font(.system(size: 11)).italic().foregroundStyle(muted.opacity(0.45))
                }
            }
            .shadow(color: .black.opacity(lightSurface ? 0 : 0.6), radius: 3, y: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: noteRowHeight)
        .background(isEditing ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isEditing ? accent : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { editing?.select(app.id) }
        .popover(isPresented: Binding(
            get: { editing?.editingKey == app.id },
            set: { if !$0 { editing?.select(nil) } }
        ), arrowEdge: .bottom) {
            if let editing {
                NoteEditorView(name: app.name, text: editing.text(app.id)) { editing.select(nil) }
            }
        }
    }

    // MARK: Fit

    /// Height the content needs at a given logical width (mirrors the layout above).
    private func estimatedHeight(width w: CGFloat) -> CGFloat {
        let titleH = titleSize * 1.3 * (doc.template == .minimal ? 0.7 : 1)
        let captionLines = doc.caption.isEmpty ? 0 : doc.caption.split(separator: "\n", omittingEmptySubsequences: false).count
        var h = titleH + 8 + (captionLines > 0 ? CGFloat(captionLines) * 19 + 8 : 0) + 20
        if doc.template == .minimal { h += 22 }
        let cellH = cellHeight
        if doc.showNotes {
            let glass = doc.template == .glass
            let sectionH: (ResolvedGroup) -> CGFloat = { g in
                let n = CGFloat(max(1, g.apps.count))
                return (g.name.isEmpty ? 0 : 22) + n * self.noteRowHeight + (n - 1) * 6 + (glass ? 2 * self.notePanelPad : 0)
            }
            let rows = Self.chunks(noteSections, noteColumnCount).map { $0.map(sectionH).max() ?? 0 }
            return h + rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * 16
        }
        switch doc.template {
        case .fjord, .paper:
            let cols = columns(forGridWidth: w - 2 * pad - labelW)
            let rows = visibleGroups.map { max(1, Int(ceil(Double($0.apps.count) / Double(cols)))) }
            h += rows.reduce(0) { $0 + CGFloat($1) * cellH + CGFloat($1 - 1) * appRowGap } + CGFloat(max(0, rows.count - 1)) * rowGap
        case .glass:
            let pc = panelColumns(), gap: CGFloat = 12
            let panelW = (w - 2 * pad - CGFloat(pc - 1) * gap) / CGFloat(pc)
            let inner = max(1, Int((panelW - 28) / (icon + 14)))
            let panelRows = Self.chunks(visibleGroups, pc).map { rowGroups in
                rowGroups.map { g -> CGFloat in
                    let r = max(1, Int(ceil(Double(g.apps.count) / Double(inner))))
                    return 28 + 16 + CGFloat(r) * cellH + CGFloat(r - 1) * 8 + 10
                }.max() ?? 0
            }
            h += panelRows.reduce(0, +) + CGFloat(max(0, panelRows.count - 1)) * gap
        case .minimal:
            let count = visibleGroups.reduce(0) { $0 + $1.apps.count }
            let cols = min(fieldColumns(), max(1, Int((w - 2 * pad) / (icon + 22))))
            let rows = max(1, Int(ceil(Double(count) / Double(cols))))
            h += CGFloat(rows) * cellH + CGFloat(rows - 1) * 14 + 6
        }
        return h
    }

    private func fitScale() -> CGFloat {
        var s: CGFloat = 1
        while s > 0.45 {
            let w = size.width / s
            if estimatedHeight(width: w) <= (size.height - topPad - footerReserve) / s { return s }
            s -= 0.05
        }
        return 0.45
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        let kind = doc.background
        if kind.hasPrefix("solid:") {
            Color(hexString: String(kind.dropFirst(6)))
        } else if let image = photo {
            ZStack {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .scaleEffect(1 + doc.blur / 160).blur(radius: doc.blur)
                    .frame(width: size.width, height: size.height).clipped()
                Color.black.opacity(doc.overlay * 0.45)
                LinearGradient(colors: [Color(hex: 0x08141E, opacity: doc.overlay * 0.9), .clear, Color(hex: 0x061018, opacity: doc.overlay * 0.7)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color(hex: 0x061018, opacity: doc.overlay * 0.7), .clear], startPoint: .leading, endPoint: .trailing)
            }
        } else {
            templateBackground
        }
    }

    private var photo: NSImage? {
        let kind = doc.background
        if kind.hasPrefix("builtin:") { return BackgroundStore.builtin(String(kind.dropFirst(8))) }
        if kind.hasPrefix("custom:") { return BackgroundStore.custom(String(kind.dropFirst(7))) }
        if kind == "default", doc.template == .fjord { return BackgroundStore.builtin("fjord") }
        return nil
    }

    @ViewBuilder
    private var templateBackground: some View {
        switch doc.template {
        case .glass:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0F2C66), Color(hex: 0x060E20)], startPoint: .topTrailing, endPoint: .bottomLeading)
                RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .init(x: 0.9, y: 0), startRadius: 0, endRadius: size.width * 0.7)
            }
        case .paper:
            LinearGradient(colors: [Color(hex: 0xF5F0E6), Color(hex: 0xE2D9C8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .minimal:
            Color(hex: 0x0B0D12)
        case .fjord:
            LinearGradient(colors: [Color(hex: 0x17293A), Color(hex: 0x0A121A)], startPoint: .top, endPoint: .bottom)
        }
    }
}

extension Color {
    init(hexString: String) { self.init(hex: UInt32(hexString, radix: 16) ?? 0x0B0D12) }
}
