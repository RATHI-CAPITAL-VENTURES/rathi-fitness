import XCTest
import SwiftData
@testable import RathiFitness

final class SnapshotTests: XCTestCase {

    private func seededContext(now: Date = .now, history: Int = 6) throws -> ModelContext {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try Seed.run(context, now: now, weeksOfHistory: history)
        return context
    }

    // MARK: the security property

    func testPassCodesNeverReachTheSnapshot() throws {
        let context = try seededContext()
        let secret = "SUPERSECRETMEMBERCODE-9931"
        context.insert(GymPass(name: "Blink Fitness", location: "Union Square",
                               code: secret, symbology: .code128,
                               memberID: "9911223344917", isPrimary: true))
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context)
        let json = String(data: try SnapshotWriter.encoder().encode(snapshot), encoding: .utf8)!

        // The snapshot lands in a folder any process on the Mac can read. A
        // scannable credential in there is the same mistake as an access code
        // in a commit message.
        XCTAssertFalse(json.contains(secret), "the pass code leaked into the snapshot")
        XCTAssertFalse(json.contains("9911223344"), "the full member number leaked")
        // But RIA still learns the pass exists and is usable.
        XCTAssertTrue(json.contains("Blink Fitness"))
        XCTAssertTrue(json.contains("\"has_code\" : true"))
        XCTAssertEqual(snapshot.passes.first?.memberIdMasked, "•••• 4917")
    }

    func testMaskingShortIDs() {
        XCTAssertEqual(SnapshotBuilder.mask(""), "")
        XCTAssertEqual(SnapshotBuilder.mask("42"), "••••")
        XCTAssertEqual(SnapshotBuilder.mask("123456"), "•••• 3456")
    }

    // MARK: the shape the CLI relies on

    func testSetKindsAndRpeReachTheSnapshot() throws {
        let context = try seededContext()
        let bench = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>()).first { $0.slug == "bench-press" })
        context.insert(SetEntry(exercise: bench, weight: 135, reps: 10, setIndex: 1,
                                kind: .warmup))
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8, setIndex: 2,
                                kind: .working, rpe: 8.5, note: "felt good"))
        try context.save()

        let data = try SnapshotWriter.encoder().encode(try SnapshotBuilder.build(from: context))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema"] as? Int, Snapshot.currentSchema)

        let exercise = try XCTUnwrap((object["exercises"] as? [[String: Any]])?
            .first { ($0["slug"] as? String) == "bench-press" })
        XCTAssertEqual(exercise["primary_muscle"] as? String, "chest")
        XCTAssertNotNil(exercise["secondary_muscles"])

        let line = try XCTUnwrap((exercise["recent"] as? [[String: Any]])?.first)
        // The warm-up is counted, not silently folded into the working sets.
        XCTAssertEqual(line["warmup_sets"] as? Int, 1)
        XCTAssertEqual((line["reps"] as? [Int])?.count, 1, "only the working set's reps")
        XCTAssertEqual(line["top_weight"] as? Double, 185)
        XCTAssertEqual(line["volume"] as? Double, 185 * 8, "the warm-up adds no volume")
        XCTAssertEqual(line["average_rpe"] as? Double, 8.5)
    }

    func testAWarmUpDoesNotTickAnExerciseOff() throws {
        // Three warm-ups used to mark an exercise done — the checklist lying
        // about the one thing it is for.
        let cal = Calendar.current
        let wednesday = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 18)))
        // No seeded history: this test is about what four warm-ups alone do.
        let context = try seededContext(now: wednesday, history: 0)
        let bench = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>()).first { $0.slug == "bench-press" })
        for i in 1...4 {
            context.insert(SetEntry(exercise: bench, weight: 135, reps: 10, setIndex: i,
                                    date: wednesday, kind: .warmup))
        }
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: wednesday)
        let item = try XCTUnwrap(snapshot.today?.items.first { $0.slug == "bench-press" })
        XCTAssertFalse(item.done, "four warm-ups is not a finished exercise")
        XCTAssertEqual(item.setsDone, 0)
        XCTAssertEqual(item.warmupSets, 4)
        XCTAssertEqual(item.volume, 0)
        XCTAssertEqual(snapshot.today?.volume, 0, "warm-ups move no load")
    }

    func testRpeIsAbsentRatherThanZeroWhenNotRecorded() throws {
        let context = try seededContext()
        let bench = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>()).first { $0.slug == "bench-press" })
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8, setIndex: 1))
        try context.save()
        let json = String(data: try SnapshotWriter.encoder()
            .encode(try SnapshotBuilder.build(from: context)), encoding: .utf8)!
        // Not recorded is not the same as easy, so it must not arrive as 0.
        XCTAssertFalse(json.contains("\"rpe\" : 0"))
    }

    func testSnakeCaseKeysAndSchemaVersion() throws {
        let context = try seededContext()
        let data = try SnapshotWriter.encoder().encode(try SnapshotBuilder.build(from: context))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schema"] as? Int, Snapshot.currentSchema)
        // Pinned as a literal on purpose, and it is the ONLY place that is.
        // The CLI refuses a version it does not know, so bumping the app's
        // schema without bumping `SCHEMA_SUPPORTED` in `cli/gym` makes RIA go
        // blind until someone notices. Failing here is the reminder.
        XCTAssertEqual(Snapshot.currentSchema, 4)
        // The CLI reads these exact keys. Renaming one is a schema bump.
        for key in ["generated_at", "body_weight", "exercises", "plan", "passes", "sessions"] {
            XCTAssertNotNil(object[key], "missing top-level key \(key)")
        }
        let body = try XCTUnwrap(object["body_weight"] as? [String: Any])
        for key in ["current", "current_date", "change_30d", "trend_per_week", "history", "unit"] {
            XCTAssertNotNil(body[key], "missing body_weight key \(key)")
        }
        // The trap this pins down: `convertToSnakeCase` splits on capitals and
        // NOT on digits, so `change30d` silently ships as "change30d" next to
        // "trend_per_week" and the CLI reads nil forever without erroring.
        XCTAssertNil(body["change30d"], "the un-snaked key must not come back")

        let exercise = try XCTUnwrap((object["exercises"] as? [[String: Any]])?.first)
        for key in ["slug", "name", "loading", "working_weight", "last_performed", "change_30d"] {
            XCTAssertNotNil(exercise[key], "missing exercise key \(key)")
        }
        XCTAssertNil(exercise["change30d"])
    }

    func testNumbersAreRoundedBeforeTheyLeaveTheApp() throws {
        let context = try seededContext()
        let snapshot = try SnapshotBuilder.build(from: context)
        // 176.4 - 178.2 is -1.799999999999983 in binary floating point. RIA may
        // read this number out loud.
        if let change = snapshot.bodyWeight.change30d {
            XCTAssertEqual(change, (change * 10).rounded() / 10, accuracy: 1e-9)
        }
        if let trend = snapshot.bodyWeight.trendPerWeek {
            XCTAssertEqual(trend, (trend * 10).rounded() / 10, accuracy: 1e-9)
        }
    }

    func testTodayIsPresentOnATrainingDayAndAbsentOnARestDay() throws {
        // Seed weekdays are Mon(2), Wed(4), Fri(6). Pick a known Wednesday and a
        // known Sunday rather than whatever day the test happens to run on.
        let cal = Calendar.current
        let wednesday = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 18)))
        let sunday = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 18)))
        XCTAssertEqual(cal.component(.weekday, from: wednesday), 4)
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)

        let context = try seededContext(now: wednesday)
        let training = try SnapshotBuilder.build(from: context, now: wednesday)
        XCTAssertEqual(training.today?.day, "Push A")
        XCTAssertEqual(training.today?.exercisesPlanned, 6)

        let rest = try SnapshotBuilder.build(from: context, now: sunday)
        XCTAssertNil(rest.today, "a rest day should have no plan, not an empty one")
    }

    func testBodyWeightTrendIsNegativeForTheSeededCut() throws {
        let context = try seededContext()
        let snapshot = try SnapshotBuilder.build(from: context)
        let change = try XCTUnwrap(snapshot.bodyWeight.change30d)
        XCTAssertLessThan(change, 0, "the seeded history is a cut; the trend should show it")
        XCTAssertEqual(snapshot.bodyWeight.current, 176.4)
        XCTAssertEqual(snapshot.bodyWeight.unit, "lb")
    }

    func testExerciseSummariesCarryWorkingWeightAndHistory() throws {
        let context = try seededContext()
        let snapshot = try SnapshotBuilder.build(from: context)
        let bench = try XCTUnwrap(snapshot.exercises.first { $0.slug == "bench-press" })
        XCTAssertEqual(bench.name, "Bench Press")
        XCTAssertEqual(bench.workingWeight, 185)
        XCTAssertFalse(bench.recent.isEmpty)
        XCTAssertNotNil(bench.best)
        // Six weeks at +2.5/wk means the 30-day change is real and positive.
        XCTAssertGreaterThan(try XCTUnwrap(bench.change30d), 0)
    }

    func testSlugsAreStableAndUrlSafe() {
        XCTAssertEqual(Exercise.slugify("Incline DB Press"), "incline-db-press")
        XCTAssertEqual(Exercise.slugify("  Leg   Curl  "), "leg-curl")
        XCTAssertEqual(Exercise.slugify("Farmer's Walk"), "farmer-s-walk")
    }

    func testWritesAtomicallyAndReadsBack() throws {
        let context = try seededContext()
        let snapshot = try SnapshotBuilder.build(from: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try SnapshotWriter.write(snapshot, to: .local(url))
        let reread = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        XCTAssertNotNil(reread as? [String: Any])
    }

    func testSeedIsDeterministic() throws {
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 18)))
        let a = try SnapshotWriter.encoder().encode(
            try SnapshotBuilder.build(from: try seededContext(now: now), now: now,
                                      appVersion: "test"))
        let b = try SnapshotWriter.encoder().encode(
            try SnapshotBuilder.build(from: try seededContext(now: now), now: now,
                                      appVersion: "test"))
        // Two fresh installs should show the same demo history — otherwise a
        // screenshot taken today does not match one taken tomorrow.
        XCTAssertEqual(a, b)
    }

    func testSeedDoesNotRunTwice() throws {
        let container = Store.makeContainer(inMemory: true)
        let context = ModelContext(container)
        try Seed.runIfNeeded(context)
        let first = try context.fetchCount(FetchDescriptor<PlannedDay>())
        try Seed.runIfNeeded(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedDay>()), first)
    }

    func testPassStateLineReadsLikeACard() {
        let punch = GymPass(name: "VITAL Climbing", code: "x", punches: 6, punchesNeeded: 10)
        XCTAssertEqual(punch.stateLine, "6 of 10 punched")
        XCTAssertFalse(punch.isExpired)

        let used = GymPass(name: "Punch", code: "x", punches: 10, punchesNeeded: 10)
        XCTAssertTrue(used.isExpired)

        let plain = GymPass(name: "Blink", code: "x")
        XCTAssertNil(plain.stateLine, "a plain membership has nothing to say about state")
    }
}
