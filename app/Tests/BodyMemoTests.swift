import XCTest
@testable import RathiFitness

/// `BodyMemo` is what keeps Today and Trends from re-deriving the day from
/// every set ever logged on each read. Its whole contract is "once per draw":
/// a value is made once until `reset()`, and nothing else.
@MainActor
final class BodyMemoTests: XCTestCase {

    func testAValueIsMadeOnceUntilReset() {
        let memo = BodyMemo()
        var made = 0
        let make = { () -> Int in made += 1; return 7 }

        XCTAssertEqual(memo("x", make), 7)
        XCTAssertEqual(memo("x", make), 7)
        XCTAssertEqual(made, 1, "the second read must be the cached answer")

        memo.reset()
        XCTAssertEqual(memo("x", make), 7)
        XCTAssertEqual(made, 2, "a new draw works it out again")
    }

    /// The case `values[key] as? T` gets wrong: on a rest day `today` is nil,
    /// and a cached nil must read as a hit, not as a miss.
    func testANilAnswerIsCachedToo() {
        let memo = BodyMemo()
        var made = 0
        let make = { () -> String? in made += 1; return nil }

        XCTAssertNil(memo("today", make))
        XCTAssertNil(memo("today", make))
        XCTAssertEqual(made, 1)
    }

    /// And the other half of that trap: a key never set must not read as a
    /// cached nil.
    func testAMissIsNotMistakenForACachedNil() {
        let memo = BodyMemo()
        let first: String? = memo("a") { nil }
        let second: String? = memo("b") { "made" }
        XCTAssertNil(first)
        XCTAssertEqual(second, "made")
    }

    func testKeysAreIndependent() {
        let memo = BodyMemo()
        XCTAssertEqual(memo("suggestion|bench") { 185.0 }, 185.0)
        XCTAssertEqual(memo("suggestion|row") { 135.0 }, 135.0)
        XCTAssertEqual(memo("suggestion|bench") { 0.0 }, 185.0)
    }
}
