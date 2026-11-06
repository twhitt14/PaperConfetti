#if canImport(UIKit)
    import UIKit

    /// Shared, bounded raster cache. Vector paths are never redrawn on animation frames.
    @_spi(Testing) @MainActor public enum ConfettiTextures {
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
                shapes.prefix(32).map { shape in
                    var r: CGFloat = 0
                    var g: CGFloat = 0
                    var b: CGFloat = 0
                    var a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let key = "\(shape.cacheKey)|\(size)|\(scale)|\(r)|\(g)|\(b)|\(a)" as NSString
                    if let image = cache.object(forKey: key)?.cgImage { return image }
                    let dimensions = CGSize(width: max(1, size * shape.relativeWidth), height: max(1, size * shape.relativeHeight))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    format.opaque = false
                    let image = UIGraphicsImageRenderer(size: dimensions, format: format).image { renderer in
                        let context = renderer.cgContext
                        context.setFillColor(color.cgColor)
                        context.setStrokeColor(color.cgColor)
                        // Half-point padding prevents strokes being cropped at texture edges.
                        let inset = min(0.6, min(dimensions.width, dimensions.height) * 0.15)
                        context.translateBy(x: inset, y: inset)
                        context.scaleBy(
                            x: max(0.1, dimensions.width - inset * 2), y: max(0.1, dimensions.height - inset * 2))
                        draw(shape, in: context)
                    }
                    cache.setObject(
                        image, forKey: key,
                        cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
                    return image.cgImage!
                }
            }
        }

        private static func draw(_ shape: ConfettiShape, in context: CGContext) {
            context.addPath(shape.normalizedPath)
            context.drawPath(using: shape.builtin == nil ? .eoFill : .fill)
        }
    }
#endif
