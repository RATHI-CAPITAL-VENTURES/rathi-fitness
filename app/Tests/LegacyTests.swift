import XCTest
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
        let scrambled = [Tally.Milestone(pounds: 100, name: "b", symbol: "x"),
                         Tally.Milestone(pounds: 10, name: "a", symbol: "x")]
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
}
