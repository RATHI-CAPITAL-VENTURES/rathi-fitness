import Combine
import Foundation
import MWDATCore
import MWDATDisplay
import UIKit

// No SwiftUI here — see the note at the top of LensRenderer.swift.

/// The fourth face: Meta Ray-Ban Display glasses, showing the set screen.
///
/// Two layers. While a set screen is open on the phone the lens MIRRORS it: the
/// screen describes itself as a `LensState`, this sends it, and a pinch comes
/// back as a `LensAction` that lands on `RemoteControls` — the same place an
/// AirPods squeeze does. With no set screen open, the layer underneath shows:
/// `WorkoutDriver`, which runs the workout from the lens with the phone locked.
/// The phone wins whenever it is in use, because two things deciding which set
/// you are on is one too many.
///
/// Everything below that touches Meta's SDK was first written as a throwaway
/// app and run on the hardware (branch `chore/lens-spike`, `FINDINGS.md`).
/// The comments that say "measured" mean that log.
///
/// Off by default, and while it is off nothing here touches the SDK at all —
/// which is also what keeps the simulator and the test suite out of it.
@MainActor
final class GlassesFace: ObservableObject {

    enum Status: Equatable {
        case off
        /// The SDK would not start. Not recoverable from here.
        case unavailable(String)
        case needsRegistration
        case registering
        /// Registered, but no display-capable glasses are connected right now:
        /// in their case, folded, or restarting.
        case waitingForGlasses
        case connected(String)

        var isConnected: Bool { if case .connected = self { return true } else { return false } }
    }

    @Published private(set) var status: Status = .off
    /// True while a set screen is on the lens.
    @Published private(set) var isShowing = false
    @Published private(set) var lastError: String?
    @Published private(set) var needsFirmwareUpdate = false
    @Published private(set) var needsGlassesAppUpdate = false
    /// Why nothing is on the lens, when nothing is. Nil while something is.
    @Published private(set) var idleReason: String?

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "glasses.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "glasses.enabled")
            enabled ? start() : stop()
        }
    }

    private var wearables: (any WearablesInterface)?
    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var sessionBegan: Date?
    private var display: Display?
    private var displayReady = false
    private var displayToken: (any AnyListenerToken)?
    private var deviceTokens: [any AnyListenerToken] = []
    private var watchers: [Task<Void, Never>] = []
    private var sessionWatchers: [Task<Void, Never>] = []
    /// Waited on before a new session is made, so a quick change of exercise
    /// does not ask the glasses for a second session while the first is still
    /// clearing the lens.
    private var teardown: Task<Void, Never>?

    private var registration: RegistrationState = .unavailable
    private var linked: String?
    /// Bumped whenever the device list is re-read. A link listener from an
    /// earlier reading must not be able to say "disconnected" about now.
    private var deviceEpoch = 0
    /// Bumped whenever a session ends. A send that was in flight when the
    /// glasses came off must not mark its screen as showing.
    private var sessionEpoch = 0
    /// Bumped whenever a set screen arms or disarms — whenever WHO is speaking
    /// through the lens changes. `display.send` is an `await`, and SwiftUI can
    /// open or close a set screen in the middle of it; a screen drawn for one
    /// layer must never have its ticket opened for the other.
    private var layerEpoch = 0

    // What to show, and what a pinch does.
    typealias Source = @MainActor () -> LensScreen?
    typealias Handler = @MainActor (LensAction) -> Void

    /// The open set screen, if there is one. It is on top.
    private var owner: UUID?
    private var screenSource: Source?
    private var screenPinch: Handler?
    /// The driver, underneath, for when no set screen is open.
    private var hostSource: Source?
    private var hostPinch: Handler?

    private var source: Source? { screenSource ?? hostSource }
    private var onPinch: Handler? { screenSource != nil ? screenPinch : hostPinch }
    private var pump: Task<Void, Never>?
    private var pacer = LensPacer()
    private var gate = LensGate()
    private var nextConnectAttempt = Date.distantPast

    init() {
        if enabled { start() }
    }

    // MARK: - On and off

    private static var configured = false

    private func start() {
        if !Self.configured {
            do {
                try Wearables.configure()
                Self.configured = true
            } catch {
                status = .unavailable(error.localizedDescription)
                return
            }
        }
        guard wearables == nil else { return }
        let wearables = Wearables.shared
        self.wearables = wearables
        // Built now rather than at connect: the selector fills from the device
        // stream, and a session created before it has seen the glasses throws
        // `noEligibleDevice` about a pair that is sitting right there.
        selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
        registration = wearables.registrationState
        publish()

        watchers.append(Task { [weak self] in
            for await state in wearables.registrationStateStream() {
                guard let self, !Task.isCancelled else { return }
                self.registration = state
                // A selector outlives neither an unregistration nor a fresh
                // registration; Meta's own sample rebuilds it here.
                if state == .available || state == .unavailable {
                    self.endSession()
                    self.selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
                }
                self.publish()
            }
        })
        watchers.append(Task { [weak self] in
            for await ids in wearables.devicesStream() {
                guard let self, !Task.isCancelled else { return }
                self.watch(ids)
            }
        })
        // A set screen may already be open — you can reach Settings without
        // closing it. Switching the glasses on should light the lens, not wait
        // for you to leave the exercise and come back.
        startPumpIfNeeded()
    }

    /// Off. The open screen's `source` and `onPinch` are KEPT: they belong to
    /// the screen, not to the switch, and switching back on has to find them.
    private func stop() {
        pump?.cancel()
        pump = nil
        endSession(clearingLens: true)
        watchers.forEach { $0.cancel() }
        watchers = []
        dropDeviceTokens()
        wearables = nil
        selector = nil
        linked = nil
        lastError = nil
        status = .off
    }

    private func dropDeviceTokens() {
        deviceEpoch += 1
        let old = deviceTokens
        deviceTokens = []
        // Cancelled, not merely released. Meta's guide says dropping a token
        // stops its listener; their SDK also ships a bag with separate "clear"
        // and "cancel all". Doing both costs nothing and assumes neither.
        Task { for token in old { await token.cancel() } }
    }

    private func watch(_ ids: [DeviceIdentifier]) {
        dropDeviceTokens()
        let epoch = deviceEpoch
        linked = nil
        var firmware = false
        for id in ids {
            guard let device = wearables?.deviceForIdentifier(id), device.supportsDisplay() else { continue }
            if device.compatibility() == .deviceUpdateRequired { firmware = true }
            if device.linkState == .connected { linked = device.nameOrId() }
            let name = device.nameOrId()
            deviceTokens.append(device.addLinkStateListener { [weak self] state in
                Task { @MainActor in
                    // From a reading of the device list that has been replaced:
                    // it may be about glasses that are no longer listed, and
                    // its "disconnected" would silence a lens that is fine.
                    guard let self, epoch == self.deviceEpoch else { return }
                    self.linked = state == .connected ? name : nil
                    self.publish()
                    // The glasses just came back. Do not wait for the next tick.
                    if state == .connected { self.nextConnectAttempt = .distantPast }
                }
            })
            deviceTokens.append(device.addCompatibilityListener { [weak self] compatibility in
                Task { @MainActor in
                    guard let self, epoch == self.deviceEpoch else { return }
                    if compatibility == .deviceUpdateRequired { self.needsFirmwareUpdate = true }
                }
            })
        }
        needsFirmwareUpdate = firmware
        publish()
    }

    private func publish() {
        guard enabled, wearables != nil else { return }
        switch registration {
        case .registered: status = linked.map { .connected($0) } ?? .waitingForGlasses
        case .registering: status = .registering
        case .available, .unavailable: status = .needsRegistration
        @unknown default: status = .needsRegistration
        }
    }

    // MARK: - Registration

    /// Hands off to the Meta AI app, which asks you to approve this one and
    /// calls back through the URL scheme.
    func register() async {
        lastError = nil
        do { try await wearables?.startRegistration() } catch { note("Could not register", error) }
    }

    func unregister() async {
        do { try await wearables?.startUnregistration() } catch { note("Could not disconnect", error) }
    }

    /// True if the URL was Meta AI's and has been dealt with.
    @discardableResult
    func handle(_ url: URL) async -> Bool {
        guard let wearables,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else { return false }
        do { return try await wearables.handleUrl(url) } catch {
            note("Meta AI's reply could not be read", error)
            return false
        }
    }

    func openFirmwareUpdate() async {
        do { try await wearables?.openFirmwareUpdate() } catch { note("Could not open the update", error) }
    }

    func openGlassesAppUpdate() async {
        do { try await wearables?.openDATGlassesAppUpdate() } catch { note("Could not open the update", error) }
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
        // Whatever is on the lens was drawn for some other screen.
        gate.close()
        pacer.forget()
        // The retry throttle is for glasses that are not answering, not a
        // penalty for changing exercise.
        nextConnectAttempt = .distantPast
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
        // Whatever is on the lens was the set screen's.
        gate.close()
        pacer.forget()
        guard hostSource != nil else {
            pump?.cancel()
            pump = nil
            endSession(clearingLens: true)
            return
        }
        // The driver is underneath. It takes over on the session that is
        // already up, rather than dropping the lens and raising it again.
        onScreenClosed?()
        refresh()
    }

    // With a host installed the pump never stops of its own accord: one task
    // waking once a second for the life of the process. That is cheap only
    // because `beatOnce` returns on its FIRST line when the glasses are not
    // connected, before asking anyone for a screen. Keep that guard first.

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

    /// Tells the driver a set screen just closed, so it re-reads the store —
    /// the sets logged on the phone happened without it.
    private var onScreenClosed: (@MainActor () -> Void)?
    private var hostIdle: (@MainActor () -> String)?

    private func startPumpIfNeeded() {
        guard enabled, source != nil, pump == nil else { return }
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
        guard pump != nil else { return }
        Task { await beat() }
    }

    private var beating = false
    /// A `refresh` that arrived while a beat was in flight. It is owed, not
    /// dropped: the first build dropped it, which left the lens showing a stale
    /// *Log set* for over a second after a pinch — the very window a second
    /// pinch lands in.
    private var beatOwed = false

    private func beat() async {
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
        guard enabled, status.isConnected else { return }
        guard let state = source?() else {
            // Nothing of ours belongs on the lens. A display session is the
            // WHOLE lens for as long as it lasts, so it is given back rather
            // than held dark.
            if session != nil { endSession(clearingLens: true) }
            let why = hostIdle?()
            if idleReason != why { idleReason = why }
            return
        }
        if idleReason != nil { idleReason = nil }
        guard await ensureLens() else { return }
        guard pacer.shouldSend(state), let display else { return }

        let epoch = sessionEpoch
        let layer = layerEpoch
        let ticket = gate.reserve()
        // Bound NOW, to the layer this screen was drawn for — not looked up when
        // the pinch arrives. Found in review: open an exercise on the phone
        // while a repaint was in the air and, for about a second, the bench's
        // "Log set" on the lens would have logged a cable fly.
        let handler = onPinch
        let view = LensRenderer.view(for: state) { [weak self] action in
            Task { @MainActor in self?.pinched(action, ticket: ticket, handler: handler) }
        }
        // Live as the send starts — see `LensGate.open`.
        gate.open(ticket)
        do {
            try await display.send(view)
            // The glasses may have come off, or a set screen opened or closed,
            // while that was in the air. Either way `gate.close()` has already
            // run; what must not happen is this marking the screen as showing.
            guard epoch == sessionEpoch, layer == layerEpoch else { return }
            pacer.sent(state)
            isShowing = true
        } catch {
            // Most often the glasses came off mid-send. The session-error
            // stream says so a moment later; all that matters here is that the
            // lens no longer shows what we think it does.
            pacer.forget()
            gate.close()
        }
    }

    /// A button on the lens. See `LensGate` for why most of these are refused.
    private func pinched(_ action: LensAction, ticket: Int, handler: Handler?) {
        guard gate.accept(ticket, writes: action.writes) else { return }
        handler?(action)
        // Repaint even if nothing visible changed. The ticket is spent, so
        // until a new screen goes out the lens shows a button that does
        // nothing — and the new screen is also how the wearer learns the pinch
        // landed.
        pacer.forget()
        refresh()
    }

    // MARK: - Session

    /// A session that has not produced a lens in this long is not going to.
    private static let sessionPatience: TimeInterval = 10

    /// True when a send will land. Starts a session if there is none.
    ///
    /// Taking the glasses off ends the session — it arrives as the *error*
    /// "Session ended by device", on a link that stays connected — and nothing
    /// says when they go back on. So this simply tries again, no more than
    /// every five seconds, for as long as a set screen is open. On the hardware
    /// a fresh session was showing content about 0.7 s after it was asked for.
    private func ensureLens() async -> Bool {
        if display != nil, displayReady { return true }
        if session != nil {
            // Starting — or wedged. Without this a session that never reaches
            // `started` and never reports `stopped` holds the lens dark for the
            // rest of the exercise, because nothing else ever clears it.
            if let sessionBegan, Date.now.timeIntervalSince(sessionBegan) > Self.sessionPatience {
                endSession()
            }
            return false
        }
        guard Date.now >= nextConnectAttempt, let wearables, let selector else { return false }
        nextConnectAttempt = Date.now.addingTimeInterval(5)
        await teardown?.value
        guard session == nil, source != nil else { return false }

        do {
            let session = try wearables.createSession(deviceSelector: selector)
            self.session = session
            sessionBegan = .now
            let states = session.stateStream()
            let errors = session.errorStream()
            sessionWatchers.append(Task { [weak self] in
                for await state in states {
                    guard let self, !Task.isCancelled, self.session === session else { return }
                    switch state {
                    case .started: self.attachDisplay(to: session)
                    // Paused is "not showing anything" as far as a wearer is
                    // concerned, and the SDK does not promise an error with it.
                    // Start again rather than send into a lens that is not there.
                    case .paused, .stopped: self.endSession()
                    case .stopping: self.displayReady = false
                    case .idle, .starting: break
                    @unknown default: break
                    }
                }
            })
            sessionWatchers.append(Task { [weak self] in
                for await error in errors {
                    guard let self, !Task.isCancelled, self.session === session else { return }
                    self.sessionFailed(error)
                }
            })
            try session.start()
        } catch let error as DeviceSessionError {
            sessionFailed(error)
        } catch {
            endSession()
        }
        // The lens comes up a moment later; the next beat will find it.
        return false
    }

    private func attachDisplay(to session: DeviceSession) {
        guard display == nil else { return }
        do {
            let lens = try session.addDisplay()
            display = lens
            displayToken = lens.statePublisher.listen { [weak self, weak lens] state in
                Task { @MainActor in
                    // Only the lens we are using may speak. After the glasses
                    // come off and go back on, the OLD lens is still winding
                    // down inside the SDK; its "stopped" arriving late would
                    // mark the new one not ready, and nothing would ever mark
                    // it ready again.
                    guard let self, let lens, self.display === lens else { return }
                    self.displayReady = state == .started
                    if state == .started {
                        self.needsGlassesAppUpdate = false
                        self.lastError = nil
                        self.refresh()
                    }
                }
            }
            lens.start()
        } catch let error as DeviceSessionError {
            sessionFailed(error)
        } catch {
            endSession()
        }
    }

    private func sessionFailed(_ error: DeviceSessionError) {
        if error == .datAppOnTheGlassesUpdateRequired {
            needsGlassesAppUpdate = true
            lastError = "The app on your glasses needs an update."
        }
        // Everything else is deliberately silent. "Session ended by device" is
        // what taking your glasses off between exercises looks like, and an
        // error banner for that would fire a dozen times a workout.
        endSession()
    }

    /// - Parameter clearingLens: true when WE are leaving — a screen closed,
    ///   the switch went off. Meta's `stop()` is not documented to blank the
    ///   lens and nobody has watched it do so, so the lens is cleared first
    ///   rather than left showing a set you have walked away from. When the
    ///   glasses ended the session there is no lens left to clear.
    private func endSession(clearingLens: Bool = false) {
        sessionWatchers.forEach { $0.cancel() }
        sessionWatchers = []
        let token = displayToken
        let lens = display
        let ending = session
        displayToken = nil
        display = nil
        session = nil
        sessionBegan = nil
        displayReady = false
        isShowing = false
        sessionEpoch += 1
        pacer.forget()
        gate.close()

        guard lens != nil || ending != nil || token != nil else { return }
        let previous = teardown
        teardown = Task {
            await previous?.value
            await token?.cancel()
            if clearingLens { try? await lens?.clearDisplay() }
            // Lens before session — the order Meta's guide gives.
            lens?.stop()
            ending?.stop()
        }
    }

    private func note(_ what: String, _ error: any Error) {
        lastError = "\(what): \(error.localizedDescription)"
    }
}
