import XCTest
import SwiftData
@testable import RathiFitness

/// One exercise over time — the line at the foot of the set screen and on the
/// Trends tab, which must be the same line.
final class TrendTests: XCTestCase {

    private let day0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func workout(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 7 * 86_400) }

    private func set(_ weight: Double, _ reps: Int = 8, kind: SetKind = .working,
                     assisted: Bool = false) -> Tally.Set {
        Tally.Set(weight: weight, reps: reps, kind: kind, assisted: assisted)
    }

    // MARK: lifts

    /// 45 → 50 → 55: the screenshot this feature was asked for from.
    func testOnePointPerWorkoutAtTheTopWorkingSet() {
        let trend = Tally.liftTrend([
            (workout(0), set(45)), (workout(0), set(45)), (workout(0), set(45)),
            (workout(1), set(50)), (workout(1), set(50)),
            (workout(2), set(55)),
        ])
        XCTAssertEqual(trend.measure, .weight)
        XCTAssertEqual(trend.points.map(\.value), [45, 50, 55])
        XCTAssertEqual(trend.points.map(\.date), [workout(0), workout(1), workout(2)])
        XCTAssertEqual(trend.change, 10)
        XCTAssertTrue(trend.isProgress)
        XCTAssertEqual(trend.days, 14)
    }

    func testInputOrderDoesNotMatter() {
        let trend = Tally.liftTrend([
            (workout(2), set(55)), (workout(0), set(45)), (workout(1), set(50)),
        ])
        XCTAssertEqual(trend.points.map(\.value), [45, 50, 55])
    }

    /// The inline `.max()` this replaced counted every set.
    func testAWarmUpIsNeverTheDaysPoint() {
        let trend = Tally.liftTrend([
            (workout(0), set(135, kind: .warmup)), (workout(0), set(95)),
            (workout(1), set(100)),
        ])
        XCTAssertEqual(trend.points.map(\.value), [95, 100])
    }

    func testAWorkoutThatWasAllWarmUpsHasNoPointRatherThanAZero() {
        let trend = Tally.liftTrend([
            (workout(0), set(95)),
            (workout(1), set(45, kind: .warmup)),
            (workout(2), set(100)),
        ])
        XCTAssertEqual(trend.points.map(\.value), [95, 100])
    }

    /// On an assisted machine `.max()` is the MOST help — the easiest set of
    /// the day — so the old line plotted your worst set and rose as you got
    /// weaker.
    func testAnAssistedMachinePlotsTheLeastHelpAndDownIsProgress() {
        let trend = Tally.liftTrend([
            (workout(0), set(100, assisted: true)), (workout(0), set(110, assisted: true)),
            (workout(1), set(80, assisted: true)), (workout(1), set(90, assisted: true)),
        ])
        XCTAssertEqual(trend.measure, .help)
        XCTAssertEqual(trend.points.map(\.value), [100, 80])
        XCTAssertEqual(trend.change, -20)
        XCTAssertTrue(trend.isProgress, "20 lb less help is the good direction")
    }

    func testNeedingMoreHelpIsNotProgress() {
        let trend = Tally.liftTrend([
            (workout(0), set(80, assisted: true)), (workout(1), set(100, assisted: true)),
        ])
        XCTAssertFalse(trend.isProgress)
    }

    func testALighterDayOnALiftIsNotProgressButHoldingIs() {
        XCTAssertFalse(Tally.liftTrend([(workout(0), set(100)), (workout(1), set(90))]).isProgress)
        XCTAssertTrue(Tally.liftTrend([(workout(0), set(100)), (workout(1), set(100))]).isProgress)
    }

    func testOneWorkoutHasNoChangeToReport() {
        let trend = Tally.liftTrend([(workout(0), set(100))])
        XCTAssertNil(trend.change)
        XCTAssertEqual(trend.points.count, 1)
        XCTAssertTrue(trend.isProgress, "nothing to compare is not a bad week")
        XCTAssertNil(trend.summary)
    }

    // MARK: a lift with no weight

    /// Push-ups are logged at 0 lb. Their weight line was dead flat along zero
    /// on an axis running −5 to 5 — a chart of nothing. What moves is the reps.
    func testABodyweightLiftPlotsItsBestSetOfReps() {
        let trend = Tally.liftTrend([
            (workout(0), set(0, 8)), (workout(0), set(0, 7)),
            (workout(1), set(0, 10)), (workout(1), set(0, 9)),
        ])
        XCTAssertEqual(trend.measure, .reps)
        XCTAssertEqual(trend.points.map(\.value), [8, 10])
        XCTAssertEqual(trend.summary, "+2 reps · 7 days")
        XCTAssertTrue(trend.isProgress)
    }

    /// One loaded set — a weighted pull-up — and it is a weight line again.
    func testALiftIsOnlyUnloadedWhenEveryWorkingSetIs() {
        let trend = Tally.liftTrend([
            (workout(0), set(0, 8)), (workout(1), set(25, 5)),
        ])
        XCTAssertEqual(trend.measure, .weight)
        XCTAssertEqual(trend.points.map(\.value), [0, 25])
    }

    func testAZeroPoundWarmUpDoesNotMakeALoadedLiftUnloaded() {
        let trend = Tally.liftTrend([
            (workout(0), set(0, 10, kind: .warmup)), (workout(0), set(95)),
            (workout(1), set(100)),
        ])
        XCTAssertEqual(trend.measure, .weight)
    }

    // MARK: the line of text beside the chart

    func testTheSummarySaysHowMuchAndOverHowLong() {
        let trend = Tally.liftTrend([
            (workout(0), set(45)), (workout(1), set(50)), (workout(3), set(55)),
        ])
        XCTAssertEqual(trend.summary, "+10 lb · 3 weeks")
    }

    /// The first version said "1 days": the count clamped to one, the plural
    /// chosen from the unclamped zero. And a two-a-day is exactly when this
    /// chart first appears.
    func testATwoADaySaysOneDayNotOneDays() {
        let morning = day0
        let evening = day0.addingTimeInterval(10 * 3600)
        let trend = Tally.liftTrend([(morning, set(45)), (evening, set(50))])
        XCTAssertEqual(trend.days, 0)
        XCTAssertEqual(trend.summary, "+5 lb · 1 day")
    }

    func testDaysUntilAFortnightThenWeeks() {
        func over(_ days: Double) -> String? {
            Tally.liftTrend([(day0, set(45)),
                             (day0.addingTimeInterval(days * 86_400), set(50))]).summary
        }
        XCTAssertEqual(over(1), "+5 lb · 1 day")
        XCTAssertEqual(over(13), "+5 lb · 13 days")
        XCTAssertEqual(over(14), "+5 lb · 2 weeks")
    }

    func testNoNewsIsNoLine() {
        XCTAssertNil(Tally.liftTrend([(workout(0), set(100)), (workout(1), set(100))]).summary)
    }

    func testTakingHelpOffReadsAsItIs() {
        let trend = Tally.liftTrend([
            (workout(0), set(100, assisted: true)), (workout(3), set(80, assisted: true)),
        ])
        XCTAssertEqual(trend.summary, "\(Fmt.signed(-20)) lb help · 3 weeks")
        XCTAssertTrue(trend.isProgress)
    }

    func testMilesKeepTheirDecimals() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(1200, 2.0)), (workout(1), bout(1200, 2.25)),
        ])
        XCTAssertEqual(trend.summary, "+\(Fmt.distance(0.25)) mi · 7 days")
    }

    // MARK: from real model objects

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    /// The retro's structural finding: "one point per workout" grouped by DAY
    /// for as long as `workoutKey` was file-private to the Trends tab, so a
    /// two-a-day was one point. It is a session now, and the set screen gets
    /// the same grouping because it is the same function.
    func testATwoADayIsTwoPointsBecauseSetsGroupBySession() throws {
        let context = context()
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        let cal = Calendar.current
        let morning = cal.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 7))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 19))!
        var entries: [SetEntry] = []
        for (start, weight) in [(morning, 180.0), (evening, 185.0)] {
            let session = Session(startedAt: start, dayName: "Push A")
            context.insert(session)
            let entry = SetEntry(exercise: bench, weight: weight, reps: 8, setIndex: 1,
                                 date: start.addingTimeInterval(300))
            entry.session = session
            context.insert(entry)
            entries.append(entry)
        }

        let trend = entries.trend(for: bench)

        XCTAssertEqual(trend.points.map(\.value), [180, 185])
        XCTAssertEqual(trend.points.map(\.date), [morning, evening],
                       "keyed on the session's start, not on the set's own time")
    }

    /// CloudKit can deliver rows from a device on an older build.
    func testASetWithNoSessionFallsBackToItsDay() {
        let context = context()
        let bench = Exercise(name: "Bench Press")
        context.insert(bench)
        let when = Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 14, hour: 18, minute: 20))!
        let entry = SetEntry(exercise: bench, weight: 185, reps: 8, setIndex: 1, date: when)
        context.insert(entry)

        XCTAssertEqual(entry.workoutKey, Calendar.current.startOfDay(for: when))
    }

    func testCardioAndLiftsAreSentToTheRightSeries() {
        let context = context()
        let run = Exercise(name: "Treadmill", loading: .machine, barWeight: 0,
                           modality: .cardio, metrics: [.duration, .distance])
        context.insert(run)
        let entries = [0, 1].map { week -> SetEntry in
            let entry = SetEntry(exercise: run, weight: 0, reps: 0, setIndex: 1,
                                 date: workout(week), seconds: 1200,
                                 distance: 2.0 + Double(week) * 0.1)
            context.insert(entry)
            return entry
        }

        let trend = entries.trend(for: run)

        XCTAssertEqual(trend.measure, .miles, "a treadmill at 0 lb must not become a reps line")
        XCTAssertEqual(trend.points.count, 2)
    }

    func testNothingLoggedIsAnEmptyLineNotACrash() {
        XCTAssertTrue(Tally.liftTrend([]).points.isEmpty)
        XCTAssertTrue(Tally.cardioTrend([]).points.isEmpty)
    }

    // MARK: cardio

    private func bout(_ seconds: Int, _ miles: Double = 0) -> Tally.Bout {
        Tally.Bout(seconds: seconds, distance: miles)
    }

    func testCardioPlotsMilesWhenTheMachineRecordsThem() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(1200, 2.0)), (workout(1), bout(1200, 2.1)),
        ])
        XCTAssertEqual(trend.measure, .miles)
        XCTAssertEqual(trend.points.map(\.value), [2.0, 2.1])
    }

    /// A stair climber has no distance. A line along zero says nothing.
    func testCardioFallsBackToMinutesWhenThereIsNoDistance() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(900)), (workout(1), bout(1200)),
        ])
        XCTAssertEqual(trend.measure, .minutes)
        XCTAssertEqual(trend.points.map(\.value), [15, 20])
    }

    func testIntervalsInOneWorkoutAreOnePoint() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(300, 0.5)), (workout(0), bout(300, 0.5)), (workout(0), bout(300, 0.6)),
            (workout(1), bout(1200, 2.0)),
        ])
        XCTAssertEqual(trend.points.map(\.value), [1.6, 2.0])
    }

    /// Never a mix. A workout where the distance was left blank is left OUT of
    /// a miles line, not plotted as a collapse to nothing.
    func testABlankDistanceIsAGapNotAZero() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(1200, 2.0)), (workout(1), bout(1200)), (workout(2), bout(1200, 2.2)),
        ])
        XCTAssertEqual(trend.measure, .miles)
        XCTAssertEqual(trend.points.map(\.value), [2.0, 2.2])
    }

    /// One distance in a history of blanks is not a line. Two are.
    func testASingleDistanceIsNotEnoughToSwitchToMiles() {
        let trend = Tally.cardioTrend([
            (workout(0), bout(900)), (workout(1), bout(1200, 2.0)), (workout(2), bout(1500)),
        ])
        XCTAssertEqual(trend.measure, .minutes)
        XCTAssertEqual(trend.points.count, 3)
    }

    func testUnitsComeWithTheMeasure() {
        XCTAssertEqual(Tally.TrendMeasure.weight.unit, "lb")
        XCTAssertEqual(Tally.TrendMeasure.help.unit, "lb help")
        XCTAssertEqual(Tally.TrendMeasure.miles.unit, "mi")
        XCTAssertEqual(Tally.TrendMeasure.minutes.unit, "min")
        XCTAssertEqual(Tally.TrendMeasure.reps.unit, "reps")
        // Exhaustive on purpose: the day someone argues a timed mile makes
        // `.minutes` lower-is-better, this is the line that has to change.
        XCTAssertEqual(Tally.TrendMeasure.allCases.filter(\.lowerIsBetter),
                       [.help, .bodyWeight])
    }

    /// Body weight was `.weight` plus three `selection == .body` checks at the
    /// call site — a `Trend` that was wrong about its own line shape, padding
    /// and direction, kept honest by callers remembering. Its `summary` would
    /// have called a gain progress.
    func testBodyWeightKnowsWhatMakesItDifferent() {
        let cut = Tally.Trend(measure: .bodyWeight, points: [
            Tally.TrendPoint(date: workout(0), value: 178.2),
            Tally.TrendPoint(date: workout(4), value: 176.4),
        ])
        XCTAssertTrue(cut.isProgress, "on this screen a cut is the goal")
        XCTAssertFalse(Tally.TrendMeasure.bodyWeight.isStepped, "a reading, not a setting")
        XCTAssertLessThan(Tally.TrendMeasure.bodyWeight.minimumPad, 1, "a body moves in tenths")
        XCTAssertEqual(Tally.TrendMeasure.bodyWeight.unit, "lb")

        let gain = Tally.Trend(measure: .bodyWeight, points: cut.points.reversed().enumerated()
            .map { Tally.TrendPoint(date: workout($0.offset * 4), value: $0.element.value) })
        XCTAssertFalse(gain.isProgress)
    }

    /// An assisted machine you no longer need help on: logged at 0 lb, plots
    /// reps, and MORE reps is progress. The Trends table read direction off
    /// `Exercise.assisted` instead, and showed "+4" in grey beside a headline
    /// showing "+4 reps" in teal.
    func testAGraduatedAssistedMachineIsJudgedAsReps() {
        let trend = Tally.liftTrend([
            (workout(0), set(0, 8, assisted: true)), (workout(3), set(0, 12, assisted: true)),
        ])
        XCTAssertEqual(trend.measure, .reps)
        XCTAssertFalse(trend.measure.lowerIsBetter)
        XCTAssertTrue(trend.isProgress)
        XCTAssertEqual(trend.summary, "+4 reps · 3 weeks")
    }

    /// One column cannot rank 25 reps against a 30 lb row.
    func testATableRanksPoundsBeforeHelpBeforeReps() {
        typealias M = Tally.TrendMeasure
        XCTAssertLessThan(M.weight.sortGroup, M.help.sortGroup)
        XCTAssertLessThan(M.help.sortGroup, M.reps.sortGroup)
        // (group, −value): push-ups at 25 must not land above a 20 lb raise.
        let rows: [(name: String, measure: M, current: Double)] = [
            ("Push-Up", .reps, 25), ("Lateral Raise", .weight, 20),
            ("Assisted Pull-Up", .help, 80), ("Row", .weight, 30),
        ]
        let sorted = rows.sorted {
            ($0.measure.sortGroup, -$0.current, $0.name) < ($1.measure.sortGroup, -$1.current, $1.name)
        }
        XCTAssertEqual(sorted.map(\.name), ["Row", "Lateral Raise", "Assisted Pull-Up", "Push-Up"])
    }

    /// One padding for every unit was the bug: half a mile flattens a
    /// 2.0 → 2.1 gain, and the same half as minutes lets one minute fill half
    /// the frame.
    func testEachMeasureBringsPaddingOnItsOwnScale() {
        XCTAssertLessThan(Tally.TrendMeasure.miles.minimumPad, 0.2)
        XCTAssertGreaterThanOrEqual(Tally.TrendMeasure.minutes.minimumPad, 1)
        XCTAssertEqual(Tally.TrendMeasure.weight.minimumPad, 5)
        XCTAssertEqual(Tally.TrendMeasure.help.minimumPad, 5)
        XCTAssertEqual(Tally.TrendMeasure.allCases.filter(\.isStepped), [.weight, .help])
        XCTAssertEqual(Tally.TrendMeasure.bodyWeight.minimumPad, 0.6)
    }
}
