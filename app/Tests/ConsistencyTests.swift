import XCTest
@testable import RathiFitness

/// Showing up, measured against the plan rather than the calendar.
///
/// The properties worth protecting are all about what the band refuses to say:
/// it does not count a week that has not finished, it does not let a big week
/// pay for a missed one, and it does not invent weeks before your first
/// workout. Each of those is a way a consistency number could quietly flatter
/// or scold, which is the whole reason this is not a streak.
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

    /// Ishan's: Tue, Thu, Sat — three workouts a week.
    private var config: Rotation.Config {
        Rotation.Config(mode: .rotation, trainingWeekdays: [3, 5, 7])
    }

    /// Monday. The week it belongs to started Sunday 30 August.
    private var now: Date { date(2026, 8, 31) }

    private func band(_ sessions: [Date],
                      config: Rotation.Config? = nil,
                      plannedDays: Int = 4,
                      weeks: Int = 12) -> Tally.Consistency {
        Tally.consistency(sessionDates: sessions,
                          config: config ?? self.config,
                          plannedDays: plannedDays,
                          weeks: weeks,
                          now: now,
                          calendar: cal)
    }

    // MARK: how many workouts a week is the plan

    func testWeeklyTargetPerMode() {
        XCTAssertEqual(Tally.weeklyTarget(config, plannedDays: 4), 3,
                       "a rotation asks for its chosen weekdays")

        let weekday = Rotation.Config(mode: .weekday)
        XCTAssertEqual(Tally.weeklyTarget(weekday, plannedDays: 4), 4,
                       "a weekday split asks for every day it has")
    }

    func testEveryNDaysTakesTheFloorSoAShortWeekIsNotAFailure() {
        var every = Rotation.Config(mode: .everyNDays)
        // Every 2 days is 3.5 workouts a week. A 3-workout week must count.
        every.everyNDays = 2
        XCTAssertEqual(Tally.weeklyTarget(every, plannedDays: 4), 3)
        every.everyNDays = 1
        XCTAssertEqual(Tally.weeklyTarget(every, plannedDays: 4), 7)
        every.everyNDays = 3
        XCTAssertEqual(Tally.weeklyTarget(every, plannedDays: 4), 2)
        // Longer than a week still asks for one, never zero — a target of zero
        // would make every week vacuously met.
        every.everyNDays = 9
        XCTAssertEqual(Tally.weeklyTarget(every, plannedDays: 4), 1)
    }

    // MARK: the shape of the band

    /// Four weeks: one thin, one short, one met, and the week in progress.
    private var fourWeeks: [Date] {
        [date(2026, 8, 15),                                       // wk of  9 Aug
         date(2026, 8, 18), date(2026, 8, 20),                    // wk of 16 Aug
         date(2026, 8, 25), date(2026, 8, 27), date(2026, 8, 29), // wk of 23 Aug
         date(2026, 8, 31)]                                       // in progress
    }

    func testBandRunsOldestFirstAndCountsEachWeekAgainstThePlan() {
        let result = band(fourWeeks)

        XCTAssertEqual(result.weeks.count, 4)
        XCTAssertEqual(result.weeks.map(\.done), [1, 2, 3, 1])
        XCTAssertEqual(result.weeks.map(\.planned), [3, 3, 3, 3])
        XCTAssertEqual(result.weeks.map(\.met), [false, false, true, false])
        XCTAssertEqual(result.weeks.first?.start, date(2026, 8, 9).startOfWeek(cal),
                       "oldest first, so the strip reads like a calendar")
    }

    func testTheWeekInProgressIsMarkedAndLeftOutOfThePercentage() {
        let result = band(fourWeeks)

        XCTAssertEqual(result.weeks.filter(\.inProgress).count, 1)
        XCTAssertTrue(result.weeks.last?.inProgress == true)

        // 1 + 2 + 3 credited out of 3 + 3 + 3 planned. The Monday session is
        // in neither half — a week that has barely started cannot be scored.
        XCTAssertEqual(result.credited, 6)
        XCTAssertEqual(result.planned, 9)
        XCTAssertEqual(try XCTUnwrap(result.adherence), 6.0 / 9.0, accuracy: 0.0001)
    }

    func testNothingBeforeYourFirstWorkoutCountsAsAMissedWeek() {
        // One session, three weeks ago. The band is three weeks long, not
        // twelve — a fresh install must not open on nine failures it did not
        // earn.
        let result = band([date(2026, 8, 18)])
        XCTAssertEqual(result.weeks.count, 3)
        XCTAssertEqual(result.weeks.first?.start, date(2026, 8, 16).startOfWeek(cal))
    }

    func testNoSessionsAtAllIsEmptyRatherThanZeroPercent() {
        let result = band([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.adherence)
        XCTAssertEqual(result.credited, 0)
    }

    func testTheBandIsCappedAtItsWindow() {
        // A year of training every Saturday, well past the twelve-week window.
        let sessions = (0..<52).compactMap {
            cal.date(byAdding: .weekOfYear, value: -$0, to: date(2026, 8, 29))
        }
        XCTAssertEqual(band(sessions).weeks.count, 12)
        XCTAssertEqual(band(sessions, weeks: 4).weeks.count, 4)
    }

    // MARK: what it refuses to flatter

    func testABigWeekCannotPayForAMissedOne() {
        // Six workouts one week, none the next, against a target of three.
        // Uncapped this reads 100%; consistency is not a quarterly total.
        let binge = [date(2026, 8, 16), date(2026, 8, 17), date(2026, 8, 18),
                     date(2026, 8, 19), date(2026, 8, 20), date(2026, 8, 21)]
        let result = band(binge)

        XCTAssertEqual(result.weeks.map(\.done), [6, 0, 0])
        XCTAssertEqual(result.credited, 3, "capped at that week's target")
        XCTAssertEqual(result.planned, 6)
        XCTAssertEqual(try XCTUnwrap(result.adherence), 0.5, accuracy: 0.0001)
    }

    func testAnOverfullWeekIsAFullWeekAndNotMore() {
        let week = band([date(2026, 8, 17), date(2026, 8, 18),
                         date(2026, 8, 19), date(2026, 8, 20),
                         date(2026, 8, 21)])
        let first = try? XCTUnwrap(week.weeks.first)
        XCTAssertEqual(first?.done, 5)
        XCTAssertEqual(first?.fraction, 1, "the mark fills once and stops")
        XCTAssertEqual(first?.met, true)
    }

    /// Sessions, not days — the same unit `Rotation.index` counts, and the one
    /// v0.3.1 settled on. Two workouts on a Saturday are two workouts; the
    /// plan asks for workouts, not attendances.
    func testTwoWorkoutsInADayCountTwice() {
        var morning = DateComponents(year: 2026, month: 8, day: 22, hour: 7)
        var evening = morning; evening.hour = 18
        let result = band([cal.date(from: morning)!, cal.date(from: evening)!])

        XCTAssertEqual(result.weeks.first?.done, 2)
    }

    func testAWeekYouTrainedButCameUpShortIsNotTheSameAsOneYouMissed() {
        let short = band([date(2026, 8, 18), date(2026, 8, 20)]).weeks.first
        XCTAssertEqual(short?.done, 2)
        XCTAssertEqual(short?.met, false)
        XCTAssertEqual(try XCTUnwrap(short?.fraction), 2.0 / 3.0, accuracy: 0.0001,
                       "the mark is short, not empty — the band draws the difference")
    }

    func testAPlanWithNoDaysHasNothingToMeasureAgainst() {
        let weekday = Rotation.Config(mode: .weekday)
        XCTAssertTrue(band([date(2026, 8, 18)], config: weekday, plannedDays: 0).isEmpty)
    }
}

private extension Date {
    /// The start of the week this date falls in, for asserting on boundaries.
    func startOfWeek(_ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? self
    }
}
