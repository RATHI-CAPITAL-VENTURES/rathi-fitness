import XCTest
@testable import RathiFitness

/// Showing up, measured as **coverage of the plan**.
///
/// v0.4.0 measured attendance: sessions counted against a target derived from
/// the schedule's training weekdays. On a four-workout plan that answered a
/// question nobody asked and sat near half of whatever you did, because the
/// target came from weekdays while the plan came from workouts.
///
/// The question is "did I get round to each of my workouts this week". So the
/// unit is a DISTINCT workout covered, and the target is the size of the plan.
/// Which weekday you did Legs on is not a fact about consistency.
///
/// The three refusals from v0.4.0 were right and are kept: no scoring a week
/// that has not finished, no letting a big week pay for a missed one, and no
/// inventing weeks before your first workout. Each is a way the number could
/// quietly flatter or scold, which is why this is not a streak.
final class ConsistencyTests: XCTestCase {

    /// Fixed rather than `.current`: week boundaries depend on `firstWeekday`,
    /// and a test whose answer changes with the machine's locale is not a test.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1          // Sunday
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 7))!
    }

    /// Monday. The week it belongs to started Sunday 30 August.
    private var now: Date { date(2026, 8, 31) }

    /// Ishan's plan, which is what sent this back for a rewrite.
    private let plan = ["Arms and Abs", "Leg Day", "Shoulders and Back", "Chest and Abs"]

    private func did(_ d: Date, _ workout: String) -> Tally.Done {
        Tally.Done(date: d, workout: workout)
    }

    private func band(_ sessions: [Tally.Done],
                      plannedWorkouts: Int = 4,
                      weeks: Int = 12) -> Tally.Consistency {
        Tally.consistency(sessions: sessions,
                          plannedWorkouts: plannedWorkouts,
                          weeks: weeks,
                          now: now,
                          calendar: cal)
    }

    // MARK: coverage, not attendance

    /// The bug, stated as a test. Two Shoulders sessions in one week is one of
    /// four workouts covered — you have not done Leg Day by doing Shoulders
    /// again, and a number that says otherwise is measuring turning up.
    func testTheSameWorkoutTwiceCoversItOnce() {
        let week = [did(date(2026, 8, 24), "Shoulders and Back"),
                    did(date(2026, 8, 25), "Shoulders and Back"),
                    did(date(2026, 8, 26), "Shoulders and Back")]
        let b = band(week)
        XCTAssertEqual(b.weeks.last(where: { !$0.inProgress })?.done, 1,
                       "three Shoulders sessions cover one workout, not three")
    }

    func testCoveringEveryWorkoutIsAFullWeek() {
        let week = plan.enumerated().map { i, w in did(date(2026, 8, 24 + i), w) }
        let finished = band(week).weeks.last { !$0.inProgress }
        XCTAssertEqual(finished?.done, 4)
        XCTAssertTrue(finished?.met ?? false)
        XCTAssertEqual(band(week).adherence, 1.0)
    }

    /// "Fine if not on the actual day." All four on consecutive days, none of
    /// them the day the schedule would have picked, is still a full week.
    func testTheDayOfTheWeekIsNotPartOfTheQuestion() {
        let crammed = plan.enumerated().map { i, w in did(date(2026, 8, 27 + i % 3), w) }
        XCTAssertEqual(band(crammed).weeks.last { !$0.inProgress }?.done, 4)
    }

    /// A two-a-day of two DIFFERENT workouts is two covered — the distinctness
    /// is about the workout, not the date.
    func testTwoDifferentWorkoutsOnOneDayCoverTwo() {
        let day = [did(date(2026, 8, 25), "Leg Day"),
                   did(date(2026, 8, 25), "Chest and Abs")]
        XCTAssertEqual(band(day).weeks.last { !$0.inProgress }?.done, 2)
    }

    // MARK: the three refusals, kept

    func testTheWeekInProgressIsMarkedAndLeftOutOfThePercentage() {
        let b = band([did(date(2026, 8, 24), "Leg Day"),
                      did(date(2026, 8, 31), "Leg Day")])
        XCTAssertTrue(b.weeks.last?.inProgress ?? false, "this week is in progress")
        XCTAssertEqual(b.planned, 4, "only the one finished week is scored")
        XCTAssertEqual(b.credited, 1)
    }

    func testABigWeekCannotPayForAMissedOne() {
        let lopsided = plan.enumerated().map { i, w in did(date(2026, 8, 17 + i), w) }
        let b = band(lopsided)                       // then a week of nothing
        XCTAssertEqual(b.planned, 8, "two finished weeks")
        XCTAssertEqual(b.credited, 4, "a full week and an empty one")
        XCTAssertEqual(b.adherence, 0.5)
    }

    func testNothingBeforeYourFirstWorkoutCountsAsAMissedWeek() {
        let b = band([did(date(2026, 8, 24), "Leg Day")])
        XCTAssertEqual(b.weeks.count, 2, "the first week, and the one in progress")
    }

    func testNoSessionsAtAllIsEmptyRatherThanZeroPercent() {
        let b = band([])
        XCTAssertTrue(b.isEmpty)
        XCTAssertNil(b.adherence, "a fresh install has not failed at anything")
    }

    // MARK: shape

    func testBandRunsOldestFirst() {
        let b = band([did(date(2026, 8, 17), "Leg Day")])
        let starts = b.weeks.map(\.start)
        XCTAssertEqual(starts, starts.sorted(), "the strip reads left to right")
    }

    func testTheBandIsCappedAtItsWindow() {
        let long = (0..<30).map { did(date(2026, 2, 1).addingTimeInterval(Double($0) * 604_800),
                                      "Leg Day") }
        XCTAssertLessThanOrEqual(band(long, weeks: 12).weeks.count, 12)
    }

    func testAWeekYouTrainedButCameUpShortIsNotTheSameAsOneYouMissed() {
        let short = band([did(date(2026, 8, 24), "Leg Day"),
                          did(date(2026, 8, 26), "Chest and Abs")])
        let none = band([did(date(2026, 8, 17), "Leg Day")])
        XCTAssertGreaterThan(short.credited, 0)
        XCTAssertNotEqual(short.weeks.last { !$0.inProgress }?.done,
                          none.weeks.last { !$0.inProgress }?.done)
    }

    func testAPlanWithNoWorkoutsHasNothingToMeasureAgainst() {
        XCTAssertTrue(band([did(date(2026, 8, 24), "Leg Day")], plannedWorkouts: 0).isEmpty)
    }

    /// A workout you have since deleted from the plan still happened, and still
    /// covers something — but it cannot push a week past full.
    func testAnOverfullWeekIsAFullWeekAndNotMore() {
        var week = plan.enumerated().map { i, w in did(date(2026, 8, 24 + i), w) }
        week.append(did(date(2026, 8, 28), "Some Old Workout"))
        let finished = band(week).weeks.last { !$0.inProgress }
        XCTAssertEqual(finished?.fraction, 1.0, "five covered against four is a full week")
        XCTAssertEqual(band(week).adherence, 1.0, "and not more than full")
    }
}
