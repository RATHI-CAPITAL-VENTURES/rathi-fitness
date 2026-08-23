import Foundation
import MediaPlayer

/// The AirPods.
///
/// iOS gives you three gestures on the stem and no way to invent a fourth:
/// a press, a double press and a triple press, delivered as `togglePlayPause`,
/// `nextTrack` and `previousTrack` to whichever app is currently now-playing.
/// (Press-and-hold is noise control and never reaches an app. The Watch's
/// controls are a separate surface and not one of these.)
///
/// So the design is a mapping, not a feature: three inputs, a table of what each
/// one means, and a default that keeps the two everybody already knows —
///
///     press   → play / pause
///     double  → next track
///     triple  → log the set, and start the cooldown
///
/// Triple gets the workout because it is the gesture nobody performs by
/// accident. While the cooldown is already running there is no set to log, so
/// the same squeeze skips the rest instead — the screen you would have been
/// looking at offers exactly those two buttons at exactly those two moments.
///
/// Every mapping is editable (Settings → Hands-free), because the honest answer
/// to "does triple-press feel right through a hoodie" is that it depends on the
/// hoodie.
@MainActor
final class RemoteControls: ObservableObject {

    /// The three inputs. Named for the gesture, not for the MediaPlayer command
    /// that carries it, because the command names are a lie at this layer:
    /// `previousTrack` is a triple-press and means nothing about tracks.
    enum Gesture: String, CaseIterable, Identifiable {
        case press, double, triple
        var id: String { rawValue }
        var label: String {
            switch self {
            case .press: return "Press"
            case .double: return "Double press"
            case .triple: return "Triple press"
            }
        }
        var defaultAction: Action {
            switch self {
            case .press: return .playPause
            case .double: return .nextTrack
            case .triple: return .logSet
            }
        }
        private var key: String { "remote.gesture.\(rawValue)" }

        var action: Action {
            get {
                UserDefaults.standard.string(forKey: key)
                    .flatMap(Action.init(rawValue:)) ?? defaultAction
            }
            nonmutating set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
        }
    }

    /// Everything a squeeze can do. The whole set lives here so adding one is a
    /// case and a row, and so Settings can list them without knowing any of it.
    enum Action: String, CaseIterable, Identifiable {
        case playPause, nextTrack, previousTrack
        case logSet, skipRest, extendRest, announce, nothing

        var id: String { rawValue }

        var label: String {
            switch self {
            case .playPause: return "Play / pause"
            case .nextTrack: return "Next track"
            case .previousTrack: return "Previous track"
            case .logSet: return "Log the set (skip the rest, while resting)"
            case .skipRest: return "Skip the rest"
            case .extendRest: return "Rest 30s longer"
            case .announce: return "Say where I am"
            case .nothing: return "Nothing"
            }
        }
    }

    /// What the current screen can do about a gesture. A workout screen fills
    /// these in when it appears and clears them when it leaves, so a squeeze on
    /// the Trends tab controls music and nothing else — there is no set there to
    /// log, and inventing one would be the worst bug this feature could have.
    struct Handlers {
        var logSet: (() -> Void)?
        var skipRest: (() -> Void)?
        var extendRest: (() -> Void)?
        /// One sentence about where you are, for `.announce`.
        var describe: (() -> String)?
        /// True while the cooldown is running — decides what a `.logSet`
        /// gesture means at this instant.
        var isResting: () -> Bool = { false }
    }

    /// Whether hands-free is armed at all. Off, the app registers nothing and
    /// the AirPods behave exactly as they did before it was installed.
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "remote.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "remote.enabled")
            enabled ? register() : unregister()
        }
    }

    /// The last thing a squeeze did, for the "it heard you" line on screen.
    @Published private(set) var lastAction: Action?

    var handlers = Handlers()

    private unowned let music: MusicController
    private let audio = AudioHub.shared
    private var registered = false

    init(music: MusicController) {
        self.music = music
    }

    // MARK: - Arming

    /// Called when a workout screen appears. Takes the now-playing role so the
    /// gestures arrive, registers the commands, and warms the haptic engine.
    func arm() {
        guard enabled else { return }
        audio.activate()
        Haptics.shared.prepare()
        register()
        // Only hold the silence if nothing real is playing; music already holds
        // the role, and doing both would have us competing with ourselves.
        audio.holdRemoteControl(!music.isPlaying)
        publishNowPlaying()
    }

    /// Called when the workout screen goes away. Hands the audio session back.
    func disarm() {
        audio.holdRemoteControl(false)
        if !music.isPlaying { audio.deactivate() }
    }

    private func register() {
        guard !registered else { return }
        registered = true
        let centre = MPRemoteCommandCenter.shared()
        centre.togglePlayPauseCommand.isEnabled = true
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.nextTrackCommand.isEnabled = true
        centre.previousTrackCommand.isEnabled = true

        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.perform(.press) ?? .commandFailed
        }
        // A press arrives as play or pause rather than toggle when the system
        // knows our state; both are the same gesture.
        centre.playCommand.addTarget { [weak self] _ in
            self?.perform(.press) ?? .commandFailed
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            self?.perform(.press) ?? .commandFailed
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            self?.perform(.double) ?? .commandFailed
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            self?.perform(.triple) ?? .commandFailed
        }
    }

    private func unregister() {
        guard registered else { return }
        registered = false
        let centre = MPRemoteCommandCenter.shared()
        for command in [centre.togglePlayPauseCommand, centre.playCommand,
                        centre.pauseCommand, centre.nextTrackCommand,
                        centre.previousTrackCommand] {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        audio.holdRemoteControl(false)
    }

    // MARK: - Dispatch

    @discardableResult
    func perform(_ gesture: Gesture) -> MPRemoteCommandHandlerStatus {
        guard enabled else { return .commandFailed }
        run(gesture.action)
        return .success
    }

    /// Exposed for the on-screen buttons and for tests: the same path a squeeze
    /// takes, so there is one implementation of what an action means.
    func run(_ action: Action) {
        var resolved = action
        // `.logSet` is the one context-sensitive action, and this is the whole
        // of that context: mid-rest there is nothing to log.
        if action == .logSet, handlers.isResting() { resolved = .skipRest }

        switch resolved {
        case .playPause:
            Task { await music.togglePlayPause() }
        case .nextTrack:
            Task { await music.next() }
        case .previousTrack:
            Task { await music.previous() }
        case .logSet:
            guard let log = handlers.logSet else { return refuse() }
            log()
        case .skipRest:
            guard let skip = handlers.skipRest else { return refuse() }
            skip()
            Haptics.shared.play(.gesture)
        case .extendRest:
            guard let extend = handlers.extendRest else { return refuse() }
            extend()
            Haptics.shared.play(.gesture)
        case .announce:
            guard let describe = handlers.describe else { return refuse() }
            audio.say(describe())
        case .nothing:
            return
        }
        lastAction = resolved
    }

    /// The gesture arrived somewhere it means nothing — on Trends, say. Two soft
    /// taps and a falling tone: heard you, nothing to do. Silence here reads as
    /// a dropped press and gets squeezed again, harder.
    private func refuse() {
        Haptics.shared.play(.refused)
        audio.play(.refused)
    }

    // MARK: - Now playing

    /// While we are holding the role with silence there is nothing on the Lock
    /// Screen, which looks like the app crashed. Put the workout there instead —
    /// it is genuinely what is "playing".
    func publishNowPlaying(title: String = "Workout", subtitle: String? = nil) {
        guard audio.isHoldingRemoteControl else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }
}
