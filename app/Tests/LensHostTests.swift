import Combine
import XCTest
@testable import RathiFitness

/// A lens that is only a list of what it was asked to show. It can hold a
/// `show` in the air, so a test can do something in the middle of a send —
/// which is exactly where every bug this class has had lived.
@MainActor
final class FakeTransport: LensTransport {
    var isAvailable = true
    var isEngaged = false
    var waitingReason: String?
    var ready = true
    var pacesClockFree = false
    var heartbeat: TimeInterval? = LensPacer.heartbeat
    var onEvent: (@MainActor (LensEvent) -> Void)?
    var wanted: (@MainActor () -> Bool)?

    struct Shown { let screen: LensScreen; let ticket: Int; let pinch: LensHost.Pinch }
    private(set) var shown: [Shown] = []
    private(set) var ends: [(clearing: Bool, reason: LensHost.Idle, ticket: Int)] = []
    private(set) var wakes = 0

    /// The next `show` waits until `release`.
    var holdNext = false
    private var held: CheckedContinuation<Void, Error>?
    var isHolding: Bool { held != nil }

    struct Dropped: Error {}

    func ensure() async -> Bool {
        // As the native lens does after its teardown await: a screen that is
        // no longer wanted opens nothing.
        guard wanted?() == true else { return false }
        isEngaged = true
        return ready
    }

    func show(_ screen: LensScreen, ticket: Int, onPinch: @escaping LensHost.Pinch) async throws {
        shown.append(Shown(screen: screen, ticket: ticket, pinch: onPinch))
        if holdNext {
            holdNext = false
            try await withCheckedThrowingContinuation { held = $0 }
        }
    }

    func release(throwing: Bool = false) {
        let waiting = held
        held = nil
        if throwing { waiting?.resume(throwing: Dropped()) } else { waiting?.resume() }
    }

    func end(clearing: Bool, reason: LensHost.Idle, ticket: Int) {
        isEngaged = false
        ends.append((clearing, reason, ticket))
    }

    func wake() { wakes += 1 }

    var last: Shown? { shown.last }
}

/// `LensHost` against a fake lens: the behaviour that moved out of
/// `GlassesFace` in v0.18.0, now reachable by a test for the first time —
/// Meta's mock device has no display, so none of this could be exercised
/// before. The mutation check for each guard is recorded in the v0.18.0 retro.
@MainActor
final class LensHostTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 100_000)
    private var driverScreen: LensScreen? = nil
    private var driverPinches: [LensAction] = []
    private var musicRuns: [LensAction] = []

    private func bench(_ actions: [LensAction] = [.logSet, .fewerReps, .back], resting: LensState.Rest? = nil) -> LensScreen {
        var state = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4,
                                       weight: 185, word: "", reps: 8, resting: resting)
        state.actions = actions
        return .set(state)
    }

    private func makeHost(_ given: FakeTransport? = nil, music: Bool = false) -> (LensHost, FakeTransport) {
        let fake = given ?? FakeTransport()
        let host = LensHost(pumps: false)
        host.now = { [unowned self] in self.clock }
        host.use(fake)
        host.host(source: { [unowned self] in self.driverScreen },
                  onPinch: { [unowned self] in self.driverPinches.append($0) },
                  idle: { "Rest day" }, onScreenClosed: {})
        if music {
            host.music(track: { .init(title: "Synthetic Track", artist: nil, isPlaying: true) },
                       available: { true }, canStart: { true },
                       run: { [unowned self] in self.musicRuns.append($0) },
                       changes: Empty().eraseToAnyPublisher())
        }
        return (host, fake)
    }

    /// Let spawned refreshes run, then beat once more and wait for it.
    private func settle(_ host: LensHost) async {
        for _ in 0..<5 { await Task.yield() }
        await host.beat()
    }

    private func waitForHold(_ fake: FakeTransport) async {
        for _ in 0..<1_000 where !fake.isHolding { await Task.yield() }
        XCTAssertTrue(fake.isHolding, "the send never reached the lens")
    }

    // MARK: - The basics

    func testAScreenGoesOutAndIsShowing() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        XCTAssertEqual(fake.shown.count, 1)
        XCTAssertEqual(fake.last?.screen, bench())
        XCTAssertTrue(host.isShowing)
        XCTAssertNil(host.idleReason)
    }

    func testAnUnchangedScreenIsNotSentAgain() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        await host.beat()
        XCTAssertEqual(fake.shown.count, 1)
    }

    func testNothingToShowGivesTheLensBackWithTheReason() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        driverScreen = nil
        await host.beat()
        XCTAssertEqual(fake.ends.last?.reason, .idle("Rest day"))
        XCTAssertEqual(fake.ends.last?.clearing, true)
        XCTAssertFalse(host.isShowing)
        XCTAssertEqual(host.idleReason, "Rest day")
    }

    /// The pump's guard: no lens reachable, no screen even asked for.
    func testAnUnreachableLensIsNotAskedForAScreen() async {
        var asked = 0
        let fake = FakeTransport()
        fake.isAvailable = false
        let host = LensHost(pumps: false)
        host.use(fake)
        host.host(source: { asked += 1; return nil }, onPinch: { _ in }, idle: { "" }, onScreenClosed: {})
        await host.beat()
        XCTAssertEqual(asked, 0)
    }

    func testAWaitingLensSaysWhy() async {
        driverScreen = bench()
        let fake = FakeTransport()
        fake.ready = false
        fake.waitingReason = "Open Fitness on your glasses."
        let (host, _) = makeHost(fake)
        await host.beat()
        XCTAssertEqual(host.idleReason, "Open Fitness on your glasses.")
        XCTAssertTrue(fake.shown.isEmpty)
    }

    // MARK: - Which pinch counts

    func testAPinchIsHonouredOnceAndRepaints() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        let screen = try! XCTUnwrap(fake.last)
        XCTAssertTrue(screen.pinch(.logSet))
        XCTAssertFalse(screen.pinch(.logSet), "the second pinch on a stale button is not a second set")
        XCTAssertEqual(driverPinches, [.logSet])
        await settle(host)
        XCTAssertEqual(fake.shown.count, 2, "an honoured pinch repaints even if nothing visible changed")
        XCTAssertGreaterThan(fake.shown[1].ticket, screen.ticket)
    }

    func testAPinchFromAReplacedScreenIsRefused() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        let old = try! XCTUnwrap(fake.last)
        driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(remaining: 80, total: 90))
        await host.beat()
        XCTAssertFalse(old.pinch(.logSet))
        XCTAssertTrue(fake.last!.pinch(.skipRest))
        XCTAssertEqual(driverPinches, [.skipRest])
    }

    /// Log → Skip → Log inside a second writes one set, through the host's clock.
    func testAWriteSoonAfterTheLastPinchIsRefusedButNotSpent() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        XCTAssertTrue(fake.last!.pinch(.logSet))
        await settle(host)
        clock += 0.4
        XCTAssertFalse(fake.last!.pinch(.logSet), "the tail of a flurry")
        clock += 1.2
        XCTAssertTrue(fake.last!.pinch(.logSet), "and the screen is still live when it is considered")
        XCTAssertEqual(driverPinches, [.logSet, .logSet])
    }

    func testAFrozenPhoneClosesTheGateAndRepaints() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        let screen = try! XCTUnwrap(fake.last)
        fake.onEvent?(.frozen)
        XCTAssertFalse(screen.pinch(.logSet))
        XCTAssertTrue(driverPinches.isEmpty)
        await settle(host)
        XCTAssertEqual(fake.shown.count, 2, "a fresh ticket")
    }

    // MARK: - In the air (the epoch guards)

    /// Open an exercise on the phone while the driver's screen is in the air:
    /// the late landing must not mark it showing, nor its button speak for
    /// either layer. Mutation: without `layer == layerEpoch` this fails.
    func testArmingMidSendNeverMarksTheOldScreenShowing() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        fake.holdNext = true
        let beat = Task { await host.beat() }
        await waitForHold(fake)
        let inAir = try! XCTUnwrap(fake.last)
        var mirrored: [LensAction] = []
        host.arm(owner: UUID(), source: { .set(.strength(exercise: "Cable Fly", day: nil, nextSet: 1, of: 3,
                                                         weight: 45, word: "", reps: 12, resting: nil)) },
                 onPinch: { mirrored.append($0) })
        fake.release()
        await beat.value
        XCTAssertFalse(host.isShowing, "drawn for the driver, landed after the set screen took over")
        XCTAssertFalse(inAir.pinch(.logSet))
        XCTAssertTrue(driverPinches.isEmpty)
        XCTAssertTrue(mirrored.isEmpty, "the bench's Log set must never log a cable fly")
        XCTAssertEqual(fake.wakes, 2, "once on use, once on arm: a change of exercise is not a lens that stopped answering")
    }

    func testDisarmingMidSendNeverMarksTheOldScreenShowing() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        let owner = UUID()
        var mirrored: [LensAction] = []
        host.arm(owner: owner, source: { [unowned self] in self.bench([.logSet]) }, onPinch: { mirrored.append($0) })
        fake.holdNext = true
        let beat = Task { await host.beat() }
        await waitForHold(fake)
        let inAir = try! XCTUnwrap(fake.last)
        host.disarm(owner: owner)
        fake.release()
        await beat.value
        await settle(host)
        // The driver took over underneath (disarm repaints), so something IS
        // showing now — the driver's screen, not the one that was in the air.
        XCTAssertEqual(fake.last?.screen, bench())
        XCTAssertFalse(inAir.pinch(.logSet))
        XCTAssertTrue(mirrored.isEmpty)
        XCTAssertTrue(driverPinches.isEmpty)
    }

    /// The glasses come off (or the socket drops) while a screen is in the
    /// air. Mutation: without `epoch == transportEpoch` this fails.
    func testADropMidSendNeverMarksTheScreenShowing() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        fake.holdNext = true
        let beat = Task { await host.beat() }
        await waitForHold(fake)
        let inAir = try! XCTUnwrap(fake.last)
        fake.onEvent?(.lost)
        fake.release()
        await beat.value
        XCTAssertFalse(host.isShowing)
        XCTAssertFalse(inAir.pinch(.logSet))
        // And the next beat sends it again: the lens shows nothing we know of.
        await host.beat()
        XCTAssertEqual(fake.shown.count, 2)
    }

    func testAFailedSendIsForgottenAndItsTicketClosed() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        fake.holdNext = true
        let beat = Task { await host.beat() }
        await waitForHold(fake)
        let inAir = try! XCTUnwrap(fake.last)
        fake.release(throwing: true)
        await beat.value
        XCTAssertFalse(host.isShowing)
        XCTAssertFalse(inAir.pinch(.logSet))
        await host.beat()
        XCTAssertEqual(fake.shown.count, 2, "sent again, because it never landed")
    }

    /// A refresh that arrives mid-beat is owed, not dropped: dropping it left a
    /// stale *Log set* up for a second after a pinch.
    func testAnOwedBeatIsHonoured() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        fake.holdNext = true
        let beat = Task { await host.beat() }
        await waitForHold(fake)
        driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(remaining: 90, total: 90))
        await host.beat()            // returns at once: one is in flight, so this one is owed
        XCTAssertEqual(fake.shown.count, 1)
        fake.release()
        await beat.value
        XCTAssertEqual(fake.shown.count, 2)
        XCTAssertEqual(fake.last?.screen.actions, [.skipRest, .extendRest, .list])
    }

    // MARK: - Music over both layers

    func testMusicBackClosesTheCardAndTheDriversBackGoesToTheDriver() async {
        driverScreen = bench()
        let (host, fake) = makeHost(music: true)
        await host.beat()
        XCTAssertEqual(fake.last?.screen.actions, [.logSet, .fewerReps, .back, .music])
        XCTAssertTrue(fake.last!.pinch(.music))
        await settle(host)
        guard case .card(let card) = fake.last?.screen else { return XCTFail("no music card") }
        XCTAssertEqual(card.actions, [.pause, .nextTrack, .back])

        XCTAssertTrue(fake.last!.pinch(.back))
        await settle(host)
        XCTAssertTrue(driverPinches.isEmpty, "the card's Back is the card's")
        XCTAssertEqual(fake.last?.screen.actions, [.logSet, .fewerReps, .back, .music])

        XCTAssertTrue(fake.last!.pinch(.back))
        XCTAssertEqual(driverPinches, [.back], "the set's Back is the driver's")
        XCTAssertTrue(musicRuns.isEmpty)
    }

    func testThePlayerButtonsDriveThePlayer() async {
        driverScreen = bench()
        let (host, fake) = makeHost(music: true)
        await host.beat()
        _ = fake.last!.pinch(.music)
        await settle(host)
        XCTAssertTrue(fake.last!.pinch(.pause))
        XCTAssertEqual(musicRuns, [.pause])
        XCTAssertTrue(driverPinches.isEmpty)
    }

    /// The rest ending is the one thing the lens must not hide.
    func testTheRestEndingClosesTheMusicCard() async {
        let start = Date(timeIntervalSince1970: 100_000)
        let clockRest = RestClock(endsAt: start.addingTimeInterval(3), total: 90)
        driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(clockRest, at: start))
        let (host, fake) = makeHost(music: true)
        await host.beat()
        _ = fake.last!.pinch(.music)
        await settle(host)
        guard case .card(let card) = fake.last?.screen else { return XCTFail("no music card") }
        XCTAssertEqual(card.specs.first?.rest, clockRest, "the card carries the rest's deadline")

        driverScreen = bench()
        await host.beat()
        XCTAssertEqual(fake.last?.screen.actions, [.logSet, .fewerReps, .back, .music])
    }

    // MARK: - Pacing, by transport

    func testTheWebLensIsNotSentTheClockEverySecond() async {
        let start = Date(timeIntervalSince1970: 100_000)
        let rest = RestClock(endsAt: start.addingTimeInterval(90), total: 90)
        let fake = FakeTransport()
        fake.pacesClockFree = true
        fake.heartbeat = nil
        driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(rest, at: start))
        let (host, _) = makeHost(fake)
        await host.beat()
        for second in 1...30 {
            driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(rest, at: start.addingTimeInterval(Double(second))))
            await host.beat()
        }
        XCTAssertEqual(fake.shown.count, 1, "the page ticks the clock itself")

        var extended = rest
        extended.endsAt += 30
        extended.total += 30
        driverScreen = bench([.skipRest, .extendRest, .list], resting: .init(extended, at: start.addingTimeInterval(31)))
        await host.beat()
        XCTAssertEqual(fake.shown.count, 2, "+30 s is a change")
    }

    func testTheNativeLensIsStillSentEverySecond() async {
        let start = Date(timeIntervalSince1970: 100_000)
        let rest = RestClock(endsAt: start.addingTimeInterval(90), total: 90)
        driverScreen = bench([.skipRest], resting: .init(rest, at: start))
        let (host, fake) = makeHost()
        await host.beat()
        for second in 1...5 {
            driverScreen = bench([.skipRest], resting: .init(rest, at: start.addingTimeInterval(Double(second))))
            await host.beat()
        }
        XCTAssertEqual(fake.shown.count, 6)
    }

    // MARK: - Switching lenses mid-workout

    func testSwitchingLensesClosesTheGateAndEndsTheOldOne() async {
        driverScreen = bench()
        let (host, native) = makeHost()
        await host.beat()
        let old = try! XCTUnwrap(native.last)
        let web = FakeTransport()
        host.use(web)
        XCTAssertEqual(native.ends.last?.reason, .moved)
        XCTAssertEqual(native.ends.last?.clearing, true)
        XCTAssertNil(native.onEvent, "the old lens can no longer speak to the host")
        XCTAssertFalse(old.pinch(.logSet))
        XCTAssertFalse(host.isShowing)
        await host.beat()
        XCTAssertEqual(web.shown.count, 1, "the same place in the workout, on the new lens")
        XCTAssertEqual(web.last?.screen, bench())
        XCTAssertTrue(web.last!.pinch(.logSet))
        XCTAssertEqual(driverPinches, [.logSet])
    }

    /// The last word gets its own ticket, so the next screen is always newer.
    func testTheLastWordHasATicketOfItsOwn() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        let shown = fake.last!.ticket
        driverScreen = nil
        await host.beat()
        let idle = try! XCTUnwrap(fake.ends.last?.ticket)
        XCTAssertGreaterThan(idle, shown)
        driverScreen = bench()
        await host.beat()
        XCTAssertGreaterThan(fake.last!.ticket, idle)
    }

    func testDisarmingWithNoDriverGivesTheLensBack() async {
        let fake = FakeTransport()
        let host = LensHost(pumps: false)
        host.use(fake)
        let owner = UUID()
        host.arm(owner: owner, source: { [unowned self] in self.bench([.logSet]) }, onPinch: { _ in })
        await host.beat()
        XCTAssertTrue(host.isShowing)
        let screen = try! XCTUnwrap(fake.last)
        host.disarm(owner: owner)
        XCTAssertEqual(fake.ends.last?.clearing, true)
        XCTAssertFalse(host.isShowing)
        XCTAssertFalse(screen.pinch(.logSet))
        XCTAssertEqual(fake.wanted?(), false, "nothing is wanted on the lens any more")
    }

    func testArmingWakesTheLens() async {
        let (host, fake) = makeHost()
        let before = fake.wakes
        host.arm(owner: UUID(), source: { nil }, onPinch: { _ in })
        XCTAssertEqual(fake.wakes, before + 1)
    }

    func testLosingTheLensClosesTheMusicCard() async {
        driverScreen = bench()
        let (host, fake) = makeHost(music: true)
        await host.beat()
        _ = fake.last!.pinch(.music)
        await settle(host)
        guard case .card = fake.last?.screen else { return XCTFail("no music card") }
        fake.onEvent?(.lost)
        await host.beat()
        XCTAssertEqual(fake.last?.screen.actions, [.logSet, .fewerReps, .back, .music],
                       "glasses off and on come back to the workout, not the card")
    }

    func testAReadyLensIsDrawnOn() async {
        driverScreen = bench()
        let fake = FakeTransport()
        fake.ready = false
        let (host, _) = makeHost(fake)
        await host.beat()
        XCTAssertTrue(fake.shown.isEmpty)
        fake.ready = true
        fake.onEvent?(.ready)
        await settle(host)
        XCTAssertEqual(fake.shown.count, 1)
    }

    func testSwitchingOffSaysSo() async {
        driverScreen = bench()
        let (host, fake) = makeHost()
        await host.beat()
        host.use(nil, leaving: .off)
        XCTAssertEqual(fake.ends.last?.reason, .off)
        await host.beat()
        XCTAssertEqual(fake.shown.count, 1)
    }
}
