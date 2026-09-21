import MWDATCore
import SwiftUI

/// Everything the spike owns, built once and in order.
///
/// The order is the point: `Wearables.configure()` has to run before anything
/// touches `Wearables.shared`, and `Glasses` touches it in its initialiser.
@MainActor
final class Spike {
    static let shared = Spike()

    let log: SpikeLog
    let audio: SilentAudio
    let glasses: Glasses
    let experiments: Experiments

    private init() {
        log = SpikeLog()
        do {
            try Wearables.configure()
            log.add("sdk", "configured · \(Glasses.reachability())")
        } catch {
            log.add("sdk FAILED", "\(error) — \(error.localizedDescription)")
        }
        audio = SilentAudio(log: log)
        glasses = Glasses(log: log)
        experiments = Experiments(glasses: glasses, log: log)
        autorun()
    }

    /// `devicectl device process launch … -autorun hello` from the Mac.
    ///
    /// Half of every question is answered by the log and needs nobody to tap
    /// anything — and each tap that had to be asked for over chat cost a
    /// round-trip. Waits for the link, because a session against glasses that
    /// have not connected yet can only say `noEligibleDevice`.
    private func autorun() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autorun"), arguments.indices.contains(flag + 1) else { return }
        let name = arguments[flag + 1]
        Task { @MainActor [self] in
            log.add("autorun", "\(name) · waiting for the link")
            for _ in 0..<300 where !glasses.canConnect { try? await Task.sleep(for: .milliseconds(100)) }
            guard glasses.canConnect else { return log.add("autorun", "gave up after 30 s · link \(glasses.link)") }
            switch name {
            case "hello": experiments.hello()
            case "bench": experiments.benchmark()
            case "list": experiments.tallList()
            case "focus": experiments.focusProbe()
            case "quiet": experiments.quietRest()
            case "ladder": experiments.gapLadder()
            case "short": experiments.countdown(minutes: 2, asImage: false)
            default: log.add("autorun", "no experiment called \(name)")
            }
        }
    }
}

@main
struct LensSpikeApp: App {
    @Environment(\.scenePhase) private var phase
    private let spike = Spike.shared

    var body: some Scene {
        WindowGroup {
            ContentView(
                log: spike.log, audio: spike.audio,
                glasses: spike.glasses, experiments: spike.experiments)
                .onOpenURL { url in Task { await spike.glasses.handle(url) } }
                .onChange(of: phase) { _, new in spike.log.add("scene", "\(new)") }
                .preferredColorScheme(.dark)
        }
    }
}
