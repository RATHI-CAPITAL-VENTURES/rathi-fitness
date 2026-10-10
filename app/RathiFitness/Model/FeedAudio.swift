import Foundation

/// A Short's sound on the lens pauses the workout music, and the music comes
/// back at READY — but only music WE paused (owner decision 2, 2026-10-09).
///
/// The rule is one bit, `pausedByUs`, and everything below is about when it
/// may be set and when it must be forgotten:
///
/// - **Set** only when the lens says the Short's sound came on, during a rest,
///   while the in-app music was actually playing. Music you had paused is not
///   ours to resume.
/// - **Paid back** (play) when the rest ends — the phone's READY is the truth,
///   not the page's clock — or when the lens says the sound went off.
/// - **Forgotten** when anyone else touches the music: it starts playing again
///   without us (you pressed play — on the phone, the AirPods or the music
///   card), or a call or Siri takes the audio. Resuming after a call
///   would be fighting the system for a song you may no longer want.
///
/// Handled beside the music card's player wiring, never in a lens layer: it is
/// not a pinch, and no screen depends on it (plan §6.7). It never touches the
/// audio session, so the keep-alive silence (`AudioHub.holdForLens`) keeps
/// running while the music is paused — `AudioHub` treats our pause like any
/// other stop and keeps the process up through it.
@MainActor
final class FeedAudio {

    private(set) var pausedByUs = false
    /// An audio interruption (a call, Siri) is in progress: no new pause.
    private(set) var interrupted = false

    private let isPlaying: @MainActor () -> Bool
    private let isResting: @MainActor () -> Bool
    private let pause: @MainActor () -> Void
    private let play: @MainActor () -> Void

    init(isPlaying: @escaping @MainActor () -> Bool,
         isResting: @escaping @MainActor () -> Bool,
         pause: @escaping @MainActor () -> Void,
         play: @escaping @MainActor () -> Void) {
        self.isPlaying = isPlaying
        self.isResting = isResting
        self.pause = pause
        self.play = play
    }

    /// `feedAudio {on}` from the lens.
    func lensSound(on: Bool) {
        if on {
            guard !pausedByUs, !interrupted, isResting(), isPlaying() else { return }
            pausedByUs = true
            pause()
        } else {
            resumeIfOurs()
        }
    }

    /// READY: the rest ended on the phone (ran out, or was skipped).
    func restEnded() {
        resumeIfOurs()
        // Siri delivers `began` and never `ended` (measured in the spike), so
        // an interruption is also taken as over once a rest has ended — it
        // only ever blocks the NEXT pause, never a resume (the claim went at
        // `began`).
        interrupted = false
    }

    /// The player changed state. Called for every change, ours included: our
    /// own pause arrives here as "not playing" and changes nothing; music
    /// playing again while we hold the claim means someone else started it.
    func playbackChanged(isPlaying playing: Bool) {
        guard playing else { return }
        pausedByUs = false
        // Music is back, so whatever interrupted it is over.
        interrupted = false
    }

    /// An audio interruption began or ended. Began: the claim is dropped — the
    /// call owns the audio now, and what plays after it is the system's and
    /// the person's call, not ours.
    func interruption(began: Bool) {
        interrupted = began
        if began { pausedByUs = false }
    }

    /// Nothing here asks about an interruption: one drops the claim when it
    /// begins, so there is never a claim to pay back into it. (A guard here was
    /// written first; the mutation check showed no test could reach it.)
    private func resumeIfOurs() {
        guard pausedByUs else { return }
        pausedByUs = false
        play()
    }
}
