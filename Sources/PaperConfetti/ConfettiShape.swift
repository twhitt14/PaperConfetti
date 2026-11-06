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
    /// A human-readable label; names do not participate in geometry identity.
    public let name: String

    enum Command: Hashable, Sendable {
        case move(Double, Double), line(Double, Double)
        case quad(Double, Double, Double, Double)
        case curve(Double, Double, Double, Double, Double, Double)
        case close
    }
    /// A reason a custom silhouette cannot be normalized safely.
    public enum PathError: Error, Equatable {
        /// The path contains no drawing elements.
        case empty
        /// A bound or path coordinate is not finite, or cannot be normalized.
        case nonFinite
        /// The path contains more than 512 elements.
        case tooComplex
        /// The path has zero area bounds or an aspect ratio thinner than 1:64.
        case invalidSize
    }

    /// Makes a filled silhouette from a Core Graphics path, preserving its proportions.
    /// Holes use the even-odd fill rule. At most 512 path elements are accepted.
    /// `name` is a display label, not a cache key; different geometry cannot collide.
    /// - Parameters:
    ///   - path: The silhouette to snapshot. Stroke open lines into a filled path first.
    ///   - name: A display label. Defaults to “Custom”.
    /// - Throws: ``PathError`` for empty, non-finite, excessive, or degenerate geometry.
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

    /// Returns whether two shapes share a built-in or normalized custom-path identity.
    ///
    /// - Parameters:
    ///   - lhs: The first shape.
    ///   - rhs: The second shape.
    /// - Returns: `true` for the same built-in or custom path representation and
    ///   proportions, regardless of display name. Different path commands are
    ///   not canonicalized merely because they produce the same silhouette.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.cacheKey == rhs.cacheKey }
    /// Hashes the geometry identity, excluding the display name.
    ///
    /// - Parameter hasher: The hasher to receive the identity.
    public func hash(into hasher: inout Hasher) { hasher.combine(cacheKey) }
    /// A filled circle.
    public static let circle = Self(.circle, name: "Circle")
    /// A compact filled triangle.
    public static let triangle = Self(.triangle, name: "Triangle")
    /// A narrow rectangular strip.
    public static let strip = Self(.strip, name: "Strip")
    /// A filled five-pointed star.
    public static let star = Self(.star, name: "Star")
    /// A hollow five-pointed star.
    public static let outlinedStar = Self(.outlinedStar, name: "Outlined star")
    /// A four-pointed curved sparkle.
    public static let sparkle = Self(.sparkle, name: "Sparkle")
    /// A thin six-spoke star.
    public static let asterisk = Self(.asterisk, name: "Asterisk")
    /// A gently curved streamer.
    public static let wave = Self(.wave, name: "Wave")
    /// A wavy, curved streamer.
    public static let squiggle = Self(.squiggle, name: "Squiggle")
    /// A single looping streamer.
    public static let loop = Self(.loop, name: "Loop")
    /// A double-loop streamer.
    public static let doubleLoop = Self(.doubleLoop, name: "Double loop")
    /// A hollow circle.
    public static let ring = Self(.ring, name: "Ring")
    /// A long triangular paper cut.
    public static let longTriangle = Self(.longTriangle, name: "Long triangle")
    /// A curved triangular paper cut.
    public static let curvedTriangle = Self(.curvedTriangle, name: "Curved triangle")
    /// A diamond-shaped paper cut.
    public static let diamond = Self(.diamond, name: "Diamond")
    /// A slanted paper cut.
    public static let parallelogram = Self(.parallelogram, name: "Parallelogram")
    /// The built-in library. Custom shapes are values and are not added to this list.
    public static let allCases: [Self] = [.circle, .triangle, .strip, .star, .outlinedStar, .sparkle, .asterisk, .wave, .squiggle, .loop, .doubleLoop, .ring, .longTriangle, .curvedTriangle, .diamond, .parallelogram]
    /// The default 13-shape mix: four stars, four streamers, a ring, and four paper cuts.
    public static let festive: [Self] = [.star, .outlinedStar, .sparkle, .asterisk,
        .wave, .squiggle, .loop, .doubleLoop, .ring, .longTriangle, .curvedTriangle, .diamond, .parallelogram]
    /// A restrained three-shape mix of circles, triangles, and strips.
    public static let classic: [Self] = [.circle, .triangle, .strip]

    @_spi(Testing) public var rawValue: Int { builtin?.rawValue ?? -1 }
    @_spi(Testing) public var width: Double { relativeWidth }
    @_spi(Testing) public var height: Double { relativeHeight }
}
