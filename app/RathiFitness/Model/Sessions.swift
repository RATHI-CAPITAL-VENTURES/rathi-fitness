import Foundation
import SwiftData

/// Opening, closing and backfilling workouts.
///
/// The rule is deliberately not a clock: **a session opens on the first set
/// logged against a given planned day, and opening one closes any other.** A
/// gap heuristic — "more than three hours apart is a new workout" — was
/// considered and rejected, because it is wrong in both directions on exactly
/// the days that matter: a long session with a break in it splits in two, and a
/// lift that runs straight into cardio merges into one. A rule that reads the
/// user's actual choice of workout cannot be wrong about it.
enum Sessions {

    /// Today's open session for `day`, opening one if there is none.
    ///
    /// Call this immediately before writing a set. It is the only place a
    /// session is created, so there is one answer to "when does a workout
    /// start" rather than one per screen.
    @discardableResult
    static func current(for day: PlannedDay?, in context: ModelContext,
                        now: Date = .now, calendar: Calendar = .current) -> Session? {
        let open = (try? context.fetch(FetchDescriptor<Session>()))?
            .filter(\.isOpen) ?? []

        if let match = open.first(where: {
            calendar.isDate($0.startedAt, inSameDayAs: now) && isSame($0.plannedDay, day)
        }) {
            return match
        }

        // A different workout is starting, so whatever was open is over. This is
        // what makes two-a-days two records: the morning's session is closed by
        // the evening's first set rather than by a timer nobody set.
        for stale in open { close(stale, in: context) }

        let session = Session(startedAt: now,
                              dayName: day?.name ?? Session.unnamed,
                              plannedDay: day)
        context.insert(session)
        return session
    }

    /// End a workout. Idempotent — finishing a finished session does nothing.
    ///
    /// `endedAt` is the last set logged, not the moment you tapped the button,
    /// so the span Apple Health receives is the workout rather than however long
    /// the app stayed open afterwards.
    static func close(_ session: Session, in context: ModelContext) {
        guard session.isOpen else { return }
        session.endedAt = session.orderedSets.last?.date ?? session.startedAt
    }

    /// Close anything left open on a previous day.
    ///
    /// The app can be killed mid-workout, and an open session from Tuesday
    /// would otherwise still be "current" on Thursday — quietly collecting
    /// Thursday's sets into Tuesday's workout.
    static func closeStale(in context: ModelContext,
                           now: Date = .now, calendar: Calendar = .current) {
        let open = (try? context.fetch(FetchDescriptor<Session>()))?.filter(\.isOpen) ?? []
        for session in open where !calendar.isDate(session.startedAt, inSameDayAs: now) {
            close(session, in: context)
        }
    }

    /// Give every set written before sessions existed one to belong to.
    ///
    /// One session per day, which is exactly the assumption the old code made —
    /// so this preserves history rather than inventing a shape for it. The name
    /// is inferred from which planned day the exercises best match, because
    /// "Workout, Workout, Workout" down the past-days list is a worse answer
    /// than a good guess, and the guess is recorded as text that can be edited.
    ///
    /// Idempotent: only sets with no session are touched.
    @discardableResult
    static func backfill(in context: ModelContext,
                         calendar: Calendar = .current) throws -> Int {
        let orphans = try context.fetch(FetchDescriptor<SetEntry>())
            .filter { $0.session == nil }
        guard !orphans.isEmpty else { return 0 }

        let days = try context.fetch(FetchDescriptor<PlannedDay>())
        let byDay = Dictionary(grouping: orphans) { calendar.startOfDay(for: $0.date) }

        for (_, sets) in byDay {
            let ordered = sets.sorted { $0.date < $1.date }
            guard let first = ordered.first, let last = ordered.last else { continue }
            let match = bestMatch(for: ordered, among: days)
            let session = Session(startedAt: first.date,
                                  dayName: match?.name ?? Session.unnamed,
                                  plannedDay: match)
            session.endedAt = last.date
            context.insert(session)
            for entry in ordered { entry.session = session }
        }
        return byDay.count
    }

    /// Which planned day these sets look most like, by how many of its
    /// exercises appear. `nil` when nothing overlaps, rather than a wrong label.
    static func bestMatch(for sets: [SetEntry], among days: [PlannedDay]) -> PlannedDay? {
        let performed = Set(sets.compactMap { $0.exercise?.slug })
        guard !performed.isEmpty else { return nil }

        var best: (day: PlannedDay, score: Int)?
        for day in days {
            let planned = Set(day.orderedItems.compactMap { $0.exercise?.slug })
            let score = planned.intersection(performed).count
            guard score > 0 else { continue }
            if best == nil || score > best!.score { best = (day, score) }
        }
        return best?.day
    }

    /// Same planned day, including "both are unscheduled".
    ///
    /// Compared by `persistentModelID` rather than by name: two days can share a
    /// name, and a rename mid-workout must not split the session in half.
    private static func isSame(_ a: PlannedDay?, _ b: PlannedDay?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.persistentModelID == y.persistentModelID
        default: return false
        }
    }
}
