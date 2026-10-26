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
        reducedMotion.tap()
        XCTAssertEqual(reducedMotion.value as? String, "1")
        XCTAssertTrue(app.staticTexts["reduced-motion-message"].exists)
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
            let delta = element.exists ? element.frame.midY - (top + bottom) / 2 : 120
            let distance = min(120, max(-120, delta))
            // The content has a 24-point gutter. Drag there so sliders and switches
            // cannot capture the gesture. Holding at the end avoids momentum overshoot.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.55))
                .withOffset(CGVector(dx: 12, dy: 0))
            let end = start.withOffset(CGVector(dx: 0, dy: -distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Could not scroll \(element.identifier) into the unobscured viewport")
    }

}
