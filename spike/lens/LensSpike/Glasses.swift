import Combine
import Foundation
import MWDATCore
import MWDATDisplay
import UIKit

// No SwiftUI in this file, deliberately. MWDATDisplay exports `Text`, `Button`
// and `Image`, and the two sets of names cannot share a file without every use
// being qualified.

/// Registration, the session, and the lens — the three things that have to
/// happen in order before a single word appears in front of your eye.
///
/// The shape follows Meta's DisplayAccess sample step for step, because
/// question 1 is "does this work at all on these glasses", and an answer of
/// "no" is only worth anything if nobody can say we held it wrong.
@MainActor
final class Glasses: ObservableObject {

    @Published private(set) var registration = "unknown"
    @Published private(set) var devices: [String] = []
    @Published private(set) var sessionState = "none"
    @Published private(set) var displayState = "none"
    @Published private(set) var lastError: String?
    /// Issue #180's failure. Surfaced as its own flag because the fix — if
    /// there is one — is a specific button, not a retry.
    @Published private(set) var needsGlassesAppUpdate = false
    @Published private(set) var needsFirmwareUpdate = false
    /// Live, unlike `devices` — which is written once when a pair of glasses is
    /// first listed. The first afternoon with real hardware was spent tapping
    /// Connect at glasses whose link had dropped three minutes earlier, under a
    /// row that still said "connecting".
    @Published private(set) var link = "none"
    @Published private(set) var compatibility = "unknown"

    var isReady: Bool { display != nil && displayState == "started" }
    /// A session against a link that is down can only say `noEligibleDevice`.
    var canConnect: Bool { registration == "registered" && link == "connected" }

    private let wearables: any WearablesInterface
    private let log: SpikeLog
    private var selector: AutoDeviceSelector
    private var session: DeviceSession?
    private var display: Display?
    private var displayToken: (any AnyListenerToken)?
    private var deviceTokens: [any AnyListenerToken] = []
    private var tasks: [Task<Void, Never>] = []
    private var sessionTasks: [Task<Void, Never>] = []

    init(log: SpikeLog) {
        self.log = log
        let wearables = Wearables.shared
        self.wearables = wearables
        // Built now rather than at "connect": the selector fills from
        // `devicesStream()`, and a session created before it has seen a device
        // throws `noEligibleDevice` about glasses that are sitting right there.
        self.selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
        self.registration = Self.name(wearables.registrationState)
        observe()
    }

    // MARK: - Watching

    /// `RegistrationState` is bridged from Objective-C, so Swift has no case
    /// names for it and prints `RegistrationState(rawValue: 0)` — which is what
    /// the first log off the phone said. Every other state in the SDK is a
    /// native enum and describes itself.
    private static func name(_ state: RegistrationState) -> String {
        switch state {
        case .unavailable: return "unavailable"
        case .available: return "available"
        case .registering: return "registering"
        case .registered: return "registered"
        @unknown default: return "unknown (\(state.rawValue))"
        }
    }

    private func observe() {
        tasks.append(Task { [weak self] in
            guard let wearables = self?.wearables else { return }
            for await state in wearables.registrationStateStream() {
                guard let self else { return }
                self.registration = Self.name(state)
                self.log.add("registration", Self.name(state))
                // Meta's sample does this too: a selector outlives neither an
                // unregistration nor a fresh registration.
                if state == .available || state == .unavailable { self.resetSelector() }
            }
        })
        tasks.append(Task { [weak self] in
            guard let wearables = self?.wearables else { return }
            for await ids in wearables.devicesStream() {
                guard let self else { return }
                self.describe(ids)
            }
        })
    }

    private func describe(_ ids: [DeviceIdentifier]) {
        deviceTokens = []
        var rows: [String] = []
        var firmware = false
        for id in ids {
            guard let device = wearables.deviceForIdentifier(id) else { continue }
            let compatibility = device.compatibility()
            if compatibility == .deviceUpdateRequired { firmware = true }
            let row = "\(device.nameOrId()) · \(device.deviceType().rawValue) · display \(device.supportsDisplay() ? "yes" : "NO") · link \(device.linkState) · \(compatibility)"
            rows.append(row)
            log.add("device", row)
            link = "\(device.linkState)"
            self.compatibility = "\(compatibility)"
            deviceTokens.append(device.addLinkStateListener { [weak self] state in
                self?.log.addFromAnywhere("link", "\(state)")
                Task { @MainActor in self?.link = "\(state)" }
            })
            // A device is first listed as `undefined` and settles a moment
            // later. `deviceUpdateRequired` here is the difference between "the
            // SDK is broken" and "update your glasses".
            deviceTokens.append(device.addCompatibilityListener { [weak self] compatibility in
                self?.log.addFromAnywhere("compatibility", "\(compatibility)")
                Task { @MainActor in
                    self?.compatibility = "\(compatibility)"
                    if compatibility == .deviceUpdateRequired { self?.needsFirmwareUpdate = true }
                }
            })
        }
        if ids.isEmpty {
            log.add("device", "none")
            link = "none"
            self.compatibility = "unknown"
        }
        devices = rows
        needsFirmwareUpdate = firmware
    }

    private func resetSelector() {
        disconnect()
        selector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
    }

    // MARK: - Registration

    func register() async {
        log.add("register", "handing off to Meta AI · state was \(registration) · \(Self.reachability())")
        do {
            try await wearables.startRegistration()
            // Not success — only that the hand-off was made. Success is the
            // state going to `registered` after Meta AI calls back.
            log.add("register", "startRegistration returned without an error")
        } catch { fail("register", error) }
    }

    /// Whether iOS will admit Meta AI is installed. False with the app sitting
    /// on the home screen means `fb-viewapp` is missing from
    /// LSApplicationQueriesSchemes, not that the app is.
    static func reachability() -> String {
        let seen = URL(string: "fb-viewapp://").map { UIApplication.shared.canOpenURL($0) } ?? false
        return "iOS says Meta AI is \(seen ? "reachable" : "NOT reachable")"
    }

    func unregister() async {
        log.add("unregister", "begin")
        do { try await wearables.startUnregistration() } catch { fail("unregister", error) }
    }

    /// Meta AI comes back through the URL scheme. Anything without their marker
    /// is not theirs and not ours either.
    func handle(_ url: URL) async {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else { return }
        do {
            let handled = try await wearables.handleUrl(url)
            log.add("callback", handled ? "handled" : "ignored")
        } catch { fail("callback", error) }
    }

    func openFirmwareUpdate() async {
        do { try await wearables.openFirmwareUpdate() } catch { fail("firmware update", error) }
    }

    func openGlassesAppUpdate() async {
        do { try await wearables.openDATGlassesAppUpdate() } catch { fail("glasses app update", error) }
    }

    // MARK: - Session

    /// Session, then lens, then wait until the lens says it is up. True means a
    /// `send` will land; false means the reason is in the log.
    @discardableResult
    func connect() async -> Bool {
        if isReady { return true }
        disconnect()
        lastError = nil
        log.add("connect", "creating session")

        do {
            let session = try wearables.createSession(deviceSelector: selector)
            self.session = session
            let states = session.stateStream()
            let errors = session.errorStream()
            sessionTasks.append(Task { [weak self] in
                for await state in states {
                    guard let self, !Task.isCancelled else { return }
                    self.sessionState = "\(state)"
                    self.log.add("session", "\(state)")
                    if state == .started { self.attachDisplay(to: session) }
                    if state == .stopped {
                        // The glasses can refuse a session without saying why:
                        // the first real attempt went starting → stopped with
                        // nothing on the error stream. Left alone, `connect`
                        // waits out its full thirty seconds for a lens that is
                        // never coming.
                        if !self.isReady, self.lastError == nil {
                            self.lastError = "session: stopped before the lens came up, and gave no reason"
                            self.log.add("session FAILED", "stopped before the lens came up · no error was reported")
                        }
                        self.display = nil
                        self.displayState = "none"
                    }
                }
            })
            sessionTasks.append(Task { [weak self] in
                for await error in errors {
                    guard let self, !Task.isCancelled else { return }
                    self.noteSessionError(error)
                }
            })
            try session.start()
        } catch let error as DeviceSessionError {
            noteSessionError(error)
            return false
        } catch {
            fail("session", error)
            return false
        }

        // Thirty seconds. Generous on purpose — a slow link should read as slow
        // in the log, not as a failure the spike invented.
        for _ in 0..<300 {
            if isReady { return true }
            if lastError != nil { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log.add("connect", "TIMED OUT after 30 s · session \(sessionState) · display \(displayState)")
        return false
    }

    private func attachDisplay(to session: DeviceSession) {
        guard display == nil else { return }
        do {
            let lens = try session.addDisplay()
            displayToken = lens.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    self?.displayState = "\(state)"
                    self?.log.add("display", "\(state)")
                }
            }
            lens.start()
            display = lens
        } catch let error as DeviceSessionError {
            noteSessionError(error)
        } catch {
            fail("display", error)
        }
    }

    func disconnect() {
        guard session != nil || display != nil else { return }
        log.add("disconnect", "")
        // Lens before session — the order Meta's guide gives.
        display?.stop()
        session?.stop()
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        displayToken = nil
        display = nil
        session = nil
        sessionState = "none"
        displayState = "none"
    }

    private func noteSessionError(_ error: DeviceSessionError) {
        needsGlassesAppUpdate = error == .datAppOnTheGlassesUpdateRequired
        fail("session", error)
    }

    // MARK: - Sending

    /// One whole screen. Returns how long the glasses took to accept it, in
    /// milliseconds, or nil if they did not.
    ///
    /// `quiet` keeps a once-a-second countdown from writing six hundred lines of
    /// success; failures are never quiet.
    func send(_ view: some DisplayableView, label: String, quiet: Bool = false) async -> Double? {
        guard let display else {
            log.add("send FAILED", "\(label) · no lens attached")
            return nil
        }
        let clock = ContinuousClock()
        let began = clock.now
        do {
            try await display.send(view)
            let ms = Self.milliseconds(began.duration(to: clock.now))
            if !quiet { log.add("send ok", "\(label) · \(Int(ms)) ms") }
            return ms
        } catch {
            let ms = Self.milliseconds(began.duration(to: clock.now))
            let reason = (error as? DisplayError)?.description ?? error.localizedDescription
            log.add("send FAILED", "\(label) · after \(Int(ms)) ms · \(reason)")
            return nil
        }
    }

    func clearLens() async {
        do { try await display?.clearDisplay() } catch { fail("clear", error) }
    }

    private func fail(_ what: String, _ error: any Error) {
        let text = "\(error) — \(error.localizedDescription)"
        lastError = "\(what): \(text)"
        log.add("\(what) FAILED", text)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
