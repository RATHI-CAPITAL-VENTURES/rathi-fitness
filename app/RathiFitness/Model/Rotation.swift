import Foundation

/// When you train, and what comes next.
///
/// The first model bound a workout to a weekday — `Push A = Wednesday` — which
/// cannot express the common case: **you train on fixed days, but the content
/// rotates.** Three sessions a week through a four-day rotation means the
/// pairing drifts every week (Sat A, Tue B, Thu C, Sat D, Tue A…), so no fixed
/// day-to-weekday mapping is ever right for more than seven days.
///
/// The position in the rotation is **derived, never stored.** A cursor that is
/// incremented on completion goes wrong the first time you log a session late,
/// delete one, or train twice in a day, and nothing tells you it has. Counting
/// the sessions you have actually done is self-correcting: skip a week and you
/// pick up exactly where you left off, which is what a rotation is for.
enum Rotation {

    enum Mode: String, CaseIterable, Identifiable {
        /// Each workout belongs to a weekday. Good for a fixed weekly split.
        case weekday
        /// You train on chosen weekdays and the workouts cycle in order.
        case rotation
        /// You train every N days, whenever that lands, and they cycle.
        case everyNDays

        var id: String { rawValue }
        var label: String {
            switch self {
            case .weekday: return "Same workout each weekday"
            case .rotation: return "Rotating, on chosen days"
            case .everyNDays: return "Rotating, every N days"
            }
        }
    }

    struct Config: Equatable {
        var mode: Mode = .weekday
        /// `Calendar` weekday numbers, 1 = Sunday.
        var trainingWeekdays: Set<Int> = [3, 5, 7]      // Tue, Thu, Sat
        var everyNDays: Int = 2
    }

    /// Is `date` a day you intend to train?
    ///
    /// For `everyNDays` this needs the last session, because "every 2 days"
    /// means two days after the last one you actually did — not every even
    /// numbered day in the calendar.
    static func isTrainingDay(_ date: Date, config: Config, lastSession: Date?,
                              calendar: Calendar = .current) -> Bool {
        switch config.mode {
        case .weekday, .rotation:
            return config.trainingWeekdays.contains(calendar.component(.weekday, from: date))
        case .everyNDays:
            guard let last = lastSession else { return true }
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: date)).day ?? 0
            return days >= max(1, config.everyNDays)
        }
    }

    /// Which workout is up on `date`, as an index into the rotation.
    ///
    /// - Parameter sessionDates: every date you have logged a set on. Duplicates
    ///   and ordering do not matter; they are reduced to distinct days here so a
    ///   caller cannot get it subtly wrong.
    ///
    /// Sessions **on** `date` do not advance it: mid-workout you are still doing
    /// today's workout, not tomorrow's.
    static func index(on date: Date, sessionDates: [Date], dayCount: Int,
                      calendar: Calendar = .current) -> Int? {
        guard dayCount > 0 else { return nil }
        let today = calendar.startOfDay(for: date)
        let completedBefore = Set(sessionDates.map { calendar.startOfDay(for: $0) })
            .filter { $0 < today }
            .count
        return completedBefore % dayCount
    }

    /// The next training date at or after `from`. Used to say "next up, Saturday".
    static func nextTrainingDay(from: Date, config: Config, lastSession: Date?,
                                calendar: Calendar = .current) -> Date? {
        for offset in 0...14 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: from)
            else { continue }
            if isTrainingDay(candidate, config: config, lastSession: lastSession,
                             calendar: calendar) {
                return calendar.startOfDay(for: candidate)
            }
        }
        return nil
    }

    /// "Tue, Thu and Sat" — for a settings row that has to be read, not parsed.
    static func describe(_ config: Config) -> String {
        switch config.mode {
        case .weekday:
            return "each workout on its own weekday"
        case .rotation:
            let names = config.trainingWeekdays.sorted().compactMap { number -> String? in
                Weekdays.all.first { $0.number == number }?.name
            }
            guard !names.isEmpty else { return "no training days chosen" }
            let short = names.map { String($0.prefix(3)) }
            if short.count == 1 { return short[0] }
            return short.dropLast().joined(separator: ", ") + " and " + short[short.count - 1]
        case .everyNDays:
            return config.everyNDays == 1 ? "every day" : "every \(config.everyNDays) days"
        }
    }
}
