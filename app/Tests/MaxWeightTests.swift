import XCTest
import SwiftData
@testable import RathiFitness

/// At the top of the stack the weight cannot go up, so the reps do.
///
/// Before `Exercise.maxWeight`, hitting every rep at the bottom plate told you
/// to add 5 lb the machine does not have — every session, for ever.
final class MaxWeightTests: XCTestCase {

    private func set(_ weight: Double, _ reps: Int, max: Double = 200) -> Tally.Set {
        Tally.Set(weight: weight, reps: reps, maxWeight: max)
    }

    func testAtTheMaxHittingEveryRepAddsARepNotWeight() {
        let next = Tally.nextTarget(lastSession: [set(200, 10), set(200, 10), set(200, 10)],
                                    target: 10)
        XCTAssertEqual(next?.weight, 200)
        XCTAssertEqual(next?.reps, 11)
        XCTAssertEqual(next?.because, "that's the heaviest it goes — one more rep instead")
    }

    /// Past the plan's target the reps keep climbing, off the weakest set:
    /// 12, 12, 11 asks for 12 on every set, not 13.
    func testTheRepsKeepClimbingOffTheWeakestSet() {
        let next = Tally.nextTarget(lastSession: [set(200, 12), set(200, 12), set(200, 11)],
                                    target: 10)
        XCTAssertEqual(next?.weight, 200)
        XCTAssertEqual(next?.reps, 12)
    }

    /// One step short of the top: the step would overshoot, so it lands on it.
    func testAStepThatWouldOvershootLandsOnTheMax() {
        let next = Tally.nextTarget(lastSession: [set(197.5, 10)], target: 10, step: 5)
        XCTAssertEqual(next?.weight, 200)
        XCTAssertEqual(next?.reps, 10)
    }

    func testBelowTheMaxNothingChanges() {
        let next = Tally.nextTarget(lastSession: [set(150, 10)], target: 10)
        XCTAssertEqual(next?.weight, 155)
        XCTAssertEqual(next?.because, "you hit every rep last time")
    }

    /// Missing reps at the max must not promise that "it goes up".
    func testShortOfTheTargetAtTheMaxDoesNotPromiseMoreWeight() {
        let next = Tally.nextTarget(lastSession: [set(200, 9), set(200, 8)], target: 10)
        XCTAssertEqual(next?.weight, 200)
        XCTAssertEqual(next?.because, "one more rep than last time")
    }

    func testNoMaxIsNoLimit() {
        let next = Tally.nextTarget(lastSession: [set(200, 10, max: 0)], target: 10)
        XCTAssertEqual(next?.weight, 205)
    }

    /// On an assisted machine harder is LESS weight; the max has no say.
    func testAnAssistedMachineIgnoresTheMax() {
        let last = [Tally.Set(weight: 70, reps: 8, assisted: true, maxWeight: 70)]
        XCTAssertEqual(Tally.nextTarget(lastSession: last, target: 8)?.weight, 65)
    }

    /// The max arrives through `SetEntry.tally`, so no call site passes it —
    /// the same door `assisted` uses.
    func testTheMaxReachesTheSuggestionFromTheExercise() throws {
        let context = ModelContext(Store.makeContainer(inMemory: true))
        let exercise = Exercise(name: "Lat Pulldown", loading: .machine)
        exercise.maxWeight = 200
        context.insert(exercise)
        let entry = SetEntry(exercise: exercise, weight: 200, reps: 10, setIndex: 1)
        context.insert(entry)

        XCTAssertEqual(entry.tally(bodyWeight: nil).maxWeight, 200)
        XCTAssertEqual(exercise.tally(weight: 200, reps: 10, kind: .working).maxWeight, 200)
        let next = Tally.nextTarget(lastSession: [entry.tally(bodyWeight: nil)], target: 10)
        XCTAssertEqual(next?.reps, 11)
    }
}
