import XCTest
import SwiftData
@testable import RathiFitness

/// What the seed puts on the calendar, on a date the test chooses.
///
/// `Seed.run(_:now:weeksOfHistory:)` has always taken a `now`, and nothing used
/// it: every caller took `.now`, so the suite only ever exercised whichever
/// weekday the run happened to land on. `mostRecent` dated a "historical"
/// workout to **today at 06:45** when the seeded weekday was today, and the
/// plan trains Monday, Wednesday and Friday — so two tests passed four days a
/// week and failed three, and which ones you saw depended on the timezone of
/// the machine running them. A Mac on EDT and a runner on UTC disagree about
/// the weekday for four hours every night.
///
/// These pin the date. Every seeded weekday is checked, not the one today
/// happens to be.
final class SeedTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    /// A date in the CURRENT calendar, at midday.
    ///
    /// The first version of this helper built the moment in UTC, to match the
    /// 02:31 UTC stamp on the CI failure — and that made
    /// `testAWednesdayGetsNoBenchPressDatedToday` pass against the unfixed
    /// code. 02:00 UTC on a Wednesday is 22:00 EDT on the Tuesday, so
    /// `Calendar.current` read it as a Tuesday, the seed put nothing on
    /// "today", and the test agreed with itself about nothing. That is the same
    /// timezone ambiguity the bug is made of, reproduced one level up.
    ///
    /// `Seed` reads `Calendar.current`, so the test has to mean the same thing
    /// by "Wednesday" that the code does. Midday keeps it clear of DST edges.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func seeded(now: Date) throws -> ModelContext {
        let context = ModelContext(Store.makeContainer(inMemory: true))
        try Seed.run(context, now: now, weeksOfHistory: 6)
        return context
    }

    /// The property the name promises: history is in the past.
    func testTheSeedPutsNoWorkoutOnTodayOnAnyTrainingDay() throws {
        // 30 Aug 2026 is a Sunday, so this walks a whole week — every weekday
        // the plan trains and every one it does not.
        for offset in 0..<7 {
            let now = date(2026, 8, 30 + offset)
            let context = try seeded(now: now)
            let today = Calendar.current.startOfDay(for: now)
            let onToday = try context.fetch(FetchDescriptor<SetEntry>())
                .filter { Calendar.current.startOfDay(for: $0.date) == today }
            XCTAssertTrue(onToday.isEmpty,
                          "seeding on \(now) put \(onToday.count) sets on today itself")
        }
    }

    /// The Wednesday that failed, named on its own so a regression reads as the
    /// bug rather than as "some day in a loop".
    func testAWednesdayGetsNoBenchPressDatedToday() throws {
        let now = date(2026, 9, 2)
        let context = try seeded(now: now)
        let today = Calendar.current.startOfDay(for: now)
        let bench = try context.fetch(FetchDescriptor<SetEntry>())
            .filter { $0.exercise?.slug == "bench-press" }
        XCTAssertFalse(bench.isEmpty, "the seed should still produce bench history")
        XCTAssertFalse(bench.contains { Calendar.current.startOfDay(for: $0.date) == today },
                       "Push A is Wednesday — its history must not land on a Wednesday run")
    }

    /// And it is still history: cutting today must not cut the whole thing.
    func testSixWeeksOfHistoryStillArrives() throws {
        let now = date(2026, 9, 2)
        let context = try seeded(now: now)
        let sets = try context.fetch(FetchDescriptor<SetEntry>())
        XCTAssertGreaterThan(sets.count, 100,
                             "six weeks of three sessions should be well over a hundred sets")
        let newest = try XCTUnwrap(sets.map(\.date).max())
        XCTAssertLessThan(newest, Calendar.current.startOfDay(for: now),
                          "the newest seeded set should be before today")
        let oldest = try XCTUnwrap(sets.map(\.date).min())
        let weeks = Calendar.current.dateComponents([.day], from: oldest, to: now).day ?? 0
        XCTAssertGreaterThan(weeks, 35, "history should reach back about six weeks")
    }
}
