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

    private let engine = AVAudioEngine()
    private let cueNode = AVAudioPlayerNode()
    private let silenceNode = AVAudioPlayerNode()
    private let speaker = AVSpeechSynthesizer()
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var buffers: [Tone: AVAudioPCMBuffer] = [:]
    private var engineRunning = false
    private var sessionActive = false

    private init() {
        volume = UserDefaults.standard.object(forKey: Keys.volume) as? Double ?? 0.85
    }

    // MARK: - Session

    /// Take the session. Called when a workout screen appears, not at launch —
    /// an app that grabs the audio session on cold start is an app that stops
    /// your podcast for no reason.
    func activate() {
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
        if engineRunning {
            engine.stop()
            engineRunning = false
        }
        #if os(iOS)
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
        sessionActive = false
        #endif
    }

    private func startEngineIfNeeded() {
        guard !engineRunning else { return }
        if engine.attachedNodes.contains(cueNode) == false {
            engine.attach(cueNode)
            engine.attach(silenceNode)
            engine.connect(cueNode, to: engine.mainMixerNode, format: format)
            engine.connect(silenceNode, to: engine.mainMixerNode, format: format)
        }
        engine.prepare()
        do {
            try engine.start()
            engineRunning = true
        } catch {
            // A dead engine costs the tones and nothing else — the haptics and
            // the local notification still land.
            engineRunning = false
        }
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

    func play(_ tone: Tone) {
        startEngineIfNeeded()
        guard engineRunning else { return }
        let buffer = buffers[tone] ?? render(tone)
        buffers[tone] = buffer
        cueNode.volume = Float(max(0, min(1, volume)))
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

    private func render(_ tone: Tone) -> AVAudioPCMBuffer {
        let notes = score(for: tone)
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
