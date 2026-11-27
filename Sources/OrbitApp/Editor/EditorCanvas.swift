import AppKit
import Combine
import OrbitCore
import SwiftUI

/// SwiftUI wrapper around the interactive canvas.
struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel
    func makeNSView(context: Context) -> EditorCanvasView { EditorCanvasView(model: model) }
    func updateNSView(_ view: EditorCanvasView, context: Context) { view.needsDisplay = true }
}

/// Draws the picture with its annotations and turns mouse and keyboard input into edits.
@MainActor
final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var cancellables = Set<AnyCancellable>()

    private enum Drag {
        case creating(start: CGPoint)
        case moving(id: UUID, start: CGPoint, original: Annotation)
        case resizing(id: UUID, handle: Handle, original: Annotation)
        case cropMoving(start: CGPoint, original: CGRect)
        case cropResizing(handle: Handle)
    }
    private var drag: Drag?
    private var draft: Annotation?
    private var blurCache: [BlurKey: CGImage] = [:]
    private var textField: NSTextField?
    private var editingIsNew = false

    private struct BlurKey: Hashable {
        var rect: [Double]; var mode: BlurMode; var strength: Int
    }

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.needsDisplay = true } }.store(in: &cancellables)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func layout() { super.layout(); needsDisplay = true }

    // MARK: Geometry (image space <-> view space)

    private let margin: CGFloat = 40

    /// Pixels shown per view point's inverse: view points per image pixel.
    private var scale: CGFloat {
        let vis = model.visibleRect
        guard vis.width > 0, vis.height > 0 else { return 1 }
        let fit = min((bounds.width - 2 * margin) / vis.width, (bounds.height - 2 * margin) / vis.height)
        // Never bigger than the screenshot's own size in points.
        let natural = 1 / max(CGFloat(model.record.scale), 1)
        return max(0.01, min(fit, natural))
    }

    private var imageOrigin: CGPoint {
        let vis = model.visibleRect, s = scale
        return CGPoint(x: (bounds.width - vis.width * s) / 2, y: (bounds.height - vis.height * s) / 2)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let vis = model.visibleRect, s = scale, o = imageOrigin
        return CGPoint(x: o.x + (p.x - vis.minX) * s, y: o.y + (p.y - vis.minY) * s)
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let vis = model.visibleRect, s = scale, o = imageOrigin
        return CGPoint(x: (p.x - o.x) / s + vis.minX, y: (p.y - o.y) / s + vis.minY)
    }

    private func viewRect(_ r: CGRect) -> CGRect {
        let a = toView(r.origin), s = scale
        return CGRect(x: a.x, y: a.y, width: r.width * s, height: r.height * s)
    }

    private func eventPoint(_ e: NSEvent) -> CGPoint { toImage(convert(e.locationInWindow, from: nil)) }

    /// A few view points, in image pixels: how close a click has to be.
    private var tolerance: Double { 6 / Double(scale) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let vis = model.visibleRect, s = scale
        let dst = viewRect(vis)

        // Picture with a soft shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: 0.55))
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(dst)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: dst)
        ctx.interpolationQuality = .high
        ctx.translateBy(x: dst.minX - vis.minX * s, y: dst.minY - vis.minY * s)
        ctx.scaleBy(x: s, y: s)
        AnnotationRenderer.drawImage(model.base, in: model.fullRect, ctx)
        for a in model.items { drawAnnotation(a, ctx) }
        if let draft { drawAnnotation(draft, ctx) }
        ctx.restoreGState()

        if model.tool == .crop, let r = model.cropRect { drawCropOverlay(r, ctx) }
        else if let a = model.selected, model.editingTextID == nil { drawHandles(for: a, ctx) }
    }

    private func drawAnnotation(_ a: Annotation, _ ctx: CGContext) {
        if a.id == model.editingTextID, case let .text(origin, _) = a.shape {
            // While typing, only the coloured pill is drawn; the text field shows the text.
            var empty = a
            empty.shape = .text(origin: origin, string: "")
            AnnotationRenderer.draw(empty, in: ctx)
            return
        }
        guard case let .blur(rect) = a.shape else { AnnotationRenderer.draw(a, in: ctx); return }
        let isDraft = a.id == draft?.id
        let key = BlurKey(rect: [rect.minX, rect.minY, rect.width, rect.height], mode: a.blurMode, strength: a.blurStrength)
        if !isDraft {
            if blurCache[key] == nil {
                blurCache[key] = AnnotationRenderer.blurredPatch(of: model.base, rect: rect, annotation: a, imageWidth: model.imageSize.width)
                if blurCache.count > 60 { blurCache = blurCache.filter { $0.key == key } }
            }
            if let patch = blurCache[key] {
                AnnotationRenderer.drawImage(patch, in: rect.integral.intersection(model.fullRect), ctx)
                return
            }
        }
        // Still being dragged: a light placeholder instead of a filter pass on every mouse move.
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.35))
        ctx.fill(rect)
    }

    private func drawHandles(for a: Annotation, _ ctx: CGContext) {
        // Dashed frame for rectangles and text, so selection is visible even on thin shapes.
        switch a.shape {
        case .rectangle, .ellipse, .blur, .text, .highlight, .marker:
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(srgbRed: 0.36, green: 0.62, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(viewRect(a.bounds))
            ctx.restoreGState()
        default: break
        }
        for h in a.handles {
            let p = toView(h.point)
            let r = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.setStrokeColor(CGColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1))
            ctx.setLineWidth(1.5)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.drawPath(using: .fillStroke)
        }
    }

    private func drawCropOverlay(_ cropImageRect: CGRect, _ ctx: CGContext) {
        let r = viewRect(cropImageRect), full = viewRect(model.fullRect)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0.016, green: 0.03, blue: 0.08, alpha: 0.62))
        ctx.addRect(full); ctx.addRect(r)
        ctx.drawPath(using: .eoFill)
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(1); ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY))
            ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.strokePath()
        for h in RectGeometry.handles(of: cropImageRect) {
            let p = toView(h.point)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.fillPath()
        }
        // Size label above the crop.
        let label = "\(Int(cropImageRect.width.rounded())) × \(Int(cropImageRect.height.rounded()))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let pill = CGRect(x: r.minX, y: max(4, r.minY - 34), width: size.width + 22, height: 26)
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.09, blue: 0.16, alpha: 0.92))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
        label.draw(at: CGPoint(x: pill.minX + 11, y: pill.minY + (26 - size.height) / 2), withAttributes: attrs)
    }

    // MARK: Hit testing

    private func handle(of a: Annotation, at viewPoint: CGPoint) -> Handle? {
        a.handles.first { hypot(toView($0.point).x - viewPoint.x, toView($0.point).y - viewPoint.y) <= 9 }?.handle
    }

    private func cropHandle(at viewPoint: CGPoint) -> Handle? {
        guard let r = model.cropRect else { return nil }
        return RectGeometry.handles(of: r).first { hypot(toView($0.point).x - viewPoint.x, toView($0.point).y - viewPoint.y) <= 11 }?.handle
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditing()
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = toImage(viewPoint)

        if model.tool == .crop {
            if let h = cropHandle(at: viewPoint) { drag = .cropResizing(handle: h) }
            else if let r = model.cropRect, r.contains(p) { drag = .cropMoving(start: p, original: r) }
            return
        }

        // A handle of the selected annotation always wins, whatever tool is active.
        if let sel = model.selected, let h = handle(of: sel, at: viewPoint) {
            model.beginLive(model.items)
            drag = .resizing(id: sel.id, handle: h, original: sel)
            return
        }

        switch model.tool {
        case .select:
            if let hit = model.items.last(where: { $0.hit(p, tolerance: tolerance) }) {
                if event.clickCount == 2, case .text = hit.shape { model.select(hit.id); beginEditing(hit.id, isNew: false); return }
                model.select(hit.id)
                model.beginLive(model.items)
                drag = .moving(id: hit.id, start: p, original: hit)
            } else {
                model.select(nil)
            }
        case .text:
            if let hit = model.items.last(where: { if case .text = $0.shape { return $0.hit(p, tolerance: tolerance) }; return false }) {
                model.select(hit.id)
                beginEditing(hit.id, isNew: false)
            } else {
                var a = model.makeAnnotation(.text(origin: p, string: ""))
                a.textSize = AnnotationRenderer.measureText(" ", fontSize: a.fontSize, background: a.textBackground)
                model.beginLive(model.items + [a])
                model.select(a.id)
                beginEditing(a.id, isNew: true)
            }
        case .marker:
            // One click, one numbered circle.
            model.add(model.makeAnnotation(.marker(center: p)))
        case .arrow, .line, .rectangle, .ellipse, .blur, .highlight:
            let shape = Self.initialShape(for: model.tool, at: p)
            draft = model.makeAnnotation(shape)
            drag = .creating(start: p)
        case .crop:
            break
        }
    }

    private static func initialShape(for tool: EditorModel.Tool, at p: CGPoint) -> AnnotationShape {
        switch tool {
        case .arrow: .arrow(from: p, to: p)
        case .line: .line(from: p, to: p)
        case .rectangle: .rectangle(CGRect(origin: p, size: .zero))
        case .ellipse: .ellipse(CGRect(origin: p, size: .zero))
        case .highlight: .highlight(CGRect(origin: p, size: .zero))
        default: .blur(CGRect(origin: p, size: .zero))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = eventPoint(event)
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case let .creating(start):
            guard var d = draft else { return }
            switch d.shape {
            case .arrow: d.shape = .arrow(from: start, to: GeometryTools.endpoint(from: start, to: p, snap: shift))
            case .line: d.shape = .line(from: start, to: GeometryTools.endpoint(from: start, to: p, snap: shift))
            case .rectangle: d.shape = .rectangle(GeometryTools.rect(from: start, to: p, square: shift))
            case .ellipse: d.shape = .ellipse(GeometryTools.rect(from: start, to: p, square: shift))
            case .highlight: d.shape = .highlight(GeometryTools.rect(from: start, to: p, square: false).intersection(model.fullRect))
            case .blur: d.shape = .blur(GeometryTools.rect(from: start, to: p, square: false).intersection(model.fullRect))
            default: break
            }
            draft = d
        case let .moving(_, start, original):
            model.replace(original.moved(by: CGVector(dx: p.x - start.x, dy: p.y - start.y)), live: true)
        case let .resizing(_, handle, original):
            model.replace(original.resized(handle, to: p, constrain: shift), live: true)
        case let .cropMoving(start, original):
            let moved = original.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            model.cropRect = GeometryTools.clamp(moved, in: model.fullRect)
        case let .cropResizing(handle):
            if let r = model.cropRect { model.cropRect = CropMath.resize(r, handle: handle, to: p, bounds: model.fullRect, ratio: model.cropRatio) }
        case nil:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; needsDisplay = true }
        switch drag {
        case .creating:
            guard let d = draft else { return }
            draft = nil
            if Self.isBigEnough(d) { model.add(d) }
        case .moving, .resizing:
            model.commitLive()
        default:
            break
        }
    }

    private static func isBigEnough(_ a: Annotation) -> Bool {
        switch a.shape {
        case let .arrow(p, q), let .line(p, q): return hypot(q.x - p.x, q.y - p.y) >= 8
        case let .rectangle(r), let .ellipse(r), let .blur(r), let .highlight(r): return r.width >= 6 && r.height >= 6
        default: return true
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if textField != nil { super.keyDown(with: event); return }
        let chars = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 51, 117: model.deleteSelected()                                    // delete
        case 53:                                                                // esc
            if model.tool == .crop { model.cancelCrop() } else { model.select(nil) }
        case 36, 76: if model.tool == .crop { model.applyCrop() }               // return
        case 123, 124, 125, 126: nudge(event)
        default:
            if !event.modifierFlags.contains(.command), let tool = EditorModel.Tool.allCases.first(where: { $0.key == chars.lowercased() }) {
                model.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func nudge(_ event: NSEvent) {
        guard let sel = model.selected else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var d = CGVector.zero
        switch event.keyCode {
        case 123: d.dx = -step
        case 124: d.dx = step
        case 125: d.dy = step
        default: d.dy = -step
        }
        model.replace(sel.moved(by: d))
    }

    // MARK: Text editing

    private func beginEditing(_ id: UUID, isNew: Bool) {
        guard let a = model.items.first(where: { $0.id == id }), case let .text(origin, string) = a.shape else { return }
        model.editingTextID = id
        editingIsNew = isNew
        let s = scale
        let pad = a.textBackground ? CGSize(width: a.fontSize * 0.45, height: a.fontSize * 0.28) : .zero
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = AnnotationRenderer.font(size: a.fontSize * s)
        let onColor: NSColor = a.color.luminance > 0.7 ? NSColor(white: 0.08, alpha: 1) : .white
        field.textColor = a.textBackground ? onColor : NSColor(cgColor: AnnotationRenderer.cgColor(a.color))
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        addSubview(field)
        textField = field
        positionTextField(origin: origin, pad: pad, annotation: a)
        window?.makeFirstResponder(field)
    }

    private func positionTextField(origin: CGPoint, pad: CGSize, annotation a: Annotation) {
        guard let field = textField else { return }
        let s = scale
        let o = toView(origin)
        let measured = AnnotationRenderer.measureText(field.stringValue.isEmpty ? " " : field.stringValue, fontSize: a.fontSize, background: false)
        field.frame = CGRect(x: o.x + pad.width * s, y: o.y + pad.height * s,
                             width: max(measured.width * s + 24, 80), height: measured.height * s)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let id = model.editingTextID, var a = model.items.first(where: { $0.id == id }), case let .text(origin, _) = a.shape,
              let field = textField else { return }
        a.shape = .text(origin: origin, string: field.stringValue)
        a.textSize = AnnotationRenderer.measureText(field.stringValue.isEmpty ? " " : field.stringValue, fontSize: a.fontSize, background: a.textBackground)
        model.replace(a, live: true)
        positionTextField(origin: origin, pad: a.textBackground ? CGSize(width: a.fontSize * 0.45, height: a.fontSize * 0.28) : .zero, annotation: a)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { commitTextEditing(); window?.makeFirstResponder(self); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelTextEditing(); window?.makeFirstResponder(self); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitTextEditing() }

    /// Finishes typing: an empty text is dropped, anything else becomes one undo step.
    func commitTextEditing() {
        guard let field = textField, let id = model.editingTextID else { return }
        let text = field.stringValue
        textField = nil
        field.removeFromSuperview()
        model.editingTextID = nil
        guard var a = model.items.first(where: { $0.id == id }), case let .text(origin, _) = a.shape else { model.cancelLive(); return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.commit(items: model.items.filter { $0.id != id })
            model.select(nil)
        } else {
            a.shape = .text(origin: origin, string: text)
            a.textSize = AnnotationRenderer.measureText(text, fontSize: a.fontSize, background: a.textBackground)
            model.replace(a)
        }
        window?.makeFirstResponder(self)
    }

    private func cancelTextEditing() {
        guard let field = textField else { return }
        textField = nil
        field.removeFromSuperview()
        model.editingTextID = nil
        model.cancelLive()
        if editingIsNew { model.select(nil) }
    }
}
