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

import SwiftUI

/// The one light surface in the app.
///
/// The pass card goes white at full brightness because a turnstile scanner
/// needs a bright ground behind the code — so its text cannot come from the
/// palette everything else uses, which is built to sit on near-black. Those
/// three values used to be written into `PassView` as literals; they are tokens
/// now, and these assertions are what stops the next person "tidying" them into
/// the dark ones and shipping white text on a white card.
final class LightSurfaceTests: XCTestCase {

    /// Relative luminance, WCAG's definition — sRGB linearised, not the raw
    /// channel values. The difference matters: the naive version rated this
    /// palette's secondary grey at 0.45 and made a threshold picked by eye look
    /// like a failure.
    private func luminance(_ color: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Contrast ratio between two colours, 1:1 to 21:1.
    private func contrast(_ a: Color, _ b: Color) -> CGFloat {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testTheCardIsActuallyWhite() {
        XCTAssertEqual(luminance(RFDesign.lightGround), 1.0, accuracy: 0.01)
    }

    /// Against a real standard rather than a number chosen by eye: WCAG AAA for
    /// the primary text, AA for the secondary line under it.
    func testItsTextIsLegibleOnWhite() {
        XCTAssertGreaterThan(contrast(RFDesign.onLight, RFDesign.lightGround), 7.0)
        XCTAssertGreaterThan(contrast(RFDesign.onLightDim, RFDesign.lightGround), 4.5)
    }

    func testTheDimOneIsDimmerButStillNotTheGround() {
        XCTAssertGreaterThan(luminance(RFDesign.onLightDim), luminance(RFDesign.onLight))
        XCTAssertLessThan(luminance(RFDesign.onLightDim), luminance(RFDesign.lightGround))
    }

    /// The trap this exists for: the dark palette's text on the light card.
    func testTheDarkPalettesTextWouldBeInvisibleThere() {
        XCTAssertLessThan(contrast(RFDesign.speech, RFDesign.lightGround), 1.5,
                          "speech is near-white — on the pass card it would vanish, "
                          + "which is why onLight exists")
    }
}
