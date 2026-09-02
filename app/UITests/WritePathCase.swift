import XCTest

/// Every control in this app that writes something, pressed by a finger.
///
/// The launch and the shared navigation live here; the cases live in the
/// `WritePath*Tests` files beside it. Split in v0.4.3 for TIME, not tidiness:
/// XCTest parallelises by CLASS, so fifteen UI tests in one class was one
/// worker doing 311 of the suite's 428 seconds while the others sat idle. The
/// grouping is the `// MARK:` sections this file already had.
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
class WritePathCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-RFDay", "Push A"]
        app.launchArguments += ["-RFSilent"]
        app.launchEnvironment["RF_NO_CLOUDKIT"] = "1"
        app.launchEnvironment["RF_UITEST"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20),
                      "the app should open on a workout")
    }

    func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func openThePlan() {
        app.descendants(matching: .any).matching(identifier: "plan-menu").firstMatch.tap()
        app.buttons["Edit the plan"].tap()
        XCTAssertTrue(app.navigationBars["The plan"].waitForExistence(timeout: 5))
    }

    func openSettings() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// From a plan item's editor into its dials. The route is the "Machine
    /// settings" `DisclosureRow` — worth naming rather than groping for,
    /// because a lookup that happens to match something else is how a test
    /// starts passing for the wrong reason.
    func openTheMachineEditor() {
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
    func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
