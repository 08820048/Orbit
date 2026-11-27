import CoreGraphics
import Foundation

// MARK: - Model
//
// Everything is in image pixels, origin top-left (y grows downward), like the screenshot itself.

public struct AnnotationColor: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public static let red = AnnotationColor(1.0, 0.30, 0.31)
    public static let orange = AnnotationColor(1.0, 0.69, 0.13)
    public static let green = AnnotationColor(0.18, 0.82, 0.48)
    public static let blue = AnnotationColor(0.23, 0.51, 0.96)
    public static let purple = AnnotationColor(0.63, 0.42, 0.94)
    public static let white = AnnotationColor(1, 1, 1)
    public static let black = AnnotationColor(0.07, 0.07, 0.07)
    public static let palette: [AnnotationColor] = [.red, .orange, .green, .blue, .purple, .white, .black]
    /// Highlighter colours: bright and meant to be drawn translucent.
    public static let highlighters: [AnnotationColor] = [AnnotationColor(1.0, 0.88, 0.29), AnnotationColor(0.36, 0.89, 0.49),
                                                          AnnotationColor(1.0, 0.49, 0.71), AnnotationColor(0.43, 0.76, 1.0)]

    /// Perceived brightness 0...1, to pick readable text on top of this colour.
    public var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
}

public enum AnnotationShape: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    /// `origin` is the top-left corner of the text box.
    case text(origin: CGPoint, string: String)
    /// A region whose pixels are hidden for good when the image is exported.
    case blur(CGRect)
    /// A numbered circle (1, 2, 3…) centred on `center`; the number is `Annotation.markerNumber`.
    case marker(center: CGPoint)
    /// A translucent rectangle laid over text, like a highlighter pen.
    case highlight(CGRect)
}

public enum BlurMode: String, Equatable, Sendable, CaseIterable {
    case blur, pixelate
    public var label: String { self == .blur ? "模糊" : "马赛克" }
}

public enum LineLevel: Int, CaseIterable, Sendable { case thin = 1, medium, thick }
public enum TextLevel: Int, CaseIterable, Sendable { case small = 1, medium, large }

public struct Annotation: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var shape: AnnotationShape
    public var color: AnnotationColor = .red
    /// Stroke width in image pixels.
    public var lineWidth: Double = 6
    public var shadow = true
    /// Text only.
    public var fontSize: Double = 28
    public var textBackground = true
    /// Measured by the app when the text is laid out; the model only stores it.
    public var textSize: CGSize = .zero
    /// Blur regions only.
    public var blurMode: BlurMode = .pixelate
    public var blurStrength: Int = 2
    /// Marker only. Kept in order by `Annotation.renumbered`.
    public var markerNumber: Int = 1

    public init(shape: AnnotationShape) { self.shape = shape }
}

/// Default sizes scale with the image so a 5K full-screen shot gets as visible a mark as a small crop.
public enum AnnotationScale {
    public static func factor(forImageWidth width: Double) -> Double { max(1, min(4, width / 1200)) }
    public static func lineWidth(_ level: LineLevel, imageWidth: Double) -> Double {
        [2.5, 5, 9][level.rawValue - 1] * factor(forImageWidth: imageWidth)
    }
    public static func fontSize(_ level: TextLevel, imageWidth: Double) -> Double {
        [20, 28, 42][level.rawValue - 1] * factor(forImageWidth: imageWidth)
    }
}

// MARK: - Geometry

public enum Handle: Equatable, Sendable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    case start, end
}

extension Annotation {
    /// Where the annotation is, including stroke and arrow head, for selection frames.
    public var bounds: CGRect {
        let pad = shapePadding
        switch shape {
        case let .arrow(a, b), let .line(a, b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -pad, dy: -pad)
        case let .rectangle(r), let .ellipse(r):
            return r.insetBy(dx: -pad, dy: -pad)
        case let .blur(r), let .highlight(r):
            return r
        case let .text(origin, _):
            return CGRect(origin: origin, size: textSize)
        case let .marker(c):
            let r = markerRadius
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        }
    }

    /// Radius of a marker circle in pixels, from its text size.
    public var markerRadius: Double { fontSize * 0.62 }

    private var shapePadding: Double {
        if case .arrow = shape { return max(lineWidth * 2.5, lineWidth / 2 + 4) }
        return lineWidth / 2
    }

    /// Whether `point` hits this annotation. Outlines are hit near their edge only, so shapes behind them stay reachable.
    public func hit(_ p: CGPoint, tolerance: Double) -> Bool {
        let reach = lineWidth / 2 + tolerance
        switch shape {
        case let .arrow(a, b), let .line(a, b):
            return Self.distance(from: p, toSegment: a, b) <= reach
        case let .rectangle(r):
            let outer = r.insetBy(dx: -reach, dy: -reach), inner = r.insetBy(dx: reach, dy: reach)
            return outer.contains(p) && (inner.width <= 0 || inner.height <= 0 || !inner.contains(p))
        case let .ellipse(r):
            return Self.ellipseEdgeDistance(p, r) <= reach
        case let .blur(r), let .highlight(r):
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case let .marker(c):
            return hypot(p.x - c.x, p.y - c.y) <= markerRadius + tolerance
        }
    }

    public func moved(by d: CGVector) -> Annotation {
        var a = self
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.dx, y: p.y + d.dy) }
        switch shape {
        case let .arrow(p, q): a.shape = .arrow(from: m(p), to: m(q))
        case let .line(p, q): a.shape = .line(from: m(p), to: m(q))
        case let .rectangle(r): a.shape = .rectangle(r.offsetBy(dx: d.dx, dy: d.dy))
        case let .ellipse(r): a.shape = .ellipse(r.offsetBy(dx: d.dx, dy: d.dy))
        case let .blur(r): a.shape = .blur(r.offsetBy(dx: d.dx, dy: d.dy))
        case let .highlight(r): a.shape = .highlight(r.offsetBy(dx: d.dx, dy: d.dy))
        case let .marker(c): a.shape = .marker(center: m(c))
        case let .text(o, s): a.shape = .text(origin: m(o), string: s)
        }
        return a
    }

    /// The handles to draw when this annotation is selected.
    public var handles: [(handle: Handle, point: CGPoint)] {
        switch shape {
        case let .arrow(a, b), let .line(a, b): return [(.start, a), (.end, b)]
        case let .rectangle(r), let .ellipse(r), let .blur(r), let .highlight(r): return RectGeometry.handles(of: r)
        case .text, .marker: return []
        }
    }

    /// Moves one handle to `point`. `constrain` keeps a rectangle square / snaps a line to 45°.
    public func resized(_ handle: Handle, to point: CGPoint, constrain: Bool) -> Annotation {
        var a = self
        switch shape {
        case let .arrow(p, q):
            a.shape = handle == .start ? .arrow(from: GeometryTools.endpoint(from: q, to: point, snap: constrain), to: q)
                                       : .arrow(from: p, to: GeometryTools.endpoint(from: p, to: point, snap: constrain))
        case let .line(p, q):
            a.shape = handle == .start ? .line(from: GeometryTools.endpoint(from: q, to: point, snap: constrain), to: q)
                                       : .line(from: p, to: GeometryTools.endpoint(from: p, to: point, snap: constrain))
        case let .rectangle(r): a.shape = .rectangle(RectGeometry.resize(r, handle: handle, to: point, square: constrain))
        case let .ellipse(r): a.shape = .ellipse(RectGeometry.resize(r, handle: handle, to: point, square: constrain))
        case let .blur(r): a.shape = .blur(RectGeometry.resize(r, handle: handle, to: point, square: constrain))
        case let .highlight(r): a.shape = .highlight(RectGeometry.resize(r, handle: handle, to: point, square: constrain))
        case .text, .marker: break
        }
        return a
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Approximate distance from `p` to the outline of the ellipse inscribed in `r`.
    static func ellipseEdgeDistance(_ p: CGPoint, _ r: CGRect) -> Double {
        let rx = r.width / 2, ry = r.height / 2
        guard rx > 0, ry > 0 else { return hypot(p.x - r.midX, p.y - r.midY) }
        let nx = (p.x - r.midX) / rx, ny = (p.y - r.midY) / ry
        let d = hypot(nx, ny)
        guard d > 0 else { return min(rx, ry) }
        return abs(d - 1) * min(rx, ry)
    }
}

extension Annotation {
    /// The same list with markers numbered 1, 2, 3… in the order they were added, so deleting one closes the gap.
    public static func renumbered(_ items: [Annotation]) -> [Annotation] {
        var n = 0
        return items.map { a in
            guard case .marker = a.shape else { return a }
            n += 1
            var b = a
            b.markerNumber = n
            return b
        }
    }
}

public enum GeometryTools {
    /// The rectangle dragged from `a` to `b`; with `square` its sides are equal.
    public static func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if square { let s = max(abs(dx), abs(dy)); dx = dx < 0 ? -s : s; dy = dy < 0 ? -s : s }
        return CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
    }

    /// `to`, or with `snap` the point that makes the segment horizontal, vertical or diagonal.
    public static func endpoint(from a: CGPoint, to b: CGPoint, snap: Bool) -> CGPoint {
        guard snap else { return b }
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return b }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: a.x + len * cos(angle), y: a.y + len * sin(angle))
    }

    public static func clamp(_ r: CGRect, in bounds: CGRect) -> CGRect {
        var out = r
        out.size.width = min(out.width, bounds.width)
        out.size.height = min(out.height, bounds.height)
        out.origin.x = min(max(out.minX, bounds.minX), bounds.maxX - out.width)
        out.origin.y = min(max(out.minY, bounds.minY), bounds.maxY - out.height)
        return out
    }
}

public enum RectGeometry {
    public static func handles(of r: CGRect) -> [(handle: Handle, point: CGPoint)] {
        [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.top, CGPoint(x: r.midX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
         (.left, CGPoint(x: r.minX, y: r.midY)), (.right, CGPoint(x: r.maxX, y: r.midY)),
         (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.bottom, CGPoint(x: r.midX, y: r.maxY)), (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))]
    }

    /// Drags one handle of `r` to `p`. The opposite edge or corner stays put; the result is normalised.
    /// With `square`, corner drags keep equal sides.
    public static func resize(_ r: CGRect, handle: Handle, to p: CGPoint, square: Bool = false) -> CGRect {
        var left = r.minX, right = r.maxX, top = r.minY, bottom = r.maxY
        switch handle {
        case .topLeft, .left, .bottomLeft: left = p.x
        case .topRight, .right, .bottomRight: right = p.x
        default: break
        }
        switch handle {
        case .topLeft, .top, .topRight: top = p.y
        case .bottomLeft, .bottom, .bottomRight: bottom = p.y
        default: break
        }
        if square, [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle) {
            let fixedX = (handle == .topLeft || handle == .bottomLeft) ? right : left
            let fixedY = (handle == .topLeft || handle == .topRight) ? bottom : top
            return GeometryTools.rect(from: CGPoint(x: fixedX, y: fixedY), to: p, square: true)
        }
        return CGRect(x: min(left, right), y: min(top, bottom), width: abs(right - left), height: abs(bottom - top))
    }
}

// MARK: - Crop

public enum CropMath {
    /// Largest rectangle with width:height = `ratio` that fits inside `r`, keeping `r`'s centre.
    public static func fit(_ r: CGRect, ratio: Double) -> CGRect {
        guard ratio > 0, r.width > 0, r.height > 0 else { return r }
        var w = r.width, h = r.width / ratio
        if h > r.height { h = r.height; w = h * ratio }
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    /// Drags a crop handle, keeping the rectangle inside `bounds`, at least `minSize` big, and (optionally) at `ratio`.
    public static func resize(_ r: CGRect, handle: Handle, to p: CGPoint, bounds: CGRect, ratio: Double?, minSize: Double = 24) -> CGRect {
        let clampedPoint = CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        var out = RectGeometry.resize(r, handle: handle, to: clampedPoint)
        if let ratio, ratio > 0 {
            // Keep the edge or corner opposite the handle fixed and adjust the other dimension to the ratio.
            switch handle {
            case .left, .right:
                let h = out.width / ratio
                out = CGRect(x: out.minX, y: r.midY - h / 2, width: out.width, height: h)
            case .top, .bottom:
                let w = out.height * ratio
                out = CGRect(x: r.midX - w / 2, y: out.minY, width: w, height: out.height)
            default:
                var w = out.width, h = out.height
                if w / max(h, 0.0001) > ratio { w = h * ratio } else { h = w / ratio }
                let x = (handle == .topLeft || handle == .bottomLeft) ? out.maxX - w : out.minX
                let y = (handle == .topLeft || handle == .topRight) ? out.maxY - h : out.minY
                out = CGRect(x: x, y: y, width: w, height: h)
            }
        }
        if out.width < minSize { out.size.width = minSize }
        if out.height < minSize { out.size.height = ratio.map { minSize / $0 } ?? minSize }
        return GeometryTools.clamp(out, in: bounds)
    }
}

// MARK: - Undo / redo

public struct EditSnapshot: Equatable, Sendable {
    public var items: [Annotation]
    /// The cropped area, or nil for the whole image.
    public var crop: CGRect?
    public init(items: [Annotation] = [], crop: CGRect? = nil) { self.items = items; self.crop = crop }
}

/// Snapshot-based history: every finished gesture commits the whole state, so undo is exact and cheap.
public struct EditHistory: Sendable {
    public private(set) var current: EditSnapshot
    private var undoStack: [EditSnapshot] = []
    private var redoStack: [EditSnapshot] = []
    private let initial: EditSnapshot

    public init(_ initial: EditSnapshot = EditSnapshot()) { self.initial = initial; current = initial }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// True when the current state differs from where editing started.
    public var isDirty: Bool { current != initial }

    public mutating func commit(_ s: EditSnapshot) {
        guard s != current else { return }
        undoStack.append(current)
        current = s
        redoStack.removeAll()
    }

    @discardableResult public mutating func undo() -> Bool {
        guard let prev = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = prev
        return true
    }

    @discardableResult public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        current = next
        return true
    }
}
