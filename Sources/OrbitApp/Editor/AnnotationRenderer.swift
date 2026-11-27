import AppKit
import CoreImage
import OrbitCore

/// Draws annotations into pixels. The same drawing code serves the live canvas and the exported image, so what you see
/// is what gets saved. Contexts here are "image space": pixels, origin top-left, y down.
enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Export

    /// The finished image: the base picture with every annotation applied in order, then cropped.
    static func render(base: CGImage, snapshot: EditSnapshot) -> CGImage? {
        let w = base.width, h = base.height
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // y-down image space
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        drawImage(base, in: CGRect(x: 0, y: 0, width: w, height: h), ctx)
        for a in snapshot.items {
            if case let .blur(rect) = a.shape {
                applyBlur(a, rect: rect, to: ctx, imageSize: CGSize(width: w, height: h))
            } else {
                draw(a, in: ctx)
            }
        }
        guard let full = ctx.makeImage() else { return nil }
        guard let crop = snapshot.crop else { return full }
        let r = crop.integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return r.isNull || r.isEmpty ? full : full.cropping(to: r)
    }

    // MARK: Drawing one annotation

    /// Draws everything except blur regions (those need the pixels underneath).
    static func draw(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let color = cgColor(a.color)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(a.lineWidth)

        let useShadow = a.shadow && !isBlur(a)
        if useShadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -a.lineWidth * 0.45), blur: a.lineWidth * 1.3,
                          color: CGColor(gray: 0, alpha: 0.45))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        switch a.shape {
        case let .arrow(from, to): drawArrow(from, to, width: a.lineWidth, ctx)
        case let .line(from, to):
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
        case let .rectangle(r):
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(a.lineWidth * 0.5, r.width / 2), cornerHeight: min(a.lineWidth * 0.5, r.height / 2), transform: nil))
            ctx.strokePath()
        case let .ellipse(r):
            ctx.strokeEllipse(in: r)
        case let .text(origin, string):
            drawText(string, origin: origin, a, ctx)
        case .blur:
            break
        }
        if useShadow { ctx.endTransparencyLayer() }
    }

    private static func isBlur(_ a: Annotation) -> Bool { if case .blur = a.shape { return true }; return false }

    private static func drawArrow(_ from: CGPoint, _ to: CGPoint, width: Double, _ ctx: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = max(width * 3.4, 16)
        let spread = Double.pi / 6.5
        let left = CGPoint(x: to.x - head * cos(angle - spread), y: to.y - head * sin(angle - spread))
        let right = CGPoint(x: to.x - head * cos(angle + spread), y: to.y - head * sin(angle + spread))
        ctx.move(to: from); ctx.addLine(to: to)
        ctx.move(to: left); ctx.addLine(to: to); ctx.addLine(to: right)
        ctx.strokePath()
    }

    // MARK: Text

    static func font(size: Double) -> NSFont { NSFont.systemFont(ofSize: size, weight: .semibold) }

    private static func padding(for size: Double) -> CGSize { CGSize(width: size * 0.45, height: size * 0.28) }

    /// Size of the text box (including the coloured pill when there is one).
    static func measureText(_ string: String, fontSize: Double, background: Bool) -> CGSize {
        let text = string.isEmpty ? " " : string
        let box = (text as NSString).boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin],
                                                  attributes: [.font: font(size: fontSize)])
        let pad = background ? padding(for: fontSize) : .zero
        return CGSize(width: ceil(box.width) + pad.width * 2, height: ceil(box.height) + pad.height * 2)
    }

    private static func drawText(_ string: String, origin: CGPoint, _ a: Annotation, _ ctx: CGContext) {
        let size = a.textSize == .zero ? measureText(string, fontSize: a.fontSize, background: a.textBackground) : a.textSize
        let rect = CGRect(origin: origin, size: size)
        let onColor: NSColor = a.color.luminance > 0.7 ? NSColor(white: 0.08, alpha: 1) : .white
        var textOrigin = origin
        if a.textBackground {
            ctx.setFillColor(cgColor(a.color))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: a.fontSize * 0.3, cornerHeight: a.fontSize * 0.3, transform: nil))
            ctx.fillPath()
            let pad = padding(for: a.fontSize)
            textOrigin = CGPoint(x: origin.x + pad.width, y: origin.y + pad.height)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font(size: a.fontSize),
                                                         .foregroundColor: a.textBackground ? onColor : NSColor(cgColor: cgColor(a.color)) ?? .red]
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (string as NSString).draw(with: CGRect(origin: textOrigin, size: CGSize(width: 10_000, height: 10_000)),
                                  options: [.usesLineFragmentOrigin], attributes: attributes)
        NSGraphicsContext.current = previous
    }

    // MARK: Blur and mosaic

    /// Block size / radius in pixels for a strength level, scaled to the image.
    static func strengthValue(_ a: Annotation, imageWidth: Double) -> Double {
        let level = max(1, min(3, a.blurStrength))
        let base: [Double] = a.blurMode == .pixelate ? [9, 16, 28] : [8, 16, 30]
        return base[level - 1] * AnnotationScale.factor(forImageWidth: imageWidth)
    }

    /// Replaces the pixels of `rect` in `ctx` with a blurred / pixelated version of what is there now.
    private static func applyBlur(_ a: Annotation, rect: CGRect, to ctx: CGContext, imageSize: CGSize) {
        guard let snapshot = ctx.makeImage(),
              let patch = blurredPatch(of: snapshot, rect: rect, annotation: a, imageWidth: imageSize.width) else { return }
        let region = rect.integral.intersection(CGRect(origin: .zero, size: imageSize))
        drawImage(patch, in: region, ctx)
    }

    /// The blurred pixels for `rect` of `image` (image space), or nil when the rectangle is empty.
    static func blurredPatch(of image: CGImage, rect: CGRect, annotation a: Annotation, imageWidth: Double) -> CGImage? {
        let region = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard region.width >= 1, region.height >= 1, let crop = image.cropping(to: region) else { return nil }
        let input = CIImage(cgImage: crop)
        let value = strengthValue(a, imageWidth: imageWidth)
        let output: CIImage?
        switch a.blurMode {
        case .pixelate:
            let f = CIFilter(name: "CIPixellate")
            f?.setValue(input, forKey: kCIInputImageKey)
            f?.setValue(value, forKey: kCIInputScaleKey)
            f?.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
            output = f?.outputImage
        case .blur:
            let f = CIFilter(name: "CIGaussianBlur")
            f?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            f?.setValue(value, forKey: kCIInputRadiusKey)
            output = f?.outputImage
        }
        guard let out = output else { return nil }
        return ciContext.createCGImage(out, from: input.extent)
    }

    // MARK: Helpers

    /// Draws `image` upright into `rect` of a y-down context.
    static func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func cgColor(_ c: AnnotationColor) -> CGColor { CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
}
