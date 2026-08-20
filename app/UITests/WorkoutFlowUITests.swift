import XCTest

/// Walks the app the way a workout does, and photographs each screen on the way
/// through. The screenshots are attachments on the result bundle, so a failing
/// run shows you what it looked like rather than only what it asserted.
final class WorkoutFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A training day whatever day the test runs on, and never CloudKit.
        app.launchArguments += ["-RFDay", "Push A"]
        // A fresh install has NO history — that is the point of the fix that
        // stopped the app inventing six weeks of it. Trends therefore needs the
        // sample data asked for explicitly.
        app.launchArguments += ["-RFDemoHistory"]
        app.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        // A fresh in-memory store per launch. Otherwise run five accumulates
        // run four's sets and the assertions drift out from under the test.
        app.launchEnvironment["RF_UITEST"] = "1"
        app.launch()
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAWorkoutFromTheListToTheCooldown() throws {
        // 1. The day is a list.
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20),
                      "the plan should open on Push A")
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        shoot("01-today")

        // 2. Tapping the live row opens the set screen.
        // `.firstMatch`: an accessibility identifier set on a SwiftUI row lands
        // on the container AND its children, so the bare query is ambiguous.
        let bench = app.descendants(matching: .any)
            .matching(identifier: "row-bench-press").firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()

        let logButton = app.descendants(matching: .any)
            .matching(identifier: "log-set").firstMatch
        XCTAssertTrue(logButton.waitForExistence(timeout: 5),
                      "the set screen should offer to log the next set")
        // Plate math for 185 on a 45 bar: a 45 and a 25 a side.
        XCTAssertTrue(app.staticTexts["45"].exists)
        XCTAssertTrue(app.staticTexts["25"].exists)
        shoot("02-set-ready")

        // 3. Logging a set starts the cooldown, and the button changes its mind
        //    about what it is for.
        logButton.tap()
        let skip = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Skip to set'"))
        XCTAssertTrue(skip.element.waitForExistence(timeout: 5),
                      "after logging, the primary action should be skipping the rest")
        XCTAssertTrue(app.staticTexts["Cooldown"].exists, "the ring should be counting")
        shoot("03-cooldown")

        // 4. Back out and the row remembers.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))
        shoot("04-today-after-a-set")
    }

    /// A real first launch: a plan, and no claims about your past.
    func testAFreshInstallHasNoInventedHistory() throws {
        let clean = XCUIApplication()
        clean.launchArguments += ["-RFDay", "Push A"]
        clean.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        clean.launchEnvironment["RF_UITEST"] = "1"   // no -RFDemoHistory
        clean.launch()

        XCTAssertTrue(clean.staticTexts["Push A"].waitForExistence(timeout: 20),
                      "the plan is a template and should still be there")
        clean.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(clean.staticTexts["Nothing to plot yet."].waitForExistence(timeout: 10),
                      "a fresh install must not show lifts that never happened")
        XCTAssertFalse(clean.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "sample data")).firstMatch.exists,
            "nothing to label when nothing was invented")
        let shot = XCTAttachment(screenshot: clean.screenshot())
        shot.name = "09-fresh-install-trends"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTrendsAndPass() throws {
        app.tabBars.buttons["Trends"].tap()
        // Assert on something the tab bar does not also say — "Trends" is both
        // the screen title and the tab label, which makes the query ambiguous.
        // Case-insensitive: the eyebrow style uppercases the rendered string,
        // and XCUITest reports what is drawn, not what the source said.
        let strengthHeader = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "working weight")).firstMatch
        XCTAssertTrue(strengthHeader.waitForExistence(timeout: 10),
                      "the strength table should be on the trends screen")
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        // Sample data must announce itself wherever it is drawn, or it is just
        // invented numbers on a chart with your name on it.
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "sample data")).firstMatch.exists,
            "demo data should be labelled on Trends")
        shoot("05-trends")

        app.tabBars.buttons["Pass"].tap()
        // No passes are seeded — a membership code cannot be invented — so the
        // empty state is the correct first screen here.
        XCTAssertTrue(app.staticTexts["No passes stored."].waitForExistence(timeout: 10))
        shoot("06-pass-empty")

        // Two things are labelled "Add a pass": the toolbar + and this button.
        app.descendants(matching: .any)
            .matching(identifier: "add-pass-cta").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add a pass"].waitForExistence(timeout: 5))
        // Matched by placeholder rather than by index: a Form reorders as
        // sections appear, and index-based lookups break silently when it does.
        let gym = app.textFields["Blink Fitness"]
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        gym.tap(); gym.typeText("Blink Fitness")
        let where_ = app.textFields["Union Square"]
        where_.tap(); where_.typeText("Union Square")
        let code = app.textFields["Scan, import or type the code"]
        code.tap(); code.typeText("RF-DEMO-CODE-0001")
        shoot("07-pass-editor")
        app.navigationBars["Add a pass"].buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Blink Fitness"].waitForExistence(timeout: 5),
                      "a saved pass should become the one you hold up at the door")
        shoot("08-pass-card")
    }
}
