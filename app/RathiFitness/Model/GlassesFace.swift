import Combine
import Foundation
import MWDATCore
import MWDATDisplay
import UIKit

// No SwiftUI here — see the note at the top of LensRenderer.swift.

/// The fourth face: Meta Ray-Ban Display glasses, showing the set screen.
///
/// It mirrors; it does not drive. Whichever set screen is open on the phone
/// describes itself as a `LensState`, this sends it, and a pinch on the lens
/// comes back as a `LensAction` that lands on `RemoteControls` — the same place
/// an AirPods squeeze does. So the glasses are, to the rest of the app, a
/// second pair of AirPods with a screen. Choosing an exercise from the lens
/// needs the workout loop to live outside a view, and is a later piece of work.
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

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "glasses.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "glasses.enabled")
            enabled ? start() : stop()
        }
    }

    private var wearables: (any WearablesInterface)?
    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var display: Display?
    private var displayReady = false
    private var displayToken: (any AnyListenerToken)?
    private var deviceTokens: [any AnyListenerToken] = []
    private var watchers: [Task<Void, Never>] = []
    private var sessionWatchers: [Task<Void, Never>] = []

    private var registration: RegistrationState = .unavailable
    private var linked: String?

    // What to show, and what a pinch does. Set by the screen that is open.
    private var source: (@MainActor () -> LensState?)?
    private var onPinch: (@MainActor (LensAction) -> Void)?
    private var pump: Task<Void, Never>?
    private var pacer = LensPacer()
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
                guard let self else { return }
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
                self?.watch(ids)
            }
        })
    }

    private func stop() {
        disarm()
        endSession()
        watchers.forEach { $0.cancel() }
        watchers = []
        deviceTokens = []
        wearables = nil
        selector = nil
        linked = nil
        lastError = nil
        status = .off
    }

    private func watch(_ ids: [DeviceIdentifier]) {
        deviceTokens = []
        linked = nil
        var firmware = false
        for id in ids {
            guard let device = wearables?.deviceForIdentifier(id), device.supportsDisplay() else { continue }
            if device.compatibility() == .deviceUpdateRequired { firmware = true }
            if device.linkState == .connected { linked = device.nameOrId() }
            let name = device.nameOrId()
            deviceTokens.append(device.addLinkStateListener { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.linked = state == .connected ? name : nil
                    self.publish()
                    // The glasses just came back. Do not wait for the next tick.
                    if state == .connected { self.nextConnectAttempt = .distantPast }
                }
            })
            deviceTokens.append(device.addCompatibilityListener { [weak self] compatibility in
                Task { @MainActor in
                    if compatibility == .deviceUpdateRequired { self?.needsFirmwareUpdate = true }
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
    func arm(source: @escaping @MainActor () -> LensState?,
             onPinch: @escaping @MainActor (LensAction) -> Void) {
        self.source = source
        self.onPinch = onPinch
        guard enabled, pump == nil else { return }
        pacer.forget()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Called when the set screen goes away. The lens is cleared rather than
    /// left showing a set you have walked away from; the session goes with it,
    /// and comes back in well under a second when the next screen opens.
    func disarm() {
        source = nil
        onPinch = nil
        pump?.cancel()
        pump = nil
        endSession()
    }

    /// Something changed on the phone — a set was logged, the weight moved.
    /// Without this the lens would catch up on the next tick, up to a second
    /// late, which is exactly long enough to look broken.
    func refresh() {
        guard pump != nil else { return }
        Task { await beat() }
    }

    private var beating = false

    private func beat() async {
        // Never two sends at once: the second would be built from the same
        // state and only queue behind the first.
        guard !beating, enabled, status.isConnected, let state = source?() else { return }
        beating = true
        defer { beating = false }

        guard await ensureLens() else { return }
        guard pacer.shouldSend(state), let display else { return }
        let view = LensRenderer.view(for: state) { [weak self] action in
            Task { @MainActor in
                self?.onPinch?(action)
                // The pinch changed something. Show it now, not next second.
                self?.refresh()
            }
        }
        do {
            try await display.send(view)
            pacer.sent(state)
            isShowing = true
        } catch {
            // Most often the glasses came off mid-send. The session-error
            // stream says so a moment later; all that matters here is that the
            // lens no longer shows what we think it does.
            pacer.forget()
        }
    }

    // MARK: - Session

    /// True when a send will land. Starts a session if there is none.
    ///
    /// Taking the glasses off ends the session — it arrives as the *error*
    /// "Session ended by device", on a link that stays connected — and nothing
    /// says when they go back on. So this simply tries again, no more than
    /// every five seconds, for as long as a set screen is open. On the hardware
    /// a fresh session was showing content about 0.7 s after it was asked for.
    private func ensureLens() async -> Bool {
        if display != nil, displayReady { return true }
        guard session == nil else { return false }          // one is already starting
        guard Date.now >= nextConnectAttempt, let wearables, let selector else { return false }
        nextConnectAttempt = Date.now.addingTimeInterval(5)

        do {
            let session = try wearables.createSession(deviceSelector: selector)
            self.session = session
            let states = session.stateStream()
            let errors = session.errorStream()
            sessionWatchers.append(Task { [weak self] in
                for await state in states {
                    guard let self, !Task.isCancelled else { return }
                    if state == .started { self.attachDisplay(to: session) }
                    if state == .stopped { self.endSession() }
                }
            })
            sessionWatchers.append(Task { [weak self] in
                for await error in errors {
                    guard let self, !Task.isCancelled else { return }
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
            displayToken = lens.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.displayReady = state == .started
                    if state == .started {
                        self.needsGlassesAppUpdate = false
                        self.lastError = nil
                        self.refresh()
                    }
                }
            }
            lens.start()
            display = lens
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

    private func endSession() {
        sessionWatchers.forEach { $0.cancel() }
        sessionWatchers = []
        displayToken = nil
        // Lens before session — the order Meta's guide gives.
        display?.stop()
        session?.stop()
        display = nil
        session = nil
        displayReady = false
        isShowing = false
        pacer.forget()
    }

    private func note(_ what: String, _ error: any Error) {
        lastError = "\(what): \(error.localizedDescription)"
    }
}
