import XCTest

/// Locker 214, by thumb. The rules live in `DayNoteTests`; this is the part
/// only a finger can check — that the chips are reachable on Today, the sheet
/// comes up with the keyboard, and the strip changes under you.
final class DayNotesUITests: XCTestCase {

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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testNotingALockerAndANoteAndTakingTheLockerBack() throws {
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20))
        let addLocker = element("day-note-add-locker")
        XCTAssertTrue(addLocker.waitForExistence(timeout: 5),
                      "an empty day should offer Locker as an outline chip")
        shoot("01-empty")

        // 1. A locker.
        addLocker.tap()
        let field = element("day-note-field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("214")
        shoot("02-sheet")
        app.buttons["Save"].tap()

        let locker = element("day-note-locker")
        XCTAssertTrue(locker.waitForExistence(timeout: 5), "the chip should now be filled")
        XCTAssertTrue(app.staticTexts["Locker 214"].exists, "and read as itself")
        XCTAssertFalse(addLocker.exists, "with no second, empty Locker beside it")

        // 2. A note is a sentence, so it is a line, not a chip.
        element("day-note-add-note").tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Left knee, go easy")
        app.buttons["Save"].tap()
        // The line is a BUTTON — tapping it edits the note — so it is found by
        // its identifier and read by its label, not as static text.
        let noteLine = element("day-note-text")
        XCTAssertTrue(noteLine.waitForExistence(timeout: 5))
        XCTAssertEqual(noteLine.label, "Left knee, go easy")
        XCTAssertFalse(element("day-note-add-note").exists, "and Note is no longer on offer")
        shoot("03-noted")

        // 3. The "etc": your own heading. The sheet must open with a cursor in
        //    the heading — it used to open with two empty fields and no
        //    keyboard, the one kind the first version of this test never opened.
        element("day-note-add-other").tap()
        let heading = element("day-note-heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        app.typeText("Towel")                 // no tap: whatever has focus gets it
        XCTAssertEqual(heading.value as? String, "Towel",
                       "the heading should already have the keyboard")
        app.typeText("\n")                    // Next → the value field
        app.typeText("31")
        app.buttons["Save"].tap()
        let towel = element("day-note-other-towel")
        XCTAssertTrue(towel.waitForExistence(timeout: 5),
                      "a saved Other gets its own identifier, not a shared one")
        XCTAssertTrue(app.staticTexts["Towel 31"].exists)
        XCTAssertTrue(element("day-note-add-other").exists, "and Other is still on offer")
        shoot("04-other")

        // 4. Tap the chip to take it back.
        locker.tap()
        let remove = element("day-note-remove")
        XCTAssertTrue(remove.waitForExistence(timeout: 5),
                      "a saved note should offer Remove by name")
        remove.tap()
        XCTAssertTrue(element("day-note-add-locker").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Locker 214"].exists)
        XCTAssertEqual(element("day-note-text").label, "Left knee, go easy",
                       "the note is untouched")
    }
}
