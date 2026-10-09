import XCTest

/// The two buttons v0.17.0 added to Today, pressed by a finger.
///
/// `-RFRestDay` makes today a day off whatever the calendar says, so the rest
/// day is tested on a Monday too; `-RFDay` does the same for a lifting day.
/// Each test logs through the real screen and then checks Today says so —
/// "the sheet closed" and "the bout was written" are different claims.
final class OptionalDayUITests: XCTestCase {

    private var app: XCUIApplication!

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += arguments + ["-RFSilent"]
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

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    /// Pick a machine in the cardio picker and log one bout of it.
    private func logCardio(_ machine: String) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the cardio picker should open")
        XCTAssertTrue(app.navigationBars["Add cardio"].exists)
        search.tap()
        search.typeText(machine)
        let hit = text(containing: machine)
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "the catalogue should have a \(machine)")
        hit.tap()

        let log = element("log-cardio")
        XCTAssertTrue(log.waitForExistence(timeout: 10), "picking it should open its cardio screen")
        let more = app.buttons["Increase Distance"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap(); more.tap()
        log.tap()
    }

    func testARestDayOffersTheOptionalDayAndCardioOnItsOwn() {
        launch(["-RFRestDay"])
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 20))
        let start = element("start-optional-day")
        XCTAssertTrue(start.waitForExistence(timeout: 5), "a day off offers the next workout")
        shoot("rest-day")

        element("add-cardio").tap()
        logCardio("Rower")
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 10),
                      "cardio on its own leaves today a rest day")
        XCTAssertTrue(text(containing: "Cardio today").waitForExistence(timeout: 5),
                      "and lists what was done")
        XCTAssertTrue(element("start-optional-day").exists,
                      "a ride does not use up the optional day")
        shoot("rest-day-with-cardio")

        element("start-optional-day").tap()
        XCTAssertTrue(text(containing: "optional day").waitForExistence(timeout: 5),
                      "the workout says it is optional")
        XCTAssertTrue(text(containing: " done").exists, "and shows the plan's checklist")
        shoot("optional-day-started")
    }

    func testCardioAddedToALiftingDayIsOutsideThePlan() {
        launch(["-RFDay", "Push A"])
        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 20))
        let progress = text(containing: " done")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let before = progress.label

        let add = element("add-cardio")
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        logCardio("Treadmill")

        XCTAssertTrue(app.staticTexts["Push A"].waitForExistence(timeout: 10),
                      "logging the bout hands you back to the workout")
        XCTAssertTrue(text(containing: "Extra · not in the plan").waitForExistence(timeout: 5),
                      "the bout is listed in a section of its own")
        XCTAssertEqual(text(containing: " done").label, before,
                       "and it does not move \"N of N done\"")
        XCTAssertFalse(text(containing: "Moved today").exists,
                       "a treadmill has no tonnage; nothing lifted, nothing to report")
        app.swipeUp()
        shoot("lifting-day-with-extra-cardio")
    }
}
