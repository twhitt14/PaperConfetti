#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@_spi(Testing) @testable import PaperConfetti

@MainActor
final class ConfettiTextureTests: XCTestCase {
    private func pattern(_ color: UIColor) -> UIColor {
        UIColor(patternImage: UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { c in
            color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        })
    }
    private func rgba(_ image: CGImage, x: Int? = nil, y: Int? = nil) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try pixels.withUnsafeMutableBytes { bytes in
            let c = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = ((y ?? image.height / 2) * image.width + (x ?? image.width / 2)) * 4
        return Array(pixels[offset..<offset+4])
    }

    func testPatternAndWideGamutColorsCannotAliasInEitherCache() throws {
        let red = pattern(.red), blue = pattern(.blue)
        let images = ConfettiTextures.make(colors: [red, blue], size: 16, scale: 1, shapes: [.circle])
        XCTAssertFalse(images[0] === images[1])
        XCTAssertGreaterThan(try rgba(images[0])[0], 240)
        XCTAssertGreaterThan(try rgba(images[1])[2], 240)
        let gamut = ConfettiTextures.make(colors: [UIColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1),
            UIColor(displayP3Red: 0.8, green: 0.3, blue: 0.1, alpha: 1)], size: 16, scale: 1, shapes: [.circle])
        XCTAssertFalse(gamut[0] === gamut[1], "Equal components in different color spaces aren't the same paint")
        XCTAssertNotEqual(try rgba(gamut[0]), try rgba(gamut[1]))
        let particles = ConfettiBurst(cannons: [.init(origin: .zero, particleCount: 1)], seed: 42, shapes: [.circle]).particles(paletteCount: 1)
        let nativeRed = ConfettiNativeTextures.make(particles: particles, colors: [red], size: 16, scale: 1)[0]
        let nativeBlue = ConfettiNativeTextures.make(particles: particles, colors: [blue], size: 16, scale: 1)[0]
        XCTAssertFalse(nativeRed === nativeBlue)
        XCTAssertGreaterThan(try rgba(nativeRed)[0], 240)
        XCTAssertGreaterThan(try rgba(nativeBlue)[2], 240)
    }

    func testOnlyUsedNativeTexturesArePreparedAndIdenticalPiecesShareAnImage() throws {
        let particles = ConfettiBurst(cannons: [.init(origin: .zero, particleCount: 1)], seed: 4,
                                     shapes: [.circle]).particles(paletteCount: 16)
        let repeated = Array(repeating: try XCTUnwrap(particles.first), count: 200)
        let colors = (0..<16).map { UIColor(hue: CGFloat($0) / 16, saturation: 1, brightness: 1, alpha: 1) }
        let images = ConfettiNativeTextures.make(particles: repeated, colors: colors, size: 64, scale: 3)
        XCTAssertEqual(images.count, repeated.count)
        XCTAssertEqual(Set(images.map(ObjectIdentifier.init)).count, 1,
                       "A sparse burst needs one bitmap, not all palette/pose combinations")
        XCTAssertLessThanOrEqual(images[0].width, 274, "Raster size follows displayed paper size and device scale")
    }

    func testCustomHoleRemainsTransparentAndPreviewsRejectInvalidBounds() throws {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        path.addRect(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let shape = try ConfettiShape(path: path)
        let image = ConfettiTextures.make(colors: [.blue], size: 32, scale: 1, shapes: [shape])[0]
        XCTAssertEqual(try rgba(image)[3], 0)
        XCTAssertGreaterThan(try rgba(image, x: 4, y: 4)[3], 240)
        XCTAssertTrue(shape.path(in: .zero).isEmpty)
        XCTAssertTrue(shape.path(in: .infinite).isEmpty)
        XCTAssertTrue(shape.path(in: CGRect(x: Double.nan, y: 0, width: 20, height: 20)).isEmpty)
    }

    func testRendererResolvesDynamicColorsForEachNewFlight() async throws {
        let view = ConfettiLayerView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let host = UIViewController()
        let window = UIWindow(frame: view.bounds)
        window.rootViewController = host; host.view.addSubview(view); window.isHidden = false
        defer { view.cancel(); window.isHidden = true; window.rootViewController = nil }
        let color = UIColor { $0.userInterfaceStyle == .dark ? .blue : .red }
        let burst = ConfettiBurst(cannons: [.init(origin: .zero, particleCount: 1)], seed: 42, shapes: [.circle])
        var pixels: [[UInt8]] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            view.overrideUserInterfaceStyle = style
            for _ in 0..<100 where view.traitCollection.userInterfaceStyle != style {
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, style)
            view.play(burst: burst, colors: [color])
            let clock = try XCTUnwrap(view.layer.sublayers?.first)
            let emitter = try XCTUnwrap(clock.sublayers?.first as? CAEmitterLayer)
            let contents = try XCTUnwrap(emitter.emitterCells?.first?.contents)
            let image = contents as! CGImage
            pixels.append(try rgba(image))
        }
        view.cancel()
        XCTAssertGreaterThan(pixels[0][0], 240)
        XCTAssertGreaterThan(pixels[1][2], 240)
    }

    func testUIKitHostCanBeArchivedAndDecodedWithoutRestoringFlights() throws {
        let original = ConfettiView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = false
        defer { decoder.finishDecoding() }
        let restored = try XCTUnwrap(decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? ConfettiView)
        XCTAssertEqual(restored.frame, original.frame)
        XCTAssertEqual(restored.subviews.filter { $0 is ConfettiLayerView }.count, 1)
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.isUserInteractionEnabled)
        XCTAssertTrue(restored.accessibilityElementsHidden)
        restored.isUserInteractionEnabled = true
        XCTAssertNil(restored.hitTest(CGPoint(x: 100, y: 100), with: nil))
    }
}
#endif
