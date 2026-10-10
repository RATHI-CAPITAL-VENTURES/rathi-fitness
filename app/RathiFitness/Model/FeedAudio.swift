import Combine
import Foundation

/// A Short's sound on the lens pauses the workout music, and the music comes
/// back at READY — but only music WE paused (owner decision 2, 2026-10-09).
///
/// The rule is one bit, `pausedByUs`, and everything below is about when it
/// may be set and when it must be forgotten:
///
/// - **Set** only when the lens says the Short's sound came on, during a rest,
///   while the in-app music was actually playing — or while our own resume is
///   still on its way (see `resuming`). Music you had paused is not ours.
/// - **Paid back** (play) when the rest ends — the phone's READY is the truth,
///   not the page's clock — or when the lens says the sound went off. Not while
///   a phone call is active: that would be fighting the call for the speaker.
/// - **Forgotten** when the music starts playing again without us (you pressed
///   play — on the phone, the AirPods or the music card), or when a call takes
///   the audio. A Siri query does NOT forget it: the owner's rule is that the
///   music comes back at READY, and a five-second question is not a reason to
///   leave it off.
///
/// Handled beside the music card's player wiring, never in a lens layer: it is
/// not a pinch, and no screen depends on it (plan §6.7). It never touches the
/// audio session, so the keep-alive silence (`AudioHub.holdForLens`) keeps
/// running while the music is paused.
@MainActor
final class FeedAudio {

    private(set) var pausedByUs = false {
        didSet { if pausedByUs != oldValue { claimChanged?(pausedByUs) } }
    }
    /// Our `play()` is on its way: MusicKit answers a moment later. A sound
    /// that comes on in that window sees the music "not playing" — without
    /// this it took no claim, the play landed, and the music played over the
    /// Short (found in review).
    private(set) var resuming = false
    /// A sound came on while `resuming`: pause as soon as the play lands.
    private(set) var pauseWhenItLands = false
    private var resumingSince: Date?
    /// A resume that has not landed in this long never will (MusicKit failed);
    /// it stops counting as "on its way".
    static let resumePatience: TimeInterval = 3

    /// Told whenever the claim changes, so the READY cue can be rendered for
    /// the music that is about to come back rather than for silence.
    var claimChanged: (@MainActor (Bool) -> Void)?

    private let isPlaying: @MainActor () -> Bool
    private let hasTrack: @MainActor () -> Bool
    private let isResting: @MainActor () -> Bool
    private let isCallActive: @MainActor () -> Bool
    private let pause: @MainActor () -> Void
    private let play: @MainActor () -> Void
    private let now: @MainActor () -> Date

    init(isPlaying: @escaping @MainActor () -> Bool,
         hasTrack: @escaping @MainActor () -> Bool = { true },
         isResting: @escaping @MainActor () -> Bool,
         isCallActive: @escaping @MainActor () -> Bool = { false },
         pause: @escaping @MainActor () -> Void,
         play: @escaping @MainActor () -> Void,
         now: @escaping @MainActor () -> Date = { .now }) {
        self.isPlaying = isPlaying
        self.hasTrack = hasTrack
        self.isResting = isResting
        self.isCallActive = isCallActive
        self.pause = pause
        self.play = play
        self.now = now
    }

    private var stillResuming: Bool {
        guard resuming, let since = resumingSince else { return false }
        if now().timeIntervalSince(since) > Self.resumePatience {
            resuming = false
            pauseWhenItLands = false
            resumingSince = nil
            return false
        }
        return true
    }

    /// `feedAudio {on}` from the lens.
    func lensSound(on: Bool) {
        if on {
            guard !pausedByUs, isResting() else { return }
            if stillResuming {
                pausedByUs = true
                pauseWhenItLands = true
                return
            }
            guard isPlaying() else { return }
            pausedByUs = true
            pause()
        } else if pauseWhenItLands {
            // Off before our resume even landed: let it land, and keep nothing.
            pauseWhenItLands = false
            pausedByUs = false
        } else {
            resumeIfOurs()
        }
    }

    /// READY: the rest ended on the phone (ran out, or was skipped).
    func restEnded() {
        if pauseWhenItLands {
            pauseWhenItLands = false
            pausedByUs = false
            return
        }
        resumeIfOurs()
    }

    /// The player changed state. Called for every change, ours included.
    func playbackChanged(isPlaying playing: Bool) {
        guard playing else { return }
        if stillResuming {
            // Our own play landing — not somebody pressing play.
            resuming = false
            resumingSince = nil
            if pauseWhenItLands {
                pauseWhenItLands = false
                pause()                      // the claim stays: READY pays it back
            }
            return
        }
        // Playing again without us: you chose it, so it is yours.
        pausedByUs = false
    }

    /// An audio interruption began or ended. `system` is the plain kind
    /// (`AVAudioSession.InterruptionReason.default`) — not the app being
    /// suspended or a route going away, which say nothing about who wants
    /// the speaker. Only a phone call drops the claim; Siri does not.
    func interruption(began: Bool, system: Bool) {
        guard began, system, isCallActive() else { return }
        pausedByUs = false
        pauseWhenItLands = false
    }

    private func resumeIfOurs() {
        guard pausedByUs else { return }
        pausedByUs = false
        // A call is on: the speaker is the call's. And with nothing queued,
        // "play" would start the favourite playlist from scratch — not the
        // song the Short interrupted.
        guard !isCallActive(), hasTrack() else { return }
        resuming = true
        resumingSince = now()
        play()
    }

    // MARK: - The wiring, as functions a test can reach

    /// READY: a rest that was running is not any more. Once per rest —
    /// extending it or restarting it mid-rest is not READY. (No
    /// `removeDuplicates`: the pairwise filter already ignores repeats, and the
    /// mutation check showed nothing could tell it was there.)
    static func readyPublisher(_ endsAt: AnyPublisher<Date?, Never>) -> AnyPublisher<Void, Never> {
        endsAt.map { $0 != nil }
            .scan((false, false)) { ($0.1, $1) }
            .filter { $0.0 && !$0.1 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Playing or not, once per change.
    static func playbackPublisher(_ now: AnyPublisher<MusicController.NowPlaying?, Never>) -> AnyPublisher<Bool, Never> {
        now.map { $0?.isPlaying == true }.removeDuplicates().eraseToAnyPublisher()
    }
}
