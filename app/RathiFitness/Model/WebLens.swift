import Combine
import Foundation

/// The Web App lens: the same screens, sent through the relay room to a page
/// the glasses run from their own app grid. The phone stays the only source of
/// truth — the page renders the screen value this publishes and sends back
/// "button X on screen #N was pressed" (docs/LENS_WIRE.md).
///
/// Built after a measured spike (docs/DECISIONS.md, 2026-10-10): pinch to new
/// screen p50 ~125–144 ms, the display stayed lit through idle rests, and a
/// locked, pocketed phone stayed reachable with `AudioHub.holdForLens` armed.
///
/// What makes it safe is the same thing that makes the native lens safe — a
/// pinch counts once, only for the screen it was aimed at — plus three rules a
/// network adds, all from plan §3:
///
/// - **Late pinches are refused.** The room stamps every input `relayedAt` on
///   its clock; one more than 1.5 s old by our estimate of room time was aimed
///   at a screen the wearer may no longer see.
/// - **A frozen phone closes the gate first.** A 1 Hz tick that comes more than
///   2 s late means the process was suspended. The gate closes BEFORE the
///   socket is read again, so inputs buffered while frozen meet a closed gate.
/// - **Writes need exactly one lens.** Two pages could each hold a *Log set*.
@MainActor
final class WebLens: ObservableObject, LensTransport {

    static let roomURL = URL(string: "wss://feed-api.ishanrathi.com/room")!
    static let lateMs: Double = 1_500
    static let pingEvery: Double = 5_000
    /// No reply of any kind in this long and the socket is treated as dead.
    static let silenceLimitMs: Double = 12_000

    enum Link: String { case off, connecting, up, down }

    @Published private(set) var link: Link = .off
    /// Pages connected to the room, by the room's count.
    @Published private(set) var lenses = 0
    @Published private(set) var roomRttMs: Int?
    /// How long the last honoured pinch took from the room to here.
    @Published private(set) var lastPinchMs: Int?
    @Published private(set) var lensVersion: String?
    @Published private(set) var relayVersion: String?
    @Published private(set) var paired: Bool

    /// This phone run's identity on the wire. New per process, so a page that
    /// saw seq 400 from the last launch takes seq 1 from this one.
    let epoch = String(UUID().uuidString.prefix(8)).lowercased()

    var onEvent: (@MainActor (LensEvent) -> Void)?
    var wanted: (@MainActor () -> Bool)?

    private let makeSocket: @MainActor () -> LensSocket
    private let keepAlive: LensKeepAlive?
    private let key: @MainActor () -> String?
    private let now: @MainActor () -> Date
    private let appVersion: String
    private let runsTimer: Bool

    private var socket: LensSocket?
    private var engaged = false
    private var attempt = 0
    private var retryAt: Date?
    private var timer: Timer?

    /// The screen on the lens and what may be pinched on it, bound when it was
    /// drawn. Nil while nothing honourable is showing.
    private struct Shown { var seq: Int; var actions: [LensAction]; var onPinch: LensHost.Pinch }
    private var shown: Shown?
    private var lastSeq: Int?
    private(set) var offset = ClockOffset()
    private var seen = SeenInputs()
    private var tick = TickWatch()
    private var pings: [(id: Int, t0: Double)] = []
    private var pingN = 0
    private var lastPingAt: Double = 0
    private var lastHeard: Double = 0
    private var helloAt: Double?

    init(socket: @escaping @MainActor () -> LensSocket = { URLSessionLensSocket() },
         keepAlive: LensKeepAlive? = nil,
         key: @escaping @MainActor () -> String? = { LensKey.phoneKey },
         now: @escaping @MainActor () -> Date = { .now },
         appVersion: String = Bundle.main.appVersion,
         runsTimer: Bool = true) {
        self.makeSocket = socket
        self.keepAlive = keepAlive
        self.key = key
        self.now = now
        self.appVersion = appVersion
        self.runsTimer = runsTimer
        self.paired = key() != nil
    }

    private func nowMs() -> Double { now().timeIntervalSince1970 * 1000 }

    // MARK: - LensTransport

    var isAvailable: Bool { paired }
    var isEngaged: Bool { engaged }
    var pacesClockFree: Bool { true }
    /// None: liveness is the ping, which carries the ticket and never moves it.
    var heartbeat: TimeInterval? { nil }

    /// Ready means a page is there to draw on — not merely a socket.
    var isReady: Bool { link == .up && lenses >= 1 }

    var waitingReason: String? {
        guard paired else { return "Pair this phone with the relay in Settings → Glasses." }
        switch link {
        case .off, .connecting: return "Connecting to the relay…"
        case .down: return "No connection to the relay — is the phone online?"
        case .up: return lenses == 0 ? "Open Fitness on your glasses." : nil
        }
    }

    func ensure() async -> Bool {
        if !engaged {
            engaged = true
            tick = TickWatch()
            // Only around a workout: this is asked only while something of
            // ours belongs on the lens (plan §6.3, gated on the driver).
            keepAlive?.holdForLens(true)
            startTimer()
            connect()
        } else if socket == nil, let retryAt, now() >= retryAt {
            connect()
        }
        return isReady
    }

    func show(_ screen: LensScreen, ticket: Int, onPinch: @escaping LensHost.Pinch) async throws {
        guard isReady, let socket else { throw NotReady() }
        let message = LensWire.screenMessage(epoch: epoch, seq: ticket, screen: screen, now: now())
        // Bound at draw time, live as the send starts — as on native.
        shown = Shown(seq: ticket, actions: screen.actions, onPinch: onPinch)
        lastSeq = ticket
        try await socket.send(LensWire.text(message))
    }

    func end(clearing: Bool, reason: LensHost.Idle) {
        let leaving = socket
        if clearing, let leaving, link == .up {
            // Said, then closed: the page shows why instead of "phone not
            // reachable" (LENS_WIRE.md, `idle`).
            let idle = LensWire.text(LensWire.idleMessage(epoch: epoch, seq: (lastSeq ?? 0) + 1,
                                                          reason: reason.reason, text: reason.text))
            Task { try? await leaving.send(idle); leaving.close() }
        } else {
            leaving?.close()
        }
        socket = nil
        engaged = false
        shown = nil
        retryAt = nil
        attempt = 0
        link = .off
        lenses = 0
        timer?.invalidate()
        timer = nil
        keepAlive?.holdForLens(false)
    }

    func wake() {
        if engaged, socket == nil { retryAt = now() }
    }

    // MARK: - Pairing

    /// The key changed in the Keychain (paired, or forgotten).
    func keyChanged() {
        paired = key() != nil
        if engaged {
            socket?.close()
            socket = nil
            link = .down
            retryAt = now()
        }
    }

    // MARK: - The socket

    private func connect() {
        guard let key = key() else {
            paired = false
            link = .down
            return
        }
        let socket = makeSocket()
        self.socket = socket
        link = .connecting
        lenses = 0
        shown = nil
        pings = []
        retryAt = nil
        socket.open(Self.roomURL, protocols: ["fitness.v\(LensWire.version)", "k.\(key)"],
                    onText: { [weak self, weak socket] text in
                        guard let self, let socket, self.socket === socket else { return }
                        self.receive(text)
                    },
                    onClose: { [weak self, weak socket] why in
                        guard let self, let socket, self.socket === socket else { return }
                        self.dropped(why)
                    })
        let t = nowMs()
        helloAt = t
        lastHeard = t
        send(LensWire.hello(version: appVersion))
        ping(at: t)
    }

    private func dropped(_ why: String) {
        socket?.close()
        socket = nil
        link = .down
        lenses = 0
        shown = nil
        pings = []
        onEvent?(.lost)
        guard engaged else { return }
        retryAt = now().addingTimeInterval(min(5, 0.5 * pow(2, Double(attempt))))
        attempt += 1
    }

    private func send(_ json: LensWire.JSON) {
        guard let socket else { return }
        let text = LensWire.text(json)
        Task { try? await socket.send(text) }
    }

    private func ping(at t: Double) {
        pingN += 1
        pings.append((pingN, t))
        if pings.count > 20 { pings.removeFirst(pings.count - 20) }
        lastPingAt = t
        send(LensWire.ping(id: pingN, t: Int(t), epoch: epoch, seq: lastSeq))
    }

    // MARK: - The 1 Hz tick

    private func startTimer() {
        guard runsTimer, timer == nil else { return }
        // `.common`, not the default mode: in the spike the tick stalled 2–5 s
        // whenever a List was scrolling, which read as a frozen phone and
        // closed the gate under the wearer's finger.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Once a second while engaged. Internal so a test can drive it.
    func tickNow() {
        guard engaged else { return }
        let t = nowMs()
        checkFrozen(at: t)
        keepAlive?.lensWatchdog()
        if socket == nil, let retryAt, now() >= retryAt { connect(); return }
        guard socket != nil, t - lastPingAt >= Self.pingEvery else { return }
        if t - lastHeard > Self.silenceLimitMs { dropped("silent"); return }
        ping(at: t)
    }

    private func checkFrozen(at t: Double) {
        guard tick.beat(t) != nil else { return }
        // Whatever arrives next was pinched at a screen the wearer may no
        // longer see. Nothing is honoured until a fresh screen goes out.
        shown = nil
        onEvent?(.frozen)
    }

    // MARK: - What comes in

    /// One message from the room. Internal so a test can deliver one.
    func receive(_ text: String) {
        let t = nowMs()
        // FIRST, before a byte of it is read.
        checkFrozen(at: t)
        lastHeard = t
        guard let message = LensWire.decode(text) else { return }
        if link != .up {
            link = .up
            attempt = 0
            // A new connection: draw again, with a fresh ticket.
            onEvent?(.repaint)
        }
        switch message["type"] as? String {
        case "hello-ok":
            if let room = message["roomNow"] as? Double, let t0 = helloAt { offset.add(t0: t0, t1: t, roomNow: room) }
            relayVersion = message["peerVersion"] as? String ?? relayVersion
            if let n = message["lenses"] as? Int { lensesChanged(n) }
        case "presence":
            if let n = message["lenses"] as? Int { lensesChanged(n) }
            lensVersion = message["lensVersion"] as? String ?? lensVersion
        case "pong":
            pong(message, at: t)
        case "input":
            input(message, at: t)
        case "repaint", "resume":
            onEvent?(.repaint)
        default:
            // `ack` and `undeliverable` are the page's; `feedAudio` is Phase 2.
            break
        }
    }

    private func lensesChanged(_ n: Int) {
        let was = lenses
        lenses = max(0, n)
        if was == 0, lenses > 0 { onEvent?(.repaint) }
    }

    private func pong(_ message: [String: Any], at t1: Double) {
        guard let room = message["roomNow"] as? Double, !pings.isEmpty else { return }
        // By id when the room echoes it; else the oldest outstanding — pongs
        // come back in order on one socket.
        let index = (message["id"] as? Int).flatMap { id in pings.firstIndex { $0.id == id } } ?? 0
        let t0 = pings.remove(at: index).t0
        if let best = offset.add(t0: t0, t1: t1, roomNow: room) { roomRttMs = Int(best.rtt) }
    }

    /// Why a pinch was refused, as the `ack` says it.
    enum Refusal: String {
        case closed, late, wrongEpoch, wrongSeq, notOnScreen, lenses, gate
    }

    private func input(_ message: [String: Any], at t: Double) {
        guard let id = message["id"] as? String, !id.isEmpty else { return }
        if let prior = seen.lookup(id) {
            // A replay: the original answer, and nothing done.
            send(LensWire.ack(id: id, accepted: prior.accepted, why: prior.why))
            return
        }
        let refusal = judge(message, at: t)
        seen.record(id, .init(accepted: refusal == nil, why: refusal?.rawValue))
        send(LensWire.ack(id: id, accepted: refusal == nil, why: refusal?.rawValue))
        // The phone always repaints after a pinch. An honoured one already did
        // (`LensHost.pinched`); a refused one gets a fresh ticket here.
        if refusal != nil { onEvent?(.repaint) }
    }

    /// Nil = honoured, and the ticket is spent.
    private func judge(_ message: [String: Any], at t: Double) -> Refusal? {
        guard let shown else { return .closed }
        let relayedAt = message["relayedAt"] as? Double
        let roomNow = offset.toRoom(t)
        // No offset yet means lateness cannot be judged, so it is not refused
        // for it — `hello-ok` gives one within a round trip of connecting.
        if let relayedAt, let roomNow, roomNow - relayedAt > Self.lateMs { return .late }
        guard message["epoch"] as? String == epoch else { return .wrongEpoch }
        guard message["seq"] as? Int == shown.seq else { return .wrongSeq }
        guard let action = LensWire.action(from: message["action"]),
              shown.actions.contains(action) else { return .notOnScreen }
        if action.writes, lenses != 1 { return .lenses }
        guard shown.onPinch(action) else { return .gate }
        if let relayedAt, let roomNow { lastPinchMs = Int(max(0, roomNow - relayedAt)) }
        return nil
    }

    private struct NotReady: Error {}
}

// MARK: - The rules, as plain values

/// The room's clock as seen from here, NTP-style. A ping sent at t0 and
/// answered at t1 with the room's `roomNow`: offset = roomNow − (t0+t1)/2, off
/// by at most rtt/2. The smallest round trip of the last `keep` wins. From the
/// spike, where it put phone and page logs on one time line to the millisecond.
struct ClockOffset {
    struct Sample: Equatable { var rtt: Double; var off: Double }

    let keep: Int
    private(set) var samples: [Sample] = []

    init(keep: Int = 12) { self.keep = keep }

    @discardableResult
    mutating func add(t0: Double, t1: Double, roomNow: Double) -> Sample? {
        let rtt = t1 - t0
        guard rtt >= 0, roomNow.isFinite else { return best }
        samples.append(Sample(rtt: rtt, off: roomNow - (t0 + t1) / 2))
        if samples.count > keep { samples.removeFirst(samples.count - keep) }
        return best
    }

    var best: Sample? { samples.min { $0.rtt < $1.rtt } }

    /// Local ms → room ms, or nil before the first answer.
    func toRoom(_ t: Double) -> Double? { best.map { t + $0.off } }
}

/// A 1 Hz tick that came more than `limitMs` after the last one means the
/// process was suspended for that long.
struct TickWatch {
    var limitMs: Double = 2_000
    private(set) var last: Double?

    mutating func beat(_ now: Double) -> Double? {
        defer { last = now }
        guard let last else { return nil }
        let gap = now - last
        return gap > limitMs ? gap : nil
    }
}

/// The last 64 input ids and what was answered, so a replayed id gets its
/// original answer and does nothing.
struct SeenInputs {
    struct Answer: Equatable { var accepted: Bool; var why: String? }
    let cap: Int
    private var order: [String] = []
    private var answers: [String: Answer] = [:]

    init(cap: Int = 64) { self.cap = cap }

    func lookup(_ id: String) -> Answer? { answers[id] }

    mutating func record(_ id: String, _ answer: Answer) {
        if answers[id] == nil { order.append(id) }
        answers[id] = answer
        while order.count > cap { answers[order.removeFirst()] = nil }
    }
}

// MARK: - Seams

/// A WebSocket, as `WebLens` needs it. The real one is `URLSessionLensSocket`;
/// the tests use a fake that records what was sent.
@MainActor
protocol LensSocket: AnyObject {
    func open(_ url: URL, protocols: [String],
              onText: @escaping @MainActor (String) -> Void,
              onClose: @escaping @MainActor (String) -> Void)
    func send(_ text: String) async throws
    func close()
}

/// What keeps a locked phone running while the Web App lens is up.
/// `AudioHub` is the real one (`holdForLens`).
@MainActor
protocol LensKeepAlive: AnyObject {
    func holdForLens(_ on: Bool)
    /// Once a second while held: is the silence really playing? Restore it if not.
    func lensWatchdog()
}

/// `URLSessionWebSocketTask`, with the key in the subprotocol — never in the
/// URL, where it would land in logs.
@MainActor
final class URLSessionLensSocket: LensSocket {
    private var task: URLSessionWebSocketTask?
    private var onText: (@MainActor (String) -> Void)?
    private var onClose: (@MainActor (String) -> Void)?

    func open(_ url: URL, protocols: [String],
              onText: @escaping @MainActor (String) -> Void,
              onClose: @escaping @MainActor (String) -> Void) {
        self.onText = onText
        self.onClose = onClose
        let task = URLSession.shared.webSocketTask(with: url, protocols: protocols)
        self.task = task
        task.resume()
        receive(task)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .failure(let error):
                    self.task = nil
                    self.onClose?("\(task.closeCode.rawValue) \(error.localizedDescription)")
                case .success(let message):
                    if case .string(let text) = message { self.onText?(text) }
                    self.receive(task)
                }
            }
        }
    }

    func send(_ text: String) async throws {
        guard let task else { throw URLError(.networkConnectionLost) }
        try await task.send(.string(text))
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
