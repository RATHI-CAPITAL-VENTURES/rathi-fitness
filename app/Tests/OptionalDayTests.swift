import XCTest
import SwiftData
@testable import RathiFitness

/// A day off, and what doing something on it moves.
///
/// The owner's plan is a four-workout rotation on Mon, Tue, Thu and Fri. On a
/// Saturday the app offers the next workout. Do it, and Monday gets the one
/// after; skip it, and Monday keeps what it had. Cardio — added to a lifting
/// day, or done on its own — counts as cardio and moves nothing.
final class OptionalDayTests: XCTestCase {

    private let cal = Calendar.current

    /// October 2026: the 5th is a Monday.
    private func oct(_ d: Int, _ h: Int = 18) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!
    }

    private struct Plan {
        let context: ModelContext
        let days: [PlannedDay]
        let schedule: Schedule
        let treadmill: Exercise
        let curl: Exercise
    }

    /// Arms, Legs, Back, Chest — in rotation on Mon, Tue, Thu, Fri, and
    /// Arms and Abs ending on a treadmill slot.
    private func plan(_ config: Rotation.Config = Rotation.Config(
        mode: .rotation, trainingWeekdays: [2, 3, 5, 6])) -> Plan {
        let context = ModelContext(Store.makeContainer(inMemory: true))
        let schedule = Schedule()
        schedule.config = config
        context.insert(schedule)
        let curl = Exercise(name: "Hammer Curl", loading: .dumbbell, dumbbells: 2)
        let treadmill = Exercise(name: "Treadmill", modality: .cardio)
        context.insert(curl)
        context.insert(treadmill)
        var days: [PlannedDay] = []
        for (i, name) in ["Arms and Abs", "Leg Day", "Shoulders and Back", "Chest and Abs"]
            .enumerated() {
            let day = PlannedDay(name: name, weekday: 0, order: i)
            context.insert(day)
            let lift = PlanItem(order: 0, exercise: i == 0 ? curl : Exercise(name: "\(name) Lift"),
                                targetSets: 3, targetReps: 10, targetWeight: 25)
            lift.day = day
            context.insert(lift)
            if i == 0 {
                let run = PlanItem(order: 1, exercise: treadmill, targetSets: 1, targetReps: 0,
                                   targetWeight: 0, restSeconds: 0, targetSeconds: 1200)
                run.day = day
                context.insert(run)
            }
            days.append(day)
        }
        return Plan(context: context, days: days, schedule: schedule,
                    treadmill: treadmill, curl: curl)
    }

    /// One lifted set on `day`, through the app's own write path.
    @discardableResult
    private func lift(_ day: PlannedDay, at date: Date, in context: ModelContext) -> SetEntry {
        let item = day.orderedItems[0]
        let exercise = item.exercise!
        Workout.logStrength(item: item, exercise: exercise, weight: 25, reps: 10,
                            kind: .working, setIndex: 1, at: date, in: context)
        Sessions.close(Sessions.current(for: day, in: context, now: date)!, in: context)
        return (try! context.fetch(FetchDescriptor<SetEntry>())).max { $0.date < $1.date }!
    }

    /// A cardio bout, written by `Workout.logBout` — the call the cardio screen
    /// makes — so the routing tested is the routing that runs.
    @discardableResult
    private func bout(_ exercise: Exercise, seconds: Int, miles: Double = 0, at date: Date,
                      extraFor day: PlannedDay? = nil, alone: Bool = false,
                      in context: ModelContext) -> SetEntry {
        let entry = SetEntry(exercise: exercise, weight: 0, reps: 0, setIndex: 1, date: date,
                             seconds: seconds, distance: miles)
        let purpose: Workout.CardioPurpose = day.map { .extra($0) } ?? .alone
        precondition(alone || day != nil, "say which button logged it")
        Workout.logBout(entry, for: purpose, in: context, now: date, calendar: cal)
        return entry
    }

    private func today(_ plan: Plan, on date: Date) throws -> PlannedDay? {
        let sessions = try plan.context.fetch(FetchDescriptor<Session>())
        let sets = try plan.context.fetch(FetchDescriptor<SetEntry>())
        return Workout.today(days: plan.days, config: plan.schedule.config,
                             sessionDates: Workout.rotationDates(sessions),
                             lastSession: Workout.lastSessionDate(in: sets, now: date, calendar: cal),
                             now: date, calendar: cal)
    }

    private func offer(_ plan: Plan, on date: Date) throws -> PlannedDay? {
        let sessions = try plan.context.fetch(FetchDescriptor<Session>())
        let sets = try plan.context.fetch(FetchDescriptor<SetEntry>())
        return Workout.optionalDay(days: plan.days, config: plan.schedule.config,
                                   sessionDates: Workout.rotationDates(sessions),
                                   lastSession: Workout.lastSessionDate(in: sets, now: date,
                                                                        calendar: cal),
                                   now: date, calendar: cal)
    }

    /// The week: all four done, Mon to Fri.
    private func trainedTheWeek(_ plan: Plan) {
        for (day, date) in zip(plan.days, [oct(5), oct(6), oct(8), oct(9)]) {
            lift(day, at: date, in: plan.context)
        }
    }

    // MARK: offered only on a day off

    func testTheOptionalDayIsOfferedOnlyOnADayOff() throws {
        XCTAssertEqual(cal.component(.weekday, from: oct(10)), 7, "the 10th is a Saturday")
        let plan = plan()
        trainedTheWeek(plan)

        XCTAssertNil(try today(plan, on: oct(10)), "Saturday is not a training day")
        XCTAssertEqual(try offer(plan, on: oct(10))?.name, "Arms and Abs",
                       "the next in the rotation, after four done")
        XCTAssertNil(try offer(plan, on: oct(12)), "Monday has its own workout — nothing to offer")
    }

    // MARK: doing it advances the rotation; skipping it does not

    func testDoingTheOptionalDayGivesMondayTheWorkoutAfterIt() throws {
        let plan = plan()
        trainedTheWeek(plan)
        let saturday = lift(plan.days[0], at: oct(10), in: plan.context)

        XCTAssertEqual(saturday.session?.sessionKind, .optional,
                       "a workout on a day the schedule left empty is marked optional")
        XCTAssertEqual(try today(plan, on: oct(12))?.name, "Leg Day",
                       "Monday gets the workout after the one done on Saturday")
    }

    func testSkippingTheOptionalDayShiftsNothing() throws {
        let plan = plan()
        trainedTheWeek(plan)

        XCTAssertEqual(try today(plan, on: oct(12))?.name, "Arms and Abs",
                       "nothing done on Saturday, so Monday keeps its workout")
    }

    func testAWorkoutOnATrainingDayIsNotOptional() throws {
        let plan = plan()
        let monday = lift(plan.days[0], at: oct(5), in: plan.context)
        XCTAssertEqual(monday.session?.sessionKind, .planned)
    }

    /// "If we don't work these days, they stay the original days": an optional
    /// session must not restart the every-N-days clock.
    func testAnOptionalDayDoesNotMoveTheEveryNDaysClock() throws {
        let plan = plan(Rotation.Config(mode: .everyNDays, everyNDays: 2))
        lift(plan.days[0], at: oct(5), in: plan.context)          // Mon, planned
        XCTAssertNil(try today(plan, on: oct(6)), "Tuesday is a day off at every 2 days")
        let tuesday = lift(plan.days[1], at: oct(6), in: plan.context)
        XCTAssertEqual(tuesday.session?.sessionKind, .optional)

        XCTAssertEqual(try today(plan, on: oct(7))?.name, "Shoulders and Back",
                       "Wednesday is still a training day, and it has the next workout")
    }

    /// Weekday mode has no rotation to advance, so it offers the next weekday's
    /// workout and that weekday keeps it.
    func testWeekdayModeOffersTheNextWeekdaysWorkout() throws {
        let plan = plan(Rotation.Config(mode: .weekday))
        plan.days[0].weekday = 2      // Monday
        plan.days[1].weekday = 4      // Wednesday
        plan.days[2].weekday = 0
        plan.days[3].weekday = 0

        XCTAssertEqual(try offer(plan, on: oct(10))?.name, "Arms and Abs",
                       "Saturday offers Monday's workout")
        XCTAssertEqual(try offer(plan, on: oct(6))?.name, "Leg Day",
                       "Tuesday offers Wednesday's")
        lift(plan.days[0], at: oct(10), in: plan.context)
        XCTAssertEqual(try today(plan, on: oct(12))?.name, "Arms and Abs",
                       "Monday keeps Monday's workout either way")
    }

    // MARK: cardio on its own moves nothing

    func testCardioOnItsOwnDoesNotAdvanceTheRotation() throws {
        let plan = plan()
        trainedTheWeek(plan)
        let ride = bout(plan.treadmill, seconds: 1800, at: oct(10), alone: true, in: plan.context)

        XCTAssertEqual(ride.session?.sessionKind, .cardio)
        XCTAssertNil(ride.session?.plannedDay)
        XCTAssertEqual(ride.session?.dayName, "Treadmill")
        XCTAssertEqual(try today(plan, on: oct(12))?.name, "Arms and Abs",
                       "a ride on Saturday leaves Monday's workout where it was")
        XCTAssertEqual(try offer(plan, on: oct(10))?.name, "Arms and Abs",
                       "and the optional day is still on offer after it")
    }

    func testCardioOnItsOwnDoesNotMoveTheEveryNDaysClock() throws {
        let plan = plan(Rotation.Config(mode: .everyNDays, everyNDays: 2))
        lift(plan.days[0], at: oct(5), in: plan.context)
        bout(plan.treadmill, seconds: 1200, at: oct(6), alone: true, in: plan.context)
        XCTAssertEqual(try today(plan, on: oct(7))?.name, "Leg Day")
    }

    /// A second machine joins the visit rather than starting a second workout.
    func testASecondMachineJoinsTheSameCardioSession() throws {
        let plan = plan()
        let rower = Exercise(name: "Rower", modality: .cardio)
        plan.context.insert(rower)
        let first = bout(plan.treadmill, seconds: 900, at: oct(10, 9), alone: true, in: plan.context)
        let second = bout(rower, seconds: 600, at: oct(10, 10), alone: true, in: plan.context)

        XCTAssertTrue(first.session === second.session)
        XCTAssertEqual(first.session?.dayName, "Treadmill + Rower")
    }

    // MARK: cardio added to a lifting day

    func testExtraCardioIsOutsideThePlanButInTheCardioTotals() throws {
        let plan = plan()
        let monday = oct(5)
        let context = plan.context
        let item = plan.days[0].orderedItems[0]
        Workout.logStrength(item: item, exercise: plan.curl, weight: 25, reps: 10,
                            kind: .working, setIndex: 1, at: monday.addingTimeInterval(60),
                            in: context)
        let extra = bout(plan.treadmill, seconds: 900, miles: 1.2,
                         at: monday.addingTimeInterval(600), extraFor: plan.days[0], in: context)
        try context.save()

        let run = plan.days[0].orderedItems[1]
        let todays = [extra] + (try context.fetch(FetchDescriptor<SetEntry>()))
            .filter { $0.persistentModelID != extra.persistentModelID }
        XCTAssertTrue(Workout.performed(run, in: todays).isEmpty,
                      "an extra treadmill bout must not tick the plan's treadmill slot")
        XCTAssertFalse(Workout.isDone(run, in: todays))
        XCTAssertEqual(Workout.extras(in: todays).map(\.seconds), [900])

        let snapshot = try SnapshotBuilder.build(from: context, now: monday.addingTimeInterval(700))
        let block = try XCTUnwrap(snapshot.today)
        XCTAssertEqual(block.exercisesPlanned, 2)
        XCTAssertEqual(block.exercisesDone, 0, "the curl has one set of three; the run none")
        XCTAssertEqual(block.setsPlanned, 4)
        XCTAssertEqual(block.setsDone, 1, "the extra bout is not a set of the plan")
        XCTAssertEqual(block.items[1].setsDone, 0)
        XCTAssertEqual(block.extras.map(\.name), ["Treadmill"])
        XCTAssertEqual(block.extras.first?.cardio?.seconds, 900)
        XCTAssertEqual(block.volume, 500, "two 25s × 10 — and no tonnage from a treadmill")
        XCTAssertNil(block.optional, "Monday is a training day")

        let session = try XCTUnwrap(snapshot.sessions.first)
        XCTAssertEqual(session.cardioMinutes, 15, "the extra bout is in the cardio total")
        XCTAssertEqual(session.cardioDistance, 1.2)
        XCTAssertEqual(session.volume, 500)
        XCTAssertNil(session.kind)
    }

    // MARK: the review's scenario — a ride from the row mid-workout

    /// Rest day: ride, start the optional day and lift, tap the treadmill under
    /// "Cardio today" for a cool-down, lift again. It used to close the lifting
    /// workout for a cardio session, so the second lift opened a SECOND optional
    /// workout and Monday skipped one.
    func testARideMidWorkoutJoinsItAndTheRotationMovesOnce() throws {
        let plan = plan()
        trainedTheWeek(plan)
        let context = plan.context
        let arms = plan.days[0]
        bout(plan.treadmill, seconds: 900, at: oct(10, 9), alone: true, in: context)

        let item = arms.orderedItems[0]
        for (i, minute) in [0, 3, 6].enumerated() {
            Workout.logStrength(item: item, exercise: plan.curl, weight: 25, reps: 10,
                                kind: .working, setIndex: i + 1,
                                at: oct(10, 10).addingTimeInterval(Double(minute) * 60), in: context)
        }
        let coolDown = bout(plan.treadmill, seconds: 600, at: oct(10, 11), alone: true, in: context)
        XCTAssertTrue(coolDown.extra, "with a workout open, a ride joins it as an extra")
        XCTAssertEqual(coolDown.session?.sessionKind, .optional)
        Workout.logStrength(item: item, exercise: plan.curl, weight: 25, reps: 10,
                            kind: .working, setIndex: 4, at: oct(10, 11).addingTimeInterval(120),
                            in: context)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let saturday = sessions.filter { cal.isDate($0.startedAt, inSameDayAs: oct(10)) }
        XCTAssertEqual(saturday.filter { !$0.isCardioOnly }.count, 1,
                       "one lifting workout on Saturday, not two")
        XCTAssertEqual(saturday.filter(\.isCardioOnly).count, 1, "the morning ride")
        XCTAssertTrue(saturday.first { !$0.isCardioOnly }?.isOpen ?? false,
                      "the cool-down did not close the workout")
        XCTAssertEqual(try today(plan, on: oct(12))?.name, "Leg Day",
                       "the rotation moved once: Monday gets the workout after Saturday's")
    }

    // MARK: "Add cardio" with nothing lifted

    /// "Add cardio" opens the day's workout to put the bout in. If nothing is
    /// then lifted, nothing of the plan happened and the rotation stays put.
    func testAnExtraWithNoLiftDoesNotAdvanceTheRotation() throws {
        let plan = plan()
        trainedTheWeek(plan)
        let monday = try XCTUnwrap(try today(plan, on: oct(12)))
        XCTAssertEqual(monday.name, "Arms and Abs")
        bout(plan.treadmill, seconds: 1200, at: oct(12), extraFor: monday, in: plan.context)
        Sessions.closeStale(in: plan.context, now: oct(13))
        try plan.context.save()

        XCTAssertEqual(try today(plan, on: oct(13))?.name, "Arms and Abs",
                       "Tuesday still owes the workout Monday never lifted")
        let sessions = try plan.context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(Workout.workouts(sessions).count, 4,
                       "the extra-only session is not a workout — not in Trends' count either")
    }

    func testTrendsCountsWorkoutsNotRides() throws {
        let plan = plan()
        trainedTheWeek(plan)
        bout(plan.treadmill, seconds: 1200, at: oct(10), alone: true, in: plan.context)
        try plan.context.save()
        let sessions = try plan.context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 5)
        XCTAssertEqual(Workout.workouts(sessions).count, 4)
    }

    // MARK: the snapshot

    /// A ride in the morning and a lift in the evening: the ride stays in
    /// `today` (as `cardio_alone`) rather than vanishing once you lift.
    func testARideBeforeLiftingStaysInToday() throws {
        let plan = plan()
        trainedTheWeek(plan)
        bout(plan.treadmill, seconds: 900, miles: 1, at: oct(10, 9), alone: true, in: plan.context)
        lift(plan.days[0], at: oct(10, 18), in: plan.context)
        try plan.context.save()

        let snapshot = try SnapshotBuilder.build(from: plan.context, now: oct(10, 19))
        let block = try XCTUnwrap(snapshot.today)
        XCTAssertEqual(block.cardioAlone.map(\.name), ["Treadmill"])
        XCTAssertEqual(block.cardioAlone.first?.cardio?.seconds, 900)
        XCTAssertTrue(block.extras.isEmpty)
        XCTAssertEqual(block.setsDone, 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: SnapshotWriter.encoder().encode(snapshot)) as? [String: Any])
        XCTAssertNotNil((json["today"] as? [String: Any])?["cardio_alone"])
    }

    /// Optional is the session's stored kind, not today's schedule: making
    /// Saturday a training day afterwards does not relabel last Saturday.
    func testOptionalIsReadFromTheSessionNotRecomputed() throws {
        let plan = plan()
        trainedTheWeek(plan)
        lift(plan.days[0], at: oct(10, 10), in: plan.context)
        plan.schedule.config = Rotation.Config(mode: .rotation, trainingWeekdays: [2, 3, 5, 6, 7])
        try plan.context.save()

        let snapshot = try SnapshotBuilder.build(from: plan.context, now: oct(10, 20))
        XCTAssertEqual(snapshot.today?.optional, true)
    }

    // MARK: the snapshot

    func testTheSnapshotHasNoTodayOnARotationsDayOff() throws {
        let plan = plan()
        trainedTheWeek(plan)
        let snapshot = try SnapshotBuilder.build(from: plan.context, now: oct(10))

        XCTAssertNil(snapshot.today,
                     "a rotation's day off is a rest day on the Mac too, as on the phone")
        XCTAssertEqual(snapshot.restDay?.optional, "Arms and Abs")
        XCTAssertEqual(snapshot.restDay?.cardio.count, 0)
        XCTAssertEqual(snapshot.restDay?.date, "2026-10-10")
    }

    func testTheSnapshotCarriesTheOptionalDayAndTheKindOfEachSession() throws {
        let plan = plan()
        trainedTheWeek(plan)
        lift(plan.days[0], at: oct(10, 10), in: plan.context)
        bout(plan.treadmill, seconds: 1500, miles: 2, at: oct(11), alone: true, in: plan.context)
        try plan.context.save()

        let saturday = try SnapshotBuilder.build(from: plan.context, now: oct(10, 20))
        XCTAssertEqual(saturday.today?.day, "Arms and Abs",
                       "a finished optional day is still the day's workout")
        XCTAssertEqual(saturday.today?.optional, true)
        XCTAssertNil(saturday.restDay)

        let sunday = try SnapshotBuilder.build(from: plan.context, now: oct(11, 20))
        XCTAssertNil(sunday.today)
        XCTAssertEqual(sunday.restDay?.optional, "Leg Day",
                       "Saturday advanced the rotation; Sunday's ride did not")
        XCTAssertEqual(sunday.restDay?.cardio.first?.cardio?.seconds, 1500)

        let data = try SnapshotWriter.encoder().encode(sunday)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rest = try XCTUnwrap(object["rest_day"] as? [String: Any])
        XCTAssertEqual(rest["optional"] as? String, "Leg Day")
        let sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.compactMap { $0["kind"] as? String }, ["cardio", "optional"],
                       "newest first; a scheduled workout carries no kind")
        XCTAssertEqual(sessions.filter { $0["kind"] == nil }.count, 4)
    }

    func testTheExportSaysWhatWasExtraAndWhatKindOfWorkout() throws {
        let plan = plan()
        lift(plan.days[0], at: oct(10), in: plan.context)
        bout(plan.treadmill, seconds: 600, at: oct(10, 19), extraFor: plan.days[0], in: plan.context)
        try plan.context.save()

        let lines = try Export.csv(from: plan.context).split(separator: "\n").map(String.init)
        XCTAssertTrue(Export.header.hasSuffix(",extra,workout"))
        XCTAssertTrue(lines[1].hasSuffix(",false,optional"), lines[1])
        XCTAssertTrue(lines[2].hasSuffix(",true,optional"), lines[2])
    }
}
