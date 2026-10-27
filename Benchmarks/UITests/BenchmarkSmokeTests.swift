import XCTest

final class BenchmarkSmokeTests: XCTestCase {
    func testAutomatedProtocolCompletesWithBothRenderers() {
        let app = XCUIApplication()
        app.launchArguments = ["--smoke", "--autostart", "--run-id=ui-smoke"]
        app.launch()
        let status = app.staticTexts["benchmark-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let done = NSPredicate(format: "label == %@", "This pass is saved")
        expectation(for: done, evaluatedWith: status)
        waitForExpectations(timeout: 45)
    }
}
