import XCTest
@testable import RathiFitness

/// "Try 2.1 mi — you covered the distance last time."
///
/// Lifting has had this since the first version and cardio did not, so a
/// treadmill slot showed the same prescription for ever: progressive overload
/// stopped at the weights. These pin the two rules that make it a suggestion
/// rather than a nag — it moves ONE dimension, and only when you met what was
/// actually asked.
final class CardioProgressionTests: XCTestCase {

    private func bout(seconds: Int = 0, distance: Double = 0,
                      speed: Double = 0, incline: Double = 0) -> Tally.Bout {
        Tally.Bout(seconds: seconds, distance: distance, incline: incline, speed: speed)
    }

    private func target(seconds: Int = 0, distance: Double = 0,
                        speed: Double = 0, incline: Double = 0) -> Tally.CardioTarget {
        Tally.CardioTarget(seconds: seconds, distance: distance,
                           speed: speed, incline: incline)
    }

    // MARK: what it pushes

    func testHittingTheDistanceAsksForMore() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 1_200, distance: 2.0),
                                       target: target(seconds: 1_200, distance: 2.0))
        XCTAssertEqual(s?.dimension, .distance)
        XCTAssertEqual(s?.value, 2.1)
        XCTAssertEqual(s?.because, "you covered the distance last time")
    }

    func testATimeOnlySlotGetsAnotherMinute() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 1_200),
                                       target: target(seconds: 1_200))
        XCTAssertEqual(s?.dimension, .duration)
        XCTAssertEqual(s?.value, 1_260)
    }

    /// **One dimension, never several.** Four dials moving at once is a
    /// different workout, not progression, and nothing could be attributed to
    /// any of them.
    func testOnlyOneThingMovesEvenWhenEverythingIsPrescribed() {
        let s = Tally.nextCardioTarget(
            lastBout: bout(seconds: 1_200, distance: 2.0, speed: 6, incline: 2),
            target: target(seconds: 1_200, distance: 2.0, speed: 6, incline: 2))
        XCTAssertEqual(s?.dimension, .distance, "the plan measures distance, so distance moves")
    }

    func testSpeedIsPushedWhenThatIsAllThePlanAsksFor() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 600, speed: 6.0),
                                       target: target(speed: 6.0))
        XCTAssertEqual(s?.dimension, .speed)
        XCTAssertEqual(s?.value, 6.1)
    }

    func testGradeIsTheLastResort() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 600, incline: 2.0),
                                       target: target(incline: 2.0))
        XCTAssertEqual(s?.dimension, .incline)
        XCTAssertEqual(s?.value, 2.5)
    }

    // MARK: when it refuses to push

    func testComingUpShortRepeatsRatherThanRaising() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 900, distance: 1.4),
                                       target: target(seconds: 1_200, distance: 2.0))
        XCTAssertEqual(s?.value, 2.0, "the same target again, not a harder one")
        XCTAssertTrue(s?.because.contains("last time") ?? false)
    }

    /// A slot that prescribes twenty minutes and leaves the pace to how you feel
    /// is not failed by running it slowly — only measured dimensions get a vote.
    func testAnUnprescribedDimensionCannotFailYou() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 1_200, distance: 1.0, speed: 3),
                                       target: target(seconds: 1_200))
        XCTAssertEqual(s?.dimension, .duration)
        XCTAssertEqual(s?.value, 1_260, "the clock was run out, so the clock goes up")
    }

    func testNothingToProgressFromIsNoSuggestion() {
        XCTAssertNil(Tally.nextCardioTarget(lastBout: nil, target: target(seconds: 1_200)))
    }

    func testNoTargetIsNoSuggestion() {
        XCTAssertNil(Tally.nextCardioTarget(lastBout: bout(seconds: 1_200), target: target()))
    }

    /// Floating point: 2.0 covered against a 2.0 target must not read as short.
    func testExactlyMeetingTheDistanceCounts() {
        let s = Tally.nextCardioTarget(lastBout: bout(seconds: 1_200, distance: 2.0),
                                       target: target(distance: 2.0))
        XCTAssertEqual(s?.because, "you covered the distance last time")
    }

    /// Increments a treadmill console actually offers. A suggestion you cannot
    /// dial in is a suggestion you ignore.
    func testIncrementsAreDialableRatherThanPercentages() {
        let d = Tally.nextCardioTarget(lastBout: bout(distance: 3.7),
                                       target: target(distance: 3.7))
        XCTAssertEqual(d?.value, 3.8, "0.1 mi, not 3.885")
    }
}
