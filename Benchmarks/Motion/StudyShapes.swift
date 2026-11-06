import PaperConfetti

// Study.json IDs are stable fixture data, not enum descriptions. ConfettiShape
// became a value type in 0.4; String(describing:) no longer names a silhouette.
enum StudyShapes {
    private static let named: [String: ConfettiShape] = [
        "circle": .circle, "triangle": .triangle, "strip": .strip,
        "star": .star, "outlinedStar": .outlinedStar, "sparkle": .sparkle, "asterisk": .asterisk,
        "wave": .wave, "squiggle": .squiggle, "loop": .loop, "doubleLoop": .doubleLoop,
        "ring": .ring, "longTriangle": .longTriangle, "curvedTriangle": .curvedTriangle,
        "diamond": .diamond, "parallelogram": .parallelogram
    ]

    static func resolve(_ name: String) -> [ConfettiShape]? {
        if name == "festive" { return ConfettiShape.festive }
        if name == "classic" { return ConfettiShape.classic }
        return named[name].map { [$0] }
    }
}
