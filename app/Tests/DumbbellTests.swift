import XCTest
import SwiftData
@testable import RathiFitness

/// A pair of dumbbells is entered per dumbbell and counted per dumbbell.
///
/// The report: "Hammer curl only adds weight assuming total 25 lbs, not 25 on
/// each side." Tonnage was `weight × reps`, so ten curls with a pair of 25s
/// counted 250 lb when 500 was lifted. Every expected number below is worked
/// out by hand from the set, not read back from the code under test.
final class DumbbellTests: XCTestCase {

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    private func exercise(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Catalogue.exercise(from: Catalogue.entry(named: name)!)
        context.insert(exercise)
        return exercise
    }

    // MARK: - the arithmetic

    func testAPairCountsBothDumbbells() {
        let pair = Tally.Set(weight: 25, reps: 10, implements: 2)
        XCTAssertEqual(pair.volume, 500, "two 25s for ten reps is 500 lb")
        let single = Tally.Set(weight: 25, reps: 10, implements: 1)
        XCTAssertEqual(single.volume, 250, "one 25 for ten reps is 250 lb")
    }

    func testAWarmUpPairStillCountsNothing() {
        XCTAssertEqual(Tally.Set(weight: 25, reps: 10, kind: .warmup, implements: 2).volume, 0)
    }

    func testAssistanceIsUntouchedByTheCount() {
        // bodyweight − help, once: a machine has no second dumbbell, and the
        // count must not leak into the one rule it has nothing to do with.
        let assisted = Tally.Set(weight: 60, reps: 8, assisted: true,
                                 bodyWeight: 180, implements: 2)
        XCTAssertEqual(assisted.volume, 960)
        XCTAssertFalse(assisted.isPair, "help is never 'each'")
    }

    func testASetEntryReadsTheCountOffItsExercise() throws {
        let context = context()
        let curl = exercise("Hammer Curl", in: context)
        let goblet = exercise("Goblet Squat", in: context)
        let bench = exercise("Bench Press", in: context)
        let entries = [
            SetEntry(exercise: curl, weight: 25, reps: 10, setIndex: 1),
            SetEntry(exercise: goblet, weight: 70, reps: 10, setIndex: 1),
            SetEntry(exercise: bench, weight: 185, reps: 5, setIndex: 1),
        ]
        entries.forEach(context.insert)
        try context.save()

        let volumes = entries.map { $0.tally(bodyWeight: nil).volume }
        XCTAssertEqual(volumes, [500, 700, 925])
        XCTAssertEqual(Tally.volume(entries.map { $0.tally(bodyWeight: nil) }), 2125)
    }

    func testTheUnwrittenSetUsesTheSameRule() {
        // `Workout.record` and the plan's advance ask about a set before it is
        // a row. They used to build the value by hand.
        let context = context()
        let curl = exercise("Hammer Curl", in: context)
        XCTAssertEqual(curl.tally(weight: 25, reps: 10, kind: .working).volume, 500)
    }

    // MARK: - which lifts are singles

    func testTheCatalogueSaysWhichAreSingles() {
        let dumbbell = Catalogue.all.filter { $0.loading == .dumbbell }
        let singles = Set(dumbbell.filter { $0.dumbbells == 1 }.map(\.name))
        XCTAssertEqual(singles, ["Goblet Squat", "Overhead Triceps Extension", "Russian Twist"])
        // One-arm and alternating work is a pair: both sides do the reps.
        for name in ["Hammer Curl", "Dumbbell Row", "Concentration Curl", "Step-Up",
                     "Walking Lunge", "Bulgarian Split Squat", "Incline DB Press",
                     "Lateral Raise", "Farmer's Walk", "Wrist Curl"] {
            XCTAssertEqual(Catalogue.entry(named: name)?.dumbbells, 2, name)
        }
    }

    func testEverySingleNamesARealDumbbellEntry() {
        // A typo in the registry would make the lift a pair, silently.
        for name in Catalogue.singles {
            XCTAssertEqual(Catalogue.entry(named: name)?.loading, .dumbbell, name)
        }
    }

    // MARK: - the backfill

    func testTheBackfillPinsUnchosenDumbbellLifts() throws {
        let context = context()
        // As they were before v0.16.0: nothing says how many.
        let curl = Exercise(name: "Hammer Curl", loading: .dumbbell, barWeight: 0)
        let goblet = Exercise(name: "Goblet Squat", loading: .dumbbell, barWeight: 0)
        let typed = Exercise(name: "Zottman Curl", loading: .dumbbell, barWeight: 0)
        let bench = Exercise(name: "Bench Press", loading: .barbell)
        let chosen = Exercise(name: "Lateral Raise", loading: .dumbbell, barWeight: 0,
                              dumbbells: 1)
        [curl, goblet, typed, bench, chosen].forEach(context.insert)
        XCTAssertEqual([curl, goblet, typed, bench, chosen].map(\.dumbbells), [0, 0, 0, 0, 1])

        XCTAssertEqual(try Exercise.backfillDumbbells(in: context), 3)
        XCTAssertEqual(curl.dumbbells, 2, "a dumbbell lift is a pair by default")
        XCTAssertEqual(goblet.dumbbells, 1, "the catalogue's singles are respected by slug")
        XCTAssertEqual(typed.dumbbells, 2, "a lift the catalogue does not know is a pair")
        XCTAssertEqual(chosen.dumbbells, 1, "a choice already made is not overwritten")
        XCTAssertEqual(bench.dumbbells, 0, "a barbell is left unchosen")
        XCTAssertEqual(bench.implements, 1, "and counts once whatever is stored")

        XCTAssertEqual(try Exercise.backfillDumbbells(in: context), 0, "idempotent")
    }

    func testAnUnchosenCountResolvesBeforeTheBackfillRuns() {
        // A row synced in from another device before this launch's backfill.
        XCTAssertEqual(Exercise(name: "Hammer Curl", loading: .dumbbell).implements, 2)
        XCTAssertEqual(Exercise(name: "Goblet Squat", loading: .dumbbell).implements, 1)
    }

    func testOnlyADumbbellCountsTwice() {
        let cable = Exercise(name: "Cable Curl", loading: .cable, dumbbells: 2)
        XCTAssertEqual(cable.implements, 1, "a stray count off a dumbbell means nothing")
        cable.loading = Exercise.Loading.dumbbell.rawValue
        XCTAssertEqual(cable.implements, 2, "and comes back if it becomes one")
    }

    // MARK: - what it says

    func testEachOnlyOnAPairOfDumbbells() {
        XCTAssertEqual(Exercise(name: "Hammer Curl", loading: .dumbbell, dumbbells: 2).weightUnit,
                       "lb each")
        XCTAssertEqual(Exercise(name: "Hammer Curl", loading: .dumbbell, dumbbells: 1).weightUnit,
                       "lb")
        XCTAssertEqual(Exercise(name: "Bench Press", loading: .barbell, dumbbells: 2).weightUnit,
                       "lb")
        XCTAssertEqual(Exercise(name: "Assisted Dip", loading: .machine, assisted: true).weightUnit,
                       "lb help")
        XCTAssertEqual(Exercise(name: "Hammer Curl", loading: .dumbbell, dumbbells: 2).each, " each")
        XCTAssertEqual(Exercise(name: "Goblet Squat", loading: .dumbbell, dumbbells: 1).each, "")
    }

    func testARecordOnAPairSaysEach() {
        let history = [Tally.Set(weight: 20, reps: 10, implements: 2)]
        XCTAssertEqual(Tally.headline(for: Tally.Set(weight: 25, reps: 10, implements: 2),
                                      history: history),
                       "Heaviest ever — 25 lb each")
        XCTAssertEqual(Tally.headline(for: Tally.Set(weight: 25, reps: 10),
                                      history: [Tally.Set(weight: 20, reps: 10)]),
                       "Heaviest ever — 25 lb")
        XCTAssertEqual(Tally.Record.reps(12, at: 25).headline(each: true),
                       "Most reps at 25 each — 12")
    }

    func testTheRecordBookSaysEach() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let book = Tally.recordBook([
            (start, "Hammer Curl", Tally.Set(weight: 20, reps: 10, implements: 2)),
            (start.addingTimeInterval(86_400), "Hammer Curl",
             Tally.Set(weight: 25, reps: 10, implements: 2)),
        ])
        XCTAssertEqual(book.map(\.headline), ["Heaviest ever — 25 lb each"])
    }

    func testTheTrendPlotsOneDumbbellAndSaysSo() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let trend = Tally.liftTrend([
            (day, Tally.Set(weight: 20, reps: 10, implements: 2)),
            (day.addingTimeInterval(86_400 * 7), Tally.Set(weight: 25, reps: 10, implements: 2)),
        ])
        XCTAssertEqual(trend.measure, .perDumbbell)
        XCTAssertEqual(trend.points.map(\.value), [20, 25], "per dumbbell, not doubled")
        XCTAssertEqual(trend.summary, "+5 lb each · 7 days")
    }

    func testTheLensSaysEachAndKeepsTheNumeralAlone() {
        let curl = Exercise(name: "Hammer Curl", loading: .dumbbell, dumbbells: 2)
        let load = LensState.load(weight: 25, word: curl.weightWord, reps: 10)
        XCTAssertEqual(load, "25 each × 10")
        XCTAssertEqual(LensArt.split(load).big, "25")
        XCTAssertEqual(LensArt.split(load).small, "each × 10")
        let bench = Exercise(name: "Bench Press", loading: .barbell)
        XCTAssertEqual(LensState.load(weight: 185, word: bench.weightWord, reps: 8), "185 × 8")
        let state = LensState.strength(exercise: "Hammer Curl", day: "Pull", nextSet: 1, of: 3,
                                       weight: 25, word: curl.weightWord, reps: 10, resting: nil)
        XCTAssertEqual(state.hero, "25 each × 10")
        XCTAssertEqual(state.detail, "Rest starts when you log it")
    }

    func testTheLensSaysHelpOnAnAssistedMachine() {
        // Found while adding "each": the lens took a unit and never read it,
        // so a pull-up assist read "70 × 8" — a load — on the glasses.
        let assist = Exercise(name: "Assisted Pull-Up", loading: .machine, assisted: true)
        let load = LensState.load(weight: 70, word: assist.weightWord, reps: 8)
        XCTAssertEqual(load, "70 help × 8")
        XCTAssertEqual(LensArt.split(load).big, "70")
        XCTAssertEqual(LensArt.split(load).small, "help × 8")
    }

    // MARK: - the export

    func testTheExportGoesThroughTally() throws {
        let context = context()
        let curl = exercise("Hammer Curl", in: context)
        let dip = exercise("Assisted Dip", in: context)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(WeighIn(pounds: 180, date: when.addingTimeInterval(-3600)))
        context.insert(SetEntry(exercise: curl, weight: 25, reps: 10, setIndex: 1, date: when))
        context.insert(SetEntry(exercise: dip, weight: 60, reps: 8, setIndex: 1,
                                date: when.addingTimeInterval(60)))
        try context.save()

        let rows = try Export.csv(from: context).split(separator: "\n").map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        let header = rows[0]
        let volume = try XCTUnwrap(header.firstIndex(of: "volume_lb"))
        let count = try XCTUnwrap(header.firstIndex(of: "dumbbells"))
        let curlRow = try XCTUnwrap(rows.first { $0.contains("hammer-curl") })
        let dipRow = try XCTUnwrap(rows.first { $0.contains("assisted-dip") })
        XCTAssertEqual(curlRow[volume], "500", "both dumbbells")
        XCTAssertEqual(curlRow[count], "2")
        // (180 − 60) × 8. The inline `weight × reps` exported 480 — the help.
        XCTAssertEqual(dipRow[volume], "960")
        XCTAssertEqual(dipRow[count], "", "blank off a dumbbell")
    }

    // MARK: - the snapshot

    func testTheSnapshotCountsThePairAndSaysHowMany() throws {
        let cal = Calendar.current
        // A Wednesday: Push A, which has Incline DB Press in it.
        let wednesday = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 18)))
        let context = context()
        try Seed.run(context, now: wednesday, weeksOfHistory: 0)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let press = try XCTUnwrap(exercises.first { $0.slug == "incline-db-press" })
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })
        context.insert(SetEntry(exercise: press, weight: 60, reps: 10, setIndex: 1, date: wednesday))
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 5, setIndex: 1,
                                date: wednesday.addingTimeInterval(60)))
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: wednesday)
        XCTAssertEqual(snapshot.schema, 8)
        let item = try XCTUnwrap(snapshot.today?.items.first { $0.slug == "incline-db-press" })
        XCTAssertEqual(item.volume, 1200, "60 × 10 × 2")
        XCTAssertEqual(item.dumbbells, 2)
        XCTAssertEqual(item.performed.first?.weight, 60, "weights stay per dumbbell")
        XCTAssertEqual(snapshot.today?.volume, 1200 + 925)

        let data = try SnapshotWriter.encoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summaries = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        let pressSummary = try XCTUnwrap(summaries.first { ($0["slug"] as? String) == "incline-db-press" })
        XCTAssertEqual(pressSummary["dumbbells"] as? Int, 2)
        XCTAssertEqual(pressSummary["working_weight"] as? Double, 60)
        let line = try XCTUnwrap((pressSummary["recent"] as? [[String: Any]])?.first)
        XCTAssertEqual(line["volume"] as? Double, 1200)
        let benchSummary = try XCTUnwrap(summaries.first { ($0["slug"] as? String) == "bench-press" })
        XCTAssertNil(benchSummary["dumbbells"], "absent off a dumbbell, not 1")

        let plan = try XCTUnwrap(object["plan"] as? [[String: Any]])
        let planned = plan.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }
        XCTAssertEqual(planned.first { ($0["slug"] as? String) == "incline-db-press" }?["dumbbells"] as? Int, 2)

        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertEqual(session.volume, 2125)
        XCTAssertEqual(session.topLifts, ["Bench Press 185", "Incline DB Press 60 each"])
    }
}
