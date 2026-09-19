import XCTest

/// The treadmills are taken. Hold the row, pick something else, and the plan
/// is none the wiser.
///
/// The rules live in `SwapTests`. This is the part only a finger can check:
/// that the long-press menu is reachable on a row that is also a navigation
/// link, that the picker comes up, and that the row changes under you.
final class SwapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-RFDay", "Push A", "-RFSilent"]
        app.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        app.launchEnvironment["RF_UITEST"] = "1"
        app.launch()
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func row(_ slug: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "row-\(slug)").firstMatch
    }

    /// A context menu item exists in the hierarchy before it will take a tap:
    /// tapped while the menu is still springing open, the touch lands on the
    /// dimming view and DISMISSES the menu, so the action never runs and the
    /// test reports a missing sheet. Measured, not guessed — the first version
    /// of this test failed exactly that way, with the one-time hint still on
    /// screen as proof the action had not fired.
    private func tapOnceSettled(_ element: XCUIElement) {
        let settled = expectation(for: NSPredicate(format: "isHittable == true"),
                                  evaluatedWith: element)
        wait(for: [settled], timeout: 5)
        Thread.sleep(forTimeInterval: 0.6)
        element.tap()
    }

    func testSwappingAnExerciseForTodayAndBack() throws {
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20))
        let bench = row("bench-press")
        XCTAssertTrue(bench.waitForExistence(timeout: 5))

        // 1. Hold the row. The menu, not the set screen.
        bench.press(forDuration: 1.2)
        let swap = app.buttons["Do something else today"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5),
                      "a long-press on a row should offer the swap")
        shoot("01-menu")
        tapOnceSettled(swap)

        // 2. The picker, titled with what is being replaced.
        XCTAssertTrue(app.navigationBars["Instead of Bench Press"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Dumbbell Bench")
        shoot("02-picker")
        let pick = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Dumbbell Bench Press'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5),
                      "the catalogue should be reachable from the swap picker")
        pick.tap()

        // 3. The row is the stand-in now, and says whose place it is in.
        let standIn = row("dumbbell-bench-press")
        XCTAssertTrue(standIn.waitForExistence(timeout: 5),
                      "the slot should show what is being done instead")
        XCTAssertFalse(row("bench-press").exists)
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'for Bench Press'")).firstMatch.exists)
        shoot("03-swapped")

        // 4. The set screen agrees, and does not offer the bench's 185.
        standIn.tap()
        // `[c]`: the eyebrow style upper-cases what it is given.
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label ==[c] 'Today, instead of Bench Press'"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["185"].exists,
                       "185 lb is a fact about the barbell bench")
        shoot("04-set-screen")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 5. And back.
        XCTAssertTrue(standIn.waitForExistence(timeout: 5))
        standIn.press(forDuration: 1.2)
        let back = app.buttons["Back to Bench Press"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        tapOnceSettled(back)
        XCTAssertTrue(row("bench-press").waitForExistence(timeout: 5))
        XCTAssertFalse(row("dumbbell-bench-press").exists)
        shoot("05-back")
    }
}
