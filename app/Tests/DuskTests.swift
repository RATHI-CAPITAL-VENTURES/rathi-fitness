import XCTest
import SwiftUI
import UIKit
@testable import RathiFitness

/// Dusk's promises that a screenshot cannot keep: the text a gym reads fast is
/// legible on the surface it is drawn on, and the lens did not get pastel.
final class DuskTests: XCTestCase {

    private func luminance(_ c: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testTextIsLegibleOnEverySolidSurface() {
        let surfaces = [RFDesign.ground, RFDesign.surfaceQuiet,
                        RFDesign.surface, RFDesign.surfaceHigh]
        for surface in surfaces {
            for text in [RFDesign.speech, RFDesign.label, RFDesign.labelDim, RFDesign.ready] {
                XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5)
            }
        }
    }

    func testTheRestClockIsLegibleAtEveryPointOfTheCooldown() {
        for step in 0...20 {
            let p = Double(step) / 20
            XCTAssertGreaterThanOrEqual(
                contrast(RFDesign.coolColor(p, brightness: 0.97), RFDesign.surface), 4.5,
                "rest colour at \(p)")
            XCTAssertGreaterThanOrEqual(
                contrast(RFDesign.coolColor(p, brightness: 0.85), RFDesign.surface), 4.5,
                "rest caption at \(p)")
        }
    }

    func testTextOnAPrimaryActionIsLegible() {
        XCTAssertGreaterThanOrEqual(contrast(RFDesign.onAction, RFDesign.ready), 7)
        for step in 0...10 {
            XCTAssertGreaterThanOrEqual(
                contrast(RFDesign.onAction, RFDesign.coolColor(Double(step) / 10)), 4.5)
        }
    }

    /// A problem must not look like a mood: peach is never what ready is.
    func testEmberIsNotTheReadyHue() {
        XCTAssertNotEqual(RFDesign.emberHue, RFDesign.readyHue)
    }

    /// The glasses add light; Dusk's pastels would read as white on them.
    func testTheLensKeepsItsSaturatedRamp() {
        var s: CGFloat = 0, h: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        RFDesign.coolUIColor(0).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        XCTAssertGreaterThan(s, 0.85)
        RFDesign.readyUIColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        XCTAssertGreaterThan(s, 0.6)
    }
}
