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
        app.launchArguments = ["--study=paper-720,layers-720,emitter-720,emitter-3d-720,sprite-720,sprite-3d-720,sprite-atlas-720,sprite-atlas-3d-720", "--study-rounds=1", "--autostart", "--run-id=study-ui-smoke"]
        app.launch()
        let status = app.staticTexts["study-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label == %@", "Comparison saved"), evaluatedWith: status)
        waitForExpectations(timeout: 105)
    }

    func testSpriteKitRepeatedReplayAnd3DAtlasStayInteractive() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--study=sprite-3d-720,sprite-atlas-3d-720"]
        app.launch()
        XCTAssertTrue(app.buttons["study-replay"].waitForExistence(timeout: 10))
        for _ in 0..<3 {
            app.buttons["study-replay"].tap()
            app.buttons["study-shuffle"].tap()
            app.buttons["study-next"].tap()
            let ready = NSPredicate(format: "NOT (label BEGINSWITH %@)", "Preparing")
            expectation(for: ready, evaluatedWith: app.staticTexts["study-status"])
            waitForExpectations(timeout: 5)
            XCTAssertTrue(app.buttons["study-stop"].isEnabled)
            app.buttons["study-tap"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["study-stop"].tap()
            XCTAssertTrue(app.staticTexts["study-status"].label.contains("Animation stopped"))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SpriteKit transparent after repeated cancellation"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShuffleChangesMixButReplayKeepsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--study=emitter-3d-720"]
        app.launch()
        let shuffle = app.buttons["study-shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 10))
        let seed = app.staticTexts["study-seed"]
        XCTAssertTrue(seed.label.contains("1001"))
        shuffle.tap()
        XCTAssertTrue(seed.label.contains("1002"))
        app.buttons["study-replay"].tap()
        XCTAssertTrue(seed.label.contains("1002"))
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
        app.launchArguments = ["--visual-review", "--study=paper-720,layers-720,emitter-720,emitter-3d-720,sprite-720,sprite-3d-720,sprite-atlas-720,sprite-atlas-3d-720"]
        app.launch()
        XCTAssertTrue(app.buttons["study-replay"].waitForExistence(timeout: 10))
        for index in 0..<8 {
            app.buttons["study-replay"].tap()
            let ready = NSPredicate(format: "NOT (label BEGINSWITH %@)", "Preparing")
            expectation(for: ready, evaluatedWith: app.staticTexts["study-status"])
            waitForExpectations(timeout: 5)
            // Do not let XCTest wait until the flight ends before performing the interaction.
            app.buttons["study-tap"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let tap = app.buttons["study-tap"]
            XCTAssertEqual(tap.label, "Tap test: \(index + 1)")
            XCTAssertEqual(app.staticTexts["study-active-taps"].label, "Taps during flight: \(index + 1)")
            let scroll = app.scrollViews["study-scroll"]
            scroll.swipeUp()
            scroll.swipeUp()
            XCTAssertTrue(app.staticTexts["study-scroll-end"].isHittable)
            if index < 7 { app.buttons["study-next"].tap() }
        }
    }
}


final class NativeEmissionTests: XCTestCase {
    /// Counts visible cannon columns from actual display screenshots, not the
    /// model's requested population. Probe controls are white and outside the ROI.
    private func cannons(in screenshot: XCUIScreenshot) -> Set<Int> {
        guard let image = screenshot.image.cgImage else { return [] }
        let width = 300, height = 650
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var counts = [Int](repeating: 0, count: 5)
        for y in 160..<620 { for x in 0..<width {
            let offset = (y * width + x) * 4
            let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
            if max(r, g, b) > 100 && max(r, g, b) - min(r, g, b) > 65 { counts[min(4, x / 60)] += 1 }
        } }
        return Set(counts.indices.filter { counts[$0] > 15 })
    }
    private func fireAndObserve(_ app: XCUIApplication, name: String) -> Set<Int> {
        app.buttons["probe-fire"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        var visible: Set<Int> = []
        for _ in 0..<10 {
            let screenshot = app.screenshot()
            visible.formUnion(cannons(in: screenshot))
            if visible.count == 5 {
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                break
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        return visible
    }
    func testAllFiveNativeCannonsAppearAt5760IncludingDelayedCommitAndReplay() {
        for (scenario, stall) in [("stress-emitter-5760", "0"), ("stress-emitter-3d-5760", "350")] {
            let app = XCUIApplication()
            app.launchArguments = ["--visual-review", "--emission-probe", "--study=" + scenario, "--native-stall-ms=" + stall]
            app.launch()
            XCTAssertTrue(app.buttons["probe-fire"].waitForExistence(timeout: 10))
            for round in 0..<3 {
                XCTAssertEqual(fireAndObserve(app, name: "\(scenario) replay \(round)"), Set(0..<5))
            }
            app.terminate()
        }
    }
    func testNativeRendersEveryRequestedParticleIn5760SlotGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--emission-probe", "--emission-grid", "--study=stress-emitter-5760"]
        app.launch()
        XCTAssertTrue(app.buttons["probe-fire"].waitForExistence(timeout: 10))
        let surface = app.otherElements["probe-surface"].frame
        app.buttons["probe-fire"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        var visible: Set<Int> = []
        for _ in 0..<10 {
            let screenshot = app.screenshot(), image = screenshot.image.cgImage!
            let width = image.width, height = image.height, scale = Double(width) / app.frame.width
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            for index in 0..<5760 where !visible.contains(index) {
                let x = Int((surface.minX + (Double(index % 60) + 0.5) * surface.width / 60) * scale)
                let y = Int((surface.minY + surface.height * 0.2 + (Double(index / 60) + 0.5) * surface.height * 0.6 / 96) * scale)
                for yy in max(0,y-3)...min(height-1,y+3) { for xx in max(0,x-3)...min(width-1,x+3) {
                    let offset = (yy * width + xx) * 4
                    if max(bytes[offset], bytes[offset+1], bytes[offset+2]) > 70 { visible.insert(index) }
                } }
            }
            if visible.count == 5760 {
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "All 5760 native slots visible"; attachment.lifetime = .keepAlways; add(attachment)
                break
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        XCTAssertEqual(visible.count, 5760, "Check actual occupied pixels, not requested native birth rates")
    }
    func testLegacyClockControlReproducesMissingFirstCannon() {
        let app = XCUIApplication()
        app.launchArguments = ["--visual-review", "--emission-probe", "--study=stress-emitter-5760", "--native-legacy-clock", "--native-stall-ms=150"]
        app.launch()
        XCTAssertTrue(app.buttons["probe-fire"].waitForExistence(timeout: 10))
        let visible = fireAndObserve(app, name: "Legacy negative control")
        XCTAssertFalse(visible.contains(0), "The negative control must detect a missed cannon, not just count requested particles")
        XCTAssertTrue(visible.contains(4), "Later cannons must still be visible; an entirely empty capture is not a valid control")
    }
}
