import Combine
import Foundation
import UIKit

/// The spike's only deliverable.
///
/// Every question this app exists to answer is about what happens while nobody
/// is looking at the phone — locked, in a pocket, mid-set. So nothing here is
/// allowed to depend on somebody watching: each line carries the time and the
/// three facts that decide how to read it (was the app in front, was the phone
/// locked, was audio holding the process open), and goes to disk immediately.
///
///     14:02:31.482 | bg | LOCKED   | audio on  | send ok | tick 47 · 38 ms
@MainActor
final class SpikeLog: ObservableObject {

    /// The tail, for the screen. The file is the record; this is a window on it.
    @Published private(set) var lines: [String] = []

    /// Set by `SilentAudio`. Stamped on every line rather than logged once,
    /// because a line read in isolation three days later still has to say which
    /// half of the locked-phone comparison it came from.
    var audioOn = false

    /// False until the app has finished launching; see `context`.
    private var settled = false

    let fileURL: URL

    private let handle: FileHandle?
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("lens-spike.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // The default protection class is already writable while locked
            // after the first unlock. Said out loud because `.complete` here
            // would make the log go silent at exactly the moment it matters.
            FileManager.default.createFile(
                atPath: fileURL.path, contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd HH:mm"
        write("\n===== launch \(day.string(from: .now)) · iOS \(UIDevice.current.systemVersion) =====")

        let center = NotificationCenter.default
        // Posted for a background relaunch too, not only when a scene comes to
        // the front — which matters, because a Bluetooth wake with the phone
        // locked is one of the launches this log most needs to get right.
        // Coming to the front is the belt to that pair of braces.
        for name in [UIApplication.didFinishLaunchingNotification, UIApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settled = true }
            }
        }
        center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.add("phone", "locked") }
        }
        center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.add("phone", "unlocked") }
        }
    }

    /// Where the app is right now, as the three columns.
    var context: String {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "fg"
        case .inactive: state = "in"
        case .background: state = "bg"
        @unknown default: state = "??"
        }
        // Protected data goes away roughly ten seconds after the screen locks,
        // so a line just after locking can still read "unlocked".
        //
        // And for the first moments of a launch iOS reports it unavailable
        // whatever the truth is — the first log off the phone opened with
        // LOCKED on a phone that was in someone's hand. Until the scene has
        // reported in, this column says it does not know rather than guess.
        let lock = !settled ? "starting" : (UIApplication.shared.isProtectedDataAvailable ? "unlocked" : "LOCKED  ")
        return "\(state) | \(lock) | audio \(audioOn ? "on " : "off")"
    }

    /// Short form of `context`, for bucketing timings.
    var bucket: String {
        let front = UIApplication.shared.applicationState == .active
        let locked = !UIApplication.shared.isProtectedDataAvailable
        return front ? "front" : (locked ? "locked" : "background")
    }

    func add(_ event: String, _ detail: String = "", at date: Date = .now) {
        write("\(stamp.string(from: date)) | \(context) | \(event)\(detail.isEmpty ? "" : " | \(detail)")")
    }

    /// For the SDK's callbacks, which arrive on whatever thread they like. The
    /// time is taken here, before the hop, so a busy main thread cannot move a
    /// pinch later than it happened.
    nonisolated func addFromAnywhere(_ event: String, _ detail: String = "") {
        let date = Date()
        Task { @MainActor in self.add(event, detail, at: date) }
    }

    func clear() {
        try? handle?.truncate(atOffset: 0)
        lines = []
        add("log", "cleared")
    }

    private func write(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) { try? handle?.write(contentsOf: data) }
        lines.append(line)
        if lines.count > 250 { lines.removeFirst(lines.count - 250) }
    }
}
