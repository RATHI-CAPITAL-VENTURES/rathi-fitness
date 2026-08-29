import XCTest
import SwiftData
@testable import RathiFitness

/// Machines where the weight makes it EASIER.
///
/// An assisted pull-up machine counterweights you, so 100 lb of help is a much
/// easier set than 40 and getting stronger means the number going down. Every
/// piece of arithmetic in the app assumed the opposite, and none of the
/// failures looked like failures — they all produced plausible numbers pointing
/// the wrong way. Each test below is one of them.
final class AssistedTests: XCTestCase {

    private func set(_ weight: Double, _ reps: Int,
                     kind: SetKind = .working) -> Tally.Set {
        Tally.Set(weight: weight, reps: reps, kind: kind, assisted: true)
    }

    // MARK: tonnage

    /// The worst one, because the number is plausible: 100 lb of help × 8 reps
    /// reads as 800 lb "moved", so the more help you needed the better the
    /// session looked.
    func testAssistanceIsNotTonnage() {
        XCTAssertEqual(Tally.volume([set(100, 8)]), 0)
        XCTAssertEqual(Tally.volume([set(100, 8), Tally.Set(weight: 185, reps: 8)]), 1480)
    }

    func testNeedingMoreHelpCannotIncreaseYourVolume() {
        let weaker = Tally.volume([set(120, 8)])
        let stronger = Tally.volume([set(40, 8)])
        XCTAssertEqual(weaker, stronger, "volume must not rank these at all")
    }

    // MARK: records

    func testLessHelpIsTheRecordAndMoreHelpIsNot() {
        let history = [set(80, 8), set(90, 8)]

        let better = Tally.records(for: set(70, 8), history: history)
        XCTAssertEqual(better.first, .leastAssistance(70))

        // The bug: 100 registering as a heaviest-ever personal best.
        let worse = Tally.records(for: set(100, 8), history: history)
        XCTAssertFalse(worse.contains { if case .leastAssistance = $0 { return true }
                                        return false })
        XCTAssertFalse(worse.contains { if case .heaviest = $0 { return true }; return false })
    }

    func testTheHeadlineNeverCongratulatesYouForNeedingHelp() {
        let headline = Tally.headline(for: set(70, 8), history: [set(80, 8)])
        XCTAssertEqual(headline, "Least help ever — 70 lb")
        XCTAssertFalse(headline?.contains("Heaviest") ?? false)
    }

    /// Zero help is a legitimate weight on these machines — it is the best one
    /// there is — so the `weight > 0` guard that protects lifts must not apply.
    func testGettingToNoHelpAtAllIsTheRecordItSoundsLike() {
        let records = Tally.records(for: set(0, 5), history: [set(20, 5)])
        XCTAssertEqual(records.first, .leastAssistance(0))
        XCTAssertEqual(Tally.headline(for: set(0, 5), history: [set(20, 5)]),
                       "Unassisted — no help at all")
    }

    /// More reps with MORE help is not a rep record. The comparison is the
    /// mirror of the resisted one, not a copy of it.
    func testMoreRepsOnlyCountsAtThisMuchHelpOrLess() {
        let history = [set(60, 6)]
        XCTAssertFalse(Tally.records(for: set(90, 10), history: history)
            .contains { if case .repsAssisted = $0 { return true }; return false },
            "ten reps with thirty pounds more help is not a record")
        XCTAssertTrue(Tally.records(for: set(60, 9), history: history)
            .contains { if case .repsAssisted = $0 { return true }; return false })
    }

    /// Epley on a counterweight is arithmetic without a meaning, and it would
    /// produce a number — which is exactly the danger.
    func testNoEstimatedOneRepMaxOnACounterweight() {
        let records = Tally.records(for: set(70, 8), history: [set(80, 5)])
        XCTAssertFalse(records.contains { if case .estimatedMax = $0 { return true }
                                          return false })
    }

    func testAWarmUpOnAnAssistedMachineStillSetsNothing() {
        XCTAssertTrue(Tally.records(for: set(40, 8, kind: .warmup),
                                    history: [set(80, 8)]).isEmpty)
    }

    // MARK: what to do next

    func testHittingEveryRepTakesHelpOffRatherThanAddingIt() {
        let last = [set(70, 8), set(70, 8), set(70, 8)]
        let next = Tally.nextTarget(lastSession: last, target: 8, assisted: true)
        XCTAssertEqual(next?.weight, 65, "the app suggested MORE help for a good session")
        XCTAssertEqual(next?.because, "you hit every rep last time")
    }

    /// Progression must anchor on the hardest set you did — the one with the
    /// least help — or it works off your easiest and never progresses.
    func testProgressionAnchorsOnTheLeastHelpNotTheMost() {
        let last = [set(90, 8), set(70, 8)]   // a heavy first set, then less help
        let next = Tally.nextTarget(lastSession: last, target: 8, assisted: true)
        XCTAssertEqual(next?.weight, 65)
    }

    func testHelpNeverGoesNegative() {
        let next = Tally.nextTarget(lastSession: [set(3, 8)], target: 8,
                                    step: 5, assisted: true)
        XCTAssertEqual(next?.weight, 0)
    }

    func testAlreadyUnassistedSaysSoRatherThanSuggestingLessThanNothing() {
        let next = Tally.nextTarget(lastSession: [set(0, 8)], target: 8, assisted: true)
        XCTAssertEqual(next?.weight, 0)
        XCTAssertEqual(next?.because, "you're doing these unassisted — try the real thing")
    }

    func testAStallKeepsTheSameHelpAndSaysHelp() {
        let next = Tally.nextTarget(lastSession: [set(70, 4)], target: 8, assisted: true)
        XCTAssertEqual(next?.weight, 70)
        XCTAssertTrue(next?.because.contains("help") ?? false)
    }

    // MARK: the ordinary case is untouched

    func testNoneOfThisChangesAPlainLift() {
        let history = [Tally.Set(weight: 180, reps: 8)]
        let candidate = Tally.Set(weight: 185, reps: 8)
        XCTAssertEqual(Tally.records(for: candidate, history: history).first,
                       .heaviest(185))
        XCTAssertEqual(Tally.volume([candidate]), 1480)
        XCTAssertEqual(Tally.nextTarget(lastSession: history, target: 8)?.weight, 185)
    }

    // MARK: the flag reaches everything through one door

    func testTheConverterCarriesTheFlagSoNoCallSiteCanForgetIt() throws {
        let container = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let machine = Catalogue.exercise(from: Catalogue.entry(named: "Assisted Pull-Up")!)
        context.insert(machine)
        let entry = SetEntry(exercise: machine, weight: 70, reps: 8, setIndex: 1)
        context.insert(entry)
        try context.save()

        XCTAssertTrue(machine.assisted)
        XCTAssertTrue(entry.tally.assisted)
        XCTAssertEqual(entry.tally.volume, 0)
    }

    func testTheCatalogueKnowsWhichMachinesWorkThisWay() {
        for name in ["Assisted Pull-Up", "Assisted Chin-Up", "Assisted Dip"] {
            let entry = Catalogue.entry(named: name)
            XCTAssertEqual(entry?.assisted, true, "\(name) should be assisted")
        }
        // The bodyweight originals are unchanged.
        XCTAssertEqual(Catalogue.entry(named: "Pull-Up")?.assisted, false)
    }

    func testTheUnitLabelSaysWhatTheNumberIs() {
        let machine = Exercise(name: "Assisted Dip", loading: .machine, assisted: true)
        XCTAssertEqual(machine.weightUnit, "lb help")
        XCTAssertTrue(machine.lowerIsBetter)
        XCTAssertEqual(Exercise(name: "Bench Press").weightUnit, "lb")
    }
}

/// What the Mac is told. RIA reads this file and talks out loud from it, so a
/// row that means the opposite of what it looks like is worse here than
/// anywhere else in the app.
final class AssistedSnapshotTests: XCTestCase {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Store.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let machine = Catalogue.exercise(from: Catalogue.entry(named: "Assisted Pull-Up")!)
        context.insert(machine)
        let bench = Catalogue.exercise(from: Catalogue.entry(named: "Bench Press")!)
        context.insert(bench)

        let old = Calendar.current.date(byAdding: .day, value: -40, to: .now)!
        // Forty days ago he needed 90 lb of help; today, 70. That is progress.
        context.insert(SetEntry(exercise: machine, weight: 90, reps: 8, setIndex: 1, date: old))
        context.insert(SetEntry(exercise: machine, weight: 70, reps: 8, setIndex: 1))
        context.insert(SetEntry(exercise: machine, weight: 80, reps: 6, setIndex: 2))
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8, setIndex: 1))
        try context.save()
        return context
    }

    func testTheFlagIsInTheContract() throws {
        let snapshot = try SnapshotBuilder.build(from: context())
        let machine = try XCTUnwrap(snapshot.exercises.first { $0.slug == "assisted-pull-up" })
        XCTAssertTrue(machine.assisted)
        XCTAssertFalse(try XCTUnwrap(snapshot.exercises.first { $0.slug == "bench-press" }).assisted)
    }

    func testWorkingWeightIsTheLeastHelpThatDayNotTheMost() throws {
        let snapshot = try SnapshotBuilder.build(from: context())
        let machine = try XCTUnwrap(snapshot.exercises.first { $0.slug == "assisted-pull-up" })
        // 70 and 80 were done today; the hard set is the 70.
        XCTAssertEqual(machine.workingWeight, 70)
    }

    func testBestIsTheLeastHelpEverNeeded() throws {
        let snapshot = try SnapshotBuilder.build(from: context())
        let machine = try XCTUnwrap(snapshot.exercises.first { $0.slug == "assisted-pull-up" })
        XCTAssertEqual(machine.best?.weight, 70,
                       "exporting 90 as a personal best is the whole bug in one field")
    }

    func testAssistanceIsNotInTheSessionVolume() throws {
        let snapshot = try SnapshotBuilder.build(from: context())
        let today = try XCTUnwrap(snapshot.sessions.first { $0.date == Fmt.day(.now) })
        XCTAssertEqual(today.volume, 1480, "only the bench press moved any weight")
    }

    func testAnAssistStackIsNeverATopLift() throws {
        let snapshot = try SnapshotBuilder.build(from: context())
        let today = try XCTUnwrap(snapshot.sessions.first { $0.date == Fmt.day(.now) })
        XCTAssertEqual(today.topLifts, ["Bench Press 185"],
                       "\"Assisted Pull-Up 80\" would top the list on your worst day")
    }

    func testTheSchemaBumpedBecauseTheMeaningChanged() {
        // A reader on schema 3 seeing `working_weight: 70` on this row would
        // congratulate him for getting weaker. Refusing is the correct response,
        // and `cli/gym` refuses anything it does not know.
        XCTAssertEqual(Snapshot.currentSchema, 5)
    }
}
