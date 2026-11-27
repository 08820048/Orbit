import AppKit
import OrbitCore
import SwiftUI

/// Everything the annotation editor knows: the picture, the annotations, the current tool and its style, undo history.
@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case select, arrow, rectangle, ellipse, line, text, blur, crop
        var id: String { rawValue }
        var title: String {
            switch self {
            case .select: "选择"
            case .arrow: "箭头"
            case .rectangle: "矩形"
            case .ellipse: "椭圆"
            case .line: "直线"
            case .text: "文字"
            case .blur: "模糊 / 马赛克"
            case .crop: "裁剪"
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
            case .blur: "b"
            case .crop: "c"
            }
        }
    }

    let record: ScreenshotRecord
    let base: CGImage
    let imageSize: CGSize

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
    }

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
    var outputSize: CGSize { (crop ?? fullRect).integral.size }

    // MARK: Editing

    func beginLive(_ items: [Annotation]) { liveItems = items }
    func updateLive(_ items: [Annotation]) { liveItems = items }
    func cancelLive() { liveItems = nil }

    /// Ends a gesture: the live annotations become one undo step.
    func commitLive() {
        guard let live = liveItems else { return }
        liveItems = nil
        history.commit(EditSnapshot(items: live, crop: history.current.crop))
        objectWillChange.send()
    }

    func commit(items: [Annotation]) {
        liveItems = nil
        history.commit(EditSnapshot(items: items, crop: history.current.crop))
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
