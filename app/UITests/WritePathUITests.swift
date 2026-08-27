import XCTest

/// Every control in this app that writes something, pressed by a finger.
///
/// "Add a day" was dead in every release through v0.1.1 and nothing noticed,
/// because nothing had ever pressed it. That is not a fact about one button —
/// there were **18** `context.insert`/`delete` sites in `Views/` and the suite
/// reached about four of them. Any of the other fourteen could have been dead
/// for the same reason and nobody would have known until the week they were
/// needed.
///
/// The set is finite, so it gets covered rather than sampled — the same
/// argument the plan makes for wrapping an API's whole surface instead of the
/// three fields today needs. Each test presses the real control and then
/// asserts the data is really there, because "the sheet closed" and "the row
/// was written" are different claims and only the second one matters.
///
/// Cardio needs a cardio exercise inside the day the test forces open, so
/// `testLoggingACardioPiece` builds one through the UI first — add a treadmill
/// to Push A, leave the plan, then log it from Today. Longer than the others,
/// and the only honest way to press that particular button.
final class WritePathUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-RFDay", "Push A"]
        app.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        app.launchEnvironment["RF_UITEST"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20),
                      "the app should open on a workout")
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openThePlan() {
        app.descendants(matching: .any).matching(identifier: "plan-menu").firstMatch.tap()
        app.buttons["Edit the plan"].tap()
        XCTAssertTrue(app.navigationBars["The plan"].waitForExistence(timeout: 5))
    }

    private func openSettings() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// From a plan item's editor into its dials. The route is the "Machine
    /// settings" `DisclosureRow` — worth naming rather than groping for,
    /// because a lookup that happens to match something else is how a test
    /// starts passing for the wrong reason.
    private func openTheMachineEditor() {
        // The static text, not `app.buttons`. A `DisclosureRow` is a
        // `NavigationLink` wrapping a `SettingRow`, and the label inside it is
        // what XCUITest can reach — querying buttons finds nothing here.
        let dials = app.staticTexts["Machine settings"].firstMatch
        XCTAssertTrue(dials.waitForExistence(timeout: 5),
                      "the plan item should link to its machine settings")
        dials.tap()
        XCTAssertTrue(app.buttons["Add a dial"].firstMatch.waitForExistence(timeout: 5),
                      "the machine editor should offer to add a dial")
    }

    /// Back out of whatever is pushed. The first toolbar button is the one that
    /// goes back — matching by index because the label is a chevron.
    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // MARK: - the plan

    /// `PlanView:129` — deleteDays.
    func testDeletingADay() {
        openThePlan()
        XCTAssertTrue(app.staticTexts["Legs"].exists)

        // The swipe has to land on the row, not on the label inside it.
        let row = app.cells.containing(.staticText, identifier: "Legs").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5),
                      "swiping a day should offer to delete it")
        delete.tap()

        XCTAssertFalse(app.staticTexts["Legs"].waitForExistence(timeout: 3),
                       "the day should be gone from the plan")
        shoot("delete-day")
    }

    /// `PlanView:659` — a lift that is in neither your log nor the catalogue.
    func testCreatingAnExerciseThatDoesNotExistYet() {
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))

        app.buttons["Add an exercise"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add an exercise"].waitForExistence(timeout: 5))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Zercher Carry")

        let create = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Create")).firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5),
                      "a name in neither the log nor the catalogue should offer to be created")
        create.tap()

        XCTAssertTrue(app.staticTexts["Zercher Carry"].waitForExistence(timeout: 5),
                      "the invented lift should be in the day")
        shoot("create-exercise")
    }

    /// `PlanView:691` — straight from the catalogue, which arrives knowing what
    /// it works.
    func testAddingAnExerciseFromTheCatalogue() {
        openThePlan()
        app.staticTexts["Legs"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Legs"].waitForExistence(timeout: 5))

        app.buttons["Add an exercise"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Bulgarian")

        let hit = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Bulgarian")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5),
                      "the catalogue should match on a partial name")
        hit.tap()

        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Bulgarian")).firstMatch
            .waitForExistence(timeout: 5),
            "the catalogue lift should be in the day")
        shoot("add-from-catalogue")
    }

    /// `PlanView:304` — removing a slot renumbers the rest.
    func testRemovingAnExerciseFromADay() {
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lateral Raise"].exists)

        app.staticTexts["Lateral Raise"].firstMatch.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        XCTAssertFalse(app.staticTexts["Lateral Raise"].waitForExistence(timeout: 3),
                       "the slot should be gone from the day")
        shoot("remove-exercise")
    }

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

        // Undo is only offered when the cooldown is not running, so the rest has
        // to be skipped first — and a tap that lands mid-render does nothing,
        // leaving a 150-second ring counting down and this test waiting for a
        // button that will not appear for two and a half minutes. That is not a
        // hypothetical: it passed on a laptop and failed on CI, which is slower.
        // So ask again rather than assuming the first one took.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 where !undo.exists {
            if skip.exists { skip.tap() }
            _ = undo.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(undo.exists,
                      "a logged set should be undoable once the cooldown is done")
        undo.tap()

        // Back to set 1: the undo really removed the row rather than only
        // hiding the button.
        XCTAssertTrue(app.buttons["Log set 1"].waitForExistence(timeout: 5),
                      "undoing should put you back on the first set")
        shoot("undo-set")
    }

    // MARK: - the body

    /// `TodayView:146` — a weigh-in.
    func testLoggingAWeighIn() {
        let add = app.buttons["Log today's weight"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let field = app.textFields["176.4"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.navigationBars["Measurement"].waitForExistence(timeout: 5))
        let field = app.textFields["32.5"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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

    // MARK: - machines

    /// `MachineSettings:168` and `:176` — adding a dial and removing it.
    func testRecordingAndRemovingAMachineDial() {
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        app.staticTexts["Cable Fly"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Cable Fly"].waitForExistence(timeout: 5))

        openTheMachineEditor()

        let add = app.buttons["Add a dial"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the machine editor should offer to add a dial")
        add.tap()

        let seat = app.buttons["Seat"].firstMatch
        XCTAssertTrue(seat.waitForExistence(timeout: 5),
                      "the dial menu should list the seat")
        seat.tap()

        let remove = app.buttons["Remove Seat"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5),
                      "the dial should have been added")
        shoot("machine-dial")
        remove.tap()
        XCTAssertFalse(remove.waitForExistence(timeout: 3),
                       "the dial should be gone again")
    }

    /// `MachineSettings:185` — the last write path, and the one with an opinion
    /// in it: a dial you added and never filled in is one you thought better of,
    /// and keeping it would put an empty chip on the set screen forever. It is
    /// swept on the way out, which means the only way to see it happen is to
    /// leave and come back.
    func testABlankDialIsSweptOnTheWayOut() {
        openThePlan()
        app.staticTexts["Push A"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Push A"].waitForExistence(timeout: 5))
        app.staticTexts["Cable Fly"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Cable Fly"].waitForExistence(timeout: 5))

        openTheMachineEditor()
        app.buttons["Add a dial"].firstMatch.tap()
        let handle = app.buttons["Handle"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.tap()
        XCTAssertTrue(app.buttons["Remove Handle"].firstMatch.waitForExistence(timeout: 5),
                      "the dial should be there before we leave")

        // Out and back in, without ever typing a value. One step back from the
        // dials is the exercise, not the day — the stack is
        // plan → day → exercise → dials.
        back()
        XCTAssertTrue(app.navigationBars["Cable Fly"].waitForExistence(timeout: 5),
                      "one step back from the dials is the exercise")
        openTheMachineEditor()

        XCTAssertFalse(app.buttons["Remove Handle"].firstMatch.waitForExistence(timeout: 3),
                       "a dial left blank should not survive the trip")
        shoot("blank-dial-swept")
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
}
