import Foundation
import MWDATCore
import MWDATDisplay
import UIKit

// No SwiftUI here — see the note at the top of LensRenderer.swift.

/// The native lens: Meta's Wearables SDK, a display session, and
/// `LensRenderer`'s vocabulary. The DAT half of what was `GlassesFace`, moved
/// here whole when the lens grew a second transport (`WebLens`); what to show
/// and which pinch counts stayed behind in `LensHost`.
///
/// Everything below that touches Meta's SDK was first written as a throwaway
/// app and run on the hardware (branch `chore/lens-spike`, `FINDINGS.md`).
/// The comments that say "measured" mean that log.
///
/// Nothing here touches the SDK until `start()` — which `GlassesFace` calls
/// only with the glasses switched on AND the lens set to Native. That is also
/// what keeps the simulator and the test suite out of it.
@MainActor
final class NativeLens: ObservableObject, LensTransport {

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
    @Published private(set) var lastError: String?
    @Published private(set) var needsFirmwareUpdate = false
    @Published private(set) var needsGlassesAppUpdate = false

    var onEvent: (@MainActor (LensEvent) -> Void)?
    var wanted: (@MainActor () -> Bool)?

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
    private var nextConnectAttempt = Date.distantPast

    // MARK: - LensTransport

    var isAvailable: Bool { status.isConnected }
    var isEngaged: Bool { session != nil }
    var waitingReason: String? { nil }
    /// The native lens is sent its clock every second, as it always was.
    var pacesClockFree: Bool { false }
    /// On the hardware a session survived thirty seconds of complete silence,
    /// and thirty is only the longest gap anyone tried — so a still screen is
    /// re-sent inside the envelope that is known to work (`LensPacer`).
    var heartbeat: TimeInterval? { LensPacer.heartbeat }

    func ensure() async -> Bool { await ensureLens() }

    func show(_ screen: LensScreen, ticket: Int, onPinch: @escaping LensHost.Pinch) async throws {
        guard let display else { throw NoDisplay() }
        let view = LensRenderer.view(for: screen) { action in
            Task { @MainActor in _ = onPinch(action) }
        }
        try await display.send(view)
    }

    func end(clearing: Bool, reason: LensHost.Idle) {
        tearDown(clearingLens: clearing)
    }

    func wake() {
        nextConnectAttempt = .distantPast
    }

    // MARK: - On and off

    private static var configured = false

    func start() {
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
    }

    /// Off. Ends any session (clearing the lens) and stops listening; the SDK
    /// stays configured — Meta offers no way to undo that — but is not called.
    func stop() {
        guard wearables != nil || status != .off else { return }
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
        guard wearables != nil else { return }
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
        guard session == nil, wanted?() == true else { return false }

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
                        self.onEvent?(.ready)
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

    /// The session ended from this side of the SDK — glasses off, a wedge, an
    /// unregistration. The host is told, so the screen it thinks is showing,
    /// and the ticket on it, go too.
    private func endSession(clearingLens: Bool = false) {
        tearDown(clearingLens: clearingLens)
        onEvent?(.lost)
    }

    /// - Parameter clearingLens: true when WE are leaving — a screen closed,
    ///   the switch went off. Meta's `stop()` is not documented to blank the
    ///   lens and nobody has watched it do so, so the lens is cleared first
    ///   rather than left showing a set you have walked away from. When the
    ///   glasses ended the session there is no lens left to clear.
    private func tearDown(clearingLens: Bool) {
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

    /// `ensure` said yes and the display went in between. Thrown, so the host
    /// forgets the screen rather than believing it landed.
    private struct NoDisplay: Error {}

    private func note(_ what: String, _ error: any Error) {
        lastError = "\(what): \(error.localizedDescription)"
    }
}
