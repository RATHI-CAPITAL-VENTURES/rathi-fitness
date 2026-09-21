import AVFoundation
import Combine
import Foundation

/// A second of nothing, on a loop.
///
/// The real app stays alive with the phone locked because it is playing audio —
/// that is how an AirPods squeeze still logs a set from a pocket. Meta's sample
/// has no such thing and leans on `bluetooth-central` alone. Whether the lens
/// needs the first, or gets by on the second, is the whole of question 2, so
/// this is a switch rather than a fact: run the pocket test once each way.
@MainActor
final class SilentAudio: ObservableObject {

    @Published private(set) var isOn = false

    private var player: AVAudioPlayer?
    private let log: SpikeLog

    init(log: SpikeLog) {
        self.log = log
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                self?.log.add("audio", began ? "interrupted — the process may now be suspendable" : "interruption ended")
                if !began, self?.isOn == true { self?.player?.play() }
            }
        }
    }

    func set(_ on: Bool) {
        if on {
            do {
                let session = AVAudioSession.sharedInstance()
                // Mixing, so this does not stop whatever you are listening to.
                try session.setCategory(.playback, options: [.mixWithOthers])
                try session.setActive(true)
                let player = try AVAudioPlayer(data: Self.silence(seconds: 1))
                player.numberOfLoops = -1
                player.volume = 0
                player.play()
                self.player = player
                isOn = true
            } catch {
                log.add("audio", "could not start: \(error.localizedDescription)")
                isOn = false
            }
        } else {
            player?.stop()
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isOn = false
        }
        log.audioOn = isOn
        log.add("audio", isOn ? "holding the process open" : "released")
    }

    /// 16-bit mono PCM at 8 kHz, all zeroes, with the 44-byte header that makes
    /// it a WAV. Built here so the spike carries no asset.
    private static func silence(seconds: Int) -> Data {
        let rate: UInt32 = 8000
        let bytes = UInt32(seconds) * rate * 2
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        data.append(Data(count: Int(bytes)))
        return data
    }
}
