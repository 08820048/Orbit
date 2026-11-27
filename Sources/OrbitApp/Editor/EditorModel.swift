import AppKit
import OrbitCore
import SwiftUI

/// Everything the annotation editor knows: the picture, the annotations, the current tool and its style, undo history.
@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case select, arrow, rectangle, ellipse, line, text, marker, highlight, blur, crop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .select: String(localized: "选择")
            case .arrow: String(localized: "箭头")
            case .rectangle: String(localized: "矩形")
            case .ellipse: String(localized: "椭圆")
            case .line: String(localized: "直线")
            case .text: String(localized: "文字")
            case .marker: String(localized: "序号")
            case .highlight: String(localized: "荧光笔")
            case .blur: String(localized: "模糊 / 马赛克")
            case .crop: String(localized: "裁剪")
            }
        }
        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .line: "line.diagonal"
            case .text: "textformat"
            case .marker: "1.circle"
            case .highlight: "highlighter"
            case .blur: "squareshape.split.2x2"
            case .crop: "crop"
            }
        }
        var key: String {
            switch self {
            case .select: "v"
            case .arrow: "a"
            case .rectangle: "r"
            case .ellipse: "o"
            case .line: "l"
            case .text: "t"
            case .marker: "n"
            case .highlight: "h"
            case .blur: "b"
            case .crop: "c"
            }
        }
    }

    let record: ScreenshotRecord
    let base: CGImage
    let imageSize: CGSize

    /// Whether the picture is dressed up (background, frame, shadow…). The canvas then shows the finished result and annotations
    /// are edited on it; off, it is the plain screenshot. Starts off for every screenshot.
    @Published var beautifyOn = false {
        didSet { if beautifyOn, tool == .crop { tool = .select } }
    }
    /// Whether the beautify popover is open.
    @Published var showBeautifyPanel = false
    /// The look used when beautify is on. Remembered across screenshots.
    @Published var style: BeautifyStyle { didSet { if style != oldValue { BeautifyStore.save(style) } } }

    @Published private(set) var history: EditHistory
    /// Annotations while a drag is in progress; nil otherwise. Committed to `history` when the gesture ends.
    @Published private(set) var liveItems: [Annotation]?

    @Published var tool: Tool = .arrow {
        didSet {
            if tool == .crop { startCrop() } else if oldValue == .crop { cropRect = nil }
            if tool != .select, tool != oldValue, tool != .crop { selectedID = nil }
        }
    }
    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?

    // Style of what is drawn next (and, when something is selected, of that).
    @Published var color: AnnotationColor = .red
    @Published var lineLevel: LineLevel = .medium
    @Published var shadow = true
    @Published var textLevel: TextLevel = .medium
    @Published var highlightColor: AnnotationColor = AnnotationColor.highlighters[0]
    @Published var textBackground = true
    @Published var blurMode: BlurMode = .pixelate
    @Published var blurStrength = 2

    // Crop
    @Published var cropRect: CGRect?
    @Published var cropRatio: Double?

    init(record: ScreenshotRecord, base: CGImage) {
        self.record = record
        self.base = base
        imageSize = CGSize(width: base.width, height: base.height)
        history = EditHistory()
        style = BeautifyStore.load()
    }

    // MARK: Beautify

    /// Pixels per point of the screenshot (2 on Retina); paddings and radii are in points.
    var pixelsPerPoint: Double { max(record.scale, 1) }

    private var contentCache: (snapshot: EditSnapshot, image: CGImage, dark: Bool)?

    /// The annotated, cropped screenshot that goes onto the canvas.
    func annotatedContent() -> CGImage? {
        if let c = contentCache, c.snapshot == history.current { return c.image }
        guard let image = renderFinal() else { return nil }
        contentCache = (history.current, image, BeautifyRenderer.averageLuminance(of: image, topFraction: 0.12) < 0.5)
        return image
    }

    /// Whether the window frame's title bar should be drawn dark (the screenshot's top edge is dark).
    var contentIsDark: Bool {
        _ = annotatedContent()
        return contentCache?.dark ?? true
    }

    /// The finished beautified picture at full resolution.
    func renderBeautified() -> CGImage? {
        guard let content = annotatedContent() else { return nil }
        return BeautifyRenderer.render(content: content, style: style, pixelsPerPoint: pixelsPerPoint)
    }

    /// What "完成" and "复制" produce: what the canvas shows.
    func renderOutput() -> CGImage? { beautifyOn ? renderBeautified() : renderFinal() }

    /// Whether the canvas shows the beautified frame right now (cropping always shows the bare picture).
    var showsFrame: Bool { beautifyOn && tool != .crop }

    /// Where everything sits on the beautified canvas, in pixels.
    func frameLayout() -> BeautifyLayout {
        BeautifyLayout.compute(content: visibleRect.size, style: style, pixelsPerPoint: pixelsPerPoint)
    }

    func applyPreset(_ preset: BeautifyPreset) { style = preset.style(keeping: style) }

    func resetStyle() { style = BeautifyPreset.social.style(keeping: BeautifyStyle()) }

    // MARK: State

    var items: [Annotation] { liveItems ?? history.current.items }
    var crop: CGRect? { history.current.crop }
    var fullRect: CGRect { CGRect(origin: .zero, size: imageSize) }
    /// The part of the image on screen: everything while cropping, the cropped area afterwards.
    var visibleRect: CGRect { tool == .crop ? fullRect : (crop ?? fullRect) }
    var isDirty: Bool { history.isDirty }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var selected: Annotation? { items.first { $0.id == selectedID } }
    /// Size of the exported picture.
    var outputSize: CGSize { beautifyOn ? frameLayout().canvas : (crop ?? fullRect).integral.size }

    // MARK: Editing

    func beginLive(_ items: [Annotation]) { liveItems = items }
    func updateLive(_ items: [Annotation]) { liveItems = items }
    func cancelLive() { liveItems = nil }

    /// Ends a gesture: the live annotations become one undo step.
    func commitLive() {
        guard let live = liveItems else { return }
        liveItems = nil
        history.commit(EditSnapshot(items: Annotation.renumbered(live), crop: history.current.crop))
        objectWillChange.send()
    }

    func commit(items: [Annotation]) {
        liveItems = nil
        history.commit(EditSnapshot(items: Annotation.renumbered(items), crop: history.current.crop))
    }

    func add(_ a: Annotation) {
        commit(items: items + [a])
        selectedID = a.id
    }

    func replace(_ a: Annotation, live: Bool = false) {
        var list = items
        guard let i = list.firstIndex(where: { $0.id == a.id }) else { return }
        list[i] = a
        if live { updateLive(list) } else { commit(items: list) }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        commit(items: items.filter { $0.id != id })
        selectedID = nil
    }

    func undo() {
        guard history.undo() else { return }
        liveItems = nil
        if let id = selectedID, !items.contains(where: { $0.id == id }) { selectedID = nil }
        objectWillChange.send()
    }

    func redo() {
        guard history.redo() else { return }
        liveItems = nil
        objectWillChange.send()
    }

    /// Makes `id` the selection and shows its style in the toolbar.
    func select(_ id: UUID?) {
        selectedID = id
        guard let a = selected else { return }
        color = a.color
        shadow = a.shadow
        switch a.shape {
        case .text:
            textBackground = a.textBackground
            textLevel = TextLevel.allCases.min { abs(AnnotationScale.fontSize($0, imageWidth: imageSize.width) - a.fontSize)
                                                  < abs(AnnotationScale.fontSize($1, imageWidth: imageSize.width) - a.fontSize) } ?? .medium
        case .blur:
            blurMode = a.blurMode; blurStrength = a.blurStrength
        case .highlight:
            highlightColor = a.color
        case .marker:
            textLevel = TextLevel.allCases.min { abs(AnnotationScale.fontSize($0, imageWidth: imageSize.width) - a.fontSize)
                                                  < abs(AnnotationScale.fontSize($1, imageWidth: imageSize.width) - a.fontSize) } ?? .medium
        default:
            lineLevel = LineLevel.allCases.min { abs(AnnotationScale.lineWidth($0, imageWidth: imageSize.width) - a.lineWidth)
                                                 < abs(AnnotationScale.lineWidth($1, imageWidth: imageSize.width) - a.lineWidth) } ?? .medium
        }
    }

    /// Builds a new annotation in the current style, at the image's own scale.
    func makeAnnotation(_ shape: AnnotationShape) -> Annotation {
        var a = Annotation(shape: shape)
        a.color = color
        a.shadow = shadow
        a.lineWidth = AnnotationScale.lineWidth(lineLevel, imageWidth: imageSize.width)
        a.fontSize = AnnotationScale.fontSize(textLevel, imageWidth: imageSize.width)
        a.textBackground = textBackground
        a.blurMode = blurMode
        a.blurStrength = blurStrength
        if case let .text(_, s) = shape { a.textSize = AnnotationRenderer.measureText(s, fontSize: a.fontSize, background: a.textBackground) }
        switch shape {
        case .highlight:
            a.color = highlightColor
            a.shadow = false
        case .marker:
            a.markerNumber = items.filter { if case .marker = $0.shape { return true }; return false }.count + 1
        default:
            break
        }
        return a
    }

    /// A style control changed: apply it to the selected annotation too, as one undo step.
    func restyleSelected(_ change: (inout Annotation) -> Void) {
        guard var a = selected else { return }
        change(&a)
        if case let .text(_, s) = a.shape { a.textSize = AnnotationRenderer.measureText(s, fontSize: a.fontSize, background: a.textBackground) }
        replace(a)
    }

    // MARK: Crop

    func startCrop() {
        selectedID = nil
        cropRect = crop ?? fullRect
        cropRatio = nil
    }

    func setCropRatio(_ ratio: Double?) {
        cropRatio = ratio
        if let ratio, let r = cropRect { cropRect = GeometryTools.clamp(CropMath.fit(r, ratio: ratio), in: fullRect) }
    }

    func applyCrop() {
        if let r = cropRect {
            let rounded = r.integral.intersection(fullRect)
            history.commit(EditSnapshot(items: history.current.items, crop: rounded == fullRect ? nil : rounded))
        }
        cropRect = nil
        tool = .select
    }

    func cancelCrop() {
        cropRect = nil
        tool = .select
    }

    // MARK: Output

    func renderFinal() -> CGImage? { AnnotationRenderer.render(base: base, snapshot: history.current) }
}
