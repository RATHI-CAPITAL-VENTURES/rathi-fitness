import XCTest
import MWDATDisplay
@testable import RathiFitness

// `MWDATDisplay` exports its own `Text`, `Button` and `Image`. This file does
// not import SwiftUI, so they are unambiguous here.

/// The glasses face, as far as a test can reach it.
///
/// Which is: what the lens is asked to say, when it is worth saying again, and
/// what that turns into in Meta's vocabulary. The part that talks to the
/// glasses cannot be reached — Meta's mock device has no display — so nothing
/// here pretends to cover it. That part was run on the hardware instead
/// (branch `chore/lens-spike`, FINDINGS.md).
@MainActor
final class LensTests: XCTestCase {

    private func bench(nextSet: Int = 2, weight: Double = 185, reps: Int = 8,
                       resting: LensState.Rest? = nil) -> LensState {
        .strength(exercise: "Bench Press", day: "Push", nextSet: nextSet, of: 4,
                  weight: weight, unit: "lb", reps: reps, resting: resting)
    }

    // MARK: what it says

    func testReadySaysWhatToLiftAndOffersOnlyTheLog() {
        let state = bench()
        XCTAssertEqual(state.eyebrow, "PUSH · SET 2 OF 4")
        XCTAssertEqual(state.title, "Bench Press")
        XCTAssertEqual(state.hero, "185 × 8")
        XCTAssertEqual(state.tone, .ready)
        XCTAssertEqual(state.actions, [.logSet])
    }

    func testAHalfPoundIsNotRoundedAway() {
        XCTAssertEqual(bench(weight: 182.5, reps: 12).hero, "182.5 × 12")
    }

    /// "0 × 12" reads as a fault. A push-up has no weight to show.
    func testNothingOnTheBarIsSaidInReps() {
        XCTAssertEqual(bench(weight: 0, reps: 12).hero, "12 reps")
    }

    func testRestingShowsTheClockAndWhatComesNext() {
        let state = bench(nextSet: 3, resting: .init(remaining: 72, total: 90))
        XCTAssertEqual(state.eyebrow, "RESTING")
        XCTAssertEqual(state.hero, "1:12")
        XCTAssertEqual(state.detail, "Then set 3 of 4 · 185 × 8")
    }

    /// The glasses light the FIRST button when a screen appears — measured on
    /// the hardware — so the first one costs a pinch and the rest cost a swipe
    /// as well. Skip is what you want nine rests in ten.
    func testTheCommonActionIsFirstBecauseTheFirstIsTheOneThatIsLit() {
        let state = bench(resting: .init(remaining: 30, total: 90))
        XCTAssertEqual(state.actions.first, .skipRest)
        XCTAssertEqual(state.actions, [.skipRest, .extendRest])
    }

    /// Resting after the last set is still a rest, but there is no "then".
    func testTheRestAfterTheLastSetPromisesNothing() {
        let state = bench(nextSet: 5, resting: .init(remaining: 40, total: 90))
        XCTAssertEqual(state.detail, "That was the last set")
    }

    /// A finished exercise offers no button: there is no set left to log, and a
    /// pinch that logged a fifth of four would be the worst bug this could have.
    func testFinishedOffersNothingToPinch() {
        let state = bench(nextSet: 5)
        XCTAssertEqual(state.hero, "Done")
        XCTAssertEqual(state.tone, .done)
        XCTAssertTrue(state.actions.isEmpty)
    }

    func testCardioOffersTheLogOnlyWhenThereIsSomethingToLog() {
        let empty = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 0,
                                     resting: nil, canLog: false)
        XCTAssertTrue(empty.actions.isEmpty)
        let set = LensState.cardio(exercise: "Treadmill", day: "Push", seconds: 1200,
                                   resting: nil, canLog: true)
        XCTAssertEqual(set.hero, "20 min")
        XCTAssertEqual(set.actions, [.logSet])
    }

    // MARK: the cooldown colour

    func testRestProgressRunsFromRackedToRecovered() {
        XCTAssertEqual(LensState.Rest(remaining: 90, total: 90).progress, 0, accuracy: 0.001)
        XCTAssertEqual(LensState.Rest(remaining: 45, total: 90).progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(LensState.Rest(remaining: 0, total: 90).progress, 1, accuracy: 0.001)
    }

    /// Extending a rest can leave more on the clock than the total it started
    /// with for an instant; the colour must not run off the end of the ramp.
    func testRestProgressStaysOnTheRamp() {
        XCTAssertEqual(LensState.Rest(remaining: 120, total: 90).progress, 0)
        XCTAssertEqual(LensState.Rest(remaining: -3, total: 90).progress, 1)
        XCTAssertEqual(LensState.Rest(remaining: 10, total: 0).progress, 1)
    }

    /// The reason progress is derived from whole seconds rather than read off
    /// the clock: two states built inside the same second must be EQUAL, or the
    /// pacer sees a change on every call and the radio runs flat out.
    func testTwoStatesInTheSameSecondAreTheSameState() {
        let a = bench(resting: .init(remaining: 72, total: 90))
        let b = bench(resting: .init(remaining: 72, total: 90))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, bench(resting: .init(remaining: 71, total: 90)))
    }

    // MARK: when to send

    func testTheFirstScreenAlwaysGoesOut() {
        XCTAssertTrue(LensPacer().shouldSend(bench()))
    }

    func testAnUnchangedScreenIsNotSentAgain() {
        var pacer = LensPacer()
        let now = Date()
        pacer.sent(bench(), at: now)
        XCTAssertFalse(pacer.shouldSend(bench(), at: now.addingTimeInterval(1)))
        XCTAssertFalse(pacer.shouldSend(bench(), at: now.addingTimeInterval(19)))
    }

    func testAChangeGoesOutAtOnce() {
        var pacer = LensPacer()
        let now = Date()
        pacer.sent(bench(), at: now)
        XCTAssertTrue(pacer.shouldSend(bench(weight: 190), at: now.addingTimeInterval(0.1)))
    }

    /// A session survived thirty seconds of silence on the hardware, and thirty
    /// is only the longest gap anyone tried. A still screen is re-sent inside
    /// that, rather than finding out what forty does during someone's workout.
    func testAStillScreenIsReSentInsideTheSilenceThatIsKnownToWork() {
        XCTAssertLessThan(LensPacer.heartbeat, 30)
        var pacer = LensPacer()
        let now = Date()
        pacer.sent(bench(), at: now)
        XCTAssertTrue(pacer.shouldSend(bench(), at: now.addingTimeInterval(LensPacer.heartbeat)))
    }

    /// After the glasses come off and go back on the lens is blank, whatever we
    /// last sent — so the same screen has to go out again.
    func testAfterADropTheSameScreenGoesOutAgain() {
        var pacer = LensPacer()
        pacer.sent(bench())
        pacer.forget()
        XCTAssertTrue(pacer.shouldSend(bench()))
    }

    // MARK: the actions

    /// One implementation of each action in the app, and the lens is its third
    /// caller. If this mapping drifts, a pinch on "Skip" does something else.
    func testEveryLensActionLandsOnTheMatchingRemoteAction() {
        XCTAssertEqual(LensAction.logSet.remote, .logSet)
        XCTAssertEqual(LensAction.skipRest.remote, .skipRest)
        XCTAssertEqual(LensAction.extendRest.remote, .extendRest)
        for action in LensAction.allCases {
            XCTAssertFalse(action.label.isEmpty)
        }
    }

    /// Through the real `RemoteControls`, because that is the path a pinch
    /// takes: the set screen's handler runs, and nothing else does.
    func testAPinchRunsTheSetScreensOwnHandler() {
        let controls = RemoteControls(music: MusicController())
        var logged = 0, skipped = 0
        controls.handlers = RemoteControls.Handlers(
            logSet: { logged += 1 }, skipRest: { skipped += 1 }, isResting: { false })
        controls.run(LensAction.logSet.remote)
        XCTAssertEqual(logged, 1)
        XCTAssertEqual(skipped, 0)
    }

    /// Mid-rest there is no set to log, so "log" means "skip" — the AirPods
    /// rule, inherited for free by going through the same function. The lens
    /// never offers Log during a rest, but a pinch can land a moment after the
    /// screen it was aimed at has been replaced.
    func testALatePinchOnLogDuringARestSkipsInsteadOfLogging() {
        let controls = RemoteControls(music: MusicController())
        var logged = 0, skipped = 0
        controls.handlers = RemoteControls.Handlers(
            logSet: { logged += 1 }, skipRest: { skipped += 1 }, isResting: { true })
        controls.run(LensAction.logSet.remote)
        XCTAssertEqual(logged, 0)
        XCTAssertEqual(skipped, 1)
    }

    // MARK: in Meta's vocabulary

    func testAScreenIsOneCardPlusItsButtons() {
        let view = LensRenderer.view(for: bench(resting: .init(remaining: 30, total: 90))) { _ in }
        XCTAssertEqual(view.children.count, 2, "the text block, then the button group")
        let group = view.children.last as? ButtonGroup
        XCTAssertEqual(group?.buttons.map(\.label), ["Skip", "+30 s"])
        // Drawn as the answer, because it is the one that arrives lit.
        XCTAssertEqual(group?.buttons.first?.style, .primary)
        XCTAssertEqual(group?.buttons.last?.style, .secondary)
    }

    func testAScreenWithNothingToPinchHasNoButtonGroup() {
        let view = LensRenderer.view(for: bench(nextSet: 5)) { _ in }
        XCTAssertEqual(view.children.count, 1)
    }

    func testAButtonReportsItsOwnAction() {
        let pinched = expectation(description: "the pinch came back")
        let view = LensRenderer.view(for: bench()) { action in
            XCTAssertEqual(action, .logSet)
            pinched.fulfill()
        }
        (view.children.last as? ButtonGroup)?.buttons.first?.onClick?()
        wait(for: [pinched], timeout: 1)
    }

    // MARK: the numeral

    /// The serif ships in the bundle; if it ever stops, the lens falls back to
    /// Meta's heading text rather than drawing a number in the wrong face.
    func testTheNumeralIsDrawnInTheAppsOwnFaceAtLensWidth() throws {
        let image = try XCTUnwrap(LensRenderer.heroImage("1:12", tone: .resting(progress: 0.2)))
        XCTAssertEqual(image.size, LensRenderer.heroSize)
        XCTAssertEqual(image.scale, 1, "one pixel per point — the radio pays for every one")
    }

    /// "182.5 × 12" is as much a hero as "1:12". Shrinking to fit, not cropping.
    func testALongNumeralStillFits() throws {
        let image = try XCTUnwrap(LensRenderer.heroImage("1822.5 × 120", tone: .ready))
        XCTAssertEqual(image.size.width, LensRenderer.heroSize.width)
    }

    // MARK: the switch

    /// Off means off: the simulator, the tests and anyone without glasses never
    /// touch Meta's SDK at all.
    func testOffByDefaultAndInertWhileOff() {
        UserDefaults.standard.removeObject(forKey: "glasses.enabled")
        let glasses = GlassesFace()
        XCTAssertFalse(glasses.enabled)
        XCTAssertEqual(glasses.status, .off)
        glasses.arm(source: { nil }, onPinch: { _ in })
        glasses.refresh()
        XCTAssertFalse(glasses.isShowing)
        glasses.disarm()
    }
}
