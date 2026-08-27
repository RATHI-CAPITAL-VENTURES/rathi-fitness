import Foundation
import SwiftData
import SwiftUI
import os

/// Writing to the database, and saying so when it does not work.
///
/// Every write in this app used to be `try? context.save()` — twenty-one of
/// them. `try?` on a save is not error handling, it is a decision that the user
/// does not need to know, taken twenty-one separate times by nobody in
/// particular. If SwiftData refused a write, the set you just logged was gone
/// and the screen carried on as though it were not.
///
/// This surfaced when "Add a day" did nothing and the obvious next move was to
/// watch the device logs while it was pressed. There was nothing to watch: no
/// log line, no thrown error, no banner. The cause turned out to be a dead
/// button rather than a failed save — but the investigation had no instrument
/// either way, and that is its own bug.
///
/// So a failed save now does three things: writes a `.fault` to the unified log
/// so `log stream` has something to show, keeps the failure so the UI can put
/// it in front of you (`SaveFailureBanner`), and returns `false` so a caller
/// with something better to do can do it.
///
/// **What is deliberately still `try?`:** the haptic engine, the audio session,
/// MusicKit playback, `AVAudioSession`, and every `Task.sleep`. Those are
/// genuinely best-effort — a haptic that does not fire costs you nothing and
/// there is no sensible recovery — and none of them is a lost workout. The rule
/// here is narrower than "never use `try?`": **nothing that writes your
/// training data may fail quietly.** `guards.d/silent-saves.sh` fails the build
/// if `try? context.save()` comes back.
///
/// Not `@MainActor`, deliberately: several call sites are `Binding` setters,
/// which are non-isolated closures and cannot call an isolated method at all.
/// The hop to the main thread happens inside `record` instead, where it is one
/// decision rather than twenty-one.
final class Saves: ObservableObject {

    /// Shared because a save happens in a dozen views and none of them should
    /// have to be handed a reporter to be allowed to report. Injected into the
    /// environment at the root all the same, so a test can use its own.
    static let shared = Saves()

    private static let log = Logger(subsystem: "com.rathi.fitness", category: "saves")

    /// What was being done, and what SwiftData said about it.
    struct Failure: Identifiable, Equatable {
        let id = UUID()
        /// In the words of the thing you were doing — "adding a day", not
        /// "NSPersistentStoreCoordinator". It is the half of the message that
        /// tells you what you have lost.
        let what: String
        let reason: String
        let site: String
    }

    /// The most recent write that did not land. Nil once acknowledged.
    ///
    /// One at a time, on purpose: if saving is failing it is failing for
    /// everything, and a stack of twenty identical banners is a worse way of
    /// saying the same thing once.
    @Published private(set) var failure: Failure?

    /// Every failure this launch, acknowledged or not. Keeps the banner's
    /// "3 others didn't save either" honest, and gives a test more than the
    /// last one to assert on.
    @Published private(set) var failures: [Failure] = []

    init() {}

    func record(what: String, error: Error,
                file: StaticString = #fileID, line: UInt = #line) {
        let entry = Failure(what: what,
                            reason: error.localizedDescription,
                            site: "\(file):\(line)")
        // `.fault` rather than `.error`: this is the level that survives the
        // default log configuration, which is the whole point — it has to be
        // there to be found later by someone streaming logs from a phone that
        // has already misbehaved.
        Self.log.fault("""
            save failed while \(what, privacy: .public) — \
            \(entry.reason, privacy: .public) [\(entry.site, privacy: .public)]
            """)
        publish(entry)
    }

    /// Dismiss the banner. The failure stays in `failures`.
    func acknowledge() { failure = nil }

    /// Test seam.
    func forget() {
        onMain {
            self.failure = nil
            self.failures.removeAll()
        }
    }

    private func publish(_ entry: Failure) {
        onMain {
            self.failures.append(entry)
            self.failure = entry
        }
    }

    /// `@Published` is being observed by a SwiftUI view, so it has to change on
    /// the main thread. Synchronously when we are already there, or the banner
    /// would lag a frame behind the tap that caused it — and a test would have
    /// to sleep to see it.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

extension ModelContext {

    /// Save, and say so when it does not work.
    ///
    /// `what` completes the sentence "save failed while ___", so write it as a
    /// gerund phrase in the user's vocabulary: `"adding a day"`, `"logging a
    /// set"`. It is what the banner shows, and "saving" is not good enough —
    /// the user already knows a save failed; what they need is which one.
    ///
    /// Returns whether the write landed. Ignorable, because most callers have
    /// nothing better to do than let the banner speak — hence
    /// `@discardableResult`.
    @discardableResult
    func saveOrReport(_ what: String,
                      to reporter: Saves = .shared,
                      file: StaticString = #fileID,
                      line: UInt = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            reporter.record(what: what, error: error, file: file, line: line)
            return false
        }
    }
}

/// The same treatment for the operations that are a save in everything but
/// name — seeding, wiping, exporting. They throw, they touch your data, and
/// they were all `try?` too.
@discardableResult
func reportingFailure<T>(_ what: String,
                         to reporter: Saves = .shared,
                         file: StaticString = #fileID,
                         line: UInt = #line,
                         _ body: () throws -> T) -> T? {
    do {
        return try body()
    } catch {
        reporter.record(what: what, error: error, file: file, line: line)
        return nil
    }
}
