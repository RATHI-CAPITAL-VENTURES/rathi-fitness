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
        XCTAssertTrue(search.waitForExistence(timeout: 15), "the cardio picker should open")
        XCTAssertTrue(app.navigationBars["Add cardio"].exists)
        search.tap()
        // On a loaded Mac the field can take a beat to own the keyboard, and
        // typing before it does fails "neither element nor any descendant has
        // keyboard focus".
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        search.typeText(machine)
        let hit = text(containing: machine)
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "the catalogue should have a \(machine)")
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

    /// The review's scenario, by finger: ride, start the optional day and lift,
    /// ride again from the "Cardio today" row, lift again. The second ride used
    /// to close the workout, and the next lift opened a second one.
    func testARideFromTheRowMidWorkoutDoesNotSplitIt() {
        launch(["-RFRestDay"])
        XCTAssertTrue(element("add-cardio").waitForExistence(timeout: 20))
        element("add-cardio").tap()
        logCardio("Rower")
        XCTAssertTrue(element("start-optional-day").waitForExistence(timeout: 10))
        element("start-optional-day").tap()

        let liftOnce = {
            // The first row of whatever is on offer — which workout that is
            // depends on the weekday the test runs (Legs on a Thursday, Push A
            // on CI's Friday), so no exercise is named here.
            let row = self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'row-'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the optional workout has a first row")
            row.tap()
            // Still cooling down from the last set: "Log set" waits behind it.
            let skip = self.app.buttons.containing(
                NSPredicate(format: "label BEGINSWITH 'Skip to set'")).firstMatch
            if skip.waitForExistence(timeout: 3) { skip.tap() }
            let log = self.element("log-set")
            XCTAssertTrue(log.waitForExistence(timeout: 10))
            log.tap()
            self.app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        liftOnce()

        let ride = element("cardio-rower")
        XCTAssertTrue(ride.waitForExistence(timeout: 10), "the morning ride is still listed")
        ride.tap()
        let log = element("log-cardio")
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "Extra · not part of the plan").exists,
                      "mid-workout, the ride goes into the workout")
        let more = app.buttons["Increase Distance"].firstMatch
        more.tap(); more.tap()
        log.tap()

        liftOnce()
        XCTAssertTrue(text(containing: "set 2 of").waitForExistence(timeout: 10),
                      "both squat sets are in one workout")
        XCTAssertFalse(text(containing: "workout 2").exists, "and there is only one workout")
        shoot("ride-mid-workout")
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
