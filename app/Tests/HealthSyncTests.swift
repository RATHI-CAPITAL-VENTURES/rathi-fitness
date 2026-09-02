import XCTest
import SwiftData
@testable import RathiFitness

final class HealthSyncTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 7) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 12))!
    }

    // MARK: importing

    func testImportsOnlyDaysWeDoNotAlreadyHave() {
        let samples = [
            HealthSync.Sample(date: day(2026, 8, 18), pounds: 177.2),
            HealthSync.Sample(date: day(2026, 8, 19), pounds: 176.9),
            HealthSync.Sample(date: day(2026, 8, 20), pounds: 176.4),
        ]
        let have = [day(2026, 8, 19, 6)]
        let wanted = HealthSync.samplesToImport(samples, existing: have)
        XCTAssertEqual(wanted.map(\.pounds), [177.2, 176.4])
    }

    func testOneWeighInPerDayEvenWhenHealthHasSeveral() {
        // Step on the scale twice in a morning and Health keeps both. Two points
        // on the chart for one morning is wrong, so the later one wins.
        let samples = [
            HealthSync.Sample(date: day(2026, 8, 20, 6), pounds: 177.0),
            HealthSync.Sample(date: day(2026, 8, 20, 9), pounds: 176.4),
        ]
        let wanted = HealthSync.samplesToImport(samples, existing: [])
        XCTAssertEqual(wanted.count, 1)
        XCTAssertEqual(wanted.first?.pounds, 176.4)
    }

    func testMatchingIsByDayNotByTimestamp() {
        // The same morning arrives from a scale at 07:12:04 and from a manual
        // entry at 07:12:00. Timestamp matching would import a duplicate.
        let existing = [day(2026, 8, 20, 7)]
        let sample = HealthSync.Sample(
            date: cal.date(byAdding: .second, value: 4, to: existing[0])!, pounds: 176.4)
        XCTAssertTrue(HealthSync.samplesToImport([sample], existing: existing).isEmpty)
    }

    func testImportsComeBackOldestFirst() {
        let samples = [
            HealthSync.Sample(date: day(2026, 8, 20), pounds: 176.4),
            HealthSync.Sample(date: day(2026, 8, 18), pounds: 177.2),
        ]
        let wanted = HealthSync.samplesToImport(samples, existing: [])
        XCTAssertEqual(wanted.map(\.date), wanted.map(\.date).sorted())
    }

    func testNothingToImportIsNotAnError() {
        XCTAssertTrue(HealthSync.samplesToImport([], existing: []).isEmpty)
    }

    // MARK: workouts

    func testWorkoutSpansFirstSetToAfterTheLast() {
        let dates = [day(2026, 8, 19, 6), day(2026, 8, 19, 7)]
        let bounds = try! XCTUnwrap(HealthSync.bounds(forSetsAt: dates))
        XCTAssertEqual(bounds.start, dates[0])
        XCTAssertEqual(bounds.duration, 3600 + 90, accuracy: 1)
    }

    func testASingleSetIsStillARealWorkout() {
        // HealthKit rejects a zero-length workout, and one heavy single is a
        // session you went to the gym for.
        let bounds = try! XCTUnwrap(HealthSync.bounds(forSetsAt: [day(2026, 8, 19)]))
        XCTAssertGreaterThan(bounds.duration, 0)
    }

    func testNoSetsIsNoWorkout() {
        XCTAssertNil(HealthSync.bounds(forSetsAt: []))
    }

    /// The gate is FINISHED, not yesterday.
    ///
    /// This used to skip anything dated today, so a workout you finished at
    /// 09:00 could not reach Health until the next day — and since the only
    /// caller ran at cold launch, often it never did.
    func testAWorkoutStillInProgressIsNotExported() {
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 20, 17), ended: nil)],
            alreadyExported: [], now: day(2026, 8, 20, 18))
        XCTAssertTrue(ready.isEmpty, "you might still be in the gym")
    }

    func testAWorkoutFinishedTodayIsExportedToday() {
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 20, 7), ended: day(2026, 8, 20, 8))],
            alreadyExported: [], now: day(2026, 8, 20, 18))
        XCTAssertEqual(ready, [day(2026, 8, 20, 7)],
                       "a finished workout is finished, whatever day it is")
    }

    func testFinishedAndUnfinishedAreSortedOutTogether() {
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 19, 7), ended: day(2026, 8, 19, 8)),
                       (start: day(2026, 8, 20, 17), ended: nil)],
            alreadyExported: [], now: day(2026, 8, 20, 18))
        XCTAssertEqual(ready, [day(2026, 8, 19, 7)])
    }

    /// The whole point of schema 5, at the Health end: a morning lift and an
    /// evening lift are two workouts, not one twelve-hour one.
    func testTwoWorkoutsInADayGoOverAsTwo() {
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 19, 7), ended: day(2026, 8, 19, 8)),
                       (start: day(2026, 8, 19, 19), ended: day(2026, 8, 19, 20))],
            alreadyExported: [], now: day(2026, 8, 20, 9))
        XCTAssertEqual(ready, [day(2026, 8, 19, 7), day(2026, 8, 19, 19)])
    }

    func testAlreadyExportedWorkoutsAreNotSentTwice() {
        let already: Set<Date> = [day(2026, 8, 19, 7)]
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 19, 7), ended: day(2026, 8, 19, 8)),
                       (start: day(2026, 8, 17, 7), ended: day(2026, 8, 17, 8))],
            alreadyExported: already, now: day(2026, 8, 20, 18))
        XCTAssertEqual(ready, [day(2026, 8, 17, 7)])
    }

    /// The upgrade path. Everything exported before sessions existed was marked
    /// by the START OF ITS DAY, so a workout inside one of those days has
    /// already gone over — matching only on its own start would write a
    /// duplicate of every historical workout into Apple Health.
    func testADayExportedBeforeSessionsExistedIsNotSentAgain() {
        let already: Set<Date> = [cal.startOfDay(for: day(2026, 8, 19))]
        let ready = HealthSync.sessionsReadyToExport(
            sessions: [(start: day(2026, 8, 19, 7), ended: day(2026, 8, 19, 8)),
                       (start: day(2026, 8, 19, 19), ended: day(2026, 8, 19, 20))],
            alreadyExported: already, now: day(2026, 8, 20, 18))
        XCTAssertTrue(ready.isEmpty,
                      "a day already sent covers the workouts inside it")
    }

    // MARK: units

    func testPoundsAndKilogramsRoundTrip() {
        let lb = HealthSync.pounds(fromKilograms: HealthSync.kilograms(fromPounds: 176.4))
        XCTAssertEqual(lb, 176.4, accuracy: 0.05)
    }

    func testHealthIsOffWhenTheBuildCannotHaveIt() {
        // Under RF_LOCAL_ONLY there is no entitlement, so the bridge must report
        // itself unavailable rather than walking into the permission sheet.
        #if RF_LOCAL_ONLY
        guard case .unsupported = HealthBridge.initialStatus() else {
            return XCTFail("a build with no Health entitlement claimed Health works")
        }
        #endif
    }
}

/// Editing the plan — the gap reported from the phone: it shipped seeded and
/// read-only, which made the app a log of someone else's programme.
final class PlanEditingTests: XCTestCase {

    private func context() throws -> ModelContext {
        let container = Store.makeContainer(inMemory: true)
        let ctx = ModelContext(container)
        try Seed.run(ctx)
        return ctx
    }

    func testADayCanBeRenamedAndRescheduled() throws {
        let ctx = try context()
        let day = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Push A" })
        day.name = "Chest & Arms"
        day.weekday = 3
        try ctx.save()

        let snapshot = try SnapshotBuilder.build(from: ctx)
        let plan = try XCTUnwrap(snapshot.plan.first { $0.name == "Chest & Arms" })
        XCTAssertEqual(plan.weekday, 3)
    }

    func testANewDayCanBeCreatedWithExercises() throws {
        let ctx = try context()
        let day = PlannedDay(name: "Conditioning", weekday: 7, order: 9)
        ctx.insert(day)
        let exercise = Exercise(name: "Farmer's Walk", loading: .dumbbell, barWeight: 0)
        ctx.insert(exercise)
        let item = PlanItem(order: 0, exercise: exercise, targetSets: 4,
                            targetReps: 1, targetWeight: 80, restSeconds: 120)
        item.day = day
        ctx.insert(item)
        try ctx.save()

        let snapshot = try SnapshotBuilder.build(from: ctx)
        let plan = try XCTUnwrap(snapshot.plan.first { $0.name == "Conditioning" })
        XCTAssertEqual(plan.items.first?.slug, "farmer-s-walk")
        XCTAssertEqual(plan.items.first?.weight, 80)
    }

    func testRemovingAnExerciseFromADayLeavesTheExerciseAlone() throws {
        let ctx = try context()
        let day = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Push A" })
        let item = try XCTUnwrap(day.orderedItems.first)
        let slug = try XCTUnwrap(item.exercise?.slug)
        ctx.delete(item)
        try ctx.save()

        // The lift and its history survive — you dropped it from a day, you did
        // not un-bench-press for six weeks.
        let exercises = try ctx.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(exercises.contains { $0.slug == slug })
        let snapshot = try SnapshotBuilder.build(from: ctx)
        XCTAssertNotNil(snapshot.exercises.first { $0.slug == slug }?.workingWeight)
    }

    func testDeletingADayTakesItsPlanItemsAndNotTheHistory() throws {
        let ctx = try context()
        let day = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Legs" })
        let beforeSets = try ctx.fetchCount(FetchDescriptor<SetEntry>())
        ctx.delete(day)
        try ctx.save()

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<SetEntry>()), beforeSets)
        XCTAssertNil(try ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Legs" })
    }

    func testReorderingIsWhatTheSnapshotReports() throws {
        let ctx = try context()
        let day = try XCTUnwrap(
            ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Push A" })
        var items = day.orderedItems
        items.reverse()
        for (i, item) in items.enumerated() { item.order = i }
        try ctx.save()

        let snapshot = try SnapshotBuilder.build(from: ctx)
        let plan = try XCTUnwrap(snapshot.plan.first { $0.name == "Push A" })
        XCTAssertEqual(plan.items.first?.name, items.first?.exercise?.name)
    }

    func testRenamingAnExerciseKeepsTheSlugInStepWithIt() {
        // The slug is what the CLI and RIA refer to, so it follows the name.
        XCTAssertEqual(Exercise.slugify("Chest-Supported Row"), "chest-supported-row")
    }

    func testWeekdayNumbersMatchCalendars() {
        for (number, name) in Weekdays.all {
            let date = Calendar.current.date(from: DateComponents(
                year: 2026, month: 8, day: 16 + number - 1))!
            XCTAssertEqual(Calendar.current.component(.weekday, from: date), number, name)
        }
    }

    func testAnUnscheduledDayNeverOpensByItself() throws {
        let ctx = try context()
        let day = PlannedDay(name: "Whenever", weekday: 0, order: 9)
        ctx.insert(day)
        try ctx.save()
        // weekday 0 matches no Calendar weekday, so `today` can never select it.
        for weekday in 1...7 {
            XCTAssertNotEqual(day.weekday, weekday)
        }
    }
}

#if canImport(HealthKit)
import HealthKit

/// Picking the Health connection back up on launch.
///
/// The bug: `status` started every launch at `.notAsked`, so closing the app
/// forgot that Health was connected. Settings offered "Connect Apple Health"
/// again — and worse, the launch sync is gated on `isConnected`, so weigh-ins
/// silently stopped arriving until you tapped the button. The permission was
/// never the problem; the app simply never asked whether it had one.
final class HealthResumeTests: XCTestCase {

    func testAnAnsweredSheetMeansConnected() {
        // `.unnecessary` = "asking would show no sheet" = every type answered.
        // It does NOT mean "authorised" — HealthKit will not answer that for
        // read types — and "answered" is what connected has always meant here.
        XCTAssertEqual(HealthSync.resumed(from: .unnecessary, current: .notAsked),
                       .connected)
    }

    func testItSurvivesARelaunch() {
        // The whole bug in one line: a fresh launch starts at .notAsked and has
        // to come back connected rather than asking again.
        XCTAssertTrue(HealthSync.resumed(from: .unnecessary, current: .notAsked).isConnected)
    }

    func testNeverAskedStaysNotAsked() {
        XCTAssertEqual(HealthSync.resumed(from: .shouldRequest, current: .notAsked),
                       .notAsked)
    }

    /// The safe wrong answer. Tapping connect when you are already connected
    /// shows no sheet and costs nothing; wrongly claiming to be connected would
    /// gate the launch sync on a permission that may not exist.
    func testAnUnknownAnswerOffersTheButton() {
        XCTAssertEqual(HealthSync.resumed(from: .unknown, current: .notAsked),
                       .notAsked)
    }
}
#endif
