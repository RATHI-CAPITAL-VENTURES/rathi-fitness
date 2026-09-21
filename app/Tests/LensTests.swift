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

    private func treadmill(seconds: Int = 1231, done: Int = 0, of bouts: Int = 1,
                           canLog: Bool = true) -> LensState {
        .cardio(exercise: "Treadmill", day: "Push", seconds: seconds,
                boutsDone: done, of: bouts, resting: nil, canLog: canLog)
    }

    func testCardioOffersTheLogOnlyWhenThereIsSomethingToLog() {
        XCTAssertTrue(treadmill(seconds: 0, canLog: false).actions.isEmpty)
        XCTAssertEqual(treadmill().actions, [.logSet])
    }

    /// The phone's hero says 20:31. A mirror that says "21 min" about the same
    /// clock is a mirror that disagrees with the thing it mirrors.
    func testTheCardioClockReadsTheWayThePhonesDoes() {
        XCTAssertEqual(treadmill(seconds: 1231).hero, Fmt.duration(1231))
        XCTAssertEqual(treadmill(seconds: 1231).hero, "20:31")
    }

    /// THE bug the review found. A strength log starts a rest, so the lens
    /// visibly becomes a clock. A cardio log starts nothing — and the first
    /// build's cardio state did not mention bouts, so the lens was identical
    /// before and after, never repainted, and the same live *Log set* took
    /// pinch after pinch, each one another twenty-minute bout in the log.
    func testLoggingACardioBoutChangesWhatTheLensShows() {
        XCTAssertNotEqual(treadmill(done: 0, of: 3), treadmill(done: 1, of: 3))
        XCTAssertNotEqual(treadmill(done: 0, of: 1), treadmill(done: 1, of: 1))
    }

    func testAFinishedMachineOffersNothingToPinch() {
        let done = treadmill(done: 1, of: 1)
        XCTAssertEqual(done.hero, "Done")
        XCTAssertTrue(done.actions.isEmpty, "the dismiss animation is a third of a second of live button otherwise")
        XCTAssertTrue(treadmill(done: 3, of: 3).actions.isEmpty)
    }

    func testIntervalsSayWhichOneYouAreOn() {
        XCTAssertEqual(treadmill(done: 1, of: 3).detail, "Interval 2 of 3")
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

    /// The serif ships in the bundle; if it ever stops, `heroImage` returns nil
    /// and the lens falls back to Meta's heading text rather than drawing a
    /// number in the wrong face. The unwrap is the assertion about the face.
    func testTheSerifIsInTheBundleAndTheNumeralIsOnePixelPerPoint() throws {
        XCTAssertNotNil(UIFont(name: RFDesign.Face.serifBold, size: 100))
        let image = try XCTUnwrap(LensRenderer.heroImage("1:12", tone: .resting(progress: 0.2)))
        XCTAssertEqual(image.size, LensRenderer.heroSize)
        XCTAssertEqual(image.scale, 1, "one pixel per point — the radio pays for every one")
    }

    /// "182.5 × 12" is as much a hero as "1:12". Shrunk to fit, not cropped —
    /// asserted on what the fitting produced, because the canvas is 552 wide
    /// whatever is drawn on it and an assertion about the canvas cannot fail.
    func testALongNumeralIsShrunkUntilItFitsBothWays() throws {
        let face = try XCTUnwrap(UIFont(name: RFDesign.Face.serifBold, size: 100))
        for text in ["1:12", "185 × 8", "182.5 × 12", "1822.5 × 120", "1:02:45"] {
            let bounds = LensRenderer.fitted(text, in: face, color: .white).size()
            XCTAssertLessThanOrEqual(bounds.width, LensRenderer.heroSize.width, text)
            XCTAssertLessThanOrEqual(bounds.height, LensRenderer.heroSize.height, text)
        }
    }

    func testAShortNumeralIsNotShrunkMoreThanItsHeightDemands() throws {
        let face = try XCTUnwrap(UIFont(name: RFDesign.Face.serifBold, size: 100))
        let clock = LensRenderer.fitted("1:12", in: face, color: .white).size()
        let long = LensRenderer.fitted("1822.5 × 120", in: face, color: .white).size()
        XCTAssertGreaterThan(clock.height, long.height, "the clock gets the room a long load cannot use")
    }

    // MARK: the switch

    /// Off means off: the simulator, the tests and anyone without glasses never
    /// touch Meta's SDK at all.
    func testOffByDefaultAndInertWhileOff() {
        UserDefaults.standard.removeObject(forKey: "glasses.enabled")
        let glasses = GlassesFace()
        XCTAssertFalse(glasses.enabled)
        XCTAssertEqual(glasses.status, .off)
        let screen = UUID()
        glasses.arm(owner: screen, source: { nil }, onPinch: { _ in })
        glasses.refresh()
        XCTAssertFalse(glasses.isShowing)
        glasses.disarm(owner: screen)
    }

    // MARK: which pinch counts
    //
    // The worst thing this feature can do is write a set you did not lift.
    // Each of these is a way the first build could, found in review.

    func testAPinchIsHonouredOncePerScreen() {
        var gate = LensGate()
        let screen = gate.reserve()
        gate.open(screen)
        XCTAssertTrue(gate.accept(screen))
        // The lens has not repainted; it still shows the same button.
        XCTAssertFalse(gate.accept(screen), "the second pinch on a stale button is not a second set")
        XCTAssertFalse(gate.accept(screen))
    }

    /// Log → (lens not yet repainted) pinch → pinch. In the first build the
    /// second became "skip the rest" and the third, finding no rest, logged a
    /// set nobody performed. Through the gate the handler runs exactly once.
    func testThreeFastPinchesLogOneSet() {
        let controls = RemoteControls(music: MusicController())
        var logged = 0, resting = false
        controls.handlers = RemoteControls.Handlers(
            logSet: { logged += 1; resting = true },
            skipRest: { resting = false },
            isResting: { resting })
        var gate = LensGate()
        let screen = gate.reserve()
        gate.open(screen)
        let start = Date()
        for beat in 0..<3 where gate.accept(screen, at: start.addingTimeInterval(Double(beat) * 0.3)) {
            controls.run(LensAction.logSet.remote)
        }
        XCTAssertEqual(logged, 1)
        XCTAssertTrue(resting, "and the rest it started is still running")
    }

    /// A button drawn for the bench must not fire once you have opened the squat.
    func testAPinchFromAScreenThatHasBeenReplacedIsRefused() {
        var gate = LensGate()
        let bench = gate.reserve()
        gate.open(bench)
        gate.close()                      // left the bench
        let squat = gate.reserve()
        gate.open(squat)
        XCTAssertFalse(gate.accept(bench))
        XCTAssertTrue(gate.accept(squat))
    }

    /// A ticket is not live until its screen has landed: nobody can pinch a
    /// button the glasses have not been sent.
    func testAScreenThatNeverArrivedCannotBePinched() {
        var gate = LensGate()
        let unsent = gate.reserve()
        XCTAssertFalse(gate.accept(unsent))
    }

    /// A refused pinch does not spend the new screen's ticket — otherwise the
    /// tail of a double-pinch would kill the button that replaced it.
    func testTheTailOfTheLastPinchDoesNotSpendTheNewScreen() {
        var gate = LensGate()
        let now = Date()
        let first = gate.reserve(); gate.open(first)
        XCTAssertTrue(gate.accept(first, at: now))
        let second = gate.reserve(); gate.open(second)
        XCTAssertFalse(gate.accept(second, at: now.addingTimeInterval(0.2)), "too soon to be a reaction to it")
        XCTAssertTrue(gate.accept(second, at: now.addingTimeInterval(1)), "and still there when it is")
    }
}
