import Combine
import Foundation
import MWDATDisplay
import UIKit

/// The seven questions, one method each.
///
/// Every experiment writes a header, runs, and writes a summary — so the log
/// can be read by someone who was not there, which after ten minutes with the
/// phone in a pocket includes the person who ran it.
@MainActor
final class Experiments: ObservableObject {

    @Published private(set) var running: String?
    @Published private(set) var pinches = 0

    private let glasses: Glasses
    private let log: SpikeLog
    private var task: Task<Void, Never>?
    private var restRemaining = 90

    init(glasses: Glasses, log: SpikeLog) {
        self.glasses = glasses
        self.log = log
    }

    func stop() {
        task?.cancel()
    }

    private func run(_ name: String, _ body: @escaping @MainActor () async -> Void) {
        guard running == nil else { return }
        running = name
        log.add("BEGIN", name)
        task = Task { [weak self] in
            await body()
            self?.log.add("END", name + (Task.isCancelled ? " · stopped by hand" : ""))
            self?.running = nil
        }
    }

    /// A pinch, from whichever thread the SDK chose.
    private func pinch(_ what: String, then action: (@MainActor @Sendable () -> Void)? = nil) -> LensScreens.Tap {
        { [weak self] in
            self?.log.addFromAnywhere("PINCH", what)
            Task { @MainActor in
                self?.pinches += 1
                action?()
            }
        }
    }

    // MARK: - 1 · Does a session start at all?

    func hello() {
        run("1 · hello") { [self] in
            guard await glasses.connect() else { return }
            _ = await glasses.send(LensScreens.hello(onPinch: pinch("Log set")), label: "hello")
        }
    }

    // MARK: - 2, 3, 5 · The countdown, in a pocket

    /// A rest timer that never ends: 90 down to 0, again, for `minutes`.
    ///
    /// Run it, lock the phone, pocket it, pinch now and then, text yourself
    /// once. Three things come out: whether ticks kept landing (2), what each
    /// cost (3), and what a notification did to the session (5).
    ///
    /// The line to look for is GAP. The loop asks to wake every second; a wake
    /// that arrives late is iOS having suspended the process, which is the
    /// thing question 2 is actually asking about.
    func countdown(minutes: Int, asImage: Bool) {
        run("2 · countdown · \(minutes) min · \(asImage ? "image" : "text") clock") { [self] in
            guard await glasses.connect() else { return }
            let clock = ContinuousClock()
            let ends = clock.now + .seconds(minutes * 60)
            var stats = Timings()
            var last = clock.now
            var lastSend: Double?
            restRemaining = 90

            while clock.now < ends, !Task.isCancelled {
                let now = clock.now
                let gap = Glasses.milliseconds(last.duration(to: now))
                if gap > 2500 {
                    let sent = lastSend.map { "\(Int($0)) ms" } ?? "failed"
                    log.add("GAP", "\(String(format: "%.1f", gap / 1000)) s between ticks · the send before it took \(sent)")
                    stats.gaps += 1
                    stats.longestGap = max(stats.longestGap, gap)
                }
                last = now

                let remaining = restRemaining
                let view = LensScreens.rest(
                    remaining: remaining,
                    caption: "Then set 3 of 4 · 185 × 8",
                    hero: asImage ? LensScreens.clockImage(remaining) : nil,
                    onLog: pinch("Skip") { [weak self] in self?.restRemaining = 90 },
                    onExtend: pinch("+30 s") { [weak self] in self?.restRemaining += 30 })

                // Every tenth tick is written out, so the log shows life without
                // drowning in it. Failures always are.
                lastSend = await glasses.send(view, label: "tick \(remaining)", quiet: remaining % 10 != 0)
                stats.record(lastSend, in: log.bucket)

                restRemaining = restRemaining > 0 ? restRemaining - 1 : 90
                try? await Task.sleep(until: last + .seconds(1), clock: clock)
            }
            for line in stats.summary { log.add("RESULT", line) }
            log.add("RESULT", stats.suspension)
            log.add("RESULT", "pinches received this session: \(pinches)")
        }
    }

    // MARK: - 3 · What does one send cost?

    /// Back to back, no sleeping: twenty of each. Front of the phone, so the
    /// number is the radio's and not the scheduler's.
    func benchmark() {
        run("3 · send cost · 20 text, 20 image") { [self] in
            guard await glasses.connect() else { return }
            let bytes = LensScreens.clockImage(88).pngData()?.count ?? 0
            log.add("note", "the clock image is 552×220, \(bytes / 1024) KB as PNG — what the SDK sends is its own business")

            for asImage in [false, true] {
                var stats = Timings()
                for n in 0..<20 where !Task.isCancelled {
                    let remaining = 90 - n
                    let view = LensScreens.rest(
                        remaining: remaining, caption: asImage ? "image clock" : "text clock",
                        hero: asImage ? LensScreens.clockImage(remaining) : nil,
                        onLog: pinch("Skip"), onExtend: pinch("+30 s"))
                    stats.record(await glasses.send(view, label: "bench \(n)", quiet: true), in: asImage ? "image" : "text")
                }
                for line in stats.summary { log.add("RESULT", line) }
            }
        }
    }

    // MARK: - 4 · Does the lens sleep through a rest?

    /// One screen, ninety seconds of saying nothing, then one more. Watch the
    /// lens: does it dim, does it go dark, and does the second screen bring it
    /// back? The phone cannot see any of that — note what you saw.
    func quietRest() {
        run("4 · quiet rest · 90 s of silence") { [self] in
            guard await glasses.connect() else { return }
            _ = await glasses.send(
                LensScreens.still(title: "Resting", body: "Nothing will be sent for 90 seconds. Watch whether this goes dark."),
                label: "quiet · first")
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            _ = await glasses.send(
                LensScreens.still(title: "Rest over", body: "Did you see this arrive on its own?"),
                label: "quiet · second, after 90 s")
        }
    }

    // MARK: - 4b · How long can the lens go unspoken-to?

    /// Found by accident on the first afternoon: an idle session is not dimmed,
    /// it is ended — 7.7 s after a lone send, while a send every second lived
    /// for two minutes. Somewhere between 1 and 7.7 is the number every static
    /// screen in the real feature has to be designed around, and this climbs
    /// until it finds it. Needs nobody watching.
    func gapLadder() {
        run("4b · gap ladder") { [self] in
            guard await glasses.connect() else { return }
            var survived = 0
            for gap in [2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 30] where !Task.isCancelled {
                let sent = await glasses.send(
                    LensScreens.still(title: "Quiet for \(gap) s", body: "Survived \(survived) s so far."),
                    label: "ladder · before a \(gap) s silence")
                guard sent != nil else { break }
                try? await Task.sleep(for: .seconds(gap))
                guard glasses.isReady else {
                    log.add("RESULT", "the session died during a \(gap) s silence · longest survived: \(survived) s")
                    return
                }
                survived = gap
            }
            // A ladder stopped at the second rung once reported "never died ·
            // survived 3 s" as though that were a finding.
            guard !Task.isCancelled else { return log.add("note", "ladder stopped by hand at \(survived) s — not a result") }
            log.add("RESULT", "never died · longest silence tried and survived: \(survived) s")
        }
    }

    /// Re-sends a static screen on a timer so the glasses do not hang up on it.
    ///
    /// `build` is called afresh each time because a send replaces the tap
    /// handlers along with the pixels. Whether it also throws away which button
    /// was lit — which would make a list under a heartbeat unusable — is
    /// something only the person wearing them can say.
    private func hold(
        _ label: String, every seconds: Int, for total: Int,
        _ build: @escaping @MainActor () -> FlexBox
    ) async {
        let clock = ContinuousClock()
        let ends = clock.now + .seconds(total)
        var beat = 0
        while clock.now < ends, !Task.isCancelled {
            guard await glasses.send(build(), label: "\(label) · beat \(beat)", quiet: beat > 0) != nil else {
                log.add("hold", "\(label) · lost the lens at beat \(beat)")
                return
            }
            beat += 1
            try? await Task.sleep(for: .seconds(seconds))
        }
        log.add("hold", "\(label) · held for \(total) s over \(beat) sends")
    }

    // MARK: - 6 · Does a tall list scroll?

    func tallList() {
        run("6 · tall list · 8 rows") { [self] in
            guard await glasses.connect() else { return }
            _ = await glasses.send(
                LensScreens.tallList { [weak self] number, name in
                    self?.log.addFromAnywhere("PINCH", "row \(number) · \(name)")
                },
                label: "tall list")
        }
    }

    // MARK: - 7 · Focus, and the back gesture

    func focusProbe() {
        run("7 · focus and back") { [self] in
            guard await glasses.connect() else { return }
            _ = await glasses.send(
                LensScreens.focusProbe { [weak self] label in
                    self?.log.addFromAnywhere("PINCH", "button · \(label)")
                },
                label: "focus probe")
        }
    }
}

/// Send times, kept apart by where the phone was when they happened — a median
/// over "front" and "locked" together would describe neither.
struct Timings {
    private var ok: [String: [Double]] = [:]
    private var failed: [String: Int] = [:]
    var gaps = 0
    var longestGap: Double = 0

    mutating func record(_ ms: Double?, in bucket: String) {
        if let ms { ok[bucket, default: []].append(ms) } else { failed[bucket, default: 0] += 1 }
    }

    var summary: [String] {
        let buckets = Set(ok.keys).union(failed.keys).sorted()
        let lines = buckets.map { bucket -> String in
            let times = (ok[bucket] ?? []).sorted()
            let lost = failed[bucket] ?? 0
            guard !times.isEmpty else { return "\(bucket): 0 sent, \(lost) FAILED" }
            func at(_ q: Double) -> Int { Int(times[min(times.count - 1, Int(Double(times.count) * q))]) }
            return "\(bucket): \(times.count) sent, \(lost) failed · median \(at(0.5)) ms · p95 \(at(0.95)) ms · worst \(Int(times.last!)) ms"
        }
        return lines
    }

    /// Only the countdown paces itself, so only it can say anything about
    /// suspension. The benchmark never sleeps and would always report "none".
    var suspension: String {
        gaps > 0
            ? "ticks arrived late \(gaps) times · longest \(String(format: "%.1f", longestGap / 1000)) s — the process was being suspended"
            : "no late ticks — the process was never suspended"
    }
}
