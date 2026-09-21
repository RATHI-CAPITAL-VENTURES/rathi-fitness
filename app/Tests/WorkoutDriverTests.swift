import XCTest
import SwiftData
@testable import RathiFitness

/// The workout, run from the lens with the phone locked.
///
/// Everything here happens with no view anywhere — which is the point, and also
/// what makes it testable end to end against a real in-memory store: pinch,
/// look at what the lens would show, look at what was written.
@MainActor
final class WorkoutDriverTests: XCTestCase {

    private let cal = Calendar.current
    private var context: ModelContext!
    private var rest: RestTimer!
    private var driver: WorkoutDriver!
    private var bench: PlanItem!
    private var fly: PlanItem!
    private var run: PlanItem!
    /// Noon today, not the moment the test runs. Several tests look fifteen and
    /// thirty minutes ahead, and with a real clock those land on TOMORROW for a
    /// quarter of an hour every night — where the fixture's weekday no longer
    /// matches and the failure message talks about something else entirely.
    private let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

    override func setUp() {
        super.setUp()
        context = ModelContext(Store.makeContainer(inMemory: true))
        rest = RestTimer()
        (bench, run, fly) = plan()
        driver = WorkoutDriver(context: context, rest: rest, calendar: cal)
    }

    /// A plan for whatever weekday the test runs on, so "today" is this one.
    private func plan() -> (PlanItem, PlanItem, PlanItem) {
        let day = PlannedDay(name: "Push", weekday: cal.component(.weekday, from: now))
        context.insert(day)
        let bench = slot(0, lift("Bench Press", .chest), sets: 2, reps: 8, weight: 185, day)
        let run = slot(1, machine("Treadmill"), sets: 1, reps: 0, weight: 0, day, seconds: 1200)
        let fly = slot(2, lift("Cable Fly", .chest, loading: .machine, bar: 0), sets: 3, reps: 12, weight: 35, day)
        try? context.save()
        return (bench, run, fly)
    }

    override func tearDown() {
        rest.stop()
        super.tearDown()
    }

    private func lift(_ name: String, _ primary: MuscleGroup,
                      loading: Exercise.Loading = .barbell, bar: Double = 45) -> Exercise {
        let exercise = Exercise(name: name, loading: loading, barWeight: bar, primary: primary)
        context.insert(exercise)
        return exercise
    }

    private func machine(_ name: String) -> Exercise {
        let exercise = Exercise(name: name, loading: .machine, barWeight: 0, primary: .quads,
                                modality: .cardio, metrics: [.duration, .distance])
        context.insert(exercise)
        return exercise
    }

    private func slot(_ order: Int, _ exercise: Exercise, sets: Int, reps: Int, weight: Double,
                      _ day: PlannedDay, seconds: Int = 0) -> PlanItem {
        let item = PlanItem(order: order, exercise: exercise, targetSets: sets, targetReps: reps,
                            targetWeight: weight, restSeconds: 90, targetSeconds: seconds)
        item.day = day
        context.insert(item)
        return item
    }

    private func sets() -> [SetEntry] {
        ((try? context.fetch(FetchDescriptor<SetEntry>())) ?? []).sorted { $0.date < $1.date }
    }

    private var list: LensList? {
        if case .list(let list) = driver.screen(at: now) { return list }
        return nil
    }
    private var card: LensCard? {
        if case .card(let card) = driver.screen(at: now) { return card }
        return nil
    }
    private var set: LensState? {
        if case .set(let state) = driver.screen(at: now) { return state }
        return nil
    }

    /// Open the row with this name, from the list.
    private func open(_ name: String) {
        guard let row = list?.rows.first(where: { $0.title == name }) else { return XCTFail("no row \(name)") }
        driver.pinched(row.action, at: now)
    }

    // MARK: when it has the lens at all

    /// A display session is the WHOLE lens. Glasses that showed your workout
    /// on the walk to the office would be glasses you stop wearing.
    func testNothingIsShownUntilYouHaveTouchedTheApp() {
        XCTAssertNil(driver.screen(at: now))
        driver.touch(at: now)
        XCTAssertNotNil(driver.screen(at: now))
    }

    func testTheLensIsGivenBackWhenYouHaveWanderedOff() {
        driver.touch(at: now)
        let later = now.addingTimeInterval(WorkoutDriver.attention + 1)
        XCTAssertNil(driver.screen(at: later))
    }

    /// ...but not in the middle of a workout. A long rest, a chat, a queue for
    /// the rack: the last set being recent is what "mid-workout" means.
    func testAWorkoutInProgressKeepsTheLensPastTheAttentionWindow() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)
        rest.stop()
        let later = now.addingTimeInterval(WorkoutDriver.attention + 60)
        XCTAssertNotNil(driver.screen(at: later), "a set was logged sixteen minutes ago; you are still here")
        let muchLater = now.addingTimeInterval(WorkoutDriver.workoutGap + 60)
        XCTAssertNil(driver.screen(at: muchLater))
    }

    func testARestDayShowsNothing() {
        for day in (try? context.fetch(FetchDescriptor<PlannedDay>())) ?? [] {
            day.weekday = day.weekday % 7 + 1          // any weekday but today
        }
        try? context.save()
        driver.touch(at: now)
        XCTAssertNil(driver.screen(at: now))
    }

    // MARK: the list

    func testTodayIsTheWholePlanInOrder() {
        driver.touch(at: now)
        XCTAssertEqual(list?.rows.map(\.title), ["Bench Press", "Treadmill", "Cable Fly"])
        XCTAssertEqual(list?.eyebrow, "PUSH · 0 OF 3 DONE")
        XCTAssertEqual(list?.rows.first?.trailing, "185 × 8", "what you are about to lift")
        XCTAssertEqual(list?.rows[1].trailing, "20 min")
    }

    /// The first row is the one that arrives lit, so what goes first is a
    /// decision: what you are part-way through, then what is left, then what is
    /// done. The usual case is a pinch with no swipe.
    func testWhatYouAreInTheMiddleOfComesFirstAndWhatIsDoneGoesLast() {
        driver.touch(at: now)
        open("Cable Fly")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)
        rest.stop()
        driver.pinched(.back, at: now)
        driver.pinched(.back, at: now)
        XCTAssertEqual(list?.rows.map(\.title), ["Cable Fly", "Bench Press", "Treadmill"])
        XCTAssertEqual(list?.rows.first?.trailing, "1 of 3")
    }

    // MARK: a card

    func testALiftsCardOffersStartFirst() {
        driver.touch(at: now)
        open("Bench Press")
        XCTAssertEqual(card?.title, "Bench Press")
        XCTAssertEqual(card?.lines.first, "185 × 8 · 2 sets · 1:30 rest")
        XCTAssertEqual(card?.actions, [.start, .taken, .back])
    }

    /// A bout's numbers come off the machine's console and the lens cannot type.
    /// "Log as planned" would write a run you may not have run.
    func testAMachineIsSentToThePhoneAndCannotBeStartedFromTheLens() {
        driver.touch(at: now)
        open("Treadmill")
        XCTAssertEqual(card?.actions, [.back])
        XCTAssertTrue(card?.lines.contains { $0.contains("phone") } ?? false)
        driver.pinched(.start, at: now)
        XCTAssertEqual(driver.place, .card(run.persistentModelID), "and a stray Start does nothing")
        XCTAssertTrue(sets().isEmpty)
    }

    // MARK: lifting

    func testStartOpensOnTheSameNumbersThePhoneWould() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        XCTAssertEqual(set?.hero, "185 × 8")
        XCTAssertEqual(set?.eyebrow, "PUSH · SET 1 OF 2")
        XCTAssertEqual(set?.actions, [.logSet, .fewerReps, .back], "Log is the one that arrives lit")
    }

    func testAPinchOnLogWritesOneSetOpensAWorkoutAndStartsTheRest() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)

        XCTAssertEqual(sets().count, 1)
        XCTAssertEqual(sets().first?.weight, 185)
        XCTAssertEqual(sets().first?.reps, 8)
        XCTAssertEqual(sets().first?.setIndex, 1)
        XCTAssertNotNil(sets().first?.session, "opened by the first set, as on the phone")
        XCTAssertTrue(rest.isResting)
        XCTAssertEqual(rest.exerciseName, "Bench Press")
        XCTAssertEqual(set?.actions, [.skipRest, .extendRest, .list])
    }

    /// Found on the first real use: after the last set the lens showed only
    /// Skip and +30 s, and the wearer was stuck on the clock until it ran out.
    func testYouCanGetBackToTheListFromARest() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now); rest.stop()
        driver.pinched(.logSet, at: now)              // the last set; now resting
        XCTAssertEqual(set?.actions.last, .list)
        driver.pinched(.list, at: now)
        XCTAssertEqual(driver.place, .list)
        XCTAssertEqual(list?.rows.last?.title, "Bench Press", "and it has sunk to the bottom, done")
        XCTAssertTrue(rest.isResting, "leaving the screen does not cancel the rest")
    }

    /// The gate stops a second pinch on a stale button; this is the belt to
    /// those braces. Mid-rest there is no set to log, whoever asks.
    func testLogDuringTheRestWritesNothing() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)
        driver.pinched(.logSet, at: now)
        driver.pinched(.logSet, at: now)
        XCTAssertEqual(sets().count, 1)
    }

    /// The lens cannot type, but "I got 7, not 8" is the correction a set needs.
    func testFewerRepsIsAboutTheSetInHandNotTheNextOne() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.fewerReps, at: now)
        XCTAssertEqual(set?.hero, "185 × 7")
        driver.pinched(.logSet, at: now)
        XCTAssertEqual(sets().first?.reps, 7)
        rest.stop()
        XCTAssertEqual(set?.hero, "185 × 8", "the next set opens on the plan again")
    }

    func testRepsNeverReachZero() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        for _ in 0..<20 { driver.pinched(.fewerReps, at: now) }
        XCTAssertEqual(set?.hero, "185 × 1")
    }

    func testSkipAndExtendReachTheSameTimerThePhoneUses() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)
        let before = rest.total
        driver.pinched(.extendRest, at: now)
        XCTAssertEqual(rest.total, before + 30)
        driver.pinched(.skipRest, at: now)
        XCTAssertFalse(rest.isResting)
    }

    // MARK: moving on

    func testAfterTheLastSetItSaysWhatIsNextAndSkipsTheMachine() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now); rest.stop()
        driver.pinched(.logSet, at: now); rest.stop()

        XCTAssertEqual(card?.eyebrow, "BENCH PRESS · DONE")
        XCTAssertEqual(card?.title, "Cable Fly", "not the treadmill — the lens cannot log it")
        XCTAssertEqual(card?.actions, [.start, .list])

        driver.pinched(.start, at: now)
        XCTAssertEqual(set?.title, "Cable Fly")
        XCTAssertEqual(set?.hero, "35 × 12")
    }

    /// Past the last set the lens offers no Log. A pinch that arrives anyway —
    /// late, or through some other door — is not a third set of two.
    func testNoSetIsWrittenPastTheLastOne() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        for _ in 0..<5 { driver.pinched(.logSet, at: now); rest.stop() }
        XCTAssertEqual(sets().count, 2)
    }

    private func finishBothLifts() {
        for name in ["Bench Press", "Cable Fly"] {
            driver.pinched(.list, at: now)
            if driver.place != .list { driver.pinched(.back, at: now) }
            open(name)
            driver.pinched(.start, at: now)
            for _ in 0..<3 { driver.pinched(.logSet, at: now); rest.stop() }
        }
    }

    /// The first version said "That's the workout · 3 of 3 done" here, with the
    /// treadmill untouched, while the list behind it said 2 of 3. Found in review.
    func testWithTheLiftsDoneAndAMachineLeftItSaysSoAndCountsLikeTheList() {
        driver.touch(at: now)
        finishBothLifts()
        XCTAssertEqual(card?.title, "Treadmill is left")
        XCTAssertEqual(card?.lines.first, "2 of 3 done")
        driver.pinched(.list, at: now)
        XCTAssertEqual(list?.eyebrow, "PUSH · 2 OF 3 DONE", "the same count, from the same slots")
    }

    func testWhenEverythingIsDoneItSaysSo() throws {
        driver.touch(at: now)
        finishBothLifts()
        // The run, logged on the phone — the only place it can be.
        let session = try XCTUnwrap(sets().first?.session)
        let bout = SetEntry(exercise: try XCTUnwrap(run.exercise), weight: 0, reps: 0, setIndex: 1,
                            date: now, seconds: 1200)
        bout.session = session
        context.insert(bout)
        try context.save()
        driver.screenClosed(at: now)
        XCTAssertEqual(card?.title, "That's the workout")
        XCTAssertEqual(card?.lines, ["3 of 3 done"])
    }

    // MARK: the machine is taken

    func testTakenOffersWhatDoesTheSameJobAndPuttingItInTheSlotLastsToday() throws {
        let pecDeck = lift("Pec Deck", .chest, loading: .machine, bar: 0)
        _ = lift("Squat", .quads)
        try context.save()

        driver.touch(at: now)
        open("Cable Fly")
        driver.pinched(.taken, at: now)
        let offered = try XCTUnwrap(list)
        XCTAssertEqual(offered.eyebrow, "INSTEAD OF CABLE FLY")
        XCTAssertTrue(offered.rows.map(\.title).contains("Pec Deck"))
        XCTAssertFalse(offered.rows.map(\.title).contains("Squat"), "legs do not stand in for chest")
        XCTAssertFalse(offered.rows.map(\.title).contains("Bench Press"), "already in today's workout")
        XCTAssertEqual(offered.footer, [.back], "Meta's back gesture leaves the app; this is the way out")

        let row = try XCTUnwrap(offered.rows.first { $0.title == "Pec Deck" })
        driver.pinched(row.action, at: now)
        XCTAssertEqual(Swaps.exercise(for: fly)?.name, pecDeck.name)
        XCTAssertEqual(card?.title, "Pec Deck")
        XCTAssertTrue(card?.lines.contains("Today, instead of Cable Fly") ?? false)
        XCTAssertEqual(fly.exercise?.name, "Cable Fly", "the plan itself is untouched")
    }

    // MARK: one implementation

    /// Two stores, the same plan in each. One set goes in the way the lens puts
    /// it in; the other the way `SetView` does — the same three calls, in its
    /// order, with its arguments. The rows and the plan must come out the same.
    ///
    /// (This was first written comparing the driver to `Tally.advancedTarget`,
    /// the function it calls — an assertion about the driver against itself.)
    func testTheLensAndThePhoneWriteTheSameSet() throws {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now)
        let lens = try XCTUnwrap(sets().first)
        let lensTarget = bench.targetWeight

        // The phone's store, and `SetView`'s own sequence: prime, judge, write.
        context = ModelContext(Store.makeContainer(inMemory: true))
        let (item, _, _) = plan()
        let exercise = try XCTUnwrap(item.exercise)
        let opening = Workout.opening(for: item, doing: exercise, doneHere: [], in: [], calendar: cal)
        _ = Workout.record(weight: opening.weight, reps: opening.reps, kind: .working,
                           exercise: exercise, history: [])
        Workout.logStrength(item: item, exercise: exercise, weight: opening.weight, reps: opening.reps,
                            kind: .working, setIndex: 1, at: now, in: context)
        let phone = try XCTUnwrap(sets().first)

        XCTAssertEqual(lens.weight, phone.weight)
        XCTAssertEqual(lens.reps, phone.reps)
        XCTAssertEqual(lens.setIndex, phone.setIndex)
        XCTAssertEqual(lens.setKind, phone.setKind)
        XCTAssertEqual(lens.date, phone.date)
        XCTAssertEqual(lens.session?.plannedDay?.name, phone.session?.plannedDay?.name)
        XCTAssertEqual(lensTarget, item.targetWeight, "and the plan moved — or did not — identically")
    }

    // MARK: found in review

    /// Start the bench on the lens at 185, open it on the phone, move to 205,
    /// log, close. Left alone the lens would write the next set at 185.
    func testNumbersInHandAreWorkedOutAgainAfterThePhoneHasLoggedASet() throws {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        XCTAssertEqual(set?.hero, "185 × 8")

        Workout.logStrength(item: bench, exercise: try XCTUnwrap(bench.exercise), weight: 205, reps: 8,
                            kind: .working, setIndex: 1, at: now, in: context)
        driver.screenClosed(at: now)

        XCTAssertEqual(set?.hero, "205 × 8", "what you are on now, not what the lens opened with")
        XCTAssertEqual(set?.eyebrow, "PUSH · SET 2 OF 2")
        driver.pinched(.logSet, at: now)
        XCTAssertEqual(sets().last?.weight, 205)
    }

    /// Push in the morning, closed; Push again in the evening. Counting by the
    /// calendar day, the morning had "done" everything and the lens would not
    /// log a thing. The phone has always counted by session.
    func testASecondWorkoutOfTheSameDayCanBeLogged() throws {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        for _ in 0..<2 { driver.pinched(.logSet, at: now); rest.stop() }
        let morning = try XCTUnwrap(sets().first?.session)
        Sessions.close(morning, in: context)
        try context.save()

        driver.screenClosed(at: now)
        driver.pinched(.list, at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        XCTAssertEqual(set?.eyebrow, "PUSH · SET 1 OF 2", "a new workout starts at set one")
        driver.pinched(.logSet, at: now)
        XCTAssertEqual(sets().count, 3)
        XCTAssertNotEqual(sets().last?.session?.persistentModelID, morning.persistentModelID)
    }

    /// "−1 rep" is not offered at one, and can never push a number UP — a
    /// zero-rep slot used to go to 1.
    func testFewerRepsIsNotOfferedWhenThereIsNothingToTakeAway() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        for _ in 0..<20 { driver.pinched(.fewerReps, at: now) }
        XCTAssertEqual(set?.actions, [.logSet, .back])
    }

    // MARK: closing it from the glasses

    /// Found on the first real use: the only way to get the lens back was to
    /// quit the app on the phone.
    func testTheListEndsInClose() {
        driver.touch(at: now)
        XCTAssertEqual(list?.footer, [.close])
    }

    func testCloseHandsTheLensBackAndOnlyThePhoneReopensIt() {
        driver.touch(at: now)
        driver.pinched(.close, at: now)
        XCTAssertNil(driver.screen(at: now))
        // A pinch that was already on its way must not bring it back.
        driver.pinched(.open(0), at: now)
        XCTAssertNil(driver.screen(at: now))
        driver.touch(at: now)
        XCTAssertNotNil(list, "opening the app is what says you are back")
    }

    func testCloseWinsEvenMidWorkout() {
        driver.touch(at: now)
        open("Bench Press")
        driver.pinched(.start, at: now)
        driver.pinched(.logSet, at: now); rest.stop()
        driver.pinched(.list, at: now)
        driver.pinched(.close, at: now)
        XCTAssertNil(driver.screen(at: now), "a workout in progress does not overrule being told to go away")
    }
}
