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
