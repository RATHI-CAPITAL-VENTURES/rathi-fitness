import XCTest
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
        XCTAssertTrue(Tally.TrendMeasure.help.lowerIsBetter)
        XCTAssertFalse(Tally.TrendMeasure.weight.lowerIsBetter)
    }
}
