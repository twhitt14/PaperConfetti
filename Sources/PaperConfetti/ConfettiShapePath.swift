import Foundation
import CoreGraphics

extension ConfettiShape {
    var normalizedPath: CGPath {
        let shape = self
        let c = CGMutablePath()
        var stroke = false
            func move(_ x: Double, _ y: Double) { c.move(to: CGPoint(x: x, y: y)) }
            func line(_ x: Double, _ y: Double) { c.addLine(to: CGPoint(x: x, y: y)) }
            func curve(_ x: Double, _ y: Double, _ a: Double, _ b: Double, _ d: Double, _ e: Double) {
                c.addCurve(
                    to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: d, y: e))
            }
            if shape.builtin == nil {
                for command in shape.commands {
                    switch command {
                    case let .move(x,y): move(x,y)
                    case let .line(x,y): line(x,y)
                    case let .quad(a,b,x,y): c.addQuadCurve(to: CGPoint(x:x,y:y), control: CGPoint(x:a,y:b))
                    case let .curve(a,b,d,e,x,y): curve(x,y,a,b,d,e)
                    case .close: c.closeSubpath()
                    }
                }
                return c
            }
            switch shape.builtin! {
            case .circle: c.addEllipse(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            case .triangle:
                move(0.5, 0)
                line(1, 1)
                line(0, 1)
                c.closeSubpath()
            case .strip: c.addRect(CGRect(x: 0.35, y: 0, width: 0.3, height: 1))
            case .star, .outlinedStar:
                let radius = shape == .outlinedStar ? 0.44 : 0.5
                for point in 0..<10 {
                    let angle = Double(point) * .pi / 5 - .pi / 2
                    let r = point.isMultiple(of: 2) ? radius : radius * 0.46
                    let p = CGPoint(x: 0.5 + cos(angle) * r, y: 0.5 + sin(angle) * r)
                    if point == 0 { c.move(to: p) } else { c.addLine(to: p) }
                }
                c.closeSubpath()
                if shape == .star { () } else { stroke = true }
            case .sparkle:
                move(0.5, 0)
                curve(1, 0.5, 0.55, 0.4, 0.6, 0.45)
                curve(0.5, 1, 0.6, 0.55, 0.55, 0.6)
                curve(0, 0.5, 0.45, 0.6, 0.4, 0.55)
                curve(0.5, 0, 0.4, 0.45, 0.45, 0.4)
                c.closeSubpath()
            case .asterisk:
                for ray in 0..<3 {
                    let angle = Double(ray) * .pi / 3
                    move(0.5 - cos(angle) * 0.44, 0.5 - sin(angle) * 0.44)
                    line(0.5 + cos(angle) * 0.44, 0.5 + sin(angle) * 0.44)
                }
                stroke = true
            case .wave:
                move(0.04, 0.55)
                curve(0.5, 0.5, 0.24, -0.28, 0.28, 1.2)
                curve(0.96, 0.45, 0.72, -0.2, 0.76, 1.28)
                stroke = true
            case .squiggle:
                move(0.05, 0.1)
                curve(0.35, 0.4, -0.05, 0.8, 0.42, -0.15)
                curve(0.65, 0.6, 0.2, 1.12, 0.81, -0.12)
                curve(0.95, 0.9, 0.58, 1.15, 1.05, 0.2)
                stroke = true
            case .loop:
                move(0.04, 0.94)
                curve(0.73, 0.15, 0.18, 0.3, 0.52, 0.05)
                curve(0.38, 0.42, 1.02, 0.45, 0.34, 0.86)
                curve(0.96, 0.08, 0.34, 0.12, 0.78, 0.35)
                stroke = true
            case .doubleLoop:
                move(0.04, 0.85)
                curve(0.25, 0.12, 0.35, 0.78, 0.43, 0.25)
                curve(0.62, 0.15, 0, 0.15, 0.53, 1.1)
                curve(0.95, 0.72, 0.8, -0.15, 0.31, 0.75)
                stroke = true
            case .ring:
                stroke = true; c.addEllipse(in: CGRect(x: 0.065, y: 0.065, width: 0.87, height: 0.87))
            case .longTriangle:
                move(0, 0.94)
                line(1, 0)
                line(0.72, 0.83)
                c.closeSubpath()
            case .curvedTriangle:
                move(0, 1)
                curve(1, 0, 0.28, 0.22, 0.6, 0.03)
                curve(0.15, 1, 0.63, 0.45, 0.4, 0.85)
                c.closeSubpath()
            case .diamond:
                move(0.5, 0)
                line(1, 0.43)
                line(0.5, 1)
                line(0, 0.57)
                c.closeSubpath()
            case .parallelogram:
                move(0, 0.13)
                line(0.68, 0.3)
                line(1, 0.88)
                line(0.32, 0.7)
                c.closeSubpath()
            }
        return stroke ? c.copy(strokingWithWidth: 0.105, lineCap: .round, lineJoin: .round, miterLimit: 10) : c
    }
}

#if canImport(SwiftUI)
import SwiftUI
extension ConfettiShape: Shape {
    /// Draw the same silhouette as the particle, fitted without distortion.
    /// - Parameter rect: The preview bounds. Empty or non-finite bounds produce an empty path.
    /// - Returns: The centered silhouette preserving its proportions. Use even-odd fill for custom holes.
    public func path(in rect: CGRect) -> Path {
        guard !rect.isEmpty, !rect.isInfinite, !rect.isNull,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else { return Path() }
        let scale = min(rect.width / CGFloat(relativeWidth), rect.height / CGFloat(relativeHeight))
        let width = scale * CGFloat(relativeWidth), height = scale * CGFloat(relativeHeight)
        var transform = CGAffineTransform(translationX: rect.midX - width / 2, y: rect.midY - height / 2)
        transform = transform.scaledBy(x: width, y: height)
        return Path(normalizedPath.copy(using: &transform) ?? normalizedPath)
    }
}
#endif
