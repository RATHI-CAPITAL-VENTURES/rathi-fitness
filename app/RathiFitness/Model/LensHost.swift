import Combine
import Foundation

// No SwiftUI and no Meta SDK here — this is the part of the glasses face that
// decides WHAT is on the lens and which pinch counts, whichever lens it is.

/// Something a lens transport tells the host.
enum LensEvent: Equatable {
    /// A lens came up and can be drawn on (native: the display started).
    case ready
    /// The lens went away under us — glasses off, socket dropped. Whatever was
    /// on it no longer speaks for the app.
    case lost
    /// The phone was frozen (a 1 Hz tick arrived more than 2 s late). Close the
    /// gate BEFORE anything buffered is read, then repaint with a fresh ticket.
    case frozen
    /// Draw the current screen again with a fresh ticket: a new connection, a
    /// lens that just arrived, a refused pinch.
    case repaint
}

/// One way of putting a screen on the glasses: `NativeLens` (Meta's SDK, a
/// display session) or `WebLens` (the relay room, to the Web App).
///
/// Everything that is the same for both — which layer speaks, the music card,
/// when a screen is worth sending, which pinch counts — is `LensHost`'s, and
/// was moved there out of `GlassesFace`, not copied (the 2026-09-21 rule).
@MainActor
protocol LensTransport: AnyObject {
    /// Could a lens be reached at all: registered and linked glasses, a paired
    /// phone. False stops a beat on its first line, before any screen is built.
    var isAvailable: Bool { get }
    /// Whether this transport holds anything open — a display session, a socket.
    var isEngaged: Bool { get }
    /// Why a screen that is wanted is not on the lens, in words for Settings.
    var waitingReason: String? { get }
    /// True when a `show` would land now. Starts a session or a connection if
    /// there is none; the next beat finds it up.
    func ensure() async -> Bool
    /// Put `screen` on the lens. `onPinch` is bound to THIS screen — its
    /// ticket, its layer — and answers whether the pinch was honoured.
    func show(_ screen: LensScreen, ticket: Int, onPinch: @escaping LensHost.Pinch) async throws
    /// Let go of the lens. `clearing`: we are leaving, so blank it (native) or
    /// tell the page why (web). `ticket` is reserved from the gate for that
    /// last word, so the next screen's ticket is always newer than it — a page
    /// renders only what is newer, and a reused number left it stuck on
    /// "closed" (found in review).
    func end(clearing: Bool, reason: LensHost.Idle, ticket: Int)
    /// Retry now. The throttle is for a lens that is not answering, not a
    /// penalty for changing exercise.
    func wake()
    /// Pace on `LensScreen.clockFree` (the page ticks the clock itself) rather
    /// than on the full screen (the native lens is sent every second).
    var pacesClockFree: Bool { get }
    /// Re-send a still screen this often, or never.
    var heartbeat: TimeInterval? { get }
    var onEvent: (@MainActor (LensEvent) -> Void)? { get set }
    /// Whether a screen is wanted at all — asked after an `await`, when it may
    /// have stopped being.
    var wanted: (@MainActor () -> Bool)? { get set }
}

/// The glasses face's brain: two layers, music over both, the pump, the pacer
/// and the gate. Moved here from `GlassesFace` unchanged in behaviour; the DAT
/// half went to `NativeLens`.
///
/// Two layers. While a set screen is open on the phone the lens MIRRORS it: the
/// screen describes itself as a `LensState`, this sends it, and a pinch comes
/// back as a `LensAction` that lands on `RemoteControls` — the same place an
/// AirPods squeeze does. With no set screen open, the layer underneath shows:
/// `WorkoutDriver`, which runs the workout from the lens with the phone locked.
/// The phone wins whenever it is in use, because two things deciding which set
/// you are on is one too many.
@MainActor
final class LensHost: ObservableObject {

    typealias Source = @MainActor () -> LensScreen?
    typealias Handler = @MainActor (LensAction) -> Void
    /// A pinch, bound to the screen it was drawn on. True if it was honoured.
    typealias Pinch = @MainActor (LensAction) -> Bool

    /// What the web page is told when there is nothing of ours on the lens.
    struct Idle: Equatable {
        var reason: String
        var text: String
        static let off = Idle(reason: "off", text: "The lens was switched off on your phone.")
        static let moved = Idle(reason: "moved", text: "Moved to the native lens.")
        static func idle(_ text: String?) -> Idle { Idle(reason: "idle", text: text ?? "") }
    }

    /// True while a screen of ours is on the lens.
    @Published private(set) var isShowing = false
    /// Why nothing is on the lens, when nothing is. Nil while something is.
    @Published private(set) var idleReason: String?
    /// How long the lens took to accept the last screen, in milliseconds.
    /// On show in Settings because the drawn screens cost more than text and the
    /// ring has never been timed: 47 ms for text and 155 ms for a 552 × 220
    /// numeral were measured; the ring is about twice those pixels.
    @Published private(set) var lastFrameMs: Int?

    private(set) var transport: (any LensTransport)?
    /// Bumped whenever the lens under us changes or goes — the transport is
    /// swapped, a session ends, a socket drops. A send that was in flight when
    /// that happened must not mark its screen as showing.
    private var transportEpoch = 0
    /// Bumped whenever a set screen arms or disarms — whenever WHO is speaking
    /// through the lens changes. A send is an `await`, and SwiftUI can open or
    /// close a set screen in the middle of it; a screen drawn for one layer must
    /// never have its ticket opened for the other.
    private var layerEpoch = 0

    /// The open set screen, if there is one. It is on top.
    private var owner: UUID?
    private var screenSource: Source?
    private var screenPinch: Handler?
    /// The driver, underneath, for when no set screen is open.
    private var hostSource: Source?
    private var hostPinch: Handler?
    private var hostIdle: (@MainActor () -> String)?
    /// Tells the driver a set screen just closed, so it re-reads the store —
    /// the sets logged on the phone happened without it.
    private var onScreenClosed: (@MainActor () -> Void)?

    private var source: Source? { screenSource ?? hostSource }
    private var onPinch: Handler? { screenSource != nil ? screenPinch : hostPinch }

    /// Music, laid over whichever layer is speaking. See `LensMusic`.
    private var music = LensMusic()
    private var musicTrack: (@MainActor () -> LensMusic.Track?)?
    private var musicAvailable: (@MainActor () -> Bool)?
    private var musicCanStart: (@MainActor () -> Bool)?
    private var musicRun: Handler?
    private var musicChanges: AnyCancellable?

    private var pump: Task<Void, Never>?
    private var pacer = LensPacer()
    private var gate = LensGate()

    /// False in tests, which call `beat()` themselves rather than race a loop.
    private let pumps: Bool
    /// The clock the gate reads. A parameter so a test can step past `writeGap`.
    var now: @MainActor () -> Date = { .now }

    init(pumps: Bool = true) {
        self.pumps = pumps
    }

    // MARK: - Which lens

    /// Hand the lens to `next` (nil: to nobody). Whatever the old one showed no
    /// longer speaks for the app: the gate closes, the pacer forgets, and the
    /// old transport is ended — clearing its lens — before the new one starts.
    /// The workout itself lives on the phone, so a set or a rest in progress
    /// carries straight over.
    func use(_ next: (any LensTransport)?, leaving reason: Idle = .moved) {
        guard next !== transport else { return }
        let old = transport
        transportEpoch += 1
        isShowing = false
        pacer.forget()
        gate.close()
        music.close()
        old?.onEvent = nil
        old?.wanted = nil
        old?.end(clearing: true, reason: reason, ticket: gate.reserve())
        transport = next
        pacer.heartbeat = next?.heartbeat
        next?.onEvent = { [weak self] event in self?.event(event) }
        next?.wanted = { [weak self] in self?.source != nil }
        next?.wake()
        if next == nil {
            pump?.cancel()
            pump = nil
        } else {
            startPumpIfNeeded()
        }
    }

    private func event(_ event: LensEvent) {
        switch event {
        case .ready:
            refresh()
        case .lost:
            // Most often the glasses came off. The lens no longer shows what we
            // think it does, and glasses off and on again comes back to the
            // workout, not to a card opened before they came off.
            transportEpoch += 1
            isShowing = false
            pacer.forget()
            gate.close()
            music.close()
        case .frozen:
            gate.close()
            pacer.forget()
            refresh()
        case .repaint:
            pacer.forget()
            refresh()
        }
    }

    // MARK: - Mirroring a set screen

    /// Called when a set screen appears. `source` is asked, about once a second,
    /// what the lens should say; `onPinch` is what a button on the lens does.
    ///
    /// Closures rather than values because the screen's numbers live in its
    /// `@State` and move without telling anyone — the same reason
    /// `RemoteControls.Handlers` is closures.
    ///
    /// `owner` is the screen's own identity, and `disarm` wants it back. SwiftUI
    /// runs a pushed screen's `onAppear` BEFORE the screen beneath it gets
    /// `onDisappear`; nothing in the app goes set screen to set screen today,
    /// but the day something does, the old screen's goodbye would otherwise
    /// switch off the lens the new screen had just switched on.
    func arm(owner: UUID, source: @escaping Source, onPinch: @escaping Handler) {
        self.owner = owner
        screenSource = source
        screenPinch = onPinch
        layerEpoch += 1
        // Whatever is on the lens was drawn for some other screen — and a card
        // opened over the driver is not what you expect over the set you just
        // opened on the phone.
        music.close()
        gate.close()
        pacer.forget()
        // The retry throttle is for glasses that are not answering, not a
        // penalty for changing exercise.
        transport?.wake()
        startPumpIfNeeded()
    }

    /// Called when the set screen goes away. The lens is cleared rather than
    /// left showing a set you have walked away from; the session goes with it,
    /// and comes back in well under a second when the next screen opens.
    func disarm(owner: UUID) {
        guard owner == self.owner else { return }
        self.owner = nil
        screenSource = nil
        screenPinch = nil
        layerEpoch += 1
        // Whatever is on the lens was the set screen's — the music card opened
        // over it included, as `arm` closes it going the other way.
        music.close()
        gate.close()
        pacer.forget()
        guard hostSource != nil else {
            pump?.cancel()
            pump = nil
            endTransport(clearing: true, reason: .idle(nil))
            return
        }
        // The driver is underneath. It takes over on the session that is
        // already up, rather than dropping the lens and raising it again.
        onScreenClosed?()
        refresh()
    }

    // With a host installed the pump never stops of its own accord: one task
    // waking once a second for the life of the process. That is cheap only
    // because `beatOnce` returns on its FIRST line when no lens can be reached,
    // before asking anyone for a screen. Keep that guard first.

    /// The layer underneath every set screen: `WorkoutDriver`. Set once, at
    /// launch. It may return nil — a rest day, no workout anywhere near — and
    /// then nothing of ours is on the lens and the session is given back.
    func host(source: @escaping Source, onPinch: @escaping Handler,
              idle: @escaping @MainActor () -> String,
              onScreenClosed: @escaping @MainActor () -> Void) {
        hostSource = source
        hostPinch = onPinch
        hostIdle = idle
        self.onScreenClosed = onScreenClosed
        startPumpIfNeeded()
    }

    /// The player, for the music card. Set once, at launch, like `host`.
    ///
    /// `changes` fires when what is playing changes. A pinch on Pause repaints
    /// at once, but MusicKit answers a moment later — without this the card
    /// would still say PLAYING until the next heartbeat, twenty seconds on, and
    /// get pinched again.
    func music(track: @escaping @MainActor () -> LensMusic.Track?,
               available: @escaping @MainActor () -> Bool,
               canStart: @escaping @MainActor () -> Bool,
               run: @escaping Handler,
               changes: AnyPublisher<Void, Never>) {
        musicTrack = track
        musicAvailable = available
        musicCanStart = canStart
        musicRun = run
        musicChanges = changes.sink { [weak self] in self?.refresh() }
    }

    private func startPumpIfNeeded() {
        guard pumps, transport != nil, source != nil, pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Something changed on the phone — a set was logged, the weight moved.
    /// Without this the lens would catch up on the next tick, up to a second
    /// late, which is exactly long enough to look broken.
    func refresh() {
        guard pump != nil || !pumps else { return }
        Task { await beat() }
    }

    private var beating = false
    /// A `refresh` that arrived while a beat was in flight. It is owed, not
    /// dropped: the first build dropped it, which left the lens showing a stale
    /// *Log set* for over a second after a pinch — the very window a second
    /// pinch lands in.
    private var beatOwed = false

    /// Internal, not private, so a test can await one beat rather than race the
    /// pump.
    func beat() async {
        guard !beating else { beatOwed = true; return }
        beating = true
        await beatOnce()
        beating = false
        if beatOwed {
            beatOwed = false
            await beat()
        }
    }

    private func beatOnce() async {
        guard let transport, transport.isAvailable else { return }
        let state = music.screen(over: source?(), track: musicTrack?(),
                                 available: musicAvailable?() ?? false,
                                 canStart: musicCanStart?() ?? false)
        guard let state else {
            // Nothing of ours belongs on the lens. A display session is the
            // WHOLE lens for as long as it lasts, so it is given back rather
            // than held dark.
            let why = hostIdle?()
            if transport.isEngaged { endTransport(clearing: true, reason: .idle(why)) }
            if idleReason != why { idleReason = why }
            return
        }
        if idleReason != nil { idleReason = nil }
        guard await transport.ensure(), transport === self.transport else {
            // Only this transport's words, and only if it is still ours: after
            // a switch mid-await the old one's reason is about nothing.
            if transport === self.transport {
                let why = transport.waitingReason
                if idleReason != why { idleReason = why }
            }
            return
        }
        let paced = transport.pacesClockFree ? state.clockFree : state
        guard pacer.shouldSend(paced) else { return }

        let epoch = transportEpoch
        let layer = layerEpoch
        let ticket = gate.reserve()
        // Bound NOW, to the layer this screen was drawn for — not looked up when
        // the pinch arrives. Found in review: open an exercise on the phone
        // while a repaint was in the air and, for about a second, the bench's
        // "Log set" on the lens would have logged a cable fly.
        let handler = onPinch
        // And whether this is the music card, which is nobody's layer: its
        // "Back" closes the card, where the driver's would leave the exercise.
        let isMusic = music.isOpen
        let pinch: Pinch = { [weak self] action in
            self?.pinched(action, ticket: ticket, handler: handler, music: isMusic) ?? false
        }
        // Live as the send starts — see `LensGate.open`.
        gate.open(ticket)
        let began = ContinuousClock.now
        do {
            try await transport.show(state, ticket: ticket, onPinch: pinch)
            let took = began.duration(to: .now).components
            let ms = Int(took.seconds) * 1000 + Int(took.attoseconds / 1_000_000_000_000_000)
            // Once a second would redraw Settings once a second for nothing.
            if lastFrameMs.map({ abs($0 - ms) > 25 }) ?? true { lastFrameMs = ms }
            // The lens may have gone, or a set screen opened or closed, while
            // that was in the air. Either way `gate.close()` has already run;
            // what must not happen is this marking the screen as showing.
            guard epoch == transportEpoch, layer == layerEpoch else { return }
            pacer.sent(paced)
            isShowing = true
        } catch {
            // Most often the glasses came off mid-send. The transport says so a
            // moment later; all that matters here is that the lens no longer
            // shows what we think it does.
            pacer.forget()
            gate.close()
        }
    }

    /// A button on the lens. See `LensGate` for why most of these are refused.
    private func pinched(_ action: LensAction, ticket: Int, handler: Handler?, music onCard: Bool) -> Bool {
        guard gate.accept(ticket, writes: action.writes, at: now()) else { return false }
        if onCard || action == .music {
            if !music.navigate(action) { musicRun?(action) }
        } else {
            handler?(action)
        }
        // Repaint even if nothing visible changed. The ticket is spent, so
        // until a new screen goes out the lens shows a button that does
        // nothing — and the new screen is also how the wearer learns the pinch
        // landed.
        pacer.forget()
        refresh()
        return true
    }

    /// WE are letting the lens go — a screen closed, nothing to show.
    private func endTransport(clearing: Bool, reason: Idle) {
        transportEpoch += 1
        isShowing = false
        pacer.forget()
        gate.close()
        music.close()
        transport?.end(clearing: clearing, reason: reason, ticket: gate.reserve())
    }
}
