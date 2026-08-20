import XCTest
import SwiftData
@testable import RathiFitness

/// The gaps `docs/RESEARCH.md` found against Hevy, Strong, Boostcamp and Jefit.
final class SetKindTests: XCTestCase {

    private func set(_ w: Double, _ r: Int, _ k: SetKind = .working) -> Tally.Set {
        Tally.Set(weight: w, reps: r, kind: k)
    }

    func testWarmUpsDoNotCountTowardTonnage() {
        // The biggest correctness gap: a 135 warm-up on bench day was inflating
        // both volume and records.
        let sets = [set(135, 10, .warmup), set(185, 8), set(185, 8)]
        XCTAssertEqual(Tally.volume(sets), 185 * 16)
    }

    func testDropAndFailureSetsDoCount() {
        // You moved the weight. A drop set is part of the working effort.
        XCTAssertEqual(Tally.volume([set(100, 10, .drop)]), 1000)
        XCTAssertEqual(Tally.volume([set(100, 10, .failure)]), 1000)
    }

    func testAWarmUpCannotSetARecord() {
        let history = [set(185, 5)]
        XCTAssertNil(Tally.headline(for: set(225, 3, .warmup), history: history),
                     "a warm-up must never announce a PR")
    }

    func testAHeavyWarmUpInHistoryCannotBlockARecord() {
        // You once warmed up at 225 for a single. Today's 200 x 5 working set is
        // still a working-weight record and must be allowed to say so.
        let history = [set(225, 1, .warmup), set(185, 5)]
        XCTAssertEqual(Tally.headline(for: set(200, 5), history: history),
                       "Heaviest ever — 200 lb")
    }

    func testWorkingSetsFilter() {
        let sets = [set(135, 10, .warmup), set(185, 8), set(185, 6, .drop)]
        XCTAssertEqual(Tally.workingSets(sets).count, 2)
    }
}

final class MuscleWorkTests: XCTestCase {

    private func logged(_ primary: MuscleGroup, _ secondary: [MuscleGroup] = [],
                        kind: SetKind = .working, daysAgo: Int = 1) -> Tally.LoggedSet {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return Tally.LoggedSet(date: date, kind: kind,
                                  primary: primary, secondary: secondary)
    }

    private var weekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    }

    func testPrimaryCountsWholeAndSecondaryCountsHalf() {
        let work = Tally.muscleWork(
            [logged(.chest, [.triceps]), logged(.chest, [.triceps])], since: weekAgo)
        XCTAssertEqual(work.first { $0.muscle == .chest }?.sets, 2)
        XCTAssertEqual(work.first { $0.muscle == .triceps }?.sets, 1)
    }

    func testWarmUpsDoNotCountAsSetsForAMuscleEither() {
        let work = Tally.muscleWork([logged(.chest, kind: .warmup)], since: weekAgo)
        XCTAssertTrue(work.isEmpty)
    }

    func testOnlyTheWindowCounts() {
        let work = Tally.muscleWork([logged(.back, daysAgo: 30)], since: weekAgo)
        XCTAssertTrue(work.isEmpty)
    }

    func testUnmappedExercisesAreNotAMuscleGroupCalledOther() {
        let work = Tally.muscleWork([logged(.other)], since: weekAgo)
        XCTAssertTrue(work.isEmpty, "'other' is an absence of data, not a muscle")
    }

    func testSortedHeaviestFirst() {
        let work = Tally.muscleWork(
            [logged(.quads), logged(.quads), logged(.calves)], since: weekAgo)
        XCTAssertEqual(work.first?.muscle, .quads)
    }
}

final class NextTargetTests: XCTestCase {

    private func set(_ w: Double, _ r: Int, _ k: SetKind = .working) -> Tally.Set {
        Tally.Set(weight: w, reps: r, kind: k)
    }

    func testHittingEveryRepMovesTheWeightUp() {
        let s = Tally.nextTarget(lastSession: [set(185, 8), set(185, 8)], target: 8)
        XCTAssertEqual(s?.weight, 190)
        XCTAssertEqual(s?.because, "you hit every rep last time")
    }

    func testMissingBadlyHoldsTheWeight() {
        let s = Tally.nextTarget(lastSession: [set(185, 5), set(185, 4)], target: 8)
        XCTAssertEqual(s?.weight, 185)
        XCTAssertTrue(s?.because.contains("stalled") ?? false)
    }

    func testJustShortSaysOneMoreRep() {
        let s = Tally.nextTarget(lastSession: [set(185, 8), set(185, 7)], target: 8)
        XCTAssertEqual(s?.weight, 185)
        XCTAssertTrue(s?.because.contains("one more rep") ?? false)
    }

    func testWarmUpsAreIgnoredWhenDecidingTheNextTarget() {
        // A 135 warm-up must not be mistaken for the working weight.
        let s = Tally.nextTarget(
            lastSession: [set(135, 10, .warmup), set(185, 8)], target: 8)
        XCTAssertEqual(s?.weight, 190)
    }

    func testNoHistoryMeansNoAdvice() {
        XCTAssertNil(Tally.nextTarget(lastSession: [], target: 8))
    }
}

final class CatalogueTests: XCTestCase {

    func testTheLibraryIsBigEnoughToPickFromRatherThanDescribe() {
        XCTAssertGreaterThan(Catalogue.all.count, 70)
    }

    func testEveryEntryHasAPrimaryMuscle() {
        for entry in Catalogue.all {
            XCTAssertNotEqual(entry.primary, .other, "\(entry.name) has no primary mover")
        }
    }

    func testSlugsAreUnique() {
        let slugs = Catalogue.all.map { Exercise.slugify($0.name) }
        XCTAssertEqual(Set(slugs).count, slugs.count, "two catalogue entries share a slug")
    }

    func testOnlyBarbellsCarryABar() {
        for entry in Catalogue.all {
            if entry.loading == .barbell { XCTAssertEqual(entry.bar, 45, entry.name) }
            else { XCTAssertEqual(entry.bar, 0, entry.name) }
        }
    }

    func testSeededPlanExercisesAllComeFromTheCatalogue() {
        // Otherwise the seeded lifts would be the only ones with no muscles.
        for day in Seed.days {
            for spec in day.items {
                XCTAssertNotNil(Catalogue.entry(named: spec.name),
                                "\(spec.name) is in the plan but not the catalogue")
            }
        }
    }

    func testSearchFindsByMuscleAsWellAsName() {
        XCTAssertFalse(Catalogue.search("quads").isEmpty)
        XCTAssertFalse(Catalogue.search("curl").isEmpty)
    }

    func testEnrichFillsInWhatWeKnow() {
        let exercise = Exercise(name: "Lat Pulldown")
        XCTAssertEqual(exercise.primary, .other)
        Catalogue.enrich(exercise)
        XCTAssertEqual(exercise.primary, .lats)
        XCTAssertEqual(exercise.loadingKind, .machine)
    }
}

final class ExportTests: XCTestCase {

    func testACommaInANoteDoesNotBecomeTwoColumns() {
        XCTAssertEqual(Export.escape("felt heavy, shoulder clicked"),
                       "\"felt heavy, shoulder clicked\"")
    }

    func testQuotesAreDoubled() {
        XCTAssertEqual(Export.escape("said \"stop\""), "\"said \"\"stop\"\"\"")
    }

    func testPlainFieldsAreLeftAlone() {
        XCTAssertEqual(Export.escape("Bench Press"), "Bench Press")
    }

    func testTheCsvCarriesEverythingNeededToRebuildTheLog() throws {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try Seed.run(context, weeksOfHistory: 0)
        let bench = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>()).first { $0.slug == "bench-press" })
        context.insert(SetEntry(exercise: bench, weight: 135, reps: 10, setIndex: 1,
                                kind: .warmup))
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8, setIndex: 2,
                                kind: .working, rpe: 8.5, note: "solid, felt easy"))
        try context.save()

        let csv = try Export.csv(from: context)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.first.map(String.init), Export.header)
        XCTAssertTrue(csv.contains("warmup"))
        XCTAssertTrue(csv.contains("8.5"))
        XCTAssertTrue(csv.contains("solid, felt easy") || csv.contains("\"solid, felt easy\""))
        // A warm-up contributes no volume, in the export as everywhere else.
        let warmupRow = rows.first { $0.contains("warmup") } ?? ""
        XCTAssertTrue(warmupRow.contains(",0,"), "warm-up volume should be 0: \(warmupRow)")
    }
}

final class SupersetTests: XCTestCase {

    func testLinkedItemsShareAGroupAndUnlinkedOnesDoNot() throws {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try Seed.run(context, weeksOfHistory: 0)
        let day = try XCTUnwrap(
            context.fetch(FetchDescriptor<PlannedDay>()).first { $0.name == "Push A" })
        let items = day.orderedItems
        items[0].supersetGroup = 1
        items[1].supersetGroup = 1
        try context.save()

        let group = day.orderedItems.filter { $0.supersetGroup == 1 }
        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(day.orderedItems.filter { $0.supersetGroup == 0 }.count, items.count - 2)
        // The last of a group is where the real rest belongs.
        XCTAssertEqual(group.last?.persistentModelID, items[1].persistentModelID)
    }
}
