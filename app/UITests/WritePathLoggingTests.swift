import XCTest

/// Logging a set, and taking one back — lifting and cardio.
///
/// One of five `WritePathCase` groups — see that file for why they are
/// separate classes rather than one.
final class WritePathLoggingTests: WritePathCase {
    // MARK: - logging

    /// `SetView:507` — undo is only offered once the cooldown is out of the
    /// way, so the route there is log, skip the rest, undo.
    func testUndoingASet() {
        let bench = app.descendants(matching: .any)
            .matching(identifier: "row-bench-press").firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10))
        bench.tap()

        let log = app.descendants(matching: .any).matching(identifier: "log-set").firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()

        let skip = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Skip to set'")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))

        skip.tap()

        // This is the first test that taps ANYTHING after logging a set, which
        // is why it is the one that found the notification-permission alert —
        // see `RestTimer.requestPermissionOnce`.
        // This assertion is why `PrimaryButton` has a `contentShape`. Unfilled,
        // its background is `Color.clear`, so the hit area was the glyphs and a
        // one-point stroke — "Skip to set N" drew a 54-point bar and answered to
        // almost none of it. Reproduced on iOS 18, not on iOS 26, which is why
        // it read as a flaky test for two CI runs before it read as a bug.
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5),
                      "a logged set should be undoable once the cooldown is done")
        undo.tap()

        // Back to set 1: the undo really removed the row rather than only
        // hiding the button.
        XCTAssertTrue(app.buttons["Log set 1"].waitForExistence(timeout: 5),
                      "undoing should put you back on the first set")
        shoot("undo-set")
    }

    // MARK: - cardio

    /// `CardioSetView:365` and `:401`. A treadmill has none of a bench's
    /// numbers, so it gets its own screen — and its own chance to be dead.
    func testLoggingACardioPiece() {
        // Put one in today's workout, since nothing is seeded.
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        app.buttons["Add an exercise"].firstMatch.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Treadmill")
        let hit = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Treadmill")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5),
                      "the catalogue should have a treadmill")
        hit.tap()
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Treadmill")).firstMatch
            .waitForExistence(timeout: 5))

        // Out of the plan editor and back to the workout.
        back()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 10))

        let row = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Treadmill")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the treadmill should be in today's workout")
        row.tap()

        let log = app.descendants(matching: .any)
            .matching(identifier: "log-cardio").firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 10),
                      "the cardio screen should offer to log the piece")

        // An all-zero row is not a workout — `hasSomethingToLog` refuses it, so
        // the button is disabled until the odometer has something on it. Put a
        // distance on before pressing, or this test proves only that a disabled
        // button does nothing.
        let more = app.buttons["Increase Distance"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5),
                      "the treadmill should offer a distance to nudge")
        more.tap(); more.tap()
        XCTAssertTrue(log.isEnabled, "with a distance on the clock it should be loggable")
        log.tap()

        // A single bout closes the screen — `log()` ends `else if isFinished {
        // dismiss() }`, deliberately, because starting a cooldown after the only
        // thing you came to do would be the app asking you to stand next to a
        // treadmill for ninety seconds. So undo is reached by going back in,
        // not by staying put.
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 10),
                      "logging the only bout should hand you back to today")
        shoot("cardio-logged")

        let again = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Treadmill")).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()

        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10),
                      "a logged cardio piece should be undoable on the way back in")
        XCTAssertTrue(app.buttons["Log another"].firstMatch.exists,
                      "a finished piece offers another rather than the first")
        undo.tap()

        XCTAssertTrue(app.buttons["Log it"].firstMatch.waitForExistence(timeout: 5),
                      "undoing should put it back to nothing logged")
    }
}
