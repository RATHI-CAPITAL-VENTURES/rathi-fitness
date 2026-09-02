import XCTest

/// The body, and the passes: weigh-ins, tape measure, QR codes.
///
/// One of five `WritePathCase` groups — see that file for why they are
/// separate classes rather than one.
final class WritePathBodyTests: WritePathCase {
    // MARK: - the body

    /// `TodayView:146` — a weigh-in.
    func testLoggingAWeighIn() {
        let add = app.buttons["Log today's weight"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        // Ten seconds, not five: this waits on a SHEET being presented, which is
        // an animation on a busy machine rather than a state change in the app.
        // It failed once at five while two full suites shared a laptop, and
        // passed alone immediately after — a longer wait is the honest fix,
        // where a retry would have been papering over a state that never came.
        let field = app.textFields["176.4"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("181.2")
        app.buttons["Save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["181.2"].waitForExistence(timeout: 5),
                      "the weigh-in should be on Today straight away")
        shoot("weigh-in")
    }

    /// `TrendsView:89` — a tape measurement.
    func testLoggingAMeasurement() {
        app.tabBars.buttons["Trends"].tap()
        let add = app.buttons["Add a measurement"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        XCTAssertTrue(app.navigationBars["Measurement"].waitForExistence(timeout: 10))
        let field = app.textFields["32.5"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("33.5")
        app.buttons["Save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "33.5")).firstMatch
            .waitForExistence(timeout: 5),
            "the measurement should be on Trends")
        shoot("measurement")
    }

    // MARK: - passes

    /// `PassView:87` — deleting one. The add path is covered by
    /// `WorkoutFlowUITests`; this is the other end of it.
    func testDeletingAPass() {
        app.tabBars.buttons["Pass"].tap()
        app.descendants(matching: .any)
            .matching(identifier: "add-pass-cta").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add a pass"].waitForExistence(timeout: 5))

        let gym = app.textFields["Blink Fitness"]
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        gym.tap(); gym.typeText("Temporary Gym")
        let code = app.textFields["Scan, import or type the code"]
        code.tap(); code.typeText("RF-DELETE-ME-0001")
        app.navigationBars["Add a pass"].buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Temporary Gym"].waitForExistence(timeout: 5))
        app.staticTexts["Temporary Gym"].firstMatch.tap()

        let delete = app.buttons["Delete this pass"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5),
                      "the pass editor should offer to delete it")
        delete.tap()

        XCTAssertFalse(app.staticTexts["Temporary Gym"].waitForExistence(timeout: 3),
                       "the pass should be gone")
        shoot("delete-pass")
    }
}
