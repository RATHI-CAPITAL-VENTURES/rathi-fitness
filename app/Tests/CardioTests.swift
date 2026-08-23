import XCTest
import SwiftData
@testable import RathiFitness

/// A treadmill answers in minutes and miles, and never in pounds.
///
/// The failure this suite exists to prevent is subtle and one-directional: a
/// cardio row whose weight and reps are zero slides silently through every
/// strength calculation and comes out as a valid-looking zero. Zero tonnage is
/// arithmetically true and completely wrong — it drags averages, it makes
/// "0 lb" a working weight, and nothing about it looks like a bug.
final class CardioTests: XCTestCase {

    // MARK: the model

    func testACardioExerciseKnowsWhichNumbersItsConsoleHas() {
        let rower = Catalogue.exercise(from: Catalogue.entry(named: "Rower")!)
        XCTAssertTrue(rower.isCardio)
        XCTAssertTrue(rower.metrics.contains(.distance))
        XCTAssertTrue(rower.metrics.contains(.resistance))
        XCTAssertFalse(rower.metrics.contains(.incline),
                       "a rower has no incline and must not offer one")

        let treadmill = Catalogue.exercise(from: Catalogue.entry(named: "Treadmill")!)
        XCTAssertTrue(treadmill.metrics.contains(.incline))
        XCTAssertFalse(treadmill.metrics.contains(.resistance),
                       "a treadmill has no damper")
    }

    func testACardioExerciseWithNoStatedMetricsStillOffersTheCommonOnes() {
        // An exercise you cannot record anything against is worse than one that
        // offers a field you ignore.
        let made = Exercise(name: "Some Machine", modality: .cardio)
        XCTAssertEqual(made.metrics, CardioMetric.commonSet)
    }

    func testMetricsKeepAFixedOrderWhicheverWayTheyWereStored() {
        let a = Exercise(name: "A", modality: .cardio,
                         metrics: [.heartRate, .duration, .distance])
        XCTAssertEqual(a.metrics, [.duration, .distance, .heartRate])
    }

    // MARK: volume must not absorb it

    func testCardioContributesNoTonnage() {
        let sets = [Tally.Set(weight: 185, reps: 8),
                    Tally.Set(weight: 0, reps: 0)]     // a 25-minute treadmill bout
        XCTAssertEqual(Tally.volume(sets), 1480)
    }

    func testCardioIsCountedInMinutesInstead() {
        let bouts = [Tally.Bout(seconds: 1500, distance: 2.1),
                     Tally.Bout(seconds: 600, distance: 0.8)]
        XCTAssertEqual(Tally.cardioMinutes(bouts), 35, accuracy: 0.001)
        XCTAssertEqual(Tally.cardioDistance(bouts), 2.9, accuracy: 0.001)
    }

    func testAverageSpeedIsDistanceOverTimeNotWhateverTheConsoleSaid() {
        // 2.1 miles in 25 minutes is 5.04 mph, whatever the belt read when you
        // happened to glance down.
        let bout = Tally.Bout(seconds: 1500, distance: 2.1, speed: 7.5)
        XCTAssertEqual(bout.averageSpeed!, 5.04, accuracy: 0.01)
    }

    func testABoutWithNoDistanceHasNoAverageSpeedRatherThanZero() {
        XCTAssertNil(Tally.Bout(seconds: 1200).averageSpeed)
    }

    // MARK: records

    func testFurthestAndLongestAreRecords() {
        let history = [Tally.Bout(seconds: 1200, distance: 1.8)]
        let further = Tally.cardioRecords(for: .init(seconds: 1200, distance: 2.4),
                                          history: history)
        XCTAssertEqual(further.first, .farthest(2.4))

        let longer = Tally.cardioRecords(for: .init(seconds: 1800, distance: 1.0),
                                         history: history)
        XCTAssertTrue(longer.contains(.longest(1800)))
    }

    func testMatchingYourBestIsNotARecord() {
        let history = [Tally.Bout(seconds: 1200, distance: 2.0)]
        XCTAssertTrue(Tally.cardioRecords(for: .init(seconds: 1200, distance: 2.0),
                                          history: history).isEmpty)
    }

    /// A twenty-minute row with no distance recorded is not evidence you have
    /// never gone faster.
    func testSpeedIsOnlyJudgedAgainstBoutsThatHaveOne() {
        let history = [Tally.Bout(seconds: 1200, distance: 0)]
        let records = Tally.cardioRecords(for: .init(seconds: 600, distance: 1.0),
                                          history: history)
        XCTAssertFalse(records.contains { if case .fastest = $0 { return true }; return false })
    }

    func testAnEmptyBoutSetsNothing() {
        XCTAssertTrue(Tally.cardioRecords(for: Tally.Bout(), history: []).isEmpty)
    }

    // MARK: Health

    func testEachMachineGoesToHealthAsWhatItActuallyIs() {
        XCTAssertEqual(HealthSync.activity(forSlug: "treadmill"), .running)
        XCTAssertEqual(HealthSync.activity(forSlug: "stationary-bike"), .cycling)
        XCTAssertEqual(HealthSync.activity(forSlug: "rower"), .rowing)
        XCTAssertEqual(HealthSync.activity(forSlug: "elliptical"), .elliptical)
        XCTAssertEqual(HealthSync.activity(forSlug: "stair-climber"), .stairs)
        XCTAssertEqual(HealthSync.activity(forSlug: "swim"), .swimming)
        // Nothing we recognise is `mixed`, not a guess at the nearest sport.
        XCTAssertEqual(HealthSync.activity(forSlug: "versaclimber"), .mixed)
    }

    /// The ordering bug this mapping is written to avoid: a bare "walk" rule
    /// tested first would claim "treadmill-walk" as a run.
    func testAQualifiedNameBeatsTheBareOne() {
        XCTAssertEqual(HealthSync.activity(forSlug: "treadmill-walk"), .walking)
        XCTAssertEqual(HealthSync.activity(forSlug: "treadmill"), .running)
    }

    func testOnlyMachinesWithARealDistanceWriteOne() {
        XCTAssertEqual(HealthSync.CardioActivity.running.distance, .walkingRunning)
        XCTAssertEqual(HealthSync.CardioActivity.cycling.distance, .cycling)
        // Inventing walking distance for a stair climber inflates a ring that
        // was not earned.
        XCTAssertEqual(HealthSync.CardioActivity.stairs.distance, .none)
        XCTAssertEqual(HealthSync.CardioActivity.jumpRope.distance, .none)
    }

    // MARK: formatting

    func testDurationsReadLikeAConsoleAndThenLikeAPerson() {
        XCTAssertEqual(Fmt.duration(1500), "25:00")
        XCTAssertEqual(Fmt.duration(5400), "1:30:00")
        XCTAssertEqual(Fmt.minutes(1500), "25 min")
        XCTAssertEqual(Fmt.minutes(5400), "1 h 30 min")
        XCTAssertEqual(Fmt.minutes(3600), "1 h")
    }

    func testDistancesKeepTheDecimalsThatMeanSomething() {
        XCTAssertEqual(Fmt.distance(0.75), "0.75")
        XCTAssertEqual(Fmt.distance(13.1), "13.1")
    }
}

/// "2 on the leg press" — the thing you otherwise rediscover every week by
/// sitting down and finding out it is wrong.
final class MachineSettingTests: XCTestCase {

    private func store() throws -> ModelContext {
        let container = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testSettingsBelongToTheExerciseAndSurviveIt() throws {
        let context = try store()
        let press = Exercise(name: "Leg Press", loading: .machine, primary: .quads)
        context.insert(press)
        context.insert(MachineSetting(kind: .seat, value: "2", exercise: press))
        context.insert(MachineSetting(kind: .back, value: "4", exercise: press))
        try context.save()

        XCTAssertEqual(press.settings.count, 2)
        // Ordered by the enum, so two screens cannot list them differently.
        XCTAssertEqual(press.settings.map(\.setting), [.seat, .back])
    }

    func testDeletingTheExerciseTakesItsSettingsWithIt() throws {
        let context = try store()
        let press = Exercise(name: "Leg Press", loading: .machine)
        context.insert(press)
        context.insert(MachineSetting(kind: .seat, value: "2", exercise: press))
        try context.save()

        context.delete(press)
        try context.save()
        let left = try context.fetch(FetchDescriptor<MachineSetting>())
        XCTAssertTrue(left.isEmpty, "an orphaned seat position belongs to nothing")
    }

    /// Free text, because machine dials are not one type. A numeric field would
    /// have forced a lie on half of them.
    func testAValueCanBeAnythingAMachineActuallySays() throws {
        let context = try store()
        let bench = Exercise(name: "Incline Bench", loading: .barbell)
        context.insert(bench)
        for (kind, value) in [(MachineSettingKind.benchAngle, "30°"),
                              (.rackPins, "hole 12"),
                              (.grip, "wide")] {
            context.insert(MachineSetting(kind: kind, value: value, exercise: bench))
        }
        try context.save()
        XCTAssertEqual(Set(bench.settings.map(\.value)), ["30°", "hole 12", "wide"])
    }

    func testEveryDialHasALabelAndAHint() {
        for kind in MachineSettingKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.hint.isEmpty)
        }
    }
}

/// The snapshot's cardio contract, which is what RIA reads on the Mac.
final class CardioSnapshotTests: XCTestCase {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func treadmillDay() throws -> ModelContext {
        let context = try context()
        let treadmill = Catalogue.exercise(from: Catalogue.entry(named: "Treadmill")!)
        context.insert(treadmill)
        context.insert(MachineSetting(kind: .other, value: "belt 3", exercise: treadmill))

        let day = PlannedDay(name: "Conditioning", weekday:
                                Calendar.current.component(.weekday, from: .now))
        context.insert(day)
        let item = PlanItem(order: 0, exercise: treadmill, targetSets: 1, targetReps: 0,
                            targetWeight: 0, restSeconds: 0,
                            targetSeconds: 20 * 60, targetIncline: 3)
        item.day = day
        context.insert(item)

        // Two bouts: a short flat walk and a long climb. The averages must be
        // weighted by time, or the walk drags the grade down as if equal.
        context.insert(SetEntry(exercise: treadmill, weight: 0, reps: 0, setIndex: 1,
                                seconds: 300, distance: 0.3, incline: 0))
        context.insert(SetEntry(exercise: treadmill, weight: 0, reps: 0, setIndex: 2,
                                seconds: 1500, distance: 2.1, incline: 4))
        try context.save()
        return context
    }

    func testCardioReachesTheSnapshotInItsOwnUnits() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let item = try XCTUnwrap(snapshot.today?.items.first)
        XCTAssertEqual(item.modality, "cardio")
        XCTAssertEqual(item.cardio?.bouts, 2)
        XCTAssertEqual(item.cardio?.seconds, 1800)
        XCTAssertEqual(item.cardio?.distance ?? 0, 2.4, accuracy: 0.05)
        XCTAssertEqual(item.cardioTarget?.seconds, 1200)
        XCTAssertEqual(item.cardioTarget?.incline ?? 0, 3, accuracy: 0.001)
    }

    /// A plain mean would let a five-minute flat walk pull a twenty-five-minute
    /// climb's grade from 4% down to 2% — and nobody reading "average incline"
    /// would guess it was computed that way.
    func testAveragesAreWeightedByTime() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let cardio = try XCTUnwrap(snapshot.today?.items.first?.cardio)
        XCTAssertEqual(cardio.averageIncline ?? 0, 4.0, accuracy: 0.01,
                       "the flat walk recorded no incline and must not be averaged in")
    }

    func testACardioExerciseCarriesNoWorkingWeightAtAll() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let summary = try XCTUnwrap(snapshot.exercises.first { $0.slug == "treadmill" })
        XCTAssertEqual(summary.modality, "cardio")
        // Nil, not zero. A reader that averages `working_weight` must not be
        // handed a 0 lb bench press it cannot tell from a real one.
        XCTAssertNil(summary.workingWeight)
        XCTAssertNil(summary.best)
        XCTAssertNotNil(summary.cardioBest)
        XCTAssertEqual(summary.cardioBest?.longestSeconds, 1500)
    }

    func testMachineSettingsRideAlongToTheMac() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let summary = try XCTUnwrap(snapshot.exercises.first { $0.slug == "treadmill" })
        let settings = try XCTUnwrap(summary.machineSettings)
        XCTAssertEqual(settings.first?.value, "belt 3")
        XCTAssertEqual(settings.first?.label, "Other")
    }

    func testATreadmillIsNeverATopLift() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertTrue(session.topLifts.isEmpty,
                      "\"Treadmill 0\" is what happens when cardio is left in the lift list")
        XCTAssertEqual(session.cardioMinutes, 30, accuracy: 0.05)
        XCTAssertEqual(session.volume, 0)
    }

    func testAnUnrecordedMetricIsAbsentRatherThanZero() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        let performed = try XCTUnwrap(snapshot.today?.items.first?.performed.first)
        XCTAssertNil(performed.incline, "0% grade and no grade recorded are different facts")
        XCTAssertNil(performed.heartRate)
        XCTAssertEqual(performed.seconds, 300)
    }

    func testCardioIsMarkedDoneByItsBoutsNotByTargetSets() throws {
        let snapshot = try SnapshotBuilder.build(from: treadmillDay())
        XCTAssertEqual(snapshot.today?.items.first?.done, true)
    }
}
