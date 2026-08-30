import XCTest
import SwiftData
@testable import RathiFitness

/// Two workouts in one day.
///
/// The app had no way to say that. A session was inferred by grouping
/// `SetEntry.date` on `startOfDay`, so a morning lift and an evening lift were
/// one workout by construction: one row in history, one twelve-hour export to
/// Apple Health, one step of the rotation, and set numbering that ran 1–8
/// across the two.
final class SessionTests: XCTestCase {

    private let cal = Calendar.current

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 7) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    private func day(_ name: String, order: Int, in context: ModelContext) -> PlannedDay {
        let day = PlannedDay(name: name, weekday: 0, order: order)
        context.insert(day)
        return day
    }

    private func lift(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name)
        context.insert(exercise)
        return exercise
    }

    // MARK: opening and closing

    func testTheFirstSetOfAWorkoutOpensIt() throws {
        let context = context()
        let pull = day("Pull A", order: 0, in: context)

        let session = try XCTUnwrap(Sessions.current(for: pull, in: context))
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(session.dayName, "Pull A")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 1)
    }

    func testMoreSetsOfTheSameWorkoutJoinIt() throws {
        let context = context()
        let pull = day("Pull A", order: 0, in: context)

        let first = try XCTUnwrap(Sessions.current(for: pull, in: context))
        let second = try XCTUnwrap(Sessions.current(for: pull, in: context))

        XCTAssertEqual(first.persistentModelID, second.persistentModelID,
                       "the same workout must not open a second session")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 1)
    }

    /// The case this whole change exists for.
    func testASecondWorkoutOpensItsOwnSessionAndClosesTheFirst() throws {
        let context = context()
        let pull = day("Pull A", order: 0, in: context)
        let push = day("Push A", order: 1, in: context)

        let morning = try XCTUnwrap(Sessions.current(for: pull, in: context))
        let evening = try XCTUnwrap(Sessions.current(for: push, in: context))

        XCTAssertNotEqual(morning.persistentModelID, evening.persistentModelID)
        XCTAssertFalse(morning.isOpen, "starting a second workout ends the first")
        XCTAssertTrue(evening.isOpen)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 2)
    }

    /// Sessions are keyed by planned day, so the same workout twice would
    /// otherwise merge. Finishing one explicitly is the way out, and it has to
    /// actually work.
    func testFinishingAWorkoutLetsYouDoItAgainTheSameDay() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)

        let first = try XCTUnwrap(Sessions.current(for: push, in: context))
        Sessions.close(first, in: context)
        let second = try XCTUnwrap(Sessions.current(for: push, in: context))

        XCTAssertNotEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 2)
    }

    func testClosingUsesTheLastSetRatherThanTheMomentYouTapped() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)
        let bench = lift("Bench Press", in: context)
        let session = try XCTUnwrap(Sessions.current(for: push, in: context))

        let last = at(2026, 8, 25, 8)
        for (i, when) in [at(2026, 8, 25, 7), last].enumerated() {
            let entry = SetEntry(exercise: bench, weight: 185, reps: 8,
                                 setIndex: i + 1, date: when)
            entry.session = session
            context.insert(entry)
        }
        Sessions.close(session, in: context)

        XCTAssertEqual(session.endedAt, last,
                       "the span sent to Health is the workout, not however long "
                       + "the app stayed open afterwards")
    }

    func testAWorkoutLeftOpenOvernightIsClosedRatherThanCollectingTomorrow() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)
        let session = try XCTUnwrap(
            Sessions.current(for: push, in: context, now: at(2026, 8, 25, 19)))
        XCTAssertTrue(session.isOpen)

        Sessions.closeStale(in: context, now: at(2026, 8, 26, 7))
        XCTAssertFalse(session.isOpen, "Tuesday's workout is not still current on Wednesday")
    }

    // MARK: the rotation

    func testTwoWorkoutsInADayAdvanceTheRotationTwice() {
        let starts = [at(2026, 8, 25, 7), at(2026, 8, 25, 19)]
        let index = Rotation.index(on: at(2026, 8, 26), sessionDates: starts,
                                   dayCount: 4, calendar: cal)
        XCTAssertEqual(index, 2, "two workouts done means the third is up")
    }

    /// The property the old day-counting had right, and which must survive:
    /// extra sets join a workout, they do not make one.
    func testExtraSetsInOneWorkoutStillAdvanceItOnce() {
        let starts = [at(2026, 8, 25, 7)]
        let index = Rotation.index(on: at(2026, 8, 26), sessionDates: starts,
                                   dayCount: 4, calendar: cal)
        XCTAssertEqual(index, 1)
    }

    func testAWorkoutTodayDoesNotAdvanceTodaysRotation() {
        let starts = [at(2026, 8, 25, 7), at(2026, 8, 26, 7)]
        let index = Rotation.index(on: at(2026, 8, 26, 9), sessionDates: starts,
                                   dayCount: 4, calendar: cal)
        XCTAssertEqual(index, 1, "mid-workout you are still doing today's workout")
    }

    // MARK: the backfill

    func testHistoryWrittenBeforeSessionsExistedGetsOnePerDay() throws {
        let context = context()
        let bench = lift("Bench Press", in: context)
        for (i, when) in [at(2026, 8, 24, 7), at(2026, 8, 24, 8), at(2026, 8, 25, 7)].enumerated() {
            context.insert(SetEntry(exercise: bench, weight: 185, reps: 8,
                                    setIndex: i + 1, date: when))
        }

        let made = try Sessions.backfill(in: context)
        XCTAssertEqual(made, 2, "two days of history become two workouts")

        let orphans = try context.fetch(FetchDescriptor<SetEntry>()).filter { $0.session == nil }
        XCTAssertTrue(orphans.isEmpty, "every set should belong to a workout")
    }

    func testBackfillIsIdempotent() throws {
        let context = context()
        let bench = lift("Bench Press", in: context)
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8,
                                setIndex: 1, date: at(2026, 8, 24)))

        XCTAssertEqual(try Sessions.backfill(in: context), 1)
        XCTAssertEqual(try Sessions.backfill(in: context), 0,
                       "a second launch must not invent a second set of workouts")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 1)
    }

    /// A backfilled workout is named by what was actually in it, so history does
    /// not read "Workout, Workout, Workout".
    func testBackfillNamesADayFromWhatWasInIt() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)
        let bench = lift("Bench Press", in: context)
        let item = PlanItem(order: 0, exercise: bench, targetSets: 4,
                            targetReps: 8, targetWeight: 185)
        item.day = push
        context.insert(item)
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8,
                                setIndex: 1, date: at(2026, 8, 24)))

        try Sessions.backfill(in: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<Session>()).first)
        XCTAssertEqual(session.dayName, "Push A")
    }

    func testBackfillWillNotGuessWhenNothingMatches() throws {
        let context = context()
        let stranger = lift("Sandbag Carry", in: context)
        context.insert(SetEntry(exercise: stranger, weight: 100, reps: 1,
                                setIndex: 1, date: at(2026, 8, 24)))

        try Sessions.backfill(in: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<Session>()).first)
        XCTAssertEqual(session.dayName, Session.unnamed,
                       "a wrong label is worse than no label")
    }

    // MARK: what the snapshot says is up

    /// `Snapshot.today` picked the planned day whose `weekday` matched, which is
    /// only right in `.weekday` mode. On a rotation the phone uses
    /// `Rotation.index` and the pairing drifts on purpose — so `gym today` on
    /// the Mac disagreed with the phone in your pocket, and had since rotations
    /// shipped.
    func testTheSnapshotFollowsTheRotationRatherThanTheWeekday() throws {
        let context = context()
        let schedule = Schedule()
        var config = schedule.config
        config.mode = .rotation
        config.trainingWeekdays = [1, 2, 3, 4, 5, 6, 7]
        schedule.config = config
        context.insert(schedule)

        let names = ["Pull A", "Push A", "Legs"]
        for (i, name) in names.enumerated() {
            let planned = day(name, order: i, in: context)
            let exercise = lift("Lift \(i)", in: context)
            let item = PlanItem(order: 0, exercise: exercise, targetSets: 3,
                                targetReps: 8, targetWeight: 100)
            item.day = planned
            context.insert(item)
        }
        // Two workouts already done, so the rotation has reached the third.
        for start in [at(2026, 8, 27, 7), at(2026, 8, 28, 7)] {
            context.insert(Session(startedAt: start, dayName: "done"))
        }
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(2026, 8, 29, 9))
        XCTAssertEqual(snapshot.today?.day, "Legs",
                       "the Mac must answer what the phone answers")
    }

    /// And a workout actually in progress beats the rotation's guess — which is
    /// also how the second half of a two-a-day reads correctly.
    func testAnOpenWorkoutIsWhatTheSnapshotReports() throws {
        let context = context()
        for (i, name) in ["Pull A", "Push A"].enumerated() {
            let planned = day(name, order: i, in: context)
            let exercise = lift("Lift \(i)", in: context)
            let item = PlanItem(order: 0, exercise: exercise, targetSets: 3,
                                targetReps: 8, targetWeight: 100)
            item.day = planned
            context.insert(item)
        }
        let plannedDays = try context.fetch(FetchDescriptor<PlannedDay>())
        let push = try XCTUnwrap(plannedDays.first { $0.name == "Push A" })
        _ = Sessions.current(for: push, in: context, now: at(2026, 8, 29, 18))
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(2026, 8, 29, 19))
        XCTAssertEqual(snapshot.today?.day, "Push A",
                       "what you are doing beats what the cycle predicted")
    }

    /// Two workouts on one date are two rows, told apart by the clock and the
    /// ordinal. A reader keying on `date` alone would merge them back.
    func testTwoWorkoutsOnOneDateAreTwoSnapshotRows() throws {
        let context = context()
        let bench = lift("Bench Press", in: context)
        for (i, start) in [at(2026, 8, 28, 7), at(2026, 8, 28, 18)].enumerated() {
            let session = Session(startedAt: start, dayName: i == 0 ? "Push A" : "Legs")
            session.endedAt = start.addingTimeInterval(3600)
            context.insert(session)
            let entry = SetEntry(exercise: bench, weight: 185, reps: 8,
                                 setIndex: 1, date: start)
            entry.session = session
            context.insert(entry)
        }
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(2026, 8, 29, 9))
        let rows = snapshot.sessions.filter { $0.date == Fmt.day(at(2026, 8, 28)) }
        XCTAssertEqual(rows.count, 2, "a two-a-day is two rows, not one")
        XCTAssertEqual(Set(rows.map(\.ordinal)), [1, 2])
        XCTAssertEqual(Set(rows.compactMap(\.day)), ["Push A", "Legs"])
        XCTAssertNotEqual(rows[0].startedAt, rows[1].startedAt,
                          "the clock is what tells them apart")
    }

    /// A set that never got a session still has to reach the Mac. CloudKit
    /// delivers rows from devices on older builds.
    func testASetWithNoSessionStillReachesTheSnapshot() throws {
        let context = context()
        let bench = lift("Bench Press", in: context)
        context.insert(SetEntry(exercise: bench, weight: 185, reps: 8,
                                setIndex: 1, date: at(2026, 8, 26, 7)))
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(2026, 8, 27, 9))
        let row = try XCTUnwrap(snapshot.sessions.first {
            $0.date == Fmt.day(at(2026, 8, 26))
        })
        XCTAssertEqual(row.sets, 1)
        XCTAssertNil(row.day, "unnamed beats a guessed name")
    }

    // MARK: the name is a record, not a pointer

    func testRenamingAWorkoutDoesNotRewriteHistory() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)
        let session = try XCTUnwrap(Sessions.current(for: push, in: context))

        push.name = "Push (heavy)"

        XCTAssertEqual(session.dayName, "Push A",
                       "what you did in August is not renamed by editing the plan in October")
    }

    func testDeletingAPlannedDayLeavesTheWorkoutReadable() throws {
        let context = context()
        let push = day("Push A", order: 0, in: context)
        let session = try XCTUnwrap(Sessions.current(for: push, in: context))
        context.delete(push)

        XCTAssertEqual(session.title, "Push A")
    }
}
