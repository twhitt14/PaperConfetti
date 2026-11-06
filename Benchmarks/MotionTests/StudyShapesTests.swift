import Foundation
import PaperConfetti
import XCTest
@testable import StudyMotion

final class StudyShapesTests: XCTestCase {
    func testEveryManifestPaletteResolvesAndEverySingleShapeIsCovered() throws {
        let manifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Study.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        let cases = try XCTUnwrap(json["scenarios"] as? [[String: Any]])
        var individual = Set<ConfettiShape>()
        for scenario in cases {
            let name = try XCTUnwrap(scenario["shapes"] as? String)
            let shapes = try XCTUnwrap(StudyShapes.resolve(name), "Unresolved fixture palette \(name)")
            XCTAssertFalse(shapes.isEmpty)
            if name == "festive" { XCTAssertEqual(shapes, ConfettiShape.festive) }
            else if name == "classic" { XCTAssertEqual(shapes, ConfettiShape.classic) }
            else { XCTAssertEqual(shapes.count, 1); individual.formUnion(shapes) }
        }
        XCTAssertEqual(individual, Set(ConfettiShape.allCases))
        XCTAssertNil(StudyShapes.resolve("unknown"))
    }
}
