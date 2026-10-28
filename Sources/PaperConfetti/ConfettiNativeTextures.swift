#if canImport(UIKit)
import UIKit

/// Small shared bitmaps provide native cells' initial orientation without private APIs.
@MainActor enum ConfettiNativeTextures {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 2_048; cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    static func make(colors: [UIColor], size: Double, scale: CGFloat, shapes: [ConfettiShape]) -> [CGImage] {
        let originals = ConfettiTextures.make(colors: colors, size: size, scale: scale, shapes: shapes)
        return originals.enumerated().flatMap { index, image in
            let color = colors[index / shapes.count]
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (0..<8).map { pose in
                let key = "\(shapes[index % shapes.count].rawValue)|\(size)|\(scale)|\(r)|\(g)|\(b)|\(a)|\(pose)" as NSString
                if let existing = cache.object(forKey: key)?.cgImage { return existing }
                let side = ceil(hypot(Double(image.width), Double(image.height))) + 2
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
                let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { c in
                    c.cgContext.translateBy(x: side / 2, y: side / 2)
                    c.cgContext.rotate(by: Double(pose) * 2 * .pi / 8)
                    UIImage(cgImage: image).draw(in: CGRect(x: -CGFloat(image.width) / 2,
                        y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
                }
                cache.setObject(result, forKey: key, cost: result.cgImage!.bytesPerRow * result.cgImage!.height)
                return result.cgImage!
            }
        }
    }
}
#endif
