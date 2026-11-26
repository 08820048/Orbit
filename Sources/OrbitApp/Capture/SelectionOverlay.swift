import AppKit
import OrbitCore

enum SelectionMode { case region, window }

enum SelectionResult {
    /// The cropped pixels, ready to save.
    case region(CGImage, scale: Double)
    case window(CapturableWindow)
    case cancelled
}

/// Full-screen overlays (one per display) showing the frozen screen, dimmed, where the user drags out a region or
/// points at a window. Space switches between the two, Esc cancels.
@MainActor
final class SelectionOverlay {
    private let frozen: [FrozenScreen]
    let windows: [CapturableWindow]
    private(set) var mode: SelectionMode
    private var panels: [OverlayWindow] = []
    private var completion: ((SelectionResult) -> Void)?

    /// Selection in the coordinates of one overlay view (points, origin bottom-left).
    private(set) var drag: (screen: Int, start: CGPoint, current: CGPoint, square: Bool)?
    private(set) var hovered: CapturableWindow?
    private(set) var mouse: NSPoint = NSEvent.mouseLocation

    init(frozen: [FrozenScreen], windows: [CapturableWindow], mode: SelectionMode, completion: @escaping (SelectionResult) -> Void) {
        self.frozen = frozen; self.windows = windows; self.mode = mode; self.completion = completion
    }

    func show() {
        for (i, f) in frozen.enumerated() {
            let panel = OverlayWindow(screen: f.screen)
            let view = OverlayView(frame: NSRect(origin: .zero, size: f.screen.frame.size), index: i, frozen: f, overlay: self)
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        updateHover()
        refresh()
    }

    // MARK: State changes (called by the views)

    func toggleMode() {
        mode = mode == .region ? .window : .region
        drag = nil
        updateHover()
        refresh()
    }

    func mouseMoved() {
        mouse = NSEvent.mouseLocation
        updateHover()
        refresh()
    }

    func mouseDown(screen: Int, at p: CGPoint) {
        mouse = NSEvent.mouseLocation
        switch mode {
        case .region: drag = (screen, p, p, false)
        case .window:
            updateHover()
            if let w = hovered { finish(.window(w)) }
        }
        refresh()
    }

    func mouseDragged(screen: Int, to p: CGPoint, square: Bool) {
        mouse = NSEvent.mouseLocation
        guard mode == .region, let d = drag, d.screen == screen else { return }
        drag = (d.screen, d.start, p, square)
        refresh()
    }

    func mouseUp(screen: Int) {
        guard mode == .region, let d = drag, d.screen == screen else { return }
        guard let rect = selection(), rect.width >= 4, rect.height >= 4 else { drag = nil; refresh(); return }
        let f = frozen[d.screen]
        let s = f.scale
        let pixels = CGRect(x: rect.minX * s, y: (f.screen.frame.height - rect.maxY) * s, width: rect.width * s, height: rect.height * s).integral
        if let cropped = f.image.cropping(to: pixels) { finish(.region(cropped, scale: Double(s))) } else { finish(.cancelled) }
    }

    func cancel() { finish(.cancelled) }

    private func finish(_ result: SelectionResult) {
        guard let done = completion else { return }
        completion = nil
        for p in panels { p.orderOut(nil) }
        panels.removeAll()
        done(result)
    }

    // MARK: Queries (used for drawing)

    /// The dragged rectangle on the screen being dragged on.
    func selection() -> CGRect? {
        guard let d = drag else { return nil }
        var dx = d.current.x - d.start.x, dy = d.current.y - d.start.y
        if d.square { let side = max(abs(dx), abs(dy)); dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side }
        return CGRect(x: min(d.start.x, d.start.x + dx), y: min(d.start.y, d.start.y + dy), width: abs(dx), height: abs(dy))
    }

    func windowFrame(onScreen index: Int) -> CGRect? {
        guard let h = hovered else { return nil }
        let screen = frozen[index].screen.frame
        let local = h.frame.offsetBy(dx: -screen.minX, dy: -screen.minY).intersection(CGRect(origin: .zero, size: screen.size))
        return local.isNull || local.isEmpty ? nil : local
    }

    private func updateHover() {
        guard mode == .window else { hovered = nil; return }
        hovered = windows.first { $0.frame.contains(mouse) }
    }

    private func refresh() { for p in panels { p.contentView?.needsDisplay = true } }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    private let index: Int
    private let frozen: FrozenScreen
    private unowned let overlay: SelectionOverlay

    init(frame: NSRect, index: Int, frozen: FrozenScreen, overlay: SelectionOverlay) {
        self.index = index; self.frozen = frozen; self.overlay = overlay
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { overlay.mouseMoved() } }
    override func mouseDown(with event: NSEvent) { let p = convert(event.locationInWindow, from: nil); MainActor.assumeIsolated { overlay.mouseDown(screen: index, at: p) } }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), square = event.modifierFlags.contains(.shift)
        MainActor.assumeIsolated { overlay.mouseDragged(screen: index, to: p, square: square) }
    }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { overlay.mouseUp(screen: index) } }
    override func rightMouseDown(with event: NSEvent) { MainActor.assumeIsolated { overlay.cancel() } }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: MainActor.assumeIsolated { overlay.cancel() }          // Esc
        case 49: MainActor.assumeIsolated { overlay.toggleMode() }      // Space
        default: break
        }
    }

    // MARK: Drawing

    private static let ink = NSColor(srgbRed: 0.016, green: 0.03, blue: 0.08, alpha: 0.52)
    private static let blue = NSColor(srgbRed: 0.36, green: 0.62, blue: 1, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        MainActor.assumeIsolated {
            ctx.draw(frozen.image, in: bounds)

            let selection = overlay.selection().flatMap { overlay.drag?.screen == index ? $0 : nil }
            let windowRect = overlay.mode == .window ? overlay.windowFrame(onScreen: index) : nil
            let hole = selection ?? windowRect

            // Dim everything except the selected area.
            let dim = NSBezierPath(rect: bounds)
            if let hole { dim.appendRect(hole) }
            dim.windingRule = .evenOdd
            Self.ink.setFill()
            dim.fill()

            if let r = selection { drawSelection(r) }
            else if let r = windowRect { drawWindowHighlight(r) }
            else if overlay.mode == .region { drawCrosshair() }
            drawHint()
        }
    }

    private func drawCrosshair() {
        let p = window?.convertPoint(fromScreen: overlay.mouse) ?? .zero
        let local = convert(p, from: nil)
        guard bounds.contains(local) else { return }
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSRect(x: bounds.minX, y: local.y, width: bounds.width, height: 1).fill()
        NSRect(x: local.x, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    private func drawSelection(_ r: CGRect) {
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
                   CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        for p in pts {
            let h = NSBezierPath(roundedRect: NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9), xRadius: 2, yRadius: 2)
            NSColor.white.setFill(); h.fill()
            NSColor.black.withAlphaComponent(0.4).setStroke(); h.lineWidth = 0.5; h.stroke()
        }
        let label = "\(Int(r.width.rounded())) × \(Int(r.height.rounded()))"
        let y = r.maxY + 8 + 26 > bounds.height ? r.minY - 8 - 26 : r.maxY + 8
        drawPill([(label, false)], at: CGPoint(x: max(8, r.minX), y: y), height: 26)
    }

    private func drawWindowHighlight(_ r: CGRect) {
        Self.blue.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        Self.blue.setStroke()
        let border = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        border.lineWidth = 2
        border.stroke()
        if let w = MainActor.assumeIsolated({ overlay.hovered }) {
            let size = "\(Int(w.frame.width.rounded())) × \(Int(w.frame.height.rounded()))"
            let y = r.maxY + 8 + 28 > bounds.height ? r.minY + 8 : r.maxY + 8
            drawPill([(w.title.isEmpty ? "窗口" : w.title, true), (size, false)], at: CGPoint(x: max(8, r.minX), y: y), height: 28)
        }
    }

    private func drawHint() {
        let parts: [(String, Bool)] = MainActor.assumeIsolated { overlay.mode } == .region
            ? [("拖动选择区域", false), ("空格", true), ("切换为窗口", false), ("⇧", true), ("锁定比例", false), ("Esc", true), ("取消", false)]
            : [("点击截取此窗口", false), ("空格", true), ("切换为区域", false), ("Esc", true), ("取消", false)]
        drawPill(parts, at: nil, height: 34)
    }

    /// A dark rounded label. Segments flagged `true` are emphasised (keys, titles). `at == nil` centres it near the bottom.
    private func drawPill(_ parts: [(String, Bool)], at origin: CGPoint?, height: CGFloat) {
        let text = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            let key = part.1
            text.append(NSAttributedString(string: (i == 0 ? "" : "  ") + part.0, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: key ? .semibold : .regular),
                .foregroundColor: key ? NSColor.white : NSColor.white.withAlphaComponent(0.78),
            ]))
        }
        let size = text.size()
        let w = size.width + 26
        let o = origin ?? CGPoint(x: (bounds.width - w) / 2, y: 46)
        let rect = NSRect(x: min(max(8, o.x), max(8, bounds.width - w - 8)), y: o.y, width: w, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 0.92).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        text.draw(at: NSPoint(x: rect.minX + 13, y: rect.minY + (height - size.height) / 2))
    }
}
