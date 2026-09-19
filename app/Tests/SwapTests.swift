import XCTest
import SwiftData
@testable import RathiFitness

/// The treadmills are all taken, so you get on a bike.
///
/// The only way to say that used to be editing the plan — which says it for
/// every week from now on. These pin the three promises a swap makes instead:
/// it lasts a day, the plan never hears about it, and the stand-in inherits the
/// shape of the work but none of the load.
final class SwapTests: XCTestCase {

    private let cal = Calendar.current

    private func at(_ d: Int, _ h: Int = 18) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    private func cardio(_ name: String, _ metrics: [CardioMetric],
                        in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, loading: .machine, barWeight: 0,
                                primary: .quads, modality: .cardio, metrics: metrics)
        context.insert(exercise)
        return exercise
    }

    private func lift(_ name: String, _ primary: MuscleGroup,
                      loading: Exercise.Loading = .barbell, bar: Double = 45,
                      in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, loading: loading, barWeight: bar, primary: primary)
        context.insert(exercise)
        return exercise
    }

    /// Legs: squat, then twenty minutes on the treadmill at 3%, two miles.
    private func legs(in context: ModelContext)
        -> (day: PlannedDay, squat: PlanItem, run: PlanItem) {
        let day = PlannedDay(name: "Legs", weekday: 0)
        context.insert(day)
        let squat = PlanItem(order: 0, exercise: lift("Squat", .quads, in: context),
                             targetSets: 4, targetReps: 6, targetWeight: 225,
                             restSeconds: 180)
        let run = PlanItem(order: 1,
                           exercise: cardio("Treadmill",
                                            [.duration, .distance, .speed, .incline],
                                            in: context),
                           targetSets: 1, targetReps: 0, targetWeight: 0, restSeconds: 0,
                           targetSeconds: 1200, targetDistance: 2,
                           targetSpeed: 6, targetIncline: 3)
        for item in [squat, run] { item.day = day; context.insert(item) }
        return (day, squat, run)
    }

    // MARK: it lasts a day

    func testASwapPutsTheStandInInTheSlotToday() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration, .distance, .resistance], in: context)

        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        XCTAssertEqual(Swaps.exercise(for: plan.run, on: at(14, 20), calendar: cal)?.slug,
                       "stationary-bike")
    }

    /// The whole reason it is a dated row and not a field on the slot: nothing
    /// has to run for tomorrow to be the treadmill again.
    func testTomorrowIsThePlanAgainWithNothingHavingToClearIt() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)

        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        XCTAssertNil(Swaps.standIn(for: plan.run, on: at(15), calendar: cal))
        XCTAssertEqual(Swaps.exercise(for: plan.run, on: at(15), calendar: cal)?.slug,
                       "treadmill")
    }

    func testThePlanNeverHearsAboutIt() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)

        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        XCTAssertEqual(plan.run.exercise?.slug, "treadmill")
        XCTAssertEqual(plan.run.targetDistance, 2)
        XCTAssertEqual(plan.run.targetIncline, 3)
    }

    func testChangingYourMindReplacesRatherThanStacks() throws {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        let rower = cardio("Rower", [.duration, .distance], in: context)

        Swaps.put(bike, in: plan.run, context: context, now: at(14, 18), calendar: cal)
        Swaps.put(rower, in: plan.run, context: context, now: at(14, 19), calendar: cal)
        try context.save()

        XCTAssertEqual(Swaps.standIn(for: plan.run, on: at(14), calendar: cal)?.slug, "rower")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Swap>()), 1,
                       "one row per slot per day")
    }

    /// Before the save, too. A deleted row stays in the relationship until
    /// pending changes are processed — the same trap `Sessions.pruneEmpty`
    /// documents — and a swap-back that only takes after the next save leaves
    /// the bike on screen while you stare at it.
    func testSwappingBackShowsThePlanImmediately() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        Swaps.clear(plan.run, context: context, on: at(14), calendar: cal)

        XCTAssertNil(Swaps.standIn(for: plan.run, on: at(14), calendar: cal))
    }

    func testChoosingTheSlotsOwnExerciseIsSwappingBackNotASwap() throws {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        Swaps.put(try XCTUnwrap(plan.run.exercise), in: plan.run,
                  context: context, now: at(14), calendar: cal)
        try context.save()

        XCTAssertNil(Swaps.standIn(for: plan.run, on: at(14), calendar: cal))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Swap>()), 0)
    }

    func testASwapOnOneSlotLeavesTheOthersAlone() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)

        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        XCTAssertNil(Swaps.standIn(for: plan.squat, on: at(14), calendar: cal))
    }

    // MARK: the shape carries, the load does not

    func testTwentyMinutesCarriesOverButTwoMilesAtThreePercentDoesNot() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration, .distance, .resistance], in: context)

        let asked = Swaps.prescription(for: plan.run, doing: bike)

        XCTAssertEqual(asked.seconds, 1200)
        XCTAssertEqual(asked.sets, 1)
        XCTAssertEqual(asked.distance, 0, "two treadmill miles is not two bike miles")
        XCTAssertEqual(asked.speed, 0)
        XCTAssertEqual(asked.incline, 0, "a bike has no grade")
    }

    func testTheSlotsOwnExerciseGetsThePlanUntouched() throws {
        let context = context()
        let plan = legs(in: context)

        let asked = Swaps.prescription(for: plan.run, doing: try XCTUnwrap(plan.run.exercise))

        XCTAssertEqual(asked, Swaps.Prescription(sets: 1, reps: 0, restSeconds: 0,
                                                 seconds: 1200, weight: 0, distance: 2,
                                                 speed: 6, incline: 3, resistance: 0))
    }

    func testAStandInLiftKeepsSetsRepsAndRestAndOpensOnItsOwnBar() {
        let context = context()
        let plan = legs(in: context)
        let front = lift("Front Squat", .quads, bar: 35, in: context)

        let asked = Swaps.prescription(for: plan.squat, doing: front)

        XCTAssertEqual(asked.sets, 4)
        XCTAssertEqual(asked.reps, 6)
        XCTAssertEqual(asked.restSeconds, 180)
        XCTAssertEqual(asked.weight, 35,
                       "225 is a fact about the back squat; the empty bar is the "
                       + "one weight known to be loadable")
    }

    func testAStandInWithNoBarOpensOnNothing() {
        let context = context()
        let plan = legs(in: context)
        let press = lift("Leg Press", .quads, loading: .machine, bar: 0, in: context)

        XCTAssertEqual(Swaps.prescription(for: plan.squat, doing: press).weight, 0)
    }

    // MARK: across the lifting/cardio line the slot has no shape to lend

    /// "4 sets" of squats is not "4 intervals" on a rower — and a squat slot
    /// has no minutes, so the rower was being asked for nothing at all.
    func testCardioStandingInForALiftIsOneBoutOfTheDefaultLength() {
        let context = context()
        let plan = legs(in: context)
        let rower = cardio("Rower", [.duration], in: context)

        let asked = Swaps.prescription(for: plan.squat, doing: rower)

        XCTAssertEqual(asked.sets, 1)
        XCTAssertEqual(asked.seconds, PlanDefaults().cardioSeconds,
                       "a lift slot has no minutes to hand over")
        XCTAssertEqual(asked.restSeconds, 0, "a single bout has nothing to rest between")
    }

    /// A treadmill slot is 1 × 0 with no rest. Inherited, a leg press opened
    /// on zero reps, had no cooldown, and ticked itself done after one set.
    func testALiftStandingInForCardioOpensLikeANewSlot() {
        let context = context()
        let plan = legs(in: context)
        let press = lift("Leg Press", .quads, loading: .machine, bar: 0, in: context)

        let asked = Swaps.prescription(for: plan.run, doing: press)

        XCTAssertEqual(asked.sets, PlanDefaults().targetSets)
        XCTAssertEqual(asked.reps, PlanDefaults().targetReps)
        XCTAssertEqual(asked.restSeconds, PlanDefaults().restSeconds)
        XCTAssertGreaterThan(asked.reps, 0)
        XCTAssertEqual(asked.seconds, 0)
    }

    func testTheCrossoverUsesYourDefaultsNotTheFactoryOnes() throws {
        let context = context()
        let plan = legs(in: context)
        let press = lift("Leg Press", .quads, loading: .machine, bar: 0, in: context)
        let mine = PlanDefaults.current(in: context)
        mine.targetSets = 5; mine.targetReps = 5; mine.restSeconds = 200
        try context.save()

        let asked = Swaps.prescription(for: plan.run, doing: press)

        XCTAssertEqual([asked.sets, asked.reps, asked.restSeconds], [5, 5, 200])
    }

    /// It is called from view bodies and from the snapshot builder.
    func testAskingForAPrescriptionNeverWritesADefaultsRow() throws {
        let context = context()
        let plan = legs(in: context)
        let rower = cardio("Rower", [.duration], in: context)

        _ = Swaps.prescription(for: plan.squat, doing: rower)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlanDefaults>()), 0)
    }

    // MARK: a slot is done when its work is done, whoever did it

    private func log(_ exercise: Exercise, at date: Date, in context: ModelContext) {
        context.insert(SetEntry(exercise: exercise, weight: 100, reps: 6,
                                setIndex: 1, date: date))
    }

    /// Two sets on the squat, someone takes the rack, on to the front squat.
    /// Counting only what is in the slot NOW sent "2 of 4" back to "0 of 4".
    func testSetsDoneBeforeTheSwapStillCountTowardTheSlot() throws {
        let context = context()
        let plan = legs(in: context)
        let squat = try XCTUnwrap(plan.squat.exercise)
        let front = lift("Front Squat", .quads, in: context)
        log(squat, at: at(14, 18), in: context)

        Swaps.put(front, in: plan.squat, context: context, now: at(14, 19), calendar: cal)

        XCTAssertEqual(Swaps.slugsCounting(toward: plan.squat, on: at(14), calendar: cal),
                       ["squat", "front-squat"])
    }

    /// The mirror: swap, lift, swap back. Deleting the row on the way back
    /// would hide the front squats from the checklist instead.
    func testSwappingBackAfterLiftingKeepsTheStandInsSetsInTheSlot() throws {
        let context = context()
        let plan = legs(in: context)
        let front = lift("Front Squat", .quads, in: context)
        Swaps.put(front, in: plan.squat, context: context, now: at(14, 18), calendar: cal)
        log(front, at: at(14, 19), in: context)

        Swaps.clear(plan.squat, context: context, on: at(14, 20), calendar: cal)

        XCTAssertNil(Swaps.standIn(for: plan.squat, on: at(14, 21), calendar: cal),
                     "the slot is the squat again")
        XCTAssertTrue(Swaps.slugsCounting(toward: plan.squat, on: at(14, 21), calendar: cal)
            .contains("front-squat"), "and the front squats still happened in it")
    }

    func testAStandInYouNeverLiftedLeavesNothingBehind() throws {
        let context = context()
        let plan = legs(in: context)
        let front = lift("Front Squat", .quads, in: context)
        Swaps.put(front, in: plan.squat, context: context, now: at(14, 18), calendar: cal)

        Swaps.clear(plan.squat, context: context, on: at(14, 19), calendar: cal)
        try context.save()

        XCTAssertEqual(Swaps.slugsCounting(toward: plan.squat, on: at(14), calendar: cal),
                       ["squat"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Swap>()), 0)
    }

    /// The way back is a row too, once there is history to keep — and it must
    /// not be mistaken for something you "usually do instead".
    func testTheWayBackIsNotCountedAsAStandIn() throws {
        let context = context()
        let plan = legs(in: context)
        let squat = try XCTUnwrap(plan.squat.exercise)
        let front = lift("Front Squat", .quads, in: context)
        Swaps.put(front, in: plan.squat, context: context, now: at(14, 18), calendar: cal)
        log(front, at: at(14, 19), in: context)
        Swaps.clear(plan.squat, context: context, on: at(14, 20), calendar: cal)

        let offered = Swaps.candidates(for: plan.squat, among: [squat, front],
                                       on: at(21), calendar: cal)

        XCTAssertEqual(offered.usual.map(\.slug), ["front-squat"])
    }

    /// Yesterday's stand-in has no claim on today's slot.
    func testTomorrowOnlyThePlansOwnExerciseCounts() {
        let context = context()
        let plan = legs(in: context)
        let front = lift("Front Squat", .quads, in: context)
        Swaps.put(front, in: plan.squat, context: context, now: at(14), calendar: cal)
        log(front, at: at(14, 19), in: context)

        XCTAssertEqual(Swaps.slugsCounting(toward: plan.squat, on: at(15), calendar: cal),
                       ["squat"])
    }

    // MARK: what the picker offers

    func testWhatIsAlreadyInTheWorkoutCannotStandIn() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        let all = [bike] + [plan.squat, plan.run].compactMap(\.exercise)

        let offered = Swaps.candidates(for: plan.run, among: all, on: at(14), calendar: cal)
        let slugs = (offered.usual + offered.alike + offered.others).map(\.slug)

        XCTAssertEqual(slugs, ["stationary-bike"],
                       "the slot's own exercise is 'swap back', and a squat in two "
                       + "slots would tick both off with one set")
    }

    func testAnotherSlotsStandInIsTakenToo() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)

        XCTAssertTrue(Swaps.takenSlugs(around: plan.squat, on: at(14), calendar: cal)
            .contains("stationary-bike"))
    }

    func testCardioIsShelvedBeforeLiftsWhenSwappingCardio() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        let curl = lift("Curl", .biceps, in: context)

        let offered = Swaps.candidates(for: plan.run, among: [curl, bike],
                                       on: at(14), calendar: cal)

        XCTAssertEqual(offered.alike.map(\.slug), ["stationary-bike"])
        XCTAssertEqual(offered.others.map(\.slug), ["curl"])
    }

    func testALiftIsAlikeWhenItWorksTheSameMuscle() {
        let context = context()
        let plan = legs(in: context)
        let front = lift("Front Squat", .quads, in: context)
        let curl = lift("Curl", .biceps, in: context)
        let mystery = lift("Mystery", .other, in: context)
        let squat = plan.squat.exercise!

        XCTAssertTrue(Swaps.alike(modality: front.kind, primary: front.primary, to: squat))
        XCTAssertFalse(Swaps.alike(modality: curl.kind, primary: curl.primary, to: squat))
        XCTAssertFalse(Swaps.alike(modality: mystery.kind, primary: mystery.primary, to: squat),
                       "'not set' matching 'not set' is not the same muscle")
    }

    /// The second time the treadmills are taken, the bike is one tap.
    func testWhatYouUsuallyDoInsteadComesFirstMostOftenFirst() {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        let rower = cardio("Rower", [.duration], in: context)
        let stairs = cardio("Stair Climber", [.duration], in: context)
        // Kept history: the bike twice, the rower once, more recently.
        Swaps.put(bike, in: plan.run, context: context, now: at(1), calendar: cal)
        Swaps.put(bike, in: plan.run, context: context, now: at(3), calendar: cal)
        Swaps.put(rower, in: plan.run, context: context, now: at(8), calendar: cal)

        let offered = Swaps.candidates(for: plan.run, among: [stairs, rower, bike],
                                       on: at(14), calendar: cal)

        XCTAssertEqual(offered.usual.map(\.slug), ["stationary-bike", "rower"])
        XCTAssertEqual(offered.alike.map(\.slug), ["stair-climber"])
    }

    // MARK: the snapshot agrees with the phone

    func testTheSnapshotShowsTheStandInAndWhosePlaceItIsIn() throws {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration, .distance, .resistance], in: context)
        let now = at(14)
        let session = Session(startedAt: now, dayName: "Legs", plannedDay: plan.day)
        context.insert(session)
        let bout = SetEntry(exercise: bike, weight: 0, reps: 0, setIndex: 1,
                            date: now, seconds: 1260, distance: 5.2)
        bout.session = session
        context.insert(bout)
        Swaps.put(bike, in: plan.run, context: context, now: now, calendar: cal)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: now, appVersion: "test")
        let slot = try XCTUnwrap(snapshot.today?.items.first { $0.slug == "stationary-bike" })

        XCTAssertEqual(slot.insteadOf, "Treadmill")
        XCTAssertEqual(slot.insteadOfSlug, "treadmill")
        XCTAssertTrue(slot.done, "riding the bike ticks the slot the bike is standing in")
        XCTAssertEqual(slot.cardioTarget?.seconds, 1200)
        XCTAssertNil(slot.cardioTarget?.incline)
        XCTAssertNil(slot.cardioTarget?.distance)
        XCTAssertNil(snapshot.today?.items.first { $0.slug == "squat" }?.insteadOf)
    }

    /// The phone's row reads the stand-in's own history; `gym today` printed 0
    /// beside it, because a stand-in's prescription has no weight to give.
    func testTheSnapshotGivesAStandInTheWeightThePhoneShows() throws {
        let context = context()
        let plan = legs(in: context)
        let press = lift("Leg Press", .quads, loading: .machine, bar: 0, in: context)
        // Last week: 3 × 6 at 300, every rep made.
        for i in 1...4 {
            context.insert(SetEntry(exercise: press, weight: 300, reps: 6,
                                    setIndex: i, date: at(7, 18)))
        }
        Swaps.put(press, in: plan.squat, context: context, now: at(14), calendar: cal)
        // `today` is only present when a workout is open or scheduled, and
        // "Legs" here is on no weekday — so open one, as the treadmill did.
        let run = try XCTUnwrap(plan.run.exercise)
        let session = Session(startedAt: at(14), dayName: "Legs", plannedDay: plan.day)
        context.insert(session)
        let bout = SetEntry(exercise: run, weight: 0, reps: 0, setIndex: 1,
                            date: at(14), seconds: 600)
        bout.session = session
        context.insert(bout)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(14), appVersion: "test")
        let slot = try XCTUnwrap(snapshot.today?.items.first { $0.slug == "leg-press" })

        XCTAssertGreaterThanOrEqual(slot.targetWeight, 300,
                                    "its own history, never the 0 the prescription carries")
        XCTAssertNotEqual(slot.targetWeight, 225, "and never the squat's")
    }

    func testTheSnapshotCountsTheWholeSlot() throws {
        let context = context()
        let plan = legs(in: context)
        let squat = try XCTUnwrap(plan.squat.exercise)
        let front = lift("Front Squat", .quads, in: context)
        let now = at(14, 18)
        let session = Session(startedAt: now, dayName: "Legs", plannedDay: plan.day)
        context.insert(session)
        for (i, exercise) in [squat, squat, front, front].enumerated() {
            let entry = SetEntry(exercise: exercise, weight: 135, reps: 6, setIndex: i + 1,
                                 date: now.addingTimeInterval(Double(i) * 180))
            entry.session = session
            context.insert(entry)
        }
        Swaps.put(front, in: plan.squat, context: context,
                  now: now.addingTimeInterval(400), calendar: cal)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context,
                                                 now: now.addingTimeInterval(900),
                                                 appVersion: "test")
        let slot = try XCTUnwrap(snapshot.today?.items.first { $0.slug == "front-squat" })

        XCTAssertEqual(slot.setsDone, 4)
        XCTAssertTrue(slot.done, "two on the squat and two on the front squat is four of four")
    }

    /// `plan[]` is the programme. A swap is not an edit to it.
    func testTheSnapshotsPlanStillSaysTreadmill() throws {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)
        try context.save()

        let snapshot = try SnapshotBuilder.build(from: context, now: at(14), appVersion: "test")
        let slugs = snapshot.plan.flatMap(\.items).map(\.slug)

        XCTAssertTrue(slugs.contains("treadmill"))
        XCTAssertFalse(slugs.contains("stationary-bike"))
    }

    // MARK: deleting things

    func testDeletingTheStandInTakesTheSwapWithIt() throws {
        let context = context()
        let plan = legs(in: context)
        let bike = cardio("Stationary Bike", [.duration], in: context)
        Swaps.put(bike, in: plan.run, context: context, now: at(14), calendar: cal)
        try context.save()

        context.delete(bike)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Swap>()), 0)
        XCTAssertEqual(Swaps.exercise(for: plan.run, on: at(14), calendar: cal)?.slug,
                       "treadmill")
    }
}
