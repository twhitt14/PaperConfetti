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

final class RendererStudyTests: XCTestCase {
    func testAllRenderersCompleteAndCleanUp() {
        let app = XCUIApplication()
        app.launchArguments = ["--study=paper-720,layers-720,emitter-720,sprite-720,sprite-atlas-720", "--study-rounds=1", "--autostart", "--run-id=study-ui-smoke"]
        app.launch()
        let status = app.staticTexts["study-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == %@", "Comparison saved"), evaluatedWith: status)
        waitForExpectations(timeout: 70)
    }

    func testOpeningAppNormallyShowsVisualReview() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["study-replay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["study-picker"].label.contains("Native particles"))
    }

    func testVisualReviewCanStopReplayAndSwitchAutomatically() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--study=emitter-720,paper-720"]
        app.launch()
        let replay = app.buttons["study-replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: 10))
        replay.tap()
        app.buttons["study-stop"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["study-status"].label.contains("Animation stopped"))
        replay.tap()
        app.buttons["study-tap"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["study-active-taps"].label, "Taps during flight: 1")
        app.buttons["study-next"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "paper-720"), evaluatedWith: app.staticTexts["study-status"])
        waitForExpectations(timeout: 5)
        app.buttons["study-tap"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["study-active-taps"].label, "Taps during flight: 2")
    }

    func testAllRendererOverlaysPassThroughRealTapsAndScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--study=paper-720,layers-720,emitter-720,sprite-720,sprite-atlas-720"]
        app.launch()
        XCTAssertTrue(app.buttons["study-replay"].waitForExistence(timeout: 10))
        for index in 0..<5 {
            app.buttons["study-replay"].tap()
            // Do not let XCTest wait until the flight ends before performing the interaction.
            app.buttons["study-tap"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let tap = app.buttons["study-tap"]
            XCTAssertEqual(tap.label, "Tap test: \(index + 1)")
            XCTAssertEqual(app.staticTexts["study-active-taps"].label, "Taps during flight: \(index + 1)")
            let scroll = app.scrollViews["study-scroll"]
            scroll.swipeUp()
            scroll.swipeUp()
            XCTAssertTrue(app.staticTexts["study-scroll-end"].isHittable)
            if index < 4 { app.buttons["study-next"].tap() }
        }
    }
}
