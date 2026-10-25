import XCTest

final class PaperConfettiExampleUITests: XCTestCase {
    func testTouchesScrollNavigationAndCancellationDuringFlight() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["pop"].waitForExistence(timeout: 10))
        app.buttons["pop"].tap()
        app.buttons["tap-through"].tap()
        XCTAssertEqual(app.staticTexts["input-proof"].label, "Tap received while confetti is active")
        app.switches["toggle-through"].tap()
        XCTAssertEqual(app.staticTexts["input-proof"].label, "Tap received while confetti is active")
        app.buttons["cannons"].tap()
        app.scrollViews["showcase-scroll"].swipeUp()
        app.scrollViews["showcase-scroll"].swipeUp()
        XCTAssertTrue(
            app.buttons["shape-15"].isHittable, "Scroll must reach the last shape through the overlay")
        app.scrollViews["showcase-scroll"].swipeDown()
        app.scrollViews["showcase-scroll"].swipeDown()
        app.buttons["stop"].tap()
        app.buttons["tap-through"].tap()
        XCTAssertEqual(app.staticTexts["input-proof"].label, "Tap received · overlay is idle")
        app.buttons["pop"].tap()
        app.buttons["details"].tap()
        XCTAssertTrue(app.staticTexts["Every tap gets through."].waitForExistence(timeout: 3))
    }

    func testReducedMotionPreviewDoesNotEmitParticles() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let tuning = app.buttons["Tune the pop"]
        scrollIntoView(tuning, in: app)
        tuning.tap()
        let reducedMotion = app.switches["reduce-motion"]
        XCTAssertTrue(reducedMotion.waitForExistence(timeout: 3))
        scrollIntoView(reducedMotion, in: app)
        app.switches["reduce-motion"].tap()
        app.buttons["pop"].tap()
        scrollIntoView(app.buttons["tap-through"], in: app)
        app.buttons["tap-through"].tap()
        XCTAssertEqual(app.staticTexts["input-proof"].label, "Tap received · overlay is idle")
    }
    // A full swipe can leave a short control behind the translucent navigation bar.
    // Keep the actual control wholly inside the unobscured part of the scroll view.
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["showcase-scroll"]
        let top = app.navigationBars.firstMatch.frame.maxY + 24
        let bottom = app.buttons["pop"].frame.minY - 24
        for _ in 0..<16 {
            if element.exists && element.frame.minY >= top && element.frame.maxY <= bottom {
                XCTAssertTrue(element.isHittable)
                return
            }
            let movingDown = element.exists && element.frame.minY < top
            let start = scroll.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.45 : 0.65))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.65 : 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Could not scroll \(element.identifier) into the unobscured viewport")
    }

}
