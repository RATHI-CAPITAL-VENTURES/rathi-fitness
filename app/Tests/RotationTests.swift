import XCTest
import SwiftData
@testable import RathiFitness

/// Train on fixed days, rotate the content. Three sessions a week through four
/// workouts means the pairing drifts — which no day-to-weekday mapping can
/// express, and which is the whole reason this exists.
final class RotationTests: XCTestCase {

    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 7))!
    }

    /// Ishan's: Tue, Thu, Sat.
    private var config: Rotation.Config {
        Rotation.Config(mode: .rotation, trainingWeekdays: [3, 5, 7])
    }

    // MARK: which days are training days

    func testOnlyTheChosenWeekdaysAreTrainingDays() {
        // 2026-08-18 is a Tuesday.
        XCTAssertEqual(cal.component(.weekday, from: date(2026, 8, 18)), 3)
        XCTAssertTrue(Rotation.isTrainingDay(date(2026, 8, 18), config: config,
                                             lastSession: nil, calendar: cal))
        // Wednesday is not.
        XCTAssertFalse(Rotation.isTrainingDay(date(2026, 8, 19), config: config,
                                              lastSession: nil, calendar: cal))
        // Saturday is.
        XCTAssertTrue(Rotation.isTrainingDay(date(2026, 8, 22), config: config,
                                             lastSession: nil, calendar: cal))
    }

    func testEveryNDaysCountsFromTheLastSessionNotTheCalendar() {
        var every = Rotation.Config(mode: .everyNDays)
        every.everyNDays = 3
        let last = date(2026, 8, 18)
        XCTAssertFalse(Rotation.isTrainingDay(date(2026, 8, 20), config: every,
                                              lastSession: last, calendar: cal))
        XCTAssertTrue(Rotation.isTrainingDay(date(2026, 8, 21), config: every,
                                             lastSession: last, calendar: cal))
    }

    func testEveryNDaysWithNoHistoryStartsToday() {
        let every = Rotation.Config(mode: .everyNDays)
        XCTAssertTrue(Rotation.isTrainingDay(date(2026, 8, 20), config: every,
                                             lastSession: nil, calendar: cal))
    }

    // MARK: where you are in the cycle

    func testTheRotationDriftsAcrossWeekdaysAsItMust() {
        // Four workouts, trained Tue/Thu/Sat. Walk three weeks and check the
        // workout that comes up each time — this is the pattern a weekday
        // mapping cannot produce.
        let trainingDays = [
            date(2026, 8, 18), date(2026, 8, 20), date(2026, 8, 22),   // Tue Thu Sat
            date(2026, 8, 25), date(2026, 8, 27), date(2026, 8, 29),
            date(2026, 9, 1),
        ]
        var done: [Date] = []
        var sequence: [Int] = []
        for day in trainingDays {
            let index = Rotation.index(on: day, sessionDates: done,
                                       dayCount: 4, calendar: cal)!
            sequence.append(index)
            done.append(day)
        }
        XCTAssertEqual(sequence, [0, 1, 2, 3, 0, 1, 2])
        // The same weekday gets a different workout a week later — the point.
        // Tuesdays are positions 0 and 3 in this list: workout 1, then workout 4.
        XCTAssertEqual(sequence[0], 0)
        XCTAssertEqual(sequence[3], 3)
        XCTAssertNotEqual(sequence[0], sequence[3])
    }

    func testLoggingMoreSetsOnTheSameDayDoesNotAdvanceIt() {
        // Mid-workout you are still doing today's workout.
        let today = date(2026, 8, 20)
        let earlier = [today, today.addingTimeInterval(600), today.addingTimeInterval(1200)]
        XCTAssertEqual(Rotation.index(on: today, sessionDates: earlier,
                                      dayCount: 4, calendar: cal), 0)
    }

    func testSkippingASessionKeepsYourPlaceRatherThanLosingIt() {
        // Two done, then a fortnight off. You are still on the third workout.
        let done = [date(2026, 8, 18), date(2026, 8, 20)]
        XCTAssertEqual(Rotation.index(on: date(2026, 9, 5), sessionDates: done,
                                      dayCount: 4, calendar: cal), 2)
    }

    func testItIsDerivedSoADeletedSessionSelfCorrects() {
        // A stored cursor would be stuck at 3 forever. Counting fixes itself.
        let done = [date(2026, 8, 18), date(2026, 8, 20), date(2026, 8, 22)]
        XCTAssertEqual(Rotation.index(on: date(2026, 8, 25), sessionDates: done,
                                      dayCount: 4, calendar: cal), 3)
        let afterDelete = Array(done.dropLast())
        XCTAssertEqual(Rotation.index(on: date(2026, 8, 25), sessionDates: afterDelete,
                                      dayCount: 4, calendar: cal), 2)
    }

    func testItWrapsAtTheEndOfTheRotation() {
        let done = (0..<4).map { date(2026, 8, 10 + $0) }
        XCTAssertEqual(Rotation.index(on: date(2026, 8, 20), sessionDates: done,
                                      dayCount: 4, calendar: cal), 0)
    }

    func testNoWorkoutsMeansNoIndexRatherThanACrash() {
        XCTAssertNil(Rotation.index(on: .now, sessionDates: [], dayCount: 0))
    }

    // MARK: what to tell him

    func testNextTrainingDayLooksForward() {
        // From Wednesday, the next of Tue/Thu/Sat is Thursday.
        let next = Rotation.nextTrainingDay(from: date(2026, 8, 19), config: config,
                                            lastSession: nil, calendar: cal)
        XCTAssertEqual(next, cal.startOfDay(for: date(2026, 8, 20)))
    }

    func testDescribeReadsLikeASentence() {
        XCTAssertEqual(Rotation.describe(config), "Tue, Thu and Sat")
        var one = config; one.trainingWeekdays = [2]
        XCTAssertEqual(Rotation.describe(one), "Mon")
        var every = Rotation.Config(mode: .everyNDays); every.everyNDays = 3
        XCTAssertEqual(Rotation.describe(every), "every 3 days")
        XCTAssertEqual(Rotation.describe(Rotation.Config()),
                       "each workout on its own weekday")
    }

    func testNoTrainingDaysChosenSaysSoRatherThanEmpty() {
        var none = config; none.trainingWeekdays = []
        XCTAssertEqual(Rotation.describe(none), "no training days chosen")
    }

    // MARK: persistence

    func testTheScheduleRoundTripsThroughTheModel() throws {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let schedule = Schedule()
        context.insert(schedule)
        var wanted = Rotation.Config(mode: .rotation, trainingWeekdays: [3, 5, 7])
        wanted.everyNDays = 4
        schedule.config = wanted
        try context.save()

        let reread = try XCTUnwrap(context.fetch(FetchDescriptor<Schedule>()).first)
        XCTAssertEqual(reread.config, wanted)
    }

    func testSeedInstallsASchedule() throws {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try Seed.run(context, weeksOfHistory: 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Schedule>()), 1)
    }
}
