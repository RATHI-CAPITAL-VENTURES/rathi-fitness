import XCTest

/// Adding, removing and renaming what is in the plan.
///
/// One of five `WritePathCase` groups — see that file for why they are
/// separate classes rather than one.
final class WritePathPlanTests: WritePathCase {
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
}
