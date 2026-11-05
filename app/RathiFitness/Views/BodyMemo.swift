import Foundation

/// Values derived from a view's inputs, worked out once per draw instead of
/// once per read.
///
/// **Why this exists.** Today, Trends and the set screen answer everything
/// through computed properties over their `@Query` arrays, and the properties
/// call each other: on Today, every read of `todaysSets` re-ran `today`, which
/// re-ran `scheduledToday`, which re-ran `lastSession` — a pass over every set
/// ever logged, faulting each one's `session` from SwiftData. Each exercise row
/// reads `todaysSets` about six times, so one draw of Today was ~50 full passes
/// over the history, on the main thread. A sysdiagnose taken while the owner
/// called the app laggy (2026-11-05) caught the main thread inside
/// `TodayView.body` and `TrendsView.body` in 8 of 8 samples, at 100% CPU.
/// See `docs/DECISIONS.md`, 2026-11-05.
///
/// **How it stays correct.** Every input those properties read — the `@Query`
/// results and the view's `@State` — invalidates `body` when it changes, so
/// `body` is the one place the inputs can have moved. `reset()` at the top of
/// `body` drops everything; the closures `body` builds (rows, the toolbar, the
/// ring's 4 Hz `TimelineView`) then share one answer per question until the
/// next draw. The cache is never observed, so filling it inside `body` does
/// not schedule another draw.
///
/// Keep it to pure functions of the inputs. Something that has to be fresh on
/// every read — `rest.progress()`, a clock — does not belong in here.
@MainActor
final class BodyMemo {
    private var values: [String: Any] = [:]

    func reset() { values.removeAll(keepingCapacity: true) }

    func callAsFunction<T>(_ key: String, _ make: () -> T) -> T {
        // Looked up by index, not `values[key] as? T`: when T is itself
        // optional, a missing key and a stored nil both cast to "some nil",
        // and `today` on a rest day would have been recomputed — or worse, a
        // miss would have read as a cached nil.
        if let i = values.index(forKey: key), let hit = values[i].value as? T { return hit }
        let made = make()
        values[key] = made
        return made
    }
}
