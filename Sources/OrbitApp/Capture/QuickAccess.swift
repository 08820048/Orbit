import AppKit
import OrbitCore
import SwiftUI

/// The small thumbnail that appears in the corner after a screenshot: copy, reveal, share, delete; drag it into any app.
@MainActor
final class QuickAccessController {
    private var panel: NSPanel?
    private var token = UUID()

    struct Actions {
        var copy: () -> Void
        var edit: () -> Void
        var reveal: () -> Void
        var delete: () -> Void
        var open: () -> Void
    }

    func show(record: ScreenshotRecord, image: NSImage, seconds: Double, actions: Actions) {
        close()
        let id = UUID()
        token = id
        let view = QuickAccessView(record: record, image: image, seconds: max(1, seconds), actions: actions) { [weak self] in
            if self?.token == id { self?.close() }
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)

        let p = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.maxX - host.frame.width - 20, y: vf.minY + 20))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        panel = p
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; p.animator().alphaValue = 0 }, completionHandler: { p.orderOut(nil) })
    }
}

private struct QuickAccessView: View {
    let record: ScreenshotRecord
    let image: NSImage
    let seconds: Double
    let actions: QuickAccessController.Actions
    let dismiss: () -> Void

    @State private var hovering = false
    @State private var remaining: Double

    init(record: ScreenshotRecord, image: NSImage, seconds: Double, actions: QuickAccessController.Actions, dismiss: @escaping () -> Void) {
        self.record = record; self.image = image; self.seconds = seconds; self.actions = actions; self.dismiss = dismiss
        _remaining = State(initialValue: seconds)
    }

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.12)
                Image(nsImage: image).resizable().scaledToFit()
                if hovering {
                    Color.black.opacity(0.5)
                    HStack(spacing: 10) {
                        roundButton("doc.on.doc", primary: true) { actions.copy(); dismiss() }.help("复制")
                        roundButton("pencil.tip.crop.circle") { actions.edit(); dismiss() }.help("编辑")
                        roundButton("folder") { actions.reveal() }.help("在 Finder 中显示")
                        ShareLink(item: record.url) { icon("square.and.arrow.up", primary: false) }.buttonStyle(.plain).help("分享")
                        roundButton("trash") { actions.delete(); dismiss() }.help("删除")
                    }
                }
                VStack { HStack { Spacer(); closeButton }; Spacer() }.padding(6)
            }
            .frame(width: 252, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .onTapGesture { actions.open(); dismiss() }
            .onDrag { NSItemProvider(contentsOf: record.url) ?? NSItemProvider() }

            HStack {
                Text(kindTitle).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(record.pointSize.width) × \(record.pointSize.height) · 刚刚").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 4).padding(.top, 10)

            Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(hovering ? .white.opacity(0.25) : Color(red: 0.36, green: 0.62, blue: 1))
                            .frame(width: g.size.width * (hovering ? 1 : max(0, remaining / seconds)))
                    }
                }
                .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 2)
        }
        .padding(8)
        .frame(width: 268)
        .background(Color(red: 0.12, green: 0.13, blue: 0.2).opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .padding(20)   // room for the shadow inside the panel
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
        .onReceive(tick) { _ in
            guard !hovering else { return }
            remaining -= 0.05
            if remaining <= 0 { dismiss() }
        }
    }

    private var kindTitle: String { record.kind == .window ? String(localized: "窗口截图") : record.kind == .fullscreen ? String(localized: "全屏截图") : String(localized: "区域截图") }

    private var closeButton: some View {
        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 20, height: 20)
            .background(.black.opacity(0.55), in: Circle()).contentShape(Circle())
            .onTapGesture { dismiss() }
    }

    private func icon(_ name: String, primary: Bool) -> some View {
        Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 38, height: 38)
            .background(primary ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1), Color(red: 0.18, green: 0.42, blue: 0.89)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(.white.opacity(0.16)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func roundButton(_ name: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(name, primary: primary) }.buttonStyle(.plain)
    }
}

/// "3 2 1" countdown for delayed screenshots. Click it to cancel.
@MainActor
enum CountdownHUD {
    static func run(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        let model = CountdownModel(remaining: seconds)
        let host = NSHostingView(rootView: CountdownView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 150, height: 150)
        let p = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - 75, y: screen.frame.maxY - 220))
        p.orderFrontRegardless()
        defer { p.orderOut(nil) }
        while model.remaining > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if model.cancelled { return false }
            model.remaining -= 1
        }
        // Let the HUD disappear before the screen is frozen.
        p.orderOut(nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        return !model.cancelled
    }
}

@MainActor
private final class CountdownModel: ObservableObject {
    @Published var remaining: Int
    var cancelled = false
    init(remaining: Int) { self.remaining = remaining }
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel
    var body: some View {
        VStack(spacing: 4) {
            Text("\(max(model.remaining, 0))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
            Text("点击取消").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 130, height: 130)
        .foregroundStyle(.white)
        .background(Color(red: 0.07, green: 0.09, blue: 0.16).opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { model.cancelled = true; model.remaining = 0 }
    }
}
