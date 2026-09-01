import Foundation
import AVFoundation
import MediaPlayer

/// Everything the app puts into your ears, and the one audio session it does it
/// through.
///
/// Three separate needs land on the same piece of hardware, and they fight if
/// they are owned separately:
///
///  1. **The cooldown ping.** It has to be audible over music, in a pocket,
///     with the screen locked.
///  2. **Music.** `MusicController` plays Apple Music through this app.
///  3. **AirPods gestures.** iOS delivers a squeeze to whichever app is
///     *currently now-playing* and to nobody else. That is the whole reason
///     this class exists rather than three call sites poking `AVAudioSession`:
///     to hear the AirPods at all we must hold that role, which means holding
///     one session, active, with something playing through it.
///
/// Hence `holdRemoteControl`. When hands-free is on and no music is playing, the
/// app loops a buffer of **silence** to keep the now-playing role. That is a
/// trick and it is written down as one: it is the documented cost of hearing a
/// triple-press, and it stops the moment you leave the workout.
///
/// The tones are synthesised rather than shipped as audio files. A chime you can
/// tune by changing two numbers stays honest to the design; a `.caf` in the
/// bundle is a thing nobody can adjust without an editor.
@MainActor
final class AudioHub: ObservableObject {
    static let shared = AudioHub()

    /// What the app can say without words. One case per meaning — the pairing
    /// to the haptic of the same name is deliberate: every cue is a sound *and*
    /// a pattern, so either channel alone carries it.
    enum Tone: String, CaseIterable {
        /// Each of the last three seconds of a cooldown.
        case tick
        /// The cooldown is over — you're up.
        case restOver
        /// A set went in.
        case logged
        /// A record.
        case record
        /// A gesture arrived with nothing to do.
        case refused
    }

    /// Loud enough to hear over a squat rack, quiet enough not to be a shock in
    /// AirPods. Adjustable, because "over the music" depends on the music.
    @Published var volume: Double {
        didSet { UserDefaults.standard.set(volume, forKey: Keys.volume) }
    }

    /// Whether the app is currently holding the now-playing role — i.e. whether
    /// an AirPods squeeze will reach us.
    @Published private(set) var isHoldingRemoteControl = false

    private enum Keys {
        static let volume = "cue.volume"
    }

    /// Whether the audio engine may run at all. `false` under `-RFSilent`.
    ///
    /// **This exists because of a crash, not a preference.** Reaching
    /// `engine.mainMixerNode` makes CoreAudio rebuild the remote IO unit, which
    /// RPCs to an audio server — and in the simulator that server may simply
    /// not answer. `AURemoteIO::Cleanup` then calls `abort()` from inside
    /// AudioToolbox: a SIGABRT in someone else's frame, with no `try?` that
    /// catches it and nothing to retry. The only lever the app has is not to
    /// touch the engine in an environment that cannot service it, so the UI
    /// tests pass `-RFSilent` and get a deterministic run.
    ///
    /// Worth stating plainly rather than letting the flag imply otherwise:
    /// this makes the UI tests deterministic, it does **not** prove the same
    /// timeout can never happen on a device. What is genuinely testable about
    /// the cues — that every tone renders non-silent and below the ceiling —
    /// is covered by tests that never start an engine.
    ///
    /// A `var` so a test can flip it; read once from the launch arguments, the
    /// same shape as `-RFDay` and `-RFDemoHistory`.
    static var isEnabled = !ProcessInfo.processInfo.arguments.contains("-RFSilent")

    private let engine = AVAudioEngine()
    private let cueNode = AVAudioPlayerNode()
    private let silenceNode = AVAudioPlayerNode()
    private let speaker = AVSpeechSynthesizer()
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var sessionActive = false
    private var watching = false

    /// Whether OUR OWN music is playing — `MusicController` sets this.
    ///
    /// It matters because `ApplicationMusicPlayer` renders through *this app's*
    /// audio session, and `.duckOthers` ducks **other** apps. You cannot duck
    /// yourself, so nothing attenuates the music under a cue and the cue has to
    /// carry itself. See `Cue.overMusic`.
    var ownMusicIsPlaying = false

    /// The engine's own answer, not a copy of it.
    ///
    /// This was a stored `engineRunning` flag set at `start()` and cleared only
    /// in `deactivate()`. `AVAudioEngine` stops itself on a configuration
    /// change — a route change when AirPods connect, or the session being
    /// reconfigured when music starts — and the flag went on saying `true`, so
    /// every later cue was scheduled into a dead engine and silently dropped
    /// until you left the screen and came back.
    private var engineRunning: Bool { engine.isRunning }

    private init() {
        volume = UserDefaults.standard.object(forKey: Keys.volume) as? Double ?? 0.85
    }

    /// Whether a cue played right now would actually be heard.
    ///
    /// The local notification asks this to decide whether to carry a sound: if
    /// the app is going to make the noise itself, two alerts a second apart
    /// reads as a bug rather than as emphasis. It used to ask
    /// `isHoldingRemoteControl`, which is a different question — and one whose
    /// answer is `false` precisely when music is playing, because `arm()` only
    /// holds silence when nothing real is.
    var willSoundCues: Bool { sessionActive && engineRunning }

    // MARK: - Session

    /// Take the session. Called when a workout screen appears, not at launch —
    /// an app that grabs the audio session on cold start is an app that stops
    /// your podcast for no reason.
    func activate() {
        guard Self.isEnabled else { return }
        #if os(iOS)
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        // `.playback` with no `.mixWithOthers`: mixing would leave the
        // now-playing role with whoever else is playing, and the AirPods would
        // never reach us. `.duckOthers` so anything we do not own — a podcast,
        // Spotify — drops under the ping instead of burying it.
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        sessionActive = true
        #endif
        startEngineIfNeeded()
    }

    /// Give it back. Anything else on the phone resumes.
    func deactivate() {
        holdRemoteControl(false)
        speaker.stopSpeaking(at: .immediate)
        if engineRunning { engine.stop() }
        #if os(iOS)
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
        sessionActive = false
        #endif
    }

    /// Restart the engine when the system pulls it out from under us.
    ///
    /// `AVAudioEngineConfigurationChange` fires when the route or format
    /// changes — plugging in AirPods, or MusicKit starting playback — and the
    /// engine is **stopped** by the time it arrives. Nothing watched for it, so
    /// the first cue after connecting AirPods was the last one you heard.
    private func watchForConfigurationChanges() {
        guard !watching else { return }
        watching = true
        let centre = NotificationCenter.default
        centre.addObserver(forName: .AVAudioEngineConfigurationChange,
                           object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartEngine() }
        }
        #if os(iOS)
        centre.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: AVAudioSession.sharedInstance(),
                           queue: .main) { [weak self] note in
            // A phone call ends and the session comes back deactivated. Without
            // this the cooldown that was running when the call arrived finishes
            // in silence.
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                self?.sessionActive = false
                self?.activate()
            }
        }
        #endif
    }

    private func restartEngine() {
        // The graph survives a configuration change; the engine does not.
        // Reconnecting is what makes it playable again on the new format.
        engine.disconnectNodeOutput(cueNode)
        engine.disconnectNodeOutput(silenceNode)
        engine.connect(cueNode, to: engine.mainMixerNode, format: format)
        engine.connect(silenceNode, to: engine.mainMixerNode, format: format)
        try? engine.start()
        if isHoldingRemoteControl {
            // The silence loop went with the engine, and with it the
            // now-playing role the AirPods gestures depend on.
            isHoldingRemoteControl = false
            holdRemoteControl(true)
        }
    }

    private func startEngineIfNeeded() {
        // Before `watchForConfigurationChanges`, deliberately: registering the
        // observer is harmless, but everything below it reaches the engine.
        guard Self.isEnabled else { return }
        watchForConfigurationChanges()
        guard !engineRunning else { return }
        if engine.attachedNodes.contains(cueNode) == false {
            engine.attach(cueNode)
            engine.attach(silenceNode)
            engine.connect(cueNode, to: engine.mainMixerNode, format: format)
            engine.connect(silenceNode, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        // A dead engine costs the tones and nothing else — the haptics and the
        // local notification still land, and `willSoundCues` tells the
        // notification to bring its own sound.
        try? engine.start()
    }

    // MARK: - Holding the now-playing role

    /// Loop silence so iOS keeps treating us as the playing app, which is the
    /// only way an AirPods squeeze is delivered here. No-op while real music is
    /// playing through `MusicController` — that already holds the role, and two
    /// things holding it is one thing too many.
    func holdRemoteControl(_ on: Bool) {
        if on {
            guard !isHoldingRemoteControl else { return }
            activate()
            startEngineIfNeeded()
            guard engineRunning else { return }
            let frames = AVAudioFrameCount(format.sampleRate / 2)   // half a second
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
            else { return }
            silence.frameLength = frames                            // zero-filled already
            silenceNode.scheduleBuffer(silence, at: nil, options: [.loops])
            silenceNode.volume = 0
            silenceNode.play()
            isHoldingRemoteControl = true
        } else {
            guard isHoldingRemoteControl else { return }
            silenceNode.stop()
            isHoldingRemoteControl = false
        }
    }

    // MARK: - Tones

    /// A tone, and whether it has to be heard over our own music.
    ///
    /// Two renders of each tone rather than one gain knob, because the
    /// difference is not a volume: an over-music cue is normalised right up to
    /// the ceiling, and a cue that sits at the ceiling all the time is a shock
    /// in AirPods in a silent room.
    /// Internal rather than private so the tests can render a cue and measure
    /// it. "The tones render without clipping" was an assertion nobody could
    /// make while the renderer was sealed; the old test only checked that
    /// calling `play` did not throw.
    struct Cue: Hashable {
        var tone: Tone
        var overMusic: Bool
    }

    func play(_ tone: Tone) {
        startEngineIfNeeded()
        guard engineRunning else { return }
        let cue = Cue(tone: tone, overMusic: ownMusicIsPlaying)
        let buffer = buffers[cue] ?? render(cue)
        buffers[cue] = buffer
        // The user's setting still scales it, but never below audibility when
        // it is competing with a track — a cue you cannot hear is the same as
        // no cue, and the whole point of the ping is that it reaches you when
        // you are not looking at the screen.
        let level = max(0, min(1, volume))
        cueNode.volume = Float(cue.overMusic ? max(0.75, level) : level)
        cueNode.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !cueNode.isPlaying { cueNode.play() }
    }

    /// One partial of a cue: a sine at `hz`, starting at `start`, lasting
    /// `length`, at `gain`, with a plucked envelope.
    private struct Note {
        var hz: Double
        var start: TimeInterval
        var length: TimeInterval
        var gain: Double
    }

    /// The score. Rising intervals mean "go", falling means "not that" — the
    /// same grammar a lift dial or an oven uses, because it is the one people
    /// already know.
    private func score(for tone: Tone) -> [Note] {
        switch tone {
        case .tick:
            return [Note(hz: 1_320, start: 0, length: 0.045, gain: 0.30)]
        case .restOver:
            // Up a fifth, twice. The app's only interruption, so it gets the
            // most distinct shape.
            return [Note(hz: 660, start: 0.00, length: 0.13, gain: 0.55),
                    Note(hz: 990, start: 0.13, length: 0.30, gain: 0.60),
                    Note(hz: 1_320, start: 0.15, length: 0.28, gain: 0.22)]
        case .logged:
            return [Note(hz: 880, start: 0, length: 0.11, gain: 0.38)]
        case .record:
            return [Note(hz: 660, start: 0.00, length: 0.10, gain: 0.45),
                    Note(hz: 880, start: 0.09, length: 0.10, gain: 0.45),
                    Note(hz: 1_320, start: 0.18, length: 0.34, gain: 0.50)]
        case .refused:
            // Down a tone: the only falling shape in the set.
            return [Note(hz: 440, start: 0.00, length: 0.10, gain: 0.34),
                    Note(hz: 330, start: 0.10, length: 0.18, gain: 0.34)]
        }
    }

    /// Peak the rendered cue is normalised to.
    ///
    /// Normalising at all is new. The scores were hand-gained and `restOver`'s
    /// second and third notes overlap, summing past 0.8 before the user's
    /// volume was applied — close enough to the ceiling to clip on a loud
    /// setting. Normalising fixes that AND makes "louder over music" a single
    /// honest number instead of a multiplier that would have clipped.
    private func peak(overMusic: Bool) -> Float { overMusic ? 0.97 : 0.55 }

    func render(_ cue: Cue) -> AVAudioPCMBuffer {
        let notes = score(for: cue.tone)
        let seconds = (notes.map { $0.start + $0.length }.max() ?? 0.2) + 0.05
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let channels = buffer.floatChannelData else { return buffer }

        for note in notes {
            let first = Int(note.start * rate)
            let count = Int(note.length * rate)
            guard count > 0 else { continue }
            for i in 0..<count {
                let frame = first + i
                guard frame < Int(frames) else { break }
                let t = Double(i) / rate
                // 4ms attack so it does not click, exponential decay after.
                let attack = min(1, t / 0.004)
                let decay = exp(-3.2 * t / note.length)
                let value = Float(sin(2 * .pi * note.hz * t) * note.gain * attack * decay)
                for channel in 0..<Int(format.channelCount) {
                    channels[channel][frame] += value
                }
            }
        }

        // Normalise. The scores are written for shape, not for level; the level
        // is decided here, once, where the ceiling is known.
        var loudest: Float = 0
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) {
                loudest = max(loudest, abs(channels[channel][frame]))
            }
        }
        guard loudest > 0 else { return buffer }
        let scale = peak(overMusic: cue.overMusic) / loudest
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(frames) {
                channels[channel][frame] *= scale
            }
        }
        return buffer
    }

    // MARK: - Speech

    /// Say it out loud — only ever for something you asked for.
    ///
    /// The first cut narrated: it read the set back to you when a squeeze logged
    /// it, and named the lift when the cooldown ended. That was wrong, and the
    /// reason is worth keeping. A rest ending is a *ping* — one bit of
    /// information, arriving while you are catching your breath — and a sentence
    /// is the app talking over the music to tell you something the tone already
    /// said. Narration you did not ask for is noise with good intentions.
    ///
    /// So the only caller left is the `announce` gesture, which exists precisely
    /// because you squeezed to ask where you are.
    func say(_ sentence: String) {
        activate()
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.06
        utterance.postUtteranceDelay = 0
        utterance.volume = Float(max(0.4, min(1, volume)))
        speaker.speak(utterance)
    }
}
