import AppKit
import OrbitCore

/// Puts a screenshot on a canvas: background, window frame, rounded corners, shadow, signature.
enum BeautifyRenderer {
    /// The finished picture at full resolution. `pixelsPerPoint` is the screenshot's own scale (2 on Retina), so paddings
    /// and corner radii keep the size they have on screen.
    static func render(content: CGImage, style: BeautifyStyle, pixelsPerPoint ppp: Double, date: Date = Date()) -> CGImage? {
        let layout = BeautifyLayout.compute(content: CGSize(width: content.width, height: content.height), style: style, pixelsPerPoint: ppp)
        let w = Int(layout.canvas.width), h = Int(layout.canvas.height)
        let space = content.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)                       // y-down, like the layout

        let background = style.backgroundValue
        drawBackground(background, size: layout.canvas, ctx)

        let window = layout.window
        let path = CGPath(roundedRect: window, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil)

        if style.shadow > 0.001 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -ppp * (6 + 22 * style.shadow)), blur: ppp * (8 + 42 * style.shadow),
                          color: CGColor(gray: 0, alpha: min(0.75, 0.15 + 0.55 * style.shadow)))
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.addPath(path); ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let dark = averageLuminance(of: content, topFraction: 0.12) < 0.5
        if layout.chrome > 0 { drawChrome(style, layout: layout, dark: dark, ppp: ppp, ctx) }
        AnnotationRenderer.drawImage(content, in: layout.content, ctx)
        ctx.restoreGState()

        if style.showSignature || style.showWatermark {
            drawSignature(style, layout: layout, light: background.luminance > 0.6, ppp: ppp, date: date, ctx)
        }
        return ctx.makeImage()
    }

    /// A smaller render for the live preview: the content is shrunk first, so dragging a slider stays smooth.
    static func preview(content: CGImage, style: BeautifyStyle, pixelsPerPoint ppp: Double, maxSide: Double) -> CGImage? {
        let layout = BeautifyLayout.compute(content: CGSize(width: content.width, height: content.height), style: style, pixelsPerPoint: ppp)
        let longest = max(layout.canvas.width, layout.canvas.height)
        guard longest > maxSide, longest > 0 else { return render(content: content, style: style, pixelsPerPoint: ppp) }
        let f = maxSide / longest
        guard let small = scaled(content, by: f) else { return nil }
        return render(content: small, style: style, pixelsPerPoint: ppp * f)
    }

    static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
        let w = max(1, Int((Double(image.width) * factor).rounded())), h = max(1, Int((Double(image.height) * factor).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: Background

    private static func drawBackground(_ bg: BeautifyBackground, size: CGSize, _ ctx: CGContext) {
        let rect = CGRect(origin: .zero, size: size)
        switch bg {
        case .none:
            break
        case let .solid(c):
            ctx.setFillColor(AnnotationRenderer.cgColor(c)); ctx.fill(rect)
        case let .gradient(a, b):
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [AnnotationRenderer.cgColor(a), AnnotationRenderer.cgColor(b)] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case let .builtin(name):
            drawPhoto(BackgroundStore.builtin(name), in: rect, ctx)
        case let .custom(file):
            drawPhoto(BackgroundStore.custom(file), in: rect, ctx)
        }
    }

    /// A photo scaled to cover the canvas, dimmed a little so the window stands out.
    private static func drawPhoto(_ image: NSImage?, in rect: CGRect, _ ctx: CGContext) {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1)); ctx.fill(rect); return
        }
        let s = max(rect.width / CGFloat(cg.width), rect.height / CGFloat(cg.height))
        let size = CGSize(width: CGFloat(cg.width) * s, height: CGFloat(cg.height) * s)
        AnnotationRenderer.drawImage(cg, in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height), ctx)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.18)); ctx.fill(rect)
    }

    // MARK: Window frame

    private static func drawChrome(_ style: BeautifyStyle, layout: BeautifyLayout, dark: Bool, ppp: Double, _ ctx: CGContext) {
        let bar = CGRect(x: layout.window.minX, y: layout.window.minY, width: layout.window.width, height: layout.chrome)
        ctx.setFillColor(dark ? CGColor(srgbRed: 0.16, green: 0.17, blue: 0.22, alpha: 1) : CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1))
        ctx.fill(bar)
        // traffic lights
        let colors = [CGColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1), CGColor(srgbRed: 1, green: 0.741, blue: 0.18, alpha: 1),
                      CGColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1)]
        let r = 6 * ppp
        for (i, c) in colors.enumerated() {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: bar.minX + (14 + 20 * Double(i)) * ppp, y: bar.midY - r, width: r * 2, height: r * 2))
        }
        let titleColor = dark ? NSColor(srgbRed: 0.67, green: 0.71, blue: 0.82, alpha: 1) : NSColor(srgbRed: 0.3, green: 0.3, blue: 0.33, alpha: 1)
        let title = style.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch style.frame {
        case .window:
            if !title.isEmpty { drawCentered(title, in: bar, size: 12 * ppp, color: titleColor, ctx) }
        case .browser:
            let left = bar.minX + (14 + 20 * 3 + 6) * ppp, right = bar.maxX - 14 * ppp
            let pill = CGRect(x: left, y: bar.midY - 10 * ppp, width: max(0, right - left), height: 20 * ppp)
            ctx.setFillColor(dark ? CGColor(gray: 1, alpha: 0.08) : CGColor(gray: 0, alpha: 0.06))
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 10 * ppp, cornerHeight: 10 * ppp, transform: nil)); ctx.fillPath()
            if !title.isEmpty { drawCentered(title, in: pill, size: 11 * ppp, color: titleColor, ctx) }
        case .none:
            break
        }
    }

    private static func drawCentered(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, _ ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color]
        var t = text as NSString
        var measured = t.size(withAttributes: attrs)
        // Shorten what does not fit instead of letting it spill over the traffic lights.
        if measured.width > rect.width - size {
            var s = text
            while s.count > 1, (s + "…" as NSString).size(withAttributes: attrs).width > rect.width - size { s.removeLast() }
            t = (s + "…") as NSString
            measured = t.size(withAttributes: attrs)
        }
        withFlipped(ctx) { t.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2), withAttributes: attrs) }
    }

    // MARK: Signature and watermark

    private static func drawSignature(_ style: BeautifyStyle, layout: BeautifyLayout, light: Bool, ppp: Double, date: Date, _ ctx: CGContext) {
        let fontSize = 11 * ppp
        let band = CGFloat(layout.canvas.height) - layout.window.maxY
        guard band >= 26 * ppp else { return }                // no room below the window: leave it out rather than overlap
        let color = light ? NSColor(white: 0, alpha: 0.55) : NSColor(white: 1, alpha: 0.72)
        let y = layout.window.maxY + (band - fontSize * 1.2) / 2
        if style.showSignature {
            let f = DateFormatter(); f.dateFormat = "yyyy.MM"
            let name = style.signature.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = [name, f.string(from: date)].filter { !$0.isEmpty }.joined(separator: " · ")
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color, .kern: fontSize * 0.1]
            withFlipped(ctx) { (text as NSString).draw(at: CGPoint(x: layout.window.minX, y: y), withAttributes: attrs) }
        }
        if style.showWatermark {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color, .kern: fontSize * 0.16]
            let s = "ORBIT" as NSString
            let width = s.size(withAttributes: attrs).width
            withFlipped(ctx) { s.draw(at: CGPoint(x: layout.window.maxX - width, y: y), withAttributes: attrs) }
        }
    }

    // MARK: Helpers

    private static func withFlipped(_ ctx: CGContext, _ body: () -> Void) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.current = previous
    }

    /// Brightness 0...1 of the top strip of the picture, to choose a title bar that does not clash with it.
    static func averageLuminance(of image: CGImage, topFraction: Double) -> Double {
        let h = max(1, Int(Double(image.height) * topFraction))
        guard let strip = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: h)),
              let ctx = CGContext(data: nil, width: 4, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 4, height: 1))
        let p = data.bindMemory(to: UInt8.self, capacity: 16)
        var total = 0.0
        for i in 0..<4 { total += (0.299 * Double(p[i * 4]) + 0.587 * Double(p[i * 4 + 1]) + 0.114 * Double(p[i * 4 + 2])) / 255 }
        return total / 4
    }
}
