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
                      target: Int = 4,
                      weeks: Int = 12) -> Tally.Consistency {
        Tally.consistency(sessions: sessions,
                          targets: Tally.Targets(constant: target),
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
        XCTAssertTrue(band([did(date(2026, 8, 24), "Leg Day")], target: 0).isEmpty)
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
    // MARK: the target as it was

    /// **The one this was rebuilt for.** Going from three days a week to four
    /// turned every finished week into a miss, retroactively: weeks already
    /// trained and already complete became 3-of-4 because of a setting changed
    /// afterwards.
    func testChangingYourScheduleDoesNotRewriteFinishedWeeks() {
        let week = [did(date(2026, 8, 24), plan[0]),
                    did(date(2026, 8, 25), plan[1]),
                    did(date(2026, 8, 27), plan[2])]
        let targets = Tally.Targets([(from: date(2026, 8, 1), weekly: 3),
                                     (from: date(2026, 8, 31), weekly: 4)])
        let b = Tally.consistency(sessions: week, targets: targets,
                                  weeks: 4, now: now, calendar: cal)
        let finished = b.weeks.last { !$0.inProgress }
        XCTAssertEqual(finished?.planned, 3, "that week was asked for three")
        XCTAssertTrue(finished?.met ?? false, "and three is what it got")
    }

    func testTheNewTargetAppliesToTheWeeksAfterIt() {
        let targets = Tally.Targets([(from: date(2026, 8, 1), weekly: 3),
                                     (from: date(2026, 8, 31), weekly: 4)])
        XCTAssertEqual(targets.weekly(on: date(2026, 8, 24)), 3)
        XCTAssertEqual(targets.weekly(on: date(2026, 8, 31)), 4, "on the day it starts")
        XCTAssertEqual(targets.weekly(on: date(2026, 9, 7)), 4)
    }

    /// A week older than any recorded schedule takes the earliest known target
    /// rather than zero — zero would score every ancient week as perfect.
    func testWeeksOlderThanAnyRecordedScheduleTakeTheEarliestTarget() {
        let targets = Tally.Targets([(from: date(2026, 8, 31), weekly: 4)])
        XCTAssertEqual(targets.weekly(on: date(2026, 1, 1)), 4)
    }

    func testEpochsAreSortedWhateverOrderTheyArriveIn() {
        let targets = Tally.Targets([(from: date(2026, 8, 31), weekly: 4),
                                     (from: date(2026, 8, 1), weekly: 3)])
        XCTAssertEqual(targets.weekly(on: date(2026, 8, 24)), 3)
    }

    // MARK: the target comes from the schedule, not the plan

    /// **The bug found in use.** Four workouts in the plan and three days a
    /// week is not a 75% week — the fourth workout was never going to happen,
    /// because there is no fourth day to do it on.
    func testAFourWorkoutPlanTrainedThreeDaysCanBeAFullWeek() {
        let config = Rotation.Config(mode: .rotation, trainingWeekdays: [3, 5, 7])
        XCTAssertEqual(Rotation.weeklyTarget(config, plannedWorkouts: 4), 3)
    }

    /// And the other way: a schedule asking for four days against a
    /// three-workout plan is asking for a workout that does not exist.
    func testAScheduleCannotAskForMoreWorkoutsThanThePlanHas() {
        let config = Rotation.Config(mode: .rotation, trainingWeekdays: [2, 3, 5, 7])
        XCTAssertEqual(Rotation.weeklyTarget(config, plannedWorkouts: 3), 3)
    }

    func testEveryNDaysTakesTheFloor() {
        let config = Rotation.Config(mode: .everyNDays, everyNDays: 2)
        XCTAssertEqual(Rotation.weeklyTarget(config, plannedWorkouts: 10), 3,
                       "every 2 days is 3.5 a week; a 3-session week is not a failure")
    }

    // MARK: time away

    private func away(_ from: Date, _ to: Date) -> Tally.Away {
        Tally.Away(from: from, to: to)
    }

    /// The band spans weeks from your FIRST workout onward, so every case needs
    /// one to anchor it — `[]` produces an empty band and nothing to inspect.
    /// 17 Aug is a Monday, in a week none of these trips touch.
    private var anchorSession: Tally.Done { did(date(2026, 8, 17), plan[0]) }

    private func band(_ sessions: [Tally.Done], away: [Tally.Away],
                      target: Int = 4, weeks: Int = 12) -> Tally.Consistency {
        Tally.consistency(sessions: sessions, targets: Tally.Targets(constant: target),
                          away: away, weeks: weeks, now: now, calendar: cal)
    }

    /// **The whole point.** A fortnight abroad used to read exactly like a
    /// fortnight of not bothering, and the percentage carried it for months.
    func testAWeekYouWereAwayIsLeftOutOfThePercentage() {
        let scored = band([did(date(2026, 8, 17), plan[0])], away: [])
        let setAside = band([did(date(2026, 8, 17), plan[0])],
                            away: [away(date(2026, 8, 24), date(2026, 8, 30))])
        XCTAssertGreaterThan(setAside.adherence ?? 0, scored.adherence ?? 0,
                             "the missed week should stop counting against you")
        XCTAssertLessThan(setAside.planned, scored.planned,
                          "and leave the denominator too")
    }

    /// NOT counted as met. "You did your four workouts" is a claim about
    /// something that did not happen.
    func testAnAwayWeekIsNotCreditedAsDone() {
        let b = band([anchorSession], away: [away(date(2026, 8, 24), date(2026, 8, 30))])
        XCTAssertEqual(b.credited, 1, "only the anchor week is scored")
        let week = b.weeks.first { $0.isAway }
        XCTAssertNotNil(week)
        XCTAssertFalse(week?.met ?? true, "an away week is set aside, not won")
    }

    /// Training on holiday shows, and changes nothing. A bonus, not a score.
    func testTrainingWhileAwayShowsButDoesNotScore() {
        let trip = [away(date(2026, 8, 24), date(2026, 8, 30))]
        let idle = band([anchorSession], away: trip)
        let trained = band([anchorSession,
                            did(date(2026, 8, 25), plan[1]),
                            did(date(2026, 8, 26), plan[2])], away: trip)
        XCTAssertEqual(trained.credited, idle.credited, "it cannot help the number")
        XCTAssertEqual(trained.planned, idle.planned, "or move the denominator")
        XCTAssertEqual(trained.weeks.first { $0.isAway }?.done, 2,
                       "but the band still knows you trained")
    }

    /// Per week, because that is the unit the band measures in. A Thursday-to-
    /// Sunday trip takes the week; pro-rating a target that counts whole
    /// workouts would ask for 2.3 of them.
    func testAnyDayAwaySetsTheWholeWeekAside() {
        let b = band([anchorSession], away: [away(date(2026, 8, 27), date(2026, 8, 30))])
        XCTAssertEqual(b.weeks.filter(\.isAway).count, 1)
    }

    func testATripSpanningTwoWeeksSetsBothAside() {
        let b = band([anchorSession], away: [away(date(2026, 8, 20), date(2026, 8, 26))])
        XCTAssertEqual(b.weeks.filter(\.isAway).count, 2)
    }

    /// `endedAt` is inclusive — a trip ending on the Sunday covers the Sunday,
    /// not up to the Sunday.
    func testTheLastDayOfATripIsPartOfIt() {
        // 30 Aug 2026 is a Sunday: the last day of the Monday-first week.
        let b = band([anchorSession], away: [away(date(2026, 8, 30), date(2026, 8, 30))])
        XCTAssertEqual(b.weeks.filter(\.isAway).count, 1,
                       "a one-day trip on the Sunday still covers that week")
    }

    /// A range entered backwards covers the same days rather than none — easy
    /// to do on a date picker and impossible to see.
    func testABackwardsRangeStillCoversItsDays() {
        let b = band([anchorSession], away: [away(date(2026, 8, 30), date(2026, 8, 24))])
        XCTAssertEqual(b.weeks.filter(\.isAway).count, 1)
    }

    func testNoTripsChangesNothing() {
        let sessions = [did(date(2026, 8, 24), plan[0]), did(date(2026, 8, 26), plan[1])]
        XCTAssertEqual(band(sessions, away: []).adherence,
                       Tally.consistency(sessions: sessions,
                                         targets: Tally.Targets(constant: 4),
                                         weeks: 12, now: now, calendar: cal).adherence)
    }

    /// Every week away is not a divide by zero and not 0%.
    func testAwayForEveryWeekHasNoPercentageRatherThanZero() {
        let b = band([did(date(2026, 8, 17), plan[0])],
                     away: [away(date(2026, 8, 1), date(2026, 9, 30))])
        XCTAssertNil(b.adherence, "nothing was scored, so there is no score")
        XCTAssertEqual(b.planned, 0)
    }

}
