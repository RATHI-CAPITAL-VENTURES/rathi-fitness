import XCTest
@testable import RathiFitness

final class PlateMathTests: XCTestCase {

    func testTheNumberFromTheMockup() {
        // 185 on a 45 bar is one 45 and one 25 a side. This is the example in
        // design/ios-first-pass.html, so if it ever stops being true the picture
        // and the app disagree.
        let l = PlateMath.loadout(target: 185, bar: 45)
        XCTAssertEqual(l.perSide, [45, 25])
        XCTAssertTrue(l.isExact)
        XCTAssertEqual(l.achievable, 185)
    }

    func testEmptyBar() {
        let l = PlateMath.loadout(target: 45, bar: 45)
        XCTAssertEqual(l.perSide, [])
        XCTAssertEqual(l.achievable, 45)
        XCTAssertTrue(l.isExact)
    }

    func testBelowTheBarIsNotNegativePlates() {
        let l = PlateMath.loadout(target: 30, bar: 45)
        XCTAssertEqual(l.perSide, [])
        XCTAssertEqual(l.achievable, 45)
    }

    func testHeavyPullUsesRepeats() {
        let l = PlateMath.loadout(target: 315, bar: 45)
        XCTAssertEqual(l.perSide, [45, 45, 45])
        XCTAssertTrue(l.isExact)
    }

    func testUnreachableWeightReportsWhatYouWillActuallyLift() {
        // 186 cannot be made with 2.5s as the smallest plate: 70.5 a side.
        let l = PlateMath.loadout(target: 186, bar: 45)
        XCTAssertFalse(l.isExact)
        XCTAssertEqual(l.achievable, 185)
        XCTAssertEqual(l.remainder, 1, accuracy: 0.001)
    }

    func testGroupingCollapsesRepeats() {
        let g = PlateMath.grouped([45, 45, 25, 10])
        XCTAssertEqual(g.count, 3)
        XCTAssertEqual(g[0].plate, 45); XCTAssertEqual(g[0].count, 2)
        XCTAssertEqual(g[1].plate, 25); XCTAssertEqual(g[1].count, 1)
    }

    func testStepperNeverLandsOnAnUnloadableWeight() {
        // The smallest pair is 2.5 + 2.5, so every reachable weight is bar + 5n.
        for start in stride(from: 45.0, through: 300.0, by: 5) {
            let up = PlateMath.step(from: start, by: 5, bar: 45)
            XCTAssertTrue(PlateMath.loadout(target: up, bar: 45).isExact,
                          "\(up) is not loadable")
        }
    }

    func testStepperClampsAtTheBar() {
        XCTAssertEqual(PlateMath.step(from: 45, by: -5, bar: 45), 45)
    }

    func testStepperPullsAnOddWeightOntoTheGrid() {
        // 187 is not loadable; stepping up from it should land somewhere that is.
        let up = PlateMath.step(from: 187, by: 5, bar: 45)
        XCTAssertTrue(PlateMath.loadout(target: up, bar: 45).isExact)
    }
}

final class CooldownRampTests: XCTestCase {

    func testStartsEmberAndEndsReady() {
        XCTAssertEqual(RFDesign.coolHue(0), RFDesign.emberHue, accuracy: 0.001)
        XCTAssertEqual(RFDesign.coolHue(1), RFDesign.readyHue, accuracy: 0.001)
    }

    func testHoldsWarmForMostOfTheRest() {
        // The whole point: at three quarters done it must still read as warm,
        // not as "nearly teal". Anything above ~60 is green.
        XCTAssertLessThan(RFDesign.coolHue(0.5), 45)
        XCTAssertLessThanOrEqual(RFDesign.coolHue(RFDesign.warmHold), RFDesign.handoffHue + 0.001)
    }

    func testHandoverHappensInTheLastQuarter() {
        let atHandoff = RFDesign.coolHue(RFDesign.warmHold)
        let nearEnd = RFDesign.coolHue(0.95)
        XCTAssertGreaterThan(nearEnd - atHandoff, 60,
                             "the change has to be catchable in peripheral vision")
    }

    func testMonotonic() {
        var previous = -1.0
        for i in 0...100 {
            let h = RFDesign.coolHue(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(h, previous, "hue must never go backwards")
            previous = h
        }
    }

    func testClampsOutOfRangeInput() {
        XCTAssertEqual(RFDesign.coolHue(-3), RFDesign.emberHue, accuracy: 0.001)
        XCTAssertEqual(RFDesign.coolHue(9), RFDesign.readyHue, accuracy: 0.001)
    }
}

final class FormattingTests: XCTestCase {
    func testWeightsDropPointlessDecimals() {
        XCTAssertEqual(Fmt.weight(185), "185")
        XCTAssertEqual(Fmt.weight(2.5), "2.5")
    }
    func testBodyWeightKeepsItsDecimal() {
        XCTAssertEqual(Fmt.bodyWeight(176), "176.0")
    }
    func testClockPadsSeconds() {
        XCTAssertEqual(Fmt.clock(107), "1:47")
        XCTAssertEqual(Fmt.clock(60), "1:00")
        XCTAssertEqual(Fmt.clock(-5), "0:00")
    }
    func testNoChangeIsADashNotAZero() {
        XCTAssertEqual(Fmt.signed(0), "—")
        XCTAssertEqual(Fmt.signed(10), "+10")
        XCTAssertEqual(Fmt.signed(-2.5), "−2.5")
    }
}
