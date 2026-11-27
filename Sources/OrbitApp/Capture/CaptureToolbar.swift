import AppKit
import SwiftUI

/// The floating menu shown while a screenshot is started from the window's capture button:
/// the four capture modes plus a close button. It sits above the selection overlay without taking focus from it.
@MainActor
final class CaptureToolbarModel: ObservableObject {
    @Published var current: CaptureAction = .region
}

@MainActor
final class CaptureToolbarController {
    private var panel: NSPanel?
    let model = CaptureToolbarModel()
    /// Called when a mode is picked; `nil` means the close button.
    var onPick: ((CaptureAction?) -> Void)?

    var isVisible: Bool { panel != nil }

    func show(current: CaptureAction) {
        model.current = current
        guard panel == nil else { return }
        let host = NSHostingView(rootView: CaptureToolbarView(model: model) { [weak self] in self?.onPick?($0) })
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let p = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        p.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 64))
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CaptureToolbarView: View {
    @ObservedObject var model: CaptureToolbarModel
    let pick: (CaptureAction?) -> Void

    private let items: [(CaptureAction, String, LocalizedStringKey)] = [
        (.region, "viewfinder", "区域"), (.window, "macwindow", "窗口"), (.fullscreen, "display", "全屏"), (.delayed, "timer", "延时"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            Button { pick(nil) } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(Text("取消截图"))
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 22).padding(.horizontal, 4)
            ForEach(items, id: \.0) { action, symbol, title in
                let on = model.current == action
                Button { pick(action) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                        Text(title).font(.system(size: 11))
                    }
                    .frame(width: 56, height: 44)
                    .background(on ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .background(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .padding(10)
    }
}
