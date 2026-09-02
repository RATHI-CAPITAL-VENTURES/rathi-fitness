import XCTest

/// The dials on a machine, kept with the exercise.
///
/// One of five `WritePathCase` groups — see that file for why they are
/// separate classes rather than one.
final class WritePathMachineTests: WritePathCase {
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

        // On iOS 18 this was the assertion that caught the dial never appearing:
        // the editor walked `exercise.settings`, and a relationship read does not
        // reliably republish when the inverse side is inserted. It is a `@Query`
        // now, like every other screen that shows a row you just wrote.
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
}
