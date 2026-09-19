import XCTest
@testable import RathiFitness

/// How long you were there: first log to last log.
final class GymTimeTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func log(_ minutes: Double, seconds: Int = 0) -> Tally.Log {
        Tally.Log(date: start.addingTimeInterval(minutes * 60), seconds: seconds)
    }

    func testFirstLogToLastLog() {
        XCTAssertEqual(Tally.gymSeconds([log(0), log(12), log(47)]), 47 * 60)
    }

    /// The query that feeds this sorts newest-first on one screen and
    /// oldest-first on another. The old Today figure was only right because
    /// of which way its array happened to be sorted.
    func testOrderDoesNotMatter() {
        XCTAssertEqual(Tally.gymSeconds([log(47), log(0), log(12)]), 47 * 60)
    }

    func testNothingLoggedIsNoTime() {
        XCTAssertEqual(Tally.gymSeconds([]), 0)
    }

    /// A single lift is an instant, not a duration.
    func testOneSetIsNoTime() {
        XCTAssertEqual(Tally.gymSeconds([log(0)]), 0)
    }

    /// A treadmill is logged when you step OFF. Without this, every workout
    /// that opens with cardio reads twenty minutes short, for ever.
    func testABoutThatOpensTheWorkoutCountsItsOwnLength() {
        let logs = [log(20, seconds: 1200), log(30), log(60)]
        XCTAssertEqual(Tally.gymSeconds(logs), 60 * 60)
    }

    func testACardioOnlyWorkoutIsAsLongAsTheCardio() {
        XCTAssertEqual(Tally.gymSeconds([log(0, seconds: 1500)]), 1500)
    }

    /// Only the FIRST log is pulled back. A finisher is already inside the
    /// span, and adding it again would count those minutes twice.
    func testABoutLaterInTheWorkoutIsNotAddedAgain() {
        let logs = [log(0), log(30), log(55, seconds: 1200)]
        XCTAssertEqual(Tally.gymSeconds(logs), 55 * 60)
    }

    /// Per workout, then summed. The span of every log at once would count
    /// the nights in between.
    func testTheLifetimeTotalDoesNotCountTheNightsBetween() {
        let monday = [log(0), log(45)]
        let wednesday = [log(2880), log(2880 + 60)]
        XCTAssertEqual(Tally.gymSeconds(workouts: [monday, wednesday]), (45 + 60) * 60)
    }

    func testTheUnitFollowsTheSize() {
        XCTAssertEqual(Tally.gymTimeText(47 * 60), "47 min")
        XCTAssertEqual(Tally.gymTimeText(60 * 60), "1 h")
        XCTAssertEqual(Tally.gymTimeText(72 * 60), "1 h 12 min")
        XCTAssertEqual(Tally.gymTimeText(72 * 60), Fmt.minutes(72 * 60),
                       "a workout and the cardio inside it are printed side by side")
        XCTAssertEqual(Tally.gymTimeText(1_312 * 3600 + 40 * 60), "1,312 h")
    }
}
