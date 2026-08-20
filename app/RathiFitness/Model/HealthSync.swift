import Foundation

/// The decisions about Health, with no HealthKit in them.
///
/// `HealthBridge` is the part that talks to Apple and cannot be unit-tested
/// without a device and a human tapping a permission sheet. Everything that can
/// be wrong on its own — which samples to import, what counts as the same
/// weigh-in, what a workout's bounds are — lives here, where it is testable.
enum HealthSync {

    struct Sample: Equatable {
        let date: Date
        let pounds: Double
    }

    /// Samples worth turning into `WeighIn` rows.
    ///
    /// Health is the source of truth for body mass once it is connected: the
    /// scale writes there, and typing a number into this app is the fallback,
    /// not the main path. So this imports anything Health has that we do not,
    /// matched by **day** rather than by timestamp — the same morning weigh-in
    /// arrives from a scale at 07:12:04 and from a manual entry at 07:12, and
    /// importing both would draw two points on the chart for one step onto a
    /// scale.
    static func samplesToImport(_ samples: [Sample],
                                existing: [Date],
                                calendar: Calendar = .current) -> [Sample] {
        let have = Set(existing.map { calendar.startOfDay(for: $0) })
        var seen = Set<Date>()
        var out: [Sample] = []
        // Newest first, so if Health holds several readings for one day we keep
        // the latest — which is the one that matches what the Health app shows.
        for sample in samples.sorted(by: { $0.date > $1.date }) {
            let day = calendar.startOfDay(for: sample.date)
            guard !have.contains(day), !seen.contains(day) else { continue }
            seen.insert(day)
            out.append(sample)
        }
        return out.sorted { $0.date < $1.date }
    }

    /// What to hand HealthKit for a finished session.
    struct WorkoutBounds: Equatable {
        let start: Date
        let end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The session's real extent: first set to last set, plus the rest you took
    /// after the last one.
    ///
    /// Deliberately **no energy estimate.** A MET formula would let us write a
    /// calorie number, and it would be a guess landing in the same ring as the
    /// watch's measured numbers. A workout with an honest duration and no energy
    /// is worth more than one with a fabricated burn.
    static func bounds(forSetsAt dates: [Date],
                       trailingRest: TimeInterval = 90) -> WorkoutBounds? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        // A single logged set is a real session, but zero-length workouts are
        // rejected by HealthKit, so give it the rest that followed it.
        let end = last.addingTimeInterval(trailingRest)
        return WorkoutBounds(start: first, end: end)
    }

    /// Sessions old enough to be finished, and not already sent.
    ///
    /// Only whole past days: writing today's workout while he is still in the
    /// gym would either be wrong or need updating, and HealthKit workouts are
    /// awkward to amend. Tomorrow it goes over complete.
    static func sessionsReadyToExport(setDates: [Date],
                                      alreadyExported: Set<Date>,
                                      now: Date = .now,
                                      calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let days = Set(setDates.map { calendar.startOfDay(for: $0) })
        return days
            .filter { $0 < today && !alreadyExported.contains($0) }
            .sorted()
    }

    static let poundsPerKilogram = 2.2046226218

    static func pounds(fromKilograms kg: Double) -> Double {
        (kg * poundsPerKilogram * 10).rounded() / 10
    }

    static func kilograms(fromPounds lb: Double) -> Double {
        lb / poundsPerKilogram
    }
}
