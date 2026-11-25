import CoreGraphics
import Foundation

public struct PackedCircle: Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var r: CGFloat
    /// Radius used to keep neighbours apart (a little larger than `r`).
    public var reach: CGFloat

    public init(x: CGFloat, y: CGFloat, r: CGFloat, reach: CGFloat? = nil) {
        self.x = x
        self.y = y
        self.r = r
        self.reach = reach ?? r
    }
}

/// Circle packing for the "bubbles" share card: the biggest circle sits in the middle and the rest
/// are pressed against the cluster, closest-first. Deterministic, so the preview and the export agree.
public enum BubblePacking {
    /// - Parameters:
    ///   - weights: usage per bubble, biggest first.
    ///   - gap: space kept between neighbouring icons, in units where the biggest icon is 200 wide.
    ///   - exponent: how strongly size follows usage. 0 = all the same size, 0.5 = area proportional to usage.
    /// - Returns: circles centred in `area` and scaled to fill it. `r` is half the icon's side.
    public static func pack(weights: [Double], in area: CGSize, gap: CGFloat = 10, exponent: Double = 0.4) -> [PackedCircle] {
        guard let maxWeight = weights.max(), maxWeight > 0, area.width > 0, area.height > 0 else { return [] }
        let radii = weights.map { 100 * max(0.3, CGFloat(pow(max($0, 0) / maxWeight, exponent))) }
        // Icons are rounded squares, so neighbours must keep a little more than a circle's distance on the diagonals.
        let reach = radii.map { $0 * 1.12 }

        var placed: [PackedCircle] = []
        for (i, r) in radii.enumerated() {
            if i == 0 { placed.append(PackedCircle(x: 0, y: 0, r: r, reach: reach[i])); continue }
            var spot = CGPoint.zero
            var rho: CGFloat = 0
            search: while rho < 5000 {
                for k in 0..<72 {
                    // The golden-ratio offset spreads successive circles around the cluster instead of stacking on one side.
                    let angle = (Double(k) / 72 + Double(i) * 0.381966) * 2 * .pi
                    let p = CGPoint(x: rho * CGFloat(cos(angle)), y: rho * CGFloat(sin(angle)))
                    if placed.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) >= $0.reach + reach[i] + gap }) { spot = p; break search }
                }
                rho += 2
            }
            placed.append(PackedCircle(x: spot.x, y: spot.y, r: r, reach: reach[i]))
        }

        let minX = placed.map { $0.x - $0.r }.min()!, maxX = placed.map { $0.x + $0.r }.max()!
        let minY = placed.map { $0.y - $0.r }.min()!, maxY = placed.map { $0.y + $0.r }.max()!
        let scale = min(area.width / (maxX - minX), area.height / (maxY - minY))
        return placed.map {
            PackedCircle(x: ($0.x - (minX + maxX) / 2) * scale + area.width / 2,
                         y: ($0.y - (minY + maxY) / 2) * scale + area.height / 2,
                         r: $0.r * scale, reach: $0.reach * scale)
        }
    }
}
