import XCTest

/// Two workouts in a day, the schedule, and plan-wide defaults.
///
/// One of five `WritePathCase` groups — see that file for why they are
/// separate classes rather than one.
final class WritePathSettingsTests: WritePathCase {
    // MARK: - two-a-days

    /// Lift in the morning, do a different workout in the evening. Before
    /// sessions existed the app could not express that at all: the second
    /// workout opened with the first one's checklist already ticked wherever the
    /// two shared an exercise, and set numbering carried straight on.
    func testASecondWorkoutInADayStartsFresh() {
        // Morning: log a set of the workout that is up.
        let bench = app.descendants(matching: .any)
            .matching(identifier: "row-bench-press").firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10))
        bench.tap()
        let log = app.descendants(matching: .any).matching(identifier: "log-set").firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Skip to set'")).firstMatch
            .waitForExistence(timeout: 5), "a set should have been logged")
        back()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 5))

        // Evening: switch to a different workout from the calendar menu.
        app.descendants(matching: .any).matching(identifier: "plan-menu").firstMatch.tap()
        app.buttons["Legs"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 10),
                      "picking another workout should open it")

        // Logging here opens a SECOND session — the header says which one.
        let squat = app.descendants(matching: .any)
            .matching(identifier: "row-back-squat").firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 5))
        squat.tap()
        let logSquat = app.descendants(matching: .any)
            .matching(identifier: "log-set").firstMatch
        XCTAssertTrue(logSquat.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Log set 1"].firstMatch.exists,
                      "a different workout starts at set 1, not at set 2")
        logSquat.tap()
        back()

        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "workout 2")).firstMatch
            .waitForExistence(timeout: 5),
            "Today should say this is the second workout of the day")
        shoot("two-a-day")
    }

    /// The escape hatch for the same workout twice: finish one, and the next set
    /// starts another.
    func testFinishingAWorkoutIsOfferedOnceOneIsOpen() {
        let menu = app.descendants(matching: .any).matching(identifier: "plan-menu").firstMatch
        menu.tap()
        XCTAssertFalse(app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Finish'")).firstMatch.exists,
            "nothing to finish before anything is logged")
        // Close the menu without choosing anything.
        app.tap()

        let bench = app.descendants(matching: .any)
            .matching(identifier: "row-bench-press").firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 10))
        bench.tap()
        let log = app.descendants(matching: .any).matching(identifier: "log-set").firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        back()

        menu.tap()
        let finish = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Finish'")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5),
                      "an open workout should offer to be finished")
        finish.tap()
        shoot("finish-workout")
    }

    // MARK: - the schedule

    /// `SettingsView:428` — switching to a rotation, which is the change that
    /// makes every day's subtitle re-read itself.
    func testChangingTheSchedule() {
        openSettings()

        // A `ChoiceRow` is a `SettingRow` with a `Menu` in its trailing slot,
        // and the Menu's label is the CURRENT value. "Schedule" is the static
        // text beside it, not the control — matching on it finds nothing.
        let schedule = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Same workout each weekday")).firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 10),
                      "settings should offer the schedule")
        schedule.tap()

        let rotation = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Rotating, on chosen days")).firstMatch
        XCTAssertTrue(rotation.waitForExistence(timeout: 5),
                      "the schedule menu should offer the rotation")
        rotation.tap()

        // The footer rewrites itself from the number of workouts once the mode
        // is a rotation — proof the write landed rather than the menu closing.
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "cycle in the order")).firstMatch
            .waitForExistence(timeout: 5),
            "a rotation should describe itself in terms of the cycle")
        shoot("schedule")
    }
    /// `SettingsView` — `PlanDefaults.applyRestToPlan`.
    ///
    /// The newest control in the app that writes, and a bulk one: it rewrites
    /// every strength slot on every day in a single tap. Exactly the shape that
    /// most wants a finger on it, since "the dialog closed" and "eleven rows
    /// changed" are very different claims.
    func testApplyingRestToTheWholePlan() {
        openSettings()

        let apply = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Apply rest to the whole plan")).firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10),
                      "settings should offer to apply rest across the plan")
        apply.tap()

        // The confirmation names a count, and the count is the reason to trust
        // the button — so the test presses the counted button, not "the first
        // one in the sheet".
        let confirm = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Set ")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "the confirmation should say how many exercises it will change")
        confirm.tap()

        // The result line, which only appears once the write returned — the
        // half of this that "the sheet closed" does not prove.
        let result = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "1:30")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5),
                      "the apply should report what it did")
        shoot("apply-rest")

        // And the data really moved: the plan's own rows quote each item's rest.
        back()
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "90s rest")).firstMatch
            .waitForExistence(timeout: 5),
            "every slot in the day should now quote the applied rest")
    }
}
