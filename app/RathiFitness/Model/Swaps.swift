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
        (item.swaps ?? [])
            // A deleted row stays in the relationship until pending changes are
            // processed — the trap `Sessions.pruneEmpty` documents. Without
            // this, swapping back leaves the bike on screen until the next save.
            .filter { !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: date) }
            .max { $0.date < $1.date }?
            .exercise
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

    /// Do `exercise` in this slot today. One row per slot per day, so changing
    /// your mind replaces rather than stacks — and choosing the slot's own
    /// exercise is how you swap back, not a swap of a thing for itself.
    static func put(_ exercise: Exercise, in item: PlanItem,
                    context: ModelContext, now: Date = .now,
                    calendar: Calendar = .current) {
        clear(item, context: context, on: now, calendar: calendar)
        guard isStandIn(exercise, in: item) else { return }
        context.insert(Swap(item: item, exercise: exercise, date: now))
    }

    /// Back to the plan. Sets already logged against the stand-in stay where
    /// they are — they happened.
    static func clear(_ item: PlanItem, context: ModelContext,
                      on date: Date = .now, calendar: Calendar = .current) {
        for swap in item.swaps ?? [] where calendar.isDate(swap.date, inSameDayAs: date) {
            context.delete(swap)
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

        // Counted over every past swap in this slot, today's included.
        var uses: [String: (count: Int, latest: Date)] = [:]
        for swap in item.swaps ?? [] where !swap.isDeleted {
            guard let slug = swap.exercise?.slug else { continue }
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
    static func takenSlugs(around item: PlanItem, on date: Date = .now,
                           calendar: Calendar = .current) -> Set<String> {
        var taken = Set<String>()
        if let own = item.exercise?.slug { taken.insert(own) }
        for other in item.day?.orderedItems ?? []
        where other.persistentModelID != item.persistentModelID {
            if let slug = other.exercise?.slug { taken.insert(slug) }
            if let slug = standIn(for: other, on: date, calendar: calendar)?.slug {
                taken.insert(slug)
            }
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
        // Across the lifting/cardio line the set count means something else —
        // "3 sets" of bench is not "3 intervals" on a rower — so cardio
        // standing in for a lift is one bout.
        let crossesOver = exercise.kind != (item.exercise?.kind ?? exercise.kind)
        return Prescription(
            sets: crossesOver && exercise.isCardio ? 1 : item.targetSets,
            reps: item.targetReps,
            restSeconds: item.restSeconds,
            seconds: item.targetSeconds,
            weight: exercise.loadingKind.showsPlateMath ? exercise.barWeight : 0)
    }
}
