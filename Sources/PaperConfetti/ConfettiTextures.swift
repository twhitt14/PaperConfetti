#if canImport(UIKit)
    import UIKit

    // UIColor equality retains color-space and pattern identity. Converting to four
    // RGBA numbers loses both, and getRed can fail entirely for pattern colors.
    final class ConfettiTextureKey: NSObject {
        let shape: ConfettiShape
        let color: UIColor
        let size: Double
        let scale: CGFloat
        let pose: Int

        init(shape: ConfettiShape, color: UIColor, size: Double, scale: CGFloat, pose: Int = -1) {
            self.shape = shape; self.color = color; self.size = size; self.scale = scale; self.pose = pose
        }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(shape); hasher.combine(color); hasher.combine(size)
            hasher.combine(scale); hasher.combine(pose)
            return hasher.finalize()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? ConfettiTextureKey else { return false }
            return shape == other.shape && color.isEqual(other.color) && size == other.size
                && scale == other.scale && pose == other.pose
        }
    }

    /// Shared, bounded raster cache. Vector paths are never redrawn on animation frames.
    @_spi(Testing) @MainActor public enum ConfettiTextures {
        private static let cache: NSCache<ConfettiTextureKey, UIImage> = {
            let cache = NSCache<ConfettiTextureKey, UIImage>()
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
                    let key = ConfettiTextureKey(shape: shape, color: color, size: size, scale: scale)
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
