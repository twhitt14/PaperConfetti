import Foundation
import CoreGraphics
import CryptoKit

/// A cached paper silhouette. Built-ins and custom paths use the same renderer.
/// Custom paths are copied, normalized and rasterized once, never drawn per frame.
public struct ConfettiShape: Hashable, Sendable, CaseIterable {
    enum Builtin: Int, Sendable { case circle, triangle, strip, star, outlinedStar, sparkle, asterisk, wave, squiggle, loop, doubleLoop, ring, longTriangle, curvedTriangle, diamond, parallelogram }
    let builtin: Builtin?
    let commands: [Command]
    let cacheKey: String
    let relativeWidth: Double
    let relativeHeight: Double
    public let name: String

    enum Command: Hashable, Sendable {
        case move(Double, Double), line(Double, Double)
        case quad(Double, Double, Double, Double)
        case curve(Double, Double, Double, Double, Double, Double)
        case close
    }
    public enum PathError: Error, Equatable {
        case empty, nonFinite, tooComplex, invalidSize
    }

    /// Makes a filled silhouette from a Core Graphics path, preserving its proportions.
    /// Holes use the even-odd fill rule. At most 512 path elements are accepted.
    /// `name` is a display label, not a cache key; different geometry cannot collide.
    public init(path: CGPath, name: String = "Custom") throws {
        guard !path.isEmpty else { throw PathError.empty }
        let bounds = path.boundingBoxOfPath
        guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else {
            throw PathError.nonFinite
        }
        guard bounds.width > 0, bounds.height > 0 else { throw PathError.invalidSize }
        var result: [Command] = []
        var invalid = false
        var count = 0
        func point(_ p: CGPoint) -> (Double, Double) {
            if !p.x.isFinite || !p.y.isFinite { invalid = true; return (0, 0) }
            let x = (p.x - bounds.minX) / bounds.width, y = (p.y - bounds.minY) / bounds.height
            guard x.isFinite, y.isFinite else { invalid = true; return (0, 0) }
            return (Double(x), Double(y))
        }
        path.applyWithBlock { element in
            count += 1
            guard count <= 512 else { return }
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                let p = point(e.points[0]); result.append(.move(p.0, p.1))
            case .addLineToPoint:
                let p = point(e.points[0]); result.append(.line(p.0, p.1))
            case .addQuadCurveToPoint:
                let a = point(e.points[0]), b = point(e.points[1])
                result.append(.quad(a.0, a.1, b.0, b.1))
            case .addCurveToPoint:
                let a = point(e.points[0]), b = point(e.points[1]), c = point(e.points[2])
                result.append(.curve(a.0, a.1, b.0, b.1, c.0, c.1))
            case .closeSubpath: result.append(.close)
            @unknown default: invalid = true
            }
        }
        guard count <= 512 else { throw PathError.tooComplex }
        guard !invalid else { throw PathError.nonFinite }
        let longest = max(bounds.width, bounds.height)
        guard min(bounds.width, bounds.height) / longest >= 1.0 / 64 else { throw PathError.invalidSize }
        self.builtin = nil
        self.commands = result
        self.relativeWidth = bounds.width / longest
        self.relativeHeight = bounds.height / longest
        self.name = name
        // Geometry and aspect ratio identify a texture independently of display names.
        let signature = "\(result)|\(relativeWidth)|\(relativeHeight)"
        self.cacheKey = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private init(_ builtin: Builtin, name: String) {
        self.builtin = builtin; self.commands = []; self.name = name
        self.cacheKey = "builtin-\(builtin.rawValue)"
        switch builtin {
        case .wave, .squiggle, .doubleLoop: relativeWidth = 2.2
        case .loop: relativeWidth = 1.6
        case .longTriangle, .curvedTriangle: relativeWidth = 1.8
        default: relativeWidth = 1
        }
        switch builtin {
        case .wave, .squiggle: relativeHeight = 0.75
        case .doubleLoop: relativeHeight = 1.1
        case .longTriangle, .curvedTriangle: relativeHeight = 0.8
        default: relativeHeight = 1
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.cacheKey == rhs.cacheKey }
    public func hash(into hasher: inout Hasher) { hasher.combine(cacheKey) }
    public static let circle = Self(.circle, name: "Circle")
    public static let triangle = Self(.triangle, name: "Triangle")
    public static let strip = Self(.strip, name: "Strip")
    public static let star = Self(.star, name: "Star")
    public static let outlinedStar = Self(.outlinedStar, name: "Outlined star")
    public static let sparkle = Self(.sparkle, name: "Sparkle")
    public static let asterisk = Self(.asterisk, name: "Asterisk")
    public static let wave = Self(.wave, name: "Wave")
    public static let squiggle = Self(.squiggle, name: "Squiggle")
    public static let loop = Self(.loop, name: "Loop")
    public static let doubleLoop = Self(.doubleLoop, name: "Double loop")
    public static let ring = Self(.ring, name: "Ring")
    public static let longTriangle = Self(.longTriangle, name: "Long triangle")
    public static let curvedTriangle = Self(.curvedTriangle, name: "Curved triangle")
    public static let diamond = Self(.diamond, name: "Diamond")
    public static let parallelogram = Self(.parallelogram, name: "Parallelogram")
    /// The built-in library. Custom shapes are values and are not added to this list.
    public static let allCases: [Self] = [.circle, .triangle, .strip, .star, .outlinedStar, .sparkle, .asterisk, .wave, .squiggle, .loop, .doubleLoop, .ring, .longTriangle, .curvedTriangle, .diamond, .parallelogram]
    public static let festive: [Self] = [.star, .outlinedStar, .sparkle, .asterisk,
        .wave, .squiggle, .loop, .doubleLoop, .ring, .longTriangle, .curvedTriangle, .diamond, .parallelogram]
    public static let classic: [Self] = [.circle, .triangle, .strip]

    @_spi(Testing) public var rawValue: Int { builtin?.rawValue ?? -1 }
    @_spi(Testing) public var width: Double { relativeWidth }
    @_spi(Testing) public var height: Double { relativeHeight }
}
