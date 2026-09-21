import Foundation
import SwiftData

/// The workout, without a screen.
///
/// Until the glasses could drive, every question here was answered inside a
/// view: which day it is lived in `TodayView`, what weight to open on and how a
/// set is written lived in `SetView`, each as a private function over that
/// view's `@Query` results. That was fine while a view was the only thing that
/// could ask. A locked phone has no views, and the lens needs the same answers.
///
/// So they moved here, and **the views call these** — they were not copied. A
/// second copy of "how a set is written" is the bug this whole feature is most
/// afraid of, arriving by a different door.
///
/// Every function takes the rows it reasons over as arguments rather than
/// fetching them. The views pass their `@Query` arrays; the driver passes a
/// fetch. Same rows, same answer, and nothing here can disagree with the
/// screen about what the store contains.
enum Workout {

    // MARK: - Which day it is

    /// What is up today, by the schedule. A view may still override this — the
    /// calendar button on Today, the `-RFDay` launch argument — and that stays
    /// the view's business.
    static func today(days: [PlannedDay], config: Rotation.Config,
                      sessionDates: [Date], lastSession: Date?,
                      now: Date = .now, calendar: Calendar = .current) -> PlannedDay? {
        switch config.mode {
        case .weekday:
            return days.first { $0.weekday == calendar.component(.weekday, from: now) }
        case .rotation, .everyNDays:
            guard Rotation.isTrainingDay(now, config: config, lastSession: lastSession,
                                         calendar: calendar) else { return nil }
            return rotationDay(days: days, sessionDates: sessionDates, now: now, calendar: calendar)
        }
    }

    /// The workout the rotation has reached, training day or not — so a rest day
    /// can still say what is coming.
    static func rotationDay(days: [PlannedDay], sessionDates: [Date],
                            now: Date = .now, calendar: Calendar = .current) -> PlannedDay? {
        guard let index = Rotation.index(on: now, sessionDates: sessionDates,
                                         dayCount: days.count, calendar: calendar)
        else { return nil }
        return days.indices.contains(index) ? days[index] : days.first
    }

    /// The last day you trained before today — what "every N days" counts from.
    static func lastSessionDate(in allSets: [SetEntry], now: Date = .now,
                                calendar: Calendar = .current) -> Date? {
        allSets.filter { !calendar.isDate($0.date, inSameDayAs: now) }.map(\.date).max()
    }

    // MARK: - A day picked by hand

    /// The workout chosen with the calendar button on Today, and when.
    ///
    /// It was `TodayView`'s `@State` and nobody else's business, until the
    /// glasses needed to know which workout the phone was showing. It is a day
    /// and a date rather than just a day because the choice is about TODAY:
    /// Legs picked on Tuesday must not still be the workout on Wednesday.
    ///
    /// Not persisted, deliberately — it was not before, and quitting the app
    /// has always put Today back on the schedule.
    @MainActor static var chosen: (day: PersistentIdentifier, on: Date)?

    @MainActor
    static func chosenDay(among days: [PlannedDay], now: Date = .now,
                          calendar: Calendar = .current) -> PlannedDay? {
        guard let chosen, calendar.isDate(chosen.on, inSameDayAs: now) else { return nil }
        return days.first { $0.persistentModelID == chosen.day }
    }

    // MARK: - What belongs to it

    /// The workout in progress for `day`, if there is one.
    static func openSession(for day: PlannedDay?, among sessions: [Session],
                            now: Date = .now, calendar: Calendar = .current) -> Session? {
        guard let day else { return nil }
        return sessions.first {
            $0.isOpen
                && calendar.isDate($0.startedAt, inSameDayAs: now)
                && $0.plannedDay?.persistentModelID == day.persistentModelID
        }
    }

    /// The sets that belong to the workout on screen.
    ///
    /// Day-scoped, the evening half of a two-a-day opened with the morning's
    /// checklist already ticked — every exercise the two shared showed done
    /// before you started. Scoped to the open session, the second workout opens
    /// empty, which is what it is. Falls back to the day when nothing is open
    /// yet, so a rest-day glance at what you did still shows it.
    static func todaysSets(in allSets: [SetEntry], openSession: Session?, today: PlannedDay?,
                           now: Date = .now, calendar: Calendar = .current) -> [SetEntry] {
        if let session = openSession {
            return allSets.filter { $0.session?.persistentModelID == session.persistentModelID }
        }
        // Today's sets FOR THIS WORKOUT. The bare calendar day let a morning's
        // Legs tick the evening's Push A before its first set. A set with no
        // session predates sessions.
        let shown = today?.persistentModelID
        return allSets.filter {
            calendar.isDate($0.date, inSameDayAs: now)
                && ($0.session == nil || $0.session?.plannedDay?.persistentModelID == shown)
        }
    }

    /// Everything done in this SLOT today — its own exercise and anything that
    /// stood in for it. See `Swaps.slugsCounting`.
    static func performed(_ item: PlanItem, in todaysSets: [SetEntry]) -> [SetEntry] {
        let slugs = Swaps.slugsCounting(toward: item)
        return todaysSets.filter { slugs.contains($0.exercise?.slug ?? "") }
    }

    /// Sets that move you toward the target. Three warm-ups used to tick an
    /// exercise off — the checklist lying about the one thing it is for.
    static func working(_ item: PlanItem, in todaysSets: [SetEntry]) -> [SetEntry] {
        performed(item, in: todaysSets).filter { $0.setKind.counts }
    }

    static func isDone(_ item: PlanItem, in todaysSets: [SetEntry]) -> Bool {
        // One bout ticks a cardio slot off unless the plan asked for intervals.
        // Counting it against `targetSets` alone would leave the treadmill
        // permanently unfinished, because its default target is three.
        let exercise = Swaps.exercise(for: item)
        let sets = exercise.map { Swaps.prescription(for: item, doing: $0).sets } ?? item.targetSets
        if exercise?.isCardio == true {
            return performed(item, in: todaysSets).count >= max(1, sets)
        }
        return working(item, in: todaysSets).count >= sets
    }

    // MARK: - What to lift

    /// What to try, from the last day this lift was done.
    static func suggestion(for item: PlanItem, doing exercise: Exercise, in allSets: [SetEntry],
                           calendar: Calendar = .current) -> Tally.Suggestion? {
        let mine = allSets.filter { $0.exercise?.slug == exercise.slug }
        return Tally.nextTarget(
            // No bodyweight: `nextTarget` reads weight and reps, never volume.
            lastSession: mine.lastSession(calendar: calendar).map { $0.tally(bodyWeight: nil) },
            target: Swaps.prescription(for: item, doing: exercise).reps)
    }

    /// The numbers a set screen opens on: what you just did in this workout,
    /// else what last time says to try, else the plan.
    ///
    /// - Parameter doneHere: THIS exercise's sets in the open workout, in order.
    ///   Not the whole slot's: two bench sets at 185 must not put 185 on the
    ///   dumbbells that replaced it.
    static func opening(for item: PlanItem, doing exercise: Exercise,
                        doneHere: [SetEntry], in allSets: [SetEntry],
                        calendar: Calendar = .current) -> (weight: Double, reps: Int) {
        let plan = Swaps.prescription(for: item, doing: exercise)
        let suggestion = suggestion(for: item, doing: exercise, in: allSets, calendar: calendar)
        return (doneHere.last?.weight ?? suggestion?.weight ?? plan.weight,
                doneHere.last.map { _ in plan.reps } ?? suggestion?.reps ?? plan.reps)
    }

    /// In a superset you walk to the next machine, you do not rest.
    ///
    /// Twenty seconds instead of the full cooldown, and the ring says "Move"
    /// rather than "Cooldown" — the whole reason the pairing has to exist in
    /// the model at all is that the timer is otherwise actively wrong here.
    static func rest(after item: PlanItem, doing exercise: Exercise) -> (seconds: Int, caption: String) {
        let plan = Swaps.prescription(for: item, doing: exercise)
        guard item.supersetGroup > 0, let day = item.day else { return (plan.restSeconds, "Cooldown") }
        let group = day.orderedItems.filter { $0.supersetGroup == item.supersetGroup }
        let isLast = group.last?.persistentModelID == item.persistentModelID
        return isLast ? (plan.restSeconds, "Cooldown") : (20, "Move")
    }

    // MARK: - Writing a set

    /// The record this set would set, in words, or nil. Asked BEFORE the set is
    /// written, for two reasons: the history must not contain it — every set
    /// would be a record for beating itself — and the buzz that answers a pinch
    /// should not wait behind a save.
    ///
    /// - Parameter history: every set ever logged for THIS exercise.
    static func record(weight: Double, reps: Int, kind: SetKind, exercise: Exercise,
                       history: [SetEntry]) -> String? {
        // Records compare weight and reps, never volume — so no bodyweight is
        // needed and none is invented.
        Tally.headline(
            for: Tally.Set(weight: weight, reps: reps, kind: kind, assisted: exercise.assisted),
            history: history.map { $0.tally(bodyWeight: nil) })
    }

    /// One lifted set, written. The only place in the app that does it.
    ///
    /// - Parameter setIndex: sequential within this exercise in this workout,
    ///   warm-ups included, so the numbering matches what you did.
    static func logStrength(
        item: PlanItem, exercise: Exercise, weight: Double, reps: Int,
        kind: SetKind, rpe: Double = 0, note: String = "", setIndex: Int,
        at now: Date = .now, in context: ModelContext
    ) {
        let candidate = Tally.Set(weight: weight, reps: reps, kind: kind, assisted: exercise.assisted)
        let entry = SetEntry(exercise: exercise, weight: weight, reps: reps, setIndex: setIndex,
                             date: now, kind: kind, rpe: rpe, note: note)
        // Opened here, on the first set, rather than when a screen appears —
        // walking into a workout and walking out again without lifting should
        // not leave an empty session in your history.
        entry.session = Sessions.current(for: item.day, in: context, now: now)
        context.insert(entry)
        // The plan follows what you actually lift. Without this the row goes on
        // showing 45 after you have been doing 50 for a month.
        //
        // Not for a stand-in. `targetWeight` belongs to the slot's OWN exercise:
        // a heavy day on the dumbbells must not become next week's barbell
        // target, which is what writing it through would do.
        if !Swaps.isStandIn(exercise, in: item),
           let advanced = Tally.advancedTarget(current: item.targetWeight,
                                               targetReps: item.targetReps, set: candidate) {
            item.targetWeight = advanced
        }
        context.saveOrReport("logging a set")
    }

    /// Two channels for every outcome: a record gets its own rising pattern and
    /// its own rising tone, an ordinary set gets the short one. This is the
    /// confirmation you get when the phone never left your pocket — and on the
    /// glasses path it is the ONLY one that does not need your eyes.
    @MainActor
    static func confirm(record: String?) {
        Haptics.shared.play(record != nil ? .record : .logged)
        AudioHub.shared.play(record != nil ? .record : .logged)
    }
}
