import XCTest
@testable import RathiFitness

/// A socket that records what was sent and delivers what a test says the room
/// said.
@MainActor
final class FakeSocket: LensSocket {
    private(set) var protocols: [String] = []
    private(set) var url: URL?
    private(set) var sent: [[String: Any]] = []
    private(set) var closed = false
    private var onText: (@MainActor (String) -> Void)?
    private var onClose: (@MainActor (String) -> Void)?

    func open(_ url: URL, protocols: [String],
              onText: @escaping @MainActor (String) -> Void,
              onClose: @escaping @MainActor (String) -> Void) {
        self.url = url
        self.protocols = protocols
        self.onText = onText
        self.onClose = onClose
    }

    func send(_ text: String) async throws {
        guard !closed else { throw URLError(.networkConnectionLost) }
        sent.append(try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any])
    }

    func close() { closed = true }

    func deliver(_ message: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: message)
        onText?(String(data: data, encoding: .utf8)!)
    }

    func drop() { onClose?("gone") }

    func sent(_ type: String) -> [[String: Any]] { sent.filter { $0["type"] as? String == type } }
}

@MainActor
final class FakeKeepAlive: LensKeepAlive {
    private(set) var holds: [Bool] = []
    private(set) var watchdogs = 0
    func holdForLens(_ on: Bool) { holds.append(on) }
    func lensWatchdog() { watchdogs += 1 }
}

/// `WebLens` with a real `LensHost` above it and a fake socket below: the §3
/// rules, end to end on the phone's side.
@MainActor
final class WebLensTests: XCTestCase {

    /// The phone's clock, and the room's, 5 s ahead of it.
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private let roomAhead: Double = 5_000
    private var roomNow: Double { clock.timeIntervalSince1970 * 1000 + roomAhead }

    private var sockets: [FakeSocket] = []
    private var socket: FakeSocket { sockets.last! }
    private let keepAlive = FakeKeepAlive()
    private var key: String? = "phone-key-0123456789"
    private var screen: LensScreen?
    private var pinches: [LensAction] = []

    private var web: WebLens!
    private var host: LensHost!

    override func setUp() async throws {
        web = WebLens(socket: { [unowned self] in
                          let s = FakeSocket(); self.sockets.append(s); return s },
                      keepAlive: keepAlive,
                      key: { [unowned self] in self.key },
                      now: { [unowned self] in self.clock },
                      appVersion: "0.18.0", runsTimer: false)
        host = LensHost(pumps: false)
        host.now = { [unowned self] in self.clock }
        host.use(web)
        host.host(source: { [unowned self] in self.screen },
                  onPinch: { [unowned self] in self.pinches.append($0) },
                  idle: { "Open the app to bring the workout back." }, onScreenClosed: {})
    }

    private func bench(_ actions: [LensAction] = [.logSet, .fewerReps, .back]) -> LensScreen {
        var state = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 2, of: 4,
                                       weight: 185, word: "", reps: 8, resting: nil)
        state.actions = actions
        return .set(state)
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        await host.beat()
        for _ in 0..<5 { await Task.yield() }
    }

    /// Connect, the room answers with `lenses` pages, and the screen goes out.
    private func connect(lenses: Int = 1) async {
        await host.beat()
        socket.deliver(["type": "hello-ok", "roomNow": roomNow, "peerVersion": "relay-1", "lenses": lenses])
        await settle()
    }

    private var screens: [[String: Any]] { socket.sent("screen") }
    private var lastSeq: Int { screens.last?["seq"] as? Int ?? -1 }

    @discardableResult
    private func input(_ action: Any, id: String = UUID().uuidString, seq: Int? = nil, epoch: String? = nil,
                       relayedAgoMs: Double = 80) async -> [String: Any]? {
        socket.deliver(["v": 1, "type": "input", "id": id, "epoch": epoch ?? web.epoch,
                        "seq": seq ?? lastSeq, "action": action, "relayedAt": roomNow - relayedAgoMs])
        await settle()
        return socket.sent("ack").last { $0["id"] as? String == id }
    }

    // MARK: - Connecting

    func testTheKeyTravelsInTheSubprotocolNeverTheURL() async {
        screen = bench()
        await host.beat()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(socket.protocols, ["fitness.v1", "k.phone-key-0123456789"])
        XCTAssertEqual(socket.url, WebLens.roomURL)
        XCTAssertFalse(socket.url!.absoluteString.contains("phone-key"))
        XCTAssertEqual(socket.sent("hello").first?["version"] as? String, "0.18.0")
        XCTAssertEqual(keepAlive.holds, [true], "the phone is held awake only once a workout wants the lens")
    }

    func testNoLensNothingOffered() async {
        screen = bench()
        await connect(lenses: 0)
        XCTAssertTrue(screens.isEmpty)
        XCTAssertEqual(host.idleReason, "Open Fitness on your glasses.")
        socket.deliver(["type": "presence", "lenses": 1, "lensVersion": "page-1"])
        await settle()
        XCTAssertEqual(screens.count, 1)
        XCTAssertEqual(web.lensVersion, "page-1")
        XCTAssertNil(host.idleReason)
    }

    func testUnpairedDoesNotConnect() async {
        key = nil
        web.keyChanged()
        screen = bench()
        await host.beat()
        XCTAssertTrue(sockets.isEmpty)
    }

    func testEveryScreenCarriesTheVersionEpochAndTicket() async {
        screen = bench()
        await connect()
        let sent = try! XCTUnwrap(screens.first)
        XCTAssertEqual(sent["v"] as? Int, 1)
        XCTAssertEqual(sent["epoch"] as? String, web.epoch)
        XCTAssertGreaterThan(sent["seq"] as? Int ?? 0, 0)
        XCTAssertEqual((sent["screen"] as? [String: Any])?["kind"] as? String, "set")
    }

    // MARK: - A pinch

    func testAPinchIsHonouredOnceAndAcked() async {
        screen = bench()
        await connect()
        let ack = await input("logSet", id: "a1")
        XCTAssertEqual(ack?["accepted"] as? Bool, true)
        XCTAssertEqual(pinches, [.logSet])
        XCTAssertGreaterThan(lastSeq, 1, "and the phone repainted with a fresh ticket")
    }

    /// A replayed id gets its original answer and does nothing.
    func testADuplicateIdGetsTheSameAck() async {
        screen = bench()
        await connect()
        let seq = lastSeq
        let first = await input("logSet", id: "dup", seq: seq)
        let again = await input("logSet", id: "dup", seq: seq)
        XCTAssertEqual(first?["accepted"] as? Bool, true)
        XCTAssertEqual(again?["accepted"] as? Bool, true)
        XCTAssertEqual(socket.sent("ack").filter { $0["id"] as? String == "dup" }.count, 2)
        XCTAssertEqual(pinches, [.logSet], "once")
    }

    func testTheWrongEpochSeqOrActionIsRefused() async {
        screen = bench()
        await connect()
        let seq = lastSeq
        let epoch = await input("logSet", epoch: "someone-else", relayedAgoMs: 50)
        XCTAssertEqual(epoch?["why"] as? String, "wrongEpoch")
        let stale = await input("logSet", seq: seq - 1)
        XCTAssertEqual(stale?["why"] as? String, "wrongSeq")
        let absent = await input("skipRest")
        XCTAssertEqual(absent?["why"] as? String, "notOnScreen", "Skip was not on that screen")
        let unknown = await input("delete-everything")
        XCTAssertEqual(unknown?["why"] as? String, "notOnScreen")
        XCTAssertTrue(pinches.isEmpty)
    }

    func testARowOutOfRangeIsRefused() async {
        screen = .list(LensList(eyebrow: "PUSH · 0 OF 2 DONE", rows: [
            .init(title: "Bench Press", trailing: "185 × 8", done: false, action: .open(0)),
            .init(title: "Leg Press", trailing: "225 × 10", done: false, action: .open(1)),
        ], footer: [.close]))
        await connect()
        let far = await input(["open": 5])
        XCTAssertEqual(far?["why"] as? String, "notOnScreen")
        let row = await input(["open": 1])
        XCTAssertEqual(row?["accepted"] as? Bool, true)
        XCTAssertEqual(pinches, [.open(1)])
    }

    /// Plan §3: an input relayed 3 s ago, by our estimate of room time, was
    /// aimed at a screen the wearer may no longer see.
    func testALatePinchIsRefused() async {
        screen = bench()
        await connect()
        let late = await input("logSet", relayedAgoMs: 3_000)
        XCTAssertEqual(late?["why"] as? String, "late")
        XCTAssertTrue(pinches.isEmpty)
        let onTime = await input("logSet", relayedAgoMs: 1_500)
        XCTAssertEqual(onTime?["accepted"] as? Bool, true, "1.5 s is the limit, not past it")
    }

    /// The phone was suspended: the next thing off the socket meets a closed
    /// gate, because the gap is checked BEFORE the message is read.
    func testATickGapClosesTheGateBeforeTheSocketIsRead() async {
        screen = bench()
        await connect()
        web.tickNow()
        clock += 3
        let buffered = await input("logSet", relayedAgoMs: 100)
        XCTAssertEqual(buffered?["why"] as? String, "closed")
        XCTAssertTrue(pinches.isEmpty)
        XCTAssertGreaterThan(lastSeq, 1, "and a fresh screen went out")
        let next = await input("logSet")
        XCTAssertEqual(next?["accepted"] as? Bool, true)
    }

    func testAShortTickGapDoesNot() async {
        screen = bench()
        await connect()
        web.tickNow()
        clock += 1.9
        let ack = await input("logSet")
        XCTAssertEqual(ack?["accepted"] as? Bool, true)
    }

    /// Two pages could each be showing *Log set*. Writes need exactly one.
    func testTwoLensesRefuseTheWriteButNotNavigation() async {
        screen = bench([.logSet, .back])
        await connect(lenses: 2)
        let log = await input("logSet")
        XCTAssertEqual(log?["why"] as? String, "lenses")
        let back = await input("back")
        XCTAssertEqual(back?["accepted"] as? Bool, true)
        XCTAssertEqual(pinches, [.back])
    }

    // MARK: - Reconnecting

    func testReconnectDrawsWithAFreshTicket() async {
        screen = bench()
        await connect()
        let before = lastSeq
        let first = socket
        first.drop()
        XCTAssertFalse(host.isShowing)
        clock += 1
        await host.beat()
        XCTAssertEqual(sockets.count, 2, "backoff is 0.5 s to start with")
        socket.deliver(["type": "hello-ok", "roomNow": roomNow, "lenses": 1])
        await settle()
        XCTAssertGreaterThan(lastSeq, before)
        let stale = await input("logSet", seq: before)
        XCTAssertEqual(stale?["why"] as? String, "wrongSeq")
        XCTAssertTrue(first.sent("ack").isEmpty)
    }

    func testBackoffGrowsAndCaps() async {
        screen = bench()
        await connect()
        for expected in [0.5, 1, 2, 4, 5, 5] {
            socket.drop()
            let count = sockets.count
            clock += expected - 0.05
            await host.beat()
            XCTAssertEqual(sockets.count, count, "not before \(expected) s")
            clock += 0.1
            await host.beat()
            XCTAssertEqual(sockets.count, count + 1, "at \(expected) s")
        }
    }

    // MARK: - Liveness, pacing, leaving

    /// Every 5 s a ping carrying the ticket on the lens — never a re-sent
    /// screen, which would move the ticket under a finger.
    func testThePingCarriesTheTicketAndTheScreenIsNotResent() async {
        screen = bench()
        await connect()
        let seq = lastSeq
        for _ in 0..<25 {
            clock += 1
            web.tickNow()
            socket.deliver(["type": "pong", "roomNow": roomNow])
            await settle()
        }
        XCTAssertEqual(screens.count, 1)
        let pings = socket.sent("ping")
        XCTAssertGreaterThanOrEqual(pings.count, 5)
        XCTAssertEqual(pings.last?["seq"] as? Int, seq)
        XCTAssertEqual(keepAlive.watchdogs, 25)
    }

    func testASilentRoomIsDropped() async {
        screen = bench()
        await connect()
        for _ in 0..<15 {
            clock += 1
            web.tickNow()
        }
        XCTAssertTrue(sockets[0].closed, "no word from the room in 12 s: the socket is dead")
        XCTAssertEqual(web.link, .down)
        clock += 1
        web.tickNow()
        XCTAssertEqual(sockets.count, 2, "and a new one is tried after the backoff")
    }

    func testThePongSetsTheRoomClock() async {
        screen = bench()
        await host.beat()
        clock += 0.1
        socket.deliver(["type": "pong", "id": 1, "roomNow": roomNow - 50])
        XCTAssertEqual(web.roomRttMs, 100)
        XCTAssertEqual(web.offset.best?.off ?? 0, roomAhead, accuracy: 0.5)
    }

    /// Close, then reopen: the next screen must be newer than the `idle`, or
    /// the page (which renders only what is newer) stays on "closed".
    func testTheScreenAfterIdleIsNewerThanIt() async {
        screen = bench()
        await connect()
        let first = socket
        screen = nil
        await host.beat()
        for _ in 0..<5 { await Task.yield() }
        let idleSeq = try! XCTUnwrap(first.sent("idle").last?["seq"] as? Int)
        screen = bench()
        await connect()
        XCTAssertGreaterThan(lastSeq, idleSeq)
    }

    func testForgettingThePairingMidWorkoutLetsThePhoneSleep() async {
        screen = bench()
        await connect()
        key = nil
        web.keyChanged()
        XCTAssertEqual(keepAlive.holds, [true, false])
        XCTAssertFalse(web.isEngaged)
        XCTAssertFalse(host.isShowing)
    }

    /// Fails closed: an unstamped input cannot be judged for lateness.
    func testAnInputTheRoomDidNotStampIsRefused() async {
        screen = bench()
        await connect()
        socket.deliver(["v": 1, "type": "input", "id": "nostamp", "epoch": web.epoch, "seq": lastSeq, "action": "logSet"])
        await settle()
        XCTAssertEqual(socket.sent("ack").last?["why"] as? String, "late")
        XCTAssertTrue(pinches.isEmpty)
    }

    func testTheLastLensLeavingClosesTheGate() async {
        screen = bench()
        await connect()
        let seq = lastSeq
        socket.deliver(["type": "presence", "lenses": 0])
        let ack = await input("logSet", seq: seq)
        XCTAssertEqual(ack?["why"] as? String, "closed")
        XCTAssertFalse(host.isShowing)
    }

    func testAPongForAPingWeAreNotWaitingForIsIgnored() async {
        screen = bench()
        await host.beat()
        clock += 0.1
        socket.deliver(["type": "pong", "id": 99, "roomNow": roomNow])
        XCTAssertNil(web.roomRttMs)
    }

    func testNothingOfOursSaysWhyAndLetsGo() async {
        screen = bench()
        await connect()
        let first = socket
        screen = nil
        await host.beat()
        for _ in 0..<5 { await Task.yield() }
        let idle = try! XCTUnwrap(first.sent("idle").last)
        XCTAssertEqual(idle["reason"] as? String, "idle")
        XCTAssertEqual(idle["text"] as? String, "Open the app to bring the workout back.")
        XCTAssertTrue(first.closed)
        XCTAssertEqual(keepAlive.holds, [true, false], "and the phone is let sleep")
    }

    func testMovingToTheNativeLensSaysSo() async {
        screen = bench()
        await connect()
        let first = socket
        host.use(FakeTransport())
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(first.sent("idle").last?["reason"] as? String, "moved")
    }

    func testARestIsSentOnceAndTicksOnThePage() async {
        let rest = RestClock(endsAt: clock.addingTimeInterval(90), total: 90)
        func resting() -> LensScreen {
            var state = LensState.strength(exercise: "Bench Press", day: "Push", nextSet: 3, of: 4, weight: 185,
                                           word: "", reps: 8, resting: .init(rest, at: clock))
            state.actions = [.skipRest, .extendRest, .list]
            return .set(state)
        }
        screen = resting()
        await connect()
        for _ in 0..<10 {
            clock += 1
            web.tickNow()
            screen = resting()
            await host.beat()
        }
        XCTAssertEqual(screens.count, 1)
        let body = try! XCTUnwrap(screens.first?["screen"] as? [String: Any])
        XCTAssertNil(body["hero"])
        XCTAssertEqual((body["rest"] as? [String: Any])?["remainingMsAtSend"] as? Int, 90_000)
    }
}
