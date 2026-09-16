import XCTest
import SwiftData
@testable import RathiFitness

/// The plan follows what you actually lift, and empty sessions do not exist.
///
/// Both came out of one screenshot: a Today screen reading "workout 3" on a day
/// with one workout, "438 min in" seven hours after the last set, and six of
/// seven rows showing a weight the user had already beaten by 5 lb.
final class PlanAdvanceTests: XCTestCase {

    private func context() -> ModelContext {
        ModelContext(Store.makeContainer(inMemory: true))
    }

    // MARK: the plan keeps up

    func testHittingTheRepsAtAHeavierWeightMovesTheTarget() {
        let set = Tally.Set(weight: 50, reps: 8)
        XCTAssertEqual(Tally.advancedTarget(current: 45, targetReps: 8, set: set), 50)
    }

    /// Evidence you own it, not evidence you tried it. Five reps at a heavier
    /// weight is a hard set, not a new working weight.
    func testAHeavierWeightYouCouldNotFinishDoesNotMoveTheTarget() {
        let set = Tally.Set(weight: 50, reps: 5)
        XCTAssertNil(Tally.advancedTarget(current: 45, targetReps: 8, set: set))
    }

    func testTheTargetNeverGoesBackwards() {
        let set = Tally.Set(weight: 40, reps: 8)
        XCTAssertNil(Tally.advancedTarget(current: 45, targetReps: 8, set: set),
                     "a lighter working set is not a demotion")
    }

    func testMatchingTheTargetChangesNothing() {
        let set = Tally.Set(weight: 45, reps: 8)
        XCTAssertNil(Tally.advancedTarget(current: 45, targetReps: 8, set: set))
    }

    func testAWarmUpNeverMovesTheTarget() {
        let set = Tally.Set(weight: 50, reps: 8, kind: .warmup)
        XCTAssertNil(Tally.advancedTarget(current: 45, targetReps: 8, set: set))
    }

    /// Harder runs the other way on an assisted machine: 75 lb of help beats 80.
    func testLessHelpMovesTheTargetDown() {
        let set = Tally.Set(weight: 75, reps: 8, assisted: true)
        XCTAssertEqual(Tally.advancedTarget(current: 80, targetReps: 8, set: set), 75)
    }

    func testMoreHelpDoesNotMoveTheTarget() {
        let set = Tally.Set(weight: 90, reps: 8, assisted: true)
        XCTAssertNil(Tally.advancedTarget(current: 80, targetReps: 8, set: set),
                     "needing more help must never become the new plan")
    }

    // MARK: the row reads the same number as the set screen

    /// The screenshot: plan 120, last time 125 × 8, 8, 8, set screen says
    /// "try 130". The row said 120. Now it says what the set screen says.
    func testTheRowShowsTheSuggestionNotTheStalePlan() {
        let last = [Tally.Set(weight: 125, reps: 8), .init(weight: 125, reps: 8),
                    .init(weight: 125, reps: 8)]
        let suggestion = Tally.nextTarget(lastSession: last, target: 8)
        XCTAssertEqual(suggestion?.weight, 130)
        XCTAssertEqual(Tally.shownWeight(plan: 120, suggestion: suggestion, today: []), 130)
    }

    func testWithNoHistoryTheRowShowsThePlan() {
        XCTAssertEqual(Tally.shownWeight(plan: 120, suggestion: nil, today: []), 120)
    }

    /// Once you are lifting, the row says what you are lifting — even when the
    /// suggestion wanted more. The set screen primes the same way.
    func testOnceAWorkingSetIsLoggedTheRowShowsThatWeight() {
        let suggestion = Tally.Suggestion(weight: 130, reps: 8, because: "x")
        let today = [Tally.Set(weight: 125, reps: 8)]
        XCTAssertEqual(Tally.shownWeight(plan: 120, suggestion: suggestion, today: today), 125)
    }

    func testTheLastWorkingSetTodayWins() {
        let today = [Tally.Set(weight: 125, reps: 8), .init(weight: 130, reps: 8)]
        XCTAssertEqual(Tally.shownWeight(plan: 120, suggestion: nil, today: today), 130)
    }

    func testAWarmUpDoesNotRelabelTheRow() {
        let suggestion = Tally.Suggestion(weight: 130, reps: 8, because: "x")
        let today = [Tally.Set(weight: 45, reps: 10, kind: .warmup)]
        XCTAssertEqual(Tally.shownWeight(plan: 120, suggestion: suggestion, today: today), 130,
                       "a bar warm-up is not what you are doing today")
    }

    /// Less help is the suggestion's direction on an assisted machine, and
    /// the row follows it without knowing why.
    func testAnAssistedRowFollowsTheSuggestionDown() {
        let last = [Tally.Set(weight: 80, reps: 8, assisted: true),
                    .init(weight: 80, reps: 8, assisted: true)]
        let suggestion = Tally.nextTarget(lastSession: last, target: 8)
        XCTAssertEqual(Tally.shownWeight(plan: 80, suggestion: suggestion, today: []), 75)
    }

    // MARK: one definition of "last session"

    func testLastSessionIsTheMostRecentPreviousDayInSetOrder() throws {
        let context = context()
        let exercise = Exercise(name: "Abdominal Crunch")
        context.insert(exercise)
        let calendar = Calendar.current
        let now = Date.now
        let twoWeeks = calendar.date(byAdding: .day, value: -14, to: now)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: now)!
        var entries: [SetEntry] = []
        for (date, weight) in [(twoWeeks, 120.0), (lastWeek, 125.0), (now, 130.0)] {
            let second = SetEntry(exercise: exercise, weight: weight, reps: 8, setIndex: 2)
            second.date = date.addingTimeInterval(120)
            let first = SetEntry(exercise: exercise, weight: weight, reps: 8, setIndex: 1)
            first.date = date
            context.insert(second); context.insert(first)
            entries += [second, first]
        }
        try context.save()

        let last = entries.lastSession(before: now, calendar: calendar)
        XCTAssertEqual(last.map(\.weight), [125, 125], "today is excluded; the newest prior day wins")
        XCTAssertEqual(last.map(\.setIndex), [1, 2], "set order, whatever order the query returned")
    }

    func testLastSessionIsEmptyWhenOnlyTodayExists() throws {
        let context = context()
        let exercise = Exercise(name: "Abdominal Crunch")
        context.insert(exercise)
        let entry = SetEntry(exercise: exercise, weight: 130, reps: 8, setIndex: 1)
        context.insert(entry)
        try context.save()
        XCTAssertTrue([entry].lastSession().isEmpty)
    }

    // MARK: sessions that hold nothing

    /// The one from the screenshot: 08:54 → 08:54, zero sets, counted as a
    /// workout. A logged-then-undone set leaves exactly this behind.
    func testAnEmptySessionIsRemoved() throws {
        let context = context()
        let day = PlannedDay(name: "Shoulders and Back", weekday: 4)
        context.insert(day)
        let real = Session(startedAt: .now, dayName: day.name, plannedDay: day)
        let empty = Session(startedAt: .now, dayName: day.name, plannedDay: day)
        context.insert(real); context.insert(empty)
        let exercise = Exercise(name: "Lat Pulldown")
        context.insert(exercise)
        let entry = SetEntry(exercise: exercise, weight: 90, reps: 8, setIndex: 1)
        entry.session = real
        context.insert(entry)
        try context.save()

        XCTAssertEqual(Sessions.pruneEmpty(in: context), 1)
        try context.save()

        let left = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(left.count, 1, "the one that holds a set survives")
        XCTAssertEqual(left.first?.orderedSets.count, 1)
    }

    func testPruningIsIdempotentAndSparesAFullSession() throws {
        let context = context()
        let exercise = Exercise(name: "Lat Pulldown")
        context.insert(exercise)
        let session = Session(startedAt: .now, dayName: "Pull")
        context.insert(session)
        let entry = SetEntry(exercise: exercise, weight: 90, reps: 8, setIndex: 1)
        entry.session = session
        context.insert(entry)
        try context.save()

        XCTAssertEqual(Sessions.pruneEmpty(in: context), 0)
        XCTAssertEqual(Sessions.pruneEmpty(in: context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 1)
    }

    /// Deleting the last set is what creates the problem, so it is what has to
    /// clean up after itself.
    func testUndoingTheOnlySetLeavesNoSessionBehind() throws {
        let context = context()
        let exercise = Exercise(name: "Lat Pulldown")
        context.insert(exercise)
        let session = Session(startedAt: .now, dayName: "Pull")
        context.insert(session)
        let entry = SetEntry(exercise: exercise, weight: 90, reps: 8, setIndex: 1)
        entry.session = session
        context.insert(entry)
        try context.save()

        context.delete(entry)
        Sessions.pruneEmpty(in: context)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 0,
                       "one mis-tap must not read as a workout for ever")
    }
}
