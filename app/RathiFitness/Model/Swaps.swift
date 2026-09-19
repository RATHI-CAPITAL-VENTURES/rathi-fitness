import Foundation
import SwiftData

/// Doing something else in a slot, today only. The model is `Swap`; this is
/// every rule about it, in one place so Today, the set screens and the snapshot
/// cannot each hold a slightly different idea of what a slot is today.
enum Swaps {

    // MARK: - What is in the slot

    /// What is standing in for this slot's exercise on `date`, if anything.
    static func standIn(for item: PlanItem, on date: Date = .now,
                        calendar: Calendar = .current) -> Exercise? {
        // The latest row wins. One naming the slot's OWN exercise is how
        // "back to the plan" is recorded once there is history to keep — see
        // `put` — and means there is no stand-in.
        guard let latest = rows(for: item, on: date, calendar: calendar).last?.exercise,
              isStandIn(latest, in: item) else { return nil }
        return latest
    }

    /// Today's rows for this slot, oldest first.
    private static func rows(for item: PlanItem, on date: Date,
                             calendar: Calendar) -> [Swap] {
        (item.swaps ?? [])
            // A deleted row stays in the relationship until pending changes are
            // processed — the trap `Sessions.pruneEmpty` documents. Without
            // this, swapping back leaves the bike on screen until the next save.
            .filter { !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    /// Every exercise whose sets count toward this slot on `date`: the plan's
    /// own, and anything that has stood in for it today.
    ///
    /// **A slot is done when its work is done, whoever did it.** Two sets on
    /// the bench, someone takes it, two more on the dumbbells: that is four of
    /// four. Counting only what is in the slot NOW made the first two vanish
    /// from the checklist the moment you swapped — "1 of 4 done" went back to
    /// "0 of 4" — and swapping back hid the dumbbells instead.
    static func slugsCounting(toward item: PlanItem, on date: Date = .now,
                              calendar: Calendar = .current) -> Set<String> {
        var slugs = Set(rows(for: item, on: date, calendar: calendar)
            .compactMap { $0.exercise?.slug })
        if let own = item.exercise?.slug { slugs.insert(own) }
        return slugs
    }

    /// What you are actually doing in this slot on `date`: the stand-in if
    /// there is one, the plan otherwise. **Everything that draws or counts a
    /// slot reads this, never `item.exercise` directly** — a checklist that
    /// ticks the treadmill off because you rode the bike needs both halves to
    /// agree on which one they are talking about.
    static func exercise(for item: PlanItem, on date: Date = .now,
                         calendar: Calendar = .current) -> Exercise? {
        standIn(for: item, on: date, calendar: calendar) ?? item.exercise
    }

    /// Whether `exercise` is a guest in this slot rather than its owner.
    static func isStandIn(_ exercise: Exercise, in item: PlanItem) -> Bool {
        item.exercise?.persistentModelID != exercise.persistentModelID
    }

    // MARK: - Changing it

    /// Do `exercise` in this slot today. Choosing the slot's own exercise is
    /// how you swap back, not a swap of a thing for itself.
    ///
    /// **A row you lifted under is kept; a row you only looked at is not.**
    /// Changing your mind before logging anything replaces the row rather than
    /// stacking another. But once sets exist on a stand-in, its row is what
    /// says those sets belong to this slot (`slugsCounting`) — deleting it on
    /// the way back to the plan would orphan them from the checklist. So the
    /// way back is then recorded as a newer row naming the slot's own
    /// exercise, and the latest row wins.
    static func put(_ exercise: Exercise, in item: PlanItem,
                    context: ModelContext, now: Date = .now,
                    calendar: Calendar = .current) {
        var kept = 0
        var latestKept: Date?
        for row in rows(for: item, on: now, calendar: calendar) {
            if let standIn = row.exercise, isStandIn(standIn, in: item),
               wasDone(standIn, in: item, on: now, calendar: calendar) {
                latestKept = max(latestKept ?? row.date, row.date)
                kept += 1
            } else {
                context.delete(row)
            }
        }
        // Back to the plan with nothing to remember is no row at all.
        if !isStandIn(exercise, in: item) && kept == 0 { return }
        // Strictly after anything kept. "Latest wins" is only a rule if there
        // IS a latest: two rows at one instant make the slot's contents
        // whichever the sort happened to put last.
        let stamp = latestKept.map { max(now, $0.addingTimeInterval(0.001)) } ?? now
        context.insert(Swap(item: item, exercise: exercise, date: stamp))
    }

    /// Back to the plan. Sets already logged against a stand-in stay where
    /// they are, and go on counting toward the slot — they happened.
    static func clear(_ item: PlanItem, context: ModelContext,
                      on date: Date = .now, calendar: Calendar = .current) {
        guard let own = item.exercise else { return }
        put(own, in: item, context: context, now: date, calendar: calendar)
    }

    /// Whether `exercise` was lifted today IN THIS WORKOUT — a set whose
    /// session belongs to the slot's planned day.
    ///
    /// Not merely "today". Leg press in the morning's Legs is not a reason to
    /// keep a leg-press row on the evening's bench slot: looked at and put
    /// back, it would have stayed counted toward that slot all day and been
    /// shelved under "what you usually do instead" for the bench for good.
    private static func wasDone(_ exercise: Exercise, in item: PlanItem,
                                on date: Date, calendar: Calendar) -> Bool {
        (exercise.sets ?? []).contains {
            !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: date)
                && $0.session?.plannedDay?.persistentModelID == item.day?.persistentModelID
        }
    }

    // MARK: - What to offer

    /// The picker's three shelves, best guess first.
    struct Candidates {
        /// What you have stood in this slot before, most often first. The
        /// second time the treadmills are taken, the bike is one tap.
        var usual: [Exercise] = []
        /// Does the same job: any cardio for cardio, the same main muscle for a
        /// lift.
        var alike: [Exercise] = []
        var others: [Exercise] = []
    }

    static func candidates(for item: PlanItem, among exercises: [Exercise],
                           on date: Date = .now,
                           calendar: Calendar = .current) -> Candidates {
        let taken = takenSlugs(around: item, on: date, calendar: calendar)
        let open = exercises.filter { !taken.contains($0.slug) }

        // Counted over every past swap in this slot, today's included. A row
        // naming the slot's own exercise is a way back, not a stand-in.
        var uses: [String: (count: Int, latest: Date)] = [:]
        for swap in item.swaps ?? [] where !swap.isDeleted {
            guard let standIn = swap.exercise, isStandIn(standIn, in: item) else { continue }
            let slug = standIn.slug
            let seen = uses[slug]
            uses[slug] = ((seen?.count ?? 0) + 1, max(seen?.latest ?? swap.date, swap.date))
        }

        var out = Candidates()
        for exercise in open {
            if uses[exercise.slug] != nil { out.usual.append(exercise) }
            else if let planned = item.exercise,
                    alike(modality: exercise.kind, primary: exercise.primary, to: planned) {
                out.alike.append(exercise)
            } else { out.others.append(exercise) }
        }
        // Total order, name last, so the list cannot reshuffle between draws.
        out.usual.sort {
            let (a, b) = (uses[$0.slug]!, uses[$1.slug]!)
            return (b.count, b.latest, $0.name) < (a.count, a.latest, $1.name)
        }
        out.alike.sort { $0.name < $1.name }
        out.others.sort { $0.name < $1.name }
        return out
    }

    /// Slugs that cannot stand in: the slot's own exercise (that is "swap
    /// back", a different button) and anything already in today's workout —
    /// the checklist matches sets to slots by exercise, so the same one in two
    /// slots would tick both off with one set.
    ///
    /// Another slot's PLANNED exercise stays taken even while that slot is
    /// swapped away, which looks over-cautious (nobody is on the treadmill
    /// today) and is not: its sets still count toward its own slot
    /// (`slugsCounting`), so doing it here would tick that one too.
    static func takenSlugs(around item: PlanItem, on date: Date = .now,
                           calendar: Calendar = .current) -> Set<String> {
        var taken = Set<String>()
        if let own = item.exercise?.slug { taken.insert(own) }
        for other in item.day?.orderedItems ?? []
        where other.persistentModelID != item.persistentModelID {
            // Everything that COUNTS toward the other slot, not merely what is
            // showing in it. A stand-in you lifted under and then swapped away
            // from is no longer that slot's `standIn`, but its sets still tick
            // that slot — so offering it here let two dumbbell sets open a
            // second slot at "2 of 3 done" before it had been touched.
            taken.formUnion(slugsCounting(toward: other, on: date, calendar: calendar))
        }
        return taken
    }

    /// Whether something does the same job as the planned exercise. Takes the
    /// two facts rather than an `Exercise` so a catalogue entry that is not in
    /// the library yet can be asked the same question.
    static func alike(modality: Exercise.Modality, primary: MuscleGroup,
                      to planned: Exercise) -> Bool {
        guard modality == planned.kind else { return false }
        if modality == .cardio { return true }
        return primary != .other && primary == planned.primary
    }

    // MARK: - What carries over

    /// What the slot asks of whatever is standing in it.
    ///
    /// The set screens read this instead of the `PlanItem`, because a slot's
    /// numbers are about ITS exercise. Three sets of ten is three sets of ten
    /// on any press, and twenty minutes is twenty minutes on any machine — but
    /// 185 lb is a fact about the bench, and 2 miles at 3% grade is a fact
    /// about the treadmill: a bike covers that in a third of the time and has
    /// no grade at all. So a stand-in inherits the SHAPE of the work and none
    /// of the load, and opens on its own history instead — or, with no history,
    /// on the empty bar, which is the one weight known to be loadable.
    struct Prescription: Equatable {
        var sets: Int
        var reps: Int
        var restSeconds: Int
        var seconds: Int
        var weight: Double = 0
        var distance: Double = 0
        var speed: Double = 0
        var incline: Double = 0
        var resistance: Double = 0
    }

    static func prescription(for item: PlanItem, doing exercise: Exercise) -> Prescription {
        guard isStandIn(exercise, in: item) else {
            return Prescription(
                sets: item.targetSets, reps: item.targetReps,
                restSeconds: item.restSeconds, seconds: item.targetSeconds,
                weight: item.targetWeight, distance: item.targetDistance,
                speed: item.targetSpeed, incline: item.targetIncline,
                resistance: item.targetResistance)
        }
        let bar = exercise.loadingKind.showsPlateMath ? exercise.barWeight : 0
        let crossesOver = exercise.kind != (item.exercise?.kind ?? exercise.kind)
        guard crossesOver else {
            return Prescription(sets: item.targetSets, reps: item.targetReps,
                                restSeconds: item.restSeconds,
                                seconds: item.targetSeconds, weight: bar)
        }
        // Across the lifting/cardio line the slot has NO shape to lend. A
        // treadmill slot is 1 × 0 with no rest, so a leg press standing in for
        // it opened on zero reps, no cooldown, and ticked itself done after one
        // set; a squat slot has no minutes, so a rower standing in for it was
        // asked for nothing. Neither is a smaller version of the plan — it is a
        // new slot for the day, so it opens on what a new slot opens on.
        let fresh = defaults(near: item)
        return exercise.isCardio
            ? Prescription(sets: 1, reps: 0, restSeconds: 0, seconds: fresh.cardioSeconds)
            : Prescription(sets: fresh.targetSets, reps: fresh.targetReps,
                           restSeconds: fresh.restSeconds, seconds: 0, weight: bar)
    }

    /// The plan defaults, READ — never made. `PlanDefaults.current` inserts a
    /// row when there is none, and this is called from view bodies and from the
    /// snapshot builder, neither of which may write. An unsaved `PlanDefaults()`
    /// carries the same numbers a first-use row would.
    private static func defaults(near item: PlanItem) -> PlanDefaults {
        (try? item.modelContext?.fetch(FetchDescriptor<PlanDefaults>()).first) ?? PlanDefaults()
    }
}
