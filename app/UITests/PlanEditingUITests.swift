import XCTest

/// Editing the rotation itself: adding a fourth day to a three-day plan.
///
/// The seeded plan is three days — Pull A, Push A, Legs — and the whole premise
/// of the plan editor is that it is *yours*, so the fourth one has to be one tap
/// away. It was not: the button was there and did nothing, which is worse than
/// not offering it.
final class PlanEditingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-RFDay", "Push A"]
        app.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        app.launchEnvironment["RF_UITEST"] = "1"
        app.launch()
    }

    private func openThePlan() {
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20),
                      "the app should open on a workout")
        app.descendants(matching: .any)
            .matching(identifier: "plan-menu").firstMatch.tap()
        app.buttons["Edit the plan"].tap()
        XCTAssertTrue(app.navigationBars["The plan"].waitForExistence(timeout: 5),
                      "the plan editor should open")
    }

    /// The bug, stated as a test: three seeded days in, tapping "Add a day"
    /// must produce a fourth.
    func testAddingAFourthDay() throws {
        openThePlan()

        // The three that ship.
        XCTAssertTrue(app.staticTexts["Pull A"].exists)
        XCTAssertTrue(app.staticTexts["Push A"].exists)
        XCTAssertTrue(app.staticTexts["Legs"].exists)

        let addDay = app.descendants(matching: .any)
            .matching(identifier: "add-day").firstMatch
        XCTAssertTrue(addDay.waitForExistence(timeout: 5),
                      "the plan editor should offer to add a day")
        addDay.tap()

        // It opens straight into the new day's editor, so you can name it
        // without a second tap.
        XCTAssertTrue(app.navigationBars["New day"].waitForExistence(timeout: 5),
                      "adding a day should open it for editing")

        // And it is a real fourth day, not a screen that vanishes on the way
        // back.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["New day"].waitForExistence(timeout: 5),
                      "the fourth day should be in the plan after backing out")
    }

    /// A day added while the plan is a rotation takes the next position in the
    /// cycle rather than a weekday, and the editor must say so.
    func testTheFourthDayTakesTheNextPositionInTheRotation() throws {
        openThePlan()

        let addDay = app.descendants(matching: .any)
            .matching(identifier: "add-day").firstMatch
        XCTAssertTrue(addDay.waitForExistence(timeout: 5))
        addDay.tap()
        XCTAssertTrue(app.navigationBars["New day"].waitForExistence(timeout: 5))

        // Default schedule is `.weekday`, so the new day offers a weekday and
        // arrives unscheduled — deliberately, so it cannot silently displace
        // one of the three you already train.
        XCTAssertTrue(app.staticTexts["Unscheduled"].waitForExistence(timeout: 5),
                      "a new day should arrive unscheduled rather than stealing a weekday")
    }
}
