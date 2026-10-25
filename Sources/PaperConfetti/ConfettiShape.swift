import Foundation

/// Paper silhouettes, independent of color, rotation and size.
public enum ConfettiShape: Int, CaseIterable, Sendable {
    case circle, triangle, strip
    case star, outlinedStar, sparkle, asterisk
    case wave, squiggle, loop, doubleLoop
    case ring, longTriangle, curvedTriangle, diamond, parallelogram

    /// Four stars, four streamers, a ring and four angular/curved paper cuts.
    public static let festive: [Self] = [
        .star, .outlinedStar, .sparkle, .asterisk,
        .wave, .squiggle, .loop, .doubleLoop,
        .ring, .longTriangle, .curvedTriangle, .diamond, .parallelogram,
    ]
    public static let classic: [Self] = [.circle, .triangle, .strip]

    /// Relative footprint. Long paper retains its proportions instead of being
    /// squeezed into the same square as a star. `size` is the nominal point size.
    public var width: Double {
        switch self {
        case .wave, .squiggle, .doubleLoop: return 2.2
        case .loop: return 1.6
        case .longTriangle, .curvedTriangle: return 1.8
        default: return 1
        }
    }
    public var height: Double {
        switch self {
        case .wave, .squiggle: return 0.75
        case .doubleLoop: return 1.1
        case .longTriangle, .curvedTriangle: return 0.8
        default: return 1
        }
    }
}
