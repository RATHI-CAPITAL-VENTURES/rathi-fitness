import XCTest
import UIKit
@testable import RathiFitness

/// The lifetime numbers: the ladder, the record book, and the calendar.
final class LegacyTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.firstWeekday = 1
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    // MARK: the ladder

    func testTheLadderOnlyEverClimbs() {
        let pounds = Tally.milestones.map(\.pounds)
        XCTAssertEqual(pounds, pounds.sorted(), "a ladder that goes backwards is not a ladder")
        XCTAssertEqual(Swift.Set(pounds).count, pounds.count, "two tiers at one weight")
        XCTAssertEqual(Swift.Set(Tally.milestones.map(\.name)).count, Tally.milestones.count)
    }

    func testNothingLiftedIsTheBottomOfTheLadder() {
        let l = Tally.legacy(total: 0)
        XCTAssertTrue(l.passed.isEmpty, "a fresh install has not passed anything")
        XCTAssertEqual(l.next?.pounds, Tally.milestones.first?.pounds)
        XCTAssertEqual(l.fraction, 0)
    }

    func testPassedAndNextAreEitherSideOfTheTotal() {
        let l = Tally.legacy(total: 6_000)
        XCTAssertEqual(l.passed.last?.pounds, 5_000)
        XCTAssertEqual(l.next?.pounds, 8_000)
        XCTAssertEqual(l.remaining, 2_000)
    }

    /// Exactly on a tier counts as passed. Reaching it is doing it.
    func testLandingExactlyOnATierPassesIt() {
        let l = Tally.legacy(total: 5_000)
        XCTAssertEqual(l.passed.last?.pounds, 5_000)
        XCTAssertEqual(l.next?.pounds, 8_000)
    }

    /// Measured between tiers, not from zero. From 875,000 toward 2,000,000 a
    /// fraction-of-target bar would sit at 44% for a year and look broken.
    func testProgressIsMeasuredFromTheLastTierNotFromZero() {
        let l = Tally.legacy(total: 6_500)          // half of 5,000 -> 8,000
        XCTAssertEqual(l.fraction, 0.5, accuracy: 0.001)
    }

    func testFinishingTheLadderHasNoNext() {
        let l = Tally.legacy(total: 9_000_000)
        XCTAssertNil(l.next)
        XCTAssertNil(l.remaining)
        XCTAssertEqual(l.fraction, 1)
        XCTAssertEqual(l.passed.count, Tally.milestones.count)
    }

    func testAnUnsortedLadderIsSortedRatherThanTrusted() {
        let scrambled = [Tally.Milestone(pounds: 100, name: "b", art: "x"),
                         Tally.Milestone(pounds: 10, name: "a", art: "x")]
        let l = Tally.legacy(total: 50, ladder: scrambled)
        XCTAssertEqual(l.passed.map(\.name), ["a"])
        XCTAssertEqual(l.next?.name, "b")
    }

    // MARK: the record book

    private func entry(_ d: Date, _ name: String, _ w: Double, _ r: Int,
                       assisted: Bool = false) -> (date: Date, exercise: String, set: Tally.Set) {
        (date: d, exercise: name,
         set: Tally.Set(weight: w, reps: r, assisted: assisted))
    }

    /// The first set of a lift beats nothing — there is no history to beat.
    func testTheFirstSetIsNotARecord() {
        let book = Tally.recordBook([entry(day(2026, 8, 1), "Bench", 185, 8)])
        XCTAssertTrue(book.isEmpty)
    }

    func testBeatingYourBestIsRecordedWithItsDateAndLift() {
        let book = Tally.recordBook([
            entry(day(2026, 8, 1), "Bench", 185, 8),
            entry(day(2026, 8, 8), "Bench", 195, 8),
        ])
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book.first?.exercise, "Bench")
        XCTAssertEqual(book.first?.date, day(2026, 8, 8))
        XCTAssertEqual(book.first?.record, .heaviest(195))
    }

    /// One entry per set: the ranked best of what it beat. Three badges for one
    /// set is confetti, which is the same rule `headline` already follows.
    func testASetThatBeatsSeveralThingsGetsOneEntry() {
        let book = Tally.recordBook([
            entry(day(2026, 8, 1), "Bench", 185, 8),
            entry(day(2026, 8, 8), "Bench", 205, 10),
        ])
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book.first?.record, .heaviest(205), "the heaviest is what matters most")
    }

    func testEachLiftIsJudgedAgainstItsOwnHistory() {
        let book = Tally.recordBook([
            entry(day(2026, 8, 1), "Bench", 185, 8),
            entry(day(2026, 8, 2), "Squat", 100, 8),     // first squat, no record
        ])
        XCTAssertTrue(book.isEmpty, "a light squat is not beaten by a heavy bench")
    }

    func testNewestFirst() {
        let book = Tally.recordBook([
            entry(day(2026, 8, 1), "Bench", 185, 8),
            entry(day(2026, 8, 8), "Bench", 195, 8),
            entry(day(2026, 8, 15), "Bench", 205, 8),
        ])
        XCTAssertEqual(book.map(\.date), [day(2026, 8, 15), day(2026, 8, 8)])
    }

    /// Less help is the record on an assisted machine, and more help is never
    /// one — the rule that already holds elsewhere must survive the replay.
    func testLessHelpIsARecordAndMoreHelpIsNot() {
        let better = Tally.recordBook([
            entry(day(2026, 8, 1), "Assisted Dip", 80, 8, assisted: true),
            entry(day(2026, 8, 8), "Assisted Dip", 70, 8, assisted: true),
        ])
        XCTAssertEqual(better.first?.record, .leastAssistance(70))

        let worse = Tally.recordBook([
            entry(day(2026, 8, 1), "Assisted Dip", 70, 8, assisted: true),
            entry(day(2026, 8, 8), "Assisted Dip", 80, 8, assisted: true),
        ])
        XCTAssertTrue(worse.isEmpty, "needing more help is not an achievement")
    }

    func testTheBookIsCapped() {
        let many = (0..<80).map { i in
            entry(day(2026, 1, 1).addingTimeInterval(Double(i) * 86_400),
                  "Bench", 100 + Double(i) * 5, 8)
        }
        XCTAssertEqual(Tally.recordBook(many, limit: 10).count, 10)
    }

    // MARK: the calendar

    func testEveryDayIsPresentIncludingTheEmptyOnes() {
        let days = Tally.activity([(date: day(2026, 8, 31), volume: 1_000)],
                                  weeks: 2, now: day(2026, 8, 31), calendar: cal)
        XCTAssertEqual(days.count, 14, "two whole weeks, gaps included")
        XCTAssertEqual(days.filter { $0.volume > 0 }.count, 1)
    }

    func testDaysRunOldestFirst() {
        let days = Tally.activity([], weeks: 4, now: day(2026, 8, 31), calendar: cal)
        XCTAssertEqual(days.map(\.day), days.map(\.day).sorted())
    }

    func testSeveralSessionsOnOneDayAddUp() {
        let days = Tally.activity([(date: day(2026, 8, 31), volume: 1_000),
                                   (date: day(2026, 8, 31), volume: 500)],
                                  weeks: 2, now: day(2026, 8, 31), calendar: cal)
        XCTAssertEqual(days.first(where: { $0.volume > 0 })?.volume, 1_500,
                       "a two-a-day is one busy square")
    }

    func testAnythingOlderThanTheWindowIsLeftOut() {
        let days = Tally.activity([(date: day(2025, 1, 1), volume: 9_999)],
                                  weeks: 2, now: day(2026, 8, 31), calendar: cal)
        XCTAssertEqual(days.filter { $0.volume > 0 }.count, 0)
        XCTAssertEqual(days.count, 14)
    }
    // MARK: the week starts on Monday

    /// `Calendar.current` is Sunday-first in the US, which cut the week through
    /// the middle of a weekend: Saturday and Sunday landed in different weeks
    /// on both the heatmap and the consistency band.
    func testTheGridStartsOnMondayEvenOnASundayFirstCalendar() {
        var sundayFirst = cal
        sundayFirst.firstWeekday = 1
        // 2 September 2026 is a Wednesday.
        let days = Tally.activity([], weeks: 1,
                                  now: day(2026, 9, 2), calendar: sundayFirst)
        let first = try? XCTUnwrap(days.first?.day)
        XCTAssertEqual(Tally.trainingWeek(cal).component(.weekday, from: first!), 2,
                       "the first square of a week must be a Monday")
    }

    /// The two screens that group by week have to agree about which seven days
    /// a week is, whatever calendar they are handed.
    func testConsistencyAndTheGridAgreeAboutTheWeek() {
        var sundayFirst = cal
        sundayFirst.firstWeekday = 1
        let now = day(2026, 9, 2)

        let grid = Tally.activity([], weeks: 1, now: now, calendar: sundayFirst)
        let band = Tally.consistency(
            sessions: [Tally.Done(date: day(2026, 8, 24), workout: "Leg Day")],
            targets: Tally.Targets(constant: 4), weeks: 2, now: now, calendar: sundayFirst)

        XCTAssertEqual(grid.first?.day, band.weeks.last?.start,
                       "the current week starts on the same day in both")
    }

    /// A Saturday and the Sunday after it are the same training week.
    func testAWeekendIsNotSplitInTwo() {
        var sundayFirst = cal
        sundayFirst.firstWeekday = 1
        let saturday = day(2026, 8, 29)
        let sunday = day(2026, 8, 30)
        let band = Tally.consistency(
            sessions: [Tally.Done(date: saturday, workout: "Leg Day"),
                       Tally.Done(date: sunday, workout: "Chest and Abs")],
            targets: Tally.Targets(constant: 4), weeks: 4,
            now: day(2026, 9, 2), calendar: sundayFirst)
        let scored = band.weeks.filter { !$0.inProgress && $0.done > 0 }
        XCTAssertEqual(scored.count, 1, "both fell in one week")
        XCTAssertEqual(scored.first?.done, 2)
    }

    // MARK: the journey

    private func workout(_ d: Date, _ v: Double) -> (date: Date, volume: Double) {
        (date: d, volume: v)
    }

    /// A tier is crossed by the SESSION that took you past it, not by the day
    /// you happened to open the app.
    func testATierIsDatedToTheWorkoutThatCrossedIt() {
        let j = Tally.journey(sessionVolumes: [
            workout(day(2026, 8, 1), 600),      // under 1,000
            workout(day(2026, 8, 8), 600),      // 1,200 — crosses the piano
        ])
        let piano = j.first { $0.milestone.pounds == 1_000 }
        XCTAssertEqual(piano?.crossedOn, day(2026, 8, 8))
    }

    func testTiersStillAheadHaveNoDate() {
        let j = Tally.journey(sessionVolumes: [workout(day(2026, 8, 1), 1_200)])
        XCTAssertNil(j.first { $0.milestone.pounds == 5_000 }?.crossedOn)
        XCTAssertFalse(j.first { $0.milestone.pounds == 5_000 }?.isPassed ?? true)
    }

    /// One big session can clear several at once, and each of them is dated to
    /// that session rather than only the last one counting.
    func testOneSessionCanCrossSeveralTiers() {
        let j = Tally.journey(sessionVolumes: [workout(day(2026, 8, 1), 6_000)])
        let passed = j.filter(\.isPassed)
        XCTAssertEqual(passed.count, 5, "250, 1,000, 2,000, 2,900 and 5,000")
        XCTAssertTrue(passed.allSatisfy { $0.crossedOn == day(2026, 8, 1) })
    }

    func testTheLadderComesBackWholeOldestFirst() {
        let j = Tally.journey(sessionVolumes: [workout(day(2026, 8, 1), 1_200)])
        XCTAssertEqual(j.count, Tally.milestones.count, "locked tiers are still listed")
        XCTAssertEqual(j.map(\.milestone.pounds), j.map(\.milestone.pounds).sorted())
    }

    func testWorkoutsOutOfOrderAreStillDatedCorrectly() {
        let j = Tally.journey(sessionVolumes: [
            workout(day(2026, 8, 8), 600),
            workout(day(2026, 8, 1), 600),
        ])
        XCTAssertEqual(j.first { $0.milestone.pounds == 1_000 }?.crossedOn,
                       day(2026, 8, 8), "the later session is the one that crossed it")
    }

    func testNothingLiftedCrossesNothing() {
        XCTAssertTrue(Tally.journey(sessionVolumes: []).allSatisfy { !$0.isPassed })
    }

    /// Every tier names an image that is actually in the bundle. A typo here is
    /// a blank badge, and nothing else would notice.
    func testEveryMilestoneHasItsArtwork() {
        for m in Tally.milestones {
            XCTAssertFalse(m.art.isEmpty, "\(m.name) has no artwork name")
            XCTAssertNotNil(UIImage(named: m.art), "\(m.name) names missing art '\(m.art)'")
        }
    }

    /// A tenth of a ton is 200 lb — real precision at 184.8, and a decimal
    /// point pretending to mean something at "2250.0".
    func testTonnageDropsPrecisionNobodyHas() {
        XCTAssertEqual(Tally.volumeText(369_600), "184.8 tons")
        XCTAssertEqual(Tally.volumeText(4_500_000), "2,250 tons")
        XCTAssertEqual(Tally.volumeText(2_000_000), "1,000 tons")
        XCTAssertEqual(Tally.volumeText(140_000), "70 tons", "no .0 on a whole one")
        XCTAssertEqual(Tally.volumeText(12_830), "12,830 lb", "under a ton stays in pounds")
        XCTAssertEqual(Tally.volumeText(0), "nothing yet")
    }

}
