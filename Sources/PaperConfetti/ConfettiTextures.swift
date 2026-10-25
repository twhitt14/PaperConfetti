#if canImport(UIKit)
    import UIKit

    /// Shared, bounded raster cache. Vector paths are never redrawn on animation frames.
    @MainActor public enum ConfettiTextures {
        private static let cache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 256
            cache.totalCostLimit = 4 * 1_024 * 1_024
            return cache
        }()

        public static func make(
            colors: [UIColor], size: Double, scale: CGFloat,
            shapes: [ConfettiShape] = ConfettiShape.classic
        ) -> [CGImage] {
            guard size.isFinite, (1...64).contains(size), scale.isFinite else { return [] }
            let scale = min(4, max(1, scale))
            return colors.prefix(16).flatMap { color in
                shapes.map { shape in
                    var r: CGFloat = 0
                    var g: CGFloat = 0
                    var b: CGFloat = 0
                    var a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let key = "\(shape.rawValue)|\(size)|\(scale)|\(r)|\(g)|\(b)|\(a)" as NSString
                    if let image = cache.object(forKey: key)?.cgImage { return image }
                    let dimensions = CGSize(width: size * shape.width, height: size * shape.height)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    format.opaque = false
                    let image = UIGraphicsImageRenderer(size: dimensions, format: format).image { renderer in
                        let context = renderer.cgContext
                        context.setFillColor(color.cgColor)
                        context.setStrokeColor(color.cgColor)
                        // Half-point padding prevents strokes being cropped at texture edges.
                        context.translateBy(x: 0.6, y: 0.6)
                        context.scaleBy(
                            x: max(0.1, dimensions.width - 1.2), y: max(0.1, dimensions.height - 1.2))
                        draw(shape, in: context)
                    }
                    cache.setObject(
                        image, forKey: key,
                        cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
                    return image.cgImage!
                }
            }
        }

        private static func draw(_ shape: ConfettiShape, in c: CGContext) {
            func move(_ x: Double, _ y: Double) { c.move(to: CGPoint(x: x, y: y)) }
            func line(_ x: Double, _ y: Double) { c.addLine(to: CGPoint(x: x, y: y)) }
            func curve(_ x: Double, _ y: Double, _ a: Double, _ b: Double, _ d: Double, _ e: Double) {
                c.addCurve(
                    to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: d, y: e))
            }
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.setLineWidth(0.105)
            switch shape {
            case .circle: c.fillEllipse(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            case .triangle:
                move(0.5, 0)
                line(1, 1)
                line(0, 1)
                c.closePath()
                c.fillPath()
            case .strip: c.fill(CGRect(x: 0.35, y: 0, width: 0.3, height: 1))
            case .star, .outlinedStar:
                let radius = shape == .outlinedStar ? 0.44 : 0.5
                for point in 0..<10 {
                    let angle = Double(point) * .pi / 5 - .pi / 2
                    let r = point.isMultiple(of: 2) ? radius : radius * 0.46
                    let p = CGPoint(x: 0.5 + cos(angle) * r, y: 0.5 + sin(angle) * r)
                    if point == 0 { c.move(to: p) } else { c.addLine(to: p) }
                }
                c.closePath()
                if shape == .star { c.fillPath() } else { c.strokePath() }
            case .sparkle:
                move(0.5, 0)
                curve(1, 0.5, 0.55, 0.4, 0.6, 0.45)
                curve(0.5, 1, 0.6, 0.55, 0.55, 0.6)
                curve(0, 0.5, 0.45, 0.6, 0.4, 0.55)
                curve(0.5, 0, 0.4, 0.45, 0.45, 0.4)
                c.closePath()
                c.fillPath()
            case .asterisk:
                for ray in 0..<3 {
                    let angle = Double(ray) * .pi / 3
                    move(0.5 - cos(angle) * 0.44, 0.5 - sin(angle) * 0.44)
                    line(0.5 + cos(angle) * 0.44, 0.5 + sin(angle) * 0.44)
                }
                c.strokePath()
            case .wave:
                move(0.04, 0.55)
                curve(0.5, 0.5, 0.24, -0.28, 0.28, 1.2)
                curve(0.96, 0.45, 0.72, -0.2, 0.76, 1.28)
                c.strokePath()
            case .squiggle:
                move(0.05, 0.1)
                curve(0.35, 0.4, -0.05, 0.8, 0.42, -0.15)
                curve(0.65, 0.6, 0.2, 1.12, 0.81, -0.12)
                curve(0.95, 0.9, 0.58, 1.15, 1.05, 0.2)
                c.strokePath()
            case .loop:
                move(0.04, 0.94)
                curve(0.73, 0.15, 0.18, 0.3, 0.52, 0.05)
                curve(0.38, 0.42, 1.02, 0.45, 0.34, 0.86)
                curve(0.96, 0.08, 0.34, 0.12, 0.78, 0.35)
                c.strokePath()
            case .doubleLoop:
                move(0.04, 0.85)
                curve(0.25, 0.12, 0.35, 0.78, 0.43, 0.25)
                curve(0.62, 0.15, 0, 0.15, 0.53, 1.1)
                curve(0.95, 0.72, 0.8, -0.15, 0.31, 0.75)
                c.strokePath()
            case .ring:
                c.strokeEllipse(in: CGRect(x: 0.065, y: 0.065, width: 0.87, height: 0.87))
            case .longTriangle:
                move(0, 0.94)
                line(1, 0)
                line(0.72, 0.83)
                c.closePath()
                c.fillPath()
            case .curvedTriangle:
                move(0, 1)
                curve(1, 0, 0.28, 0.22, 0.6, 0.03)
                curve(0.15, 1, 0.63, 0.45, 0.4, 0.85)
                c.closePath()
                c.fillPath()
            case .diamond:
                move(0.5, 0)
                line(1, 0.43)
                line(0.5, 1)
                line(0, 0.57)
                c.closePath()
                c.fillPath()
            case .parallelogram:
                move(0, 0.13)
                line(0.68, 0.3)
                line(1, 0.88)
                line(0.32, 0.7)
                c.closePath()
                c.fillPath()
            }
        }
    }
#endif
