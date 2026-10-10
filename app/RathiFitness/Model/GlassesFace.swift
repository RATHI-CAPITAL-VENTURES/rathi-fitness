import Combine
import Foundation

/// The fourth face: Meta Ray-Ban Display glasses, showing the workout.
///
/// What Settings binds to, and the door the rest of the app knocks on — the set
/// screens arm and disarm it, the app installs the driver and the player. Since
/// v0.18.0 it is three parts, and this file only wires them:
///
/// - `LensHost` decides what is on the lens: the set screen mirrored on top,
///   `WorkoutDriver` underneath, the music card over both, and which pinch
///   counts (`LensGate`).
/// - `NativeLens` puts it there through Meta's SDK — the display session.
/// - `WebLens` puts it there through the relay room, to the Fitness Web App in
///   the glasses' own app grid (docs/LENS_WIRE.md).
///
/// Settings → Glasses picks one. Native is the default until the Web App has
/// been worn through a real workout and accepted (docs/DECISIONS.md,
/// 2026-10-10). Off by default, and while off — or set to Web App — nothing
/// here calls Meta's SDK at all, which is also what keeps the simulator and the
/// test suite out of it.
@MainActor
final class GlassesFace: ObservableObject {

    typealias Status = NativeLens.Status

    /// Which lens. Raw values are what UserDefaults keeps.
    enum Lens: String, CaseIterable {
        case native, web

        var title: String { self == .native ? "Native" : "Web App" }
    }

    let host: LensHost
    let native: NativeLens
    let web: WebLens

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "glasses.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "glasses.enabled")
            apply()
        }
    }

    @Published var lens: Lens = Lens(rawValue: UserDefaults.standard.string(forKey: "glasses.lens") ?? "") ?? .native {
        didSet {
            guard lens != oldValue else { return }
            UserDefaults.standard.set(lens.rawValue, forKey: "glasses.lens")
            apply()
        }
    }

    private var relays: Set<AnyCancellable> = []

    init(host: LensHost? = nil, native: NativeLens? = nil, web: WebLens? = nil) {
        self.host = host ?? LensHost()
        self.native = native ?? NativeLens()
        self.web = web ?? WebLens(keepAlive: AudioHub.shared)
        // Settings reads through this object; it redraws when any part moves.
        for part in [self.host.objectWillChange, self.native.objectWillChange, self.web.objectWillChange] {
            part.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &relays)
        }
        if enabled { apply() }
    }

    /// Make the parts match the two settings. Switching mid-workout is safe:
    /// the host closes the gate, forgets the pacer and ends the old lens before
    /// the new one starts, and the workout itself — the driver's place, the
    /// weight in hand, the rest — lives on the phone and carries over.
    private func apply() {
        guard enabled else {
            host.use(nil, leaving: .off)
            native.stop()
            return
        }
        switch lens {
        case .native:
            native.start()
            host.use(native)
        case .web:
            // The web lens is handed the lens first, so the native session is
            // ended (and cleared) by the host before the SDK is let go of. In
            // Web App mode the SDK is never configured.
            host.use(web)
            native.stop()
        }
    }

    // MARK: - What Settings reads

    var status: Status { native.status }
    var isShowing: Bool { host.isShowing }
    var idleReason: String? { host.idleReason }
    var lastFrameMs: Int? { host.lastFrameMs }
    var lastError: String? { native.lastError }
    var needsFirmwareUpdate: Bool { native.needsFirmwareUpdate }
    var needsGlassesAppUpdate: Bool { native.needsGlassesAppUpdate }

    // MARK: - Registration (native)

    func register() async { await native.register() }
    func unregister() async { await native.unregister() }
    @discardableResult
    func handle(_ url: URL) async -> Bool { await native.handle(url) }
    func openFirmwareUpdate() async { await native.openFirmwareUpdate() }
    func openGlassesAppUpdate() async { await native.openGlassesAppUpdate() }

    // MARK: - Pairing (web)

    /// A scanned pairing code. False if it was not one.
    @discardableResult
    func pair(_ scanned: String) -> Bool {
        guard let paired = LensPairing.parse(scanned), LensKey.store(paired) else { return false }
        web.keyChanged()
        if lens == .web { host.refresh() }
        return true
    }

    func unpair() {
        LensKey.forget()
        web.keyChanged()
    }

    // MARK: - The layers (see LensHost)

    func arm(owner: UUID, source: @escaping LensHost.Source, onPinch: @escaping LensHost.Handler) {
        host.arm(owner: owner, source: source, onPinch: onPinch)
    }

    func disarm(owner: UUID) { host.disarm(owner: owner) }

    func host(source: @escaping LensHost.Source, onPinch: @escaping LensHost.Handler,
              idle: @escaping @MainActor () -> String,
              onScreenClosed: @escaping @MainActor () -> Void) {
        host.host(source: source, onPinch: onPinch, idle: idle, onScreenClosed: onScreenClosed)
    }

    func music(track: @escaping @MainActor () -> LensMusic.Track?,
               available: @escaping @MainActor () -> Bool,
               canStart: @escaping @MainActor () -> Bool,
               run: @escaping LensHost.Handler,
               changes: AnyPublisher<Void, Never>) {
        host.music(track: track, available: available, canStart: canStart, run: run, changes: changes)
    }

    func refresh() { host.refresh() }
}
