#if canImport(UIKit)
import UIKit

/// Shared bitmaps provide initial orientation without private APIs or per-frame drawing.
@MainActor enum ConfettiNativeTextures {
    private static let cache: NSCache<ConfettiTextureKey, UIImage> = {
        let cache = NSCache<ConfettiTextureKey, UIImage>()
        cache.countLimit = 2_048
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    // Prepare only the color/shape/pose combinations this flight actually uses.
    // A sparse burst with a large palette must not allocate the entire Cartesian
    // product. Retain used images locally so cache eviction can't rerasterize one
    // combination hundreds of times while constructing a large burst.
    static func make(particles: [ConfettiParticle], colors: [UIColor], size: Double, scale: CGFloat) -> [CGImage] {
        var used: [ConfettiTextureKey: CGImage] = [:]
        return particles.map { particle in
            let pose = Int(particle.phase / (2 * .pi) * 8) % 8
            let color = colors[particle.color]
            let key = ConfettiTextureKey(shape: particle.shape, color: color, size: size, scale: scale, pose: pose)
            if let image = used[key] { return image }
            if let image = cache.object(forKey: key)?.cgImage {
                used[key] = image
                return image
            }
            let image = ConfettiTextures.make(colors: [color], size: size, scale: scale, shapes: [particle.shape])[0]
            let side = ceil(hypot(Double(image.width), Double(image.height))) + 2
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = false
            let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
                context.cgContext.translateBy(x: side / 2, y: side / 2)
                context.cgContext.rotate(by: Double(pose) * 2 * .pi / 8)
                UIImage(cgImage: image).draw(in: CGRect(x: -CGFloat(image.width) / 2,
                    y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
            }
            let rotated = result.cgImage!
            cache.setObject(result, forKey: key, cost: rotated.bytesPerRow * rotated.height)
            used[key] = rotated
            return rotated
        }
    }
}
#endif
