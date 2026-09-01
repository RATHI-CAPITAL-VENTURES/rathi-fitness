import Foundation

/// How much you moved, and whether it was the most you ever have.
///
/// Named `Tally` rather than `Progress` because Foundation already has a
/// `Progress` class, and the shadow made the name ambiguous in every file that
/// imports Foundation — which is all of them.
///
/// Pure functions over sets, so every claim the app makes about progress is
/// testable without a database. The reinforcement is the point: a session is
/// four exercises and a lot of standing around, and "you moved 12,830 lb" is
/// the only number that makes the whole hour add up to something.
enum Tally {

    // MARK: - Volume

    struct Set: Equatable {
        let weight: Double
        let reps: Int
        /// Warm-ups are excluded from everything below. Left as a property on
        /// the value rather than filtered by the caller so there is exactly one
        /// place that decides what counts, and callers cannot forget.
        var kind: SetKind = .working
        /// The weight made this set EASIER — an assisted pull-up machine. Carried
        /// on the value for the same reason `kind` is: every rule about it lives
        /// in one place and no caller can forget to apply it.
        var assisted: Bool = false

        /// Assistance is not tonnage.
        ///
        /// This is the worst of the assisted bugs, because the number it
        /// produces is plausible: 100 lb of help × 8 reps reads as 800 lb
        /// "moved", so the *more* help you needed the better your session
        /// looked. Excluded outright rather than converted — turning it into
        /// bodyweight-minus-assistance means storing a bodyweight per set and
        /// guessing for every day you did not weigh yourself, which is the same
        /// invention that keeps push-ups out of tonnage.
        var volume: Double { (kind.counts && !assisted) ? weight * Double(reps) : 0 }
        var counts: Bool { kind.counts }
    }

    /// Total load moved: every working set's weight × reps.
    ///
    /// Warm-ups do not count. Neither do bodyweight movements, which is honest
    /// rather than clever — guessing what fraction of you a push-up lifts would
    /// put an invented number into the one figure that is supposed to be
    /// countable. Assisted machines do not count either, and for a sharper
    /// reason: their weight would count the wrong way round.
    static func volume(_ sets: [Set]) -> Double {
        sets.reduce(0) { $0 + $1.volume }
    }

    /// Working sets only. What "3 × 8" means, and what a muscle-group count is
    /// counting.
    static func workingSets(_ sets: [Set]) -> [Set] { sets.filter(\.counts) }

    /// Tonnage reads better than a six-digit number of pounds.
    /// `12830` → `12,830 lb`; `41200` → `20.6 tons`.
    static func volumeText(_ pounds: Double) -> String {
        guard pounds > 0 else { return "nothing yet" }
        if pounds < 20_000 {
            let whole = Int(pounds.rounded())
            return "\(grouped(whole)) lb"
        }
        return String(format: "%.1f tons", pounds / 2000)
    }

    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    // MARK: - Estimated one-rep max
    //
    // Epley. Every formula is a fit to somebody else's data and they disagree
    // past about ten reps, which is why this is only ever shown as "e1RM" and
    // never as a number to go and attempt.

    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        // Past 12 reps the estimate stops meaning anything; cap rather than
        // extrapolate a number that would flatter a set of twenty.
        let capped = min(reps, 12)
        return weight * (1 + Double(capped) / 30)
    }

    // MARK: - Records

    enum Record: Equatable {
        /// The heaviest weight ever moved for a rep on this lift.
        case heaviest(Double)
        /// The least help ever needed on an assisted machine — the mirror of
        /// `heaviest`, and the reason it needs its own case rather than a
        /// reused one: "Heaviest ever — 100 lb" on a pull-up assist is the app
        /// congratulating you for getting weaker.
        case leastAssistance(Double)
        /// Most reps ever at this much help or LESS.
        case repsAssisted(Int, at: Double)
        /// A better estimated max, without the weight itself being a record —
        /// 185 × 9 beats 185 × 8 and beats a lifetime best e1RM.
        case estimatedMax(Double)
        /// Most reps ever at this weight or above.
        case reps(Int, at: Double)

        /// Ranked, so one set announces one thing. Three badges for one set is
        /// confetti; the heaviest lift is the one that matters most.
        var rank: Int {
            switch self {
            case .heaviest, .leastAssistance: return 0
            case .estimatedMax: return 1
            case .reps, .repsAssisted: return 2
            }
        }

        var headline: String {
            switch self {
            case .heaviest(let w): return "Heaviest ever — \(Fmt.weight(w)) lb"
            case .estimatedMax(let e): return "Best estimated max — \(Fmt.weight(e.rounded())) lb"
            case .reps(let r, let w): return "Most reps at \(Fmt.weight(w)) — \(r)"
            case .leastAssistance(let w):
                return w == 0 ? "Unassisted — no help at all"
                              : "Least help ever — \(Fmt.weight(w)) lb"
            case .repsAssisted(let r, let w):
                return w == 0 ? "Most reps unassisted — \(r)"
                              : "Most reps at \(Fmt.weight(w)) lb of help — \(r)"
            }
        }
    }

    /// What (if anything) the set just logged beat.
    ///
    /// `history` must NOT include the new set. Ties do not count: matching your
    /// best is not a record, and an app that says it is teaches you to
    /// disbelieve it.
    static func records(for candidate: Set, history rawHistory: [Set]) -> [Record] {
        // A warm-up cannot set a record, and warm-ups in the history cannot
        // stop one: a heavy single last week should not be beaten by the fact
        // you once warmed up heavier than you are lifting today.
        //
        // Zero is a legitimate weight on an assisted machine — it is the best
        // one there is, the day you finally need no help — so the `> 0` guard
        // applies only to lifts.
        guard candidate.counts, candidate.reps > 0,
              candidate.assisted || candidate.weight > 0 else { return [] }
        let history = workingSets(rawHistory)
        if candidate.assisted { return assistedRecords(for: candidate, history: history) }
        var found: [Record] = []

        let heaviest = history.map(\.weight).max() ?? 0
        if candidate.weight > heaviest { found.append(.heaviest(candidate.weight)) }

        let bestMax = history
            .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        let candidateMax = estimatedOneRepMax(weight: candidate.weight, reps: candidate.reps)
        // A hair over is float noise, not a record.
        if candidateMax > bestMax + 0.5 { found.append(.estimatedMax(candidateMax)) }

        let repsAtWeight = history
            .filter { $0.weight >= candidate.weight }.map(\.reps).max() ?? 0
        if candidate.reps > repsAtWeight && !history.isEmpty {
            found.append(.reps(candidate.reps, at: candidate.weight))
        }

        return found.sorted { $0.rank < $1.rank }
    }

    /// The same three questions, asked the other way up.
    ///
    /// No estimated one-rep max: Epley on a counterweight is arithmetic without
    /// a meaning. It would produce a number, which is exactly the danger.
    private static func assistedRecords(for candidate: Set, history: [Set]) -> [Record] {
        var found: [Record] = []

        // `.greatestFiniteMagnitude` so the first set ever recorded is a record,
        // which is what the heaviest-ever branch does with its `?? 0`.
        let least = history.map(\.weight).min() ?? .greatestFiniteMagnitude
        if candidate.weight < least { found.append(.leastAssistance(candidate.weight)) }

        // A rep record only counts at your hardest setting to date — this is
        // STRICTER than the resisted rule, deliberately.
        //
        // The mirror of "most reps at this weight or above" would be "most reps
        // at this help or less", and it is technically true and practically
        // awful: adding help almost always buys reps, so every deload would
        // manufacture a record and the app would cheer each step backwards.
        // That is the exact failure this whole flag exists to stop, so the
        // claim is only made when you are at least as unassisted as you have
        // ever been.
        if candidate.weight <= least {
            let repsAtOrBelow = history
                .filter { $0.weight <= candidate.weight }.map(\.reps).max() ?? 0
            if candidate.reps > repsAtOrBelow && !history.isEmpty {
                found.append(.repsAssisted(candidate.reps, at: candidate.weight))
            }
        }

        return found.sorted { $0.rank < $1.rank }
    }

    /// The one thing to say about a set, or nothing.
    static func headline(for candidate: Set, history: [Set]) -> String? {
        records(for: candidate, history: history).first?.headline
    }

    // MARK: - Sets per muscle group per week
    //
    // The standard hypertrophy question, and the one Trends could not answer.
    // Secondary movers count as half a set — the usual convention, written down
    // here so nobody has to wonder why the numbers are fractional.

    static let secondaryWeight = 0.5

    struct MuscleWork: Identifiable, Equatable {
        let muscle: MuscleGroup
        var sets: Double
        var id: String { muscle.rawValue }
    }

    struct LoggedSet {
        let date: Date
        let kind: SetKind
        let primary: MuscleGroup
        let secondary: [MuscleGroup]
    }

    /// Working sets per muscle over a window, heaviest first.
    static func muscleWork(_ sets: [LoggedSet], since: Date) -> [MuscleWork] {
        var totals: [MuscleGroup: Double] = [:]
        for set in sets where set.kind.counts && set.date >= since {
            totals[set.primary, default: 0] += 1
            for muscle in set.secondary { totals[muscle, default: 0] += secondaryWeight }
        }
        return totals
            .filter { $0.key != .other && $0.value > 0 }
            .map { MuscleWork(muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets == $1.sets ? $0.muscle.label < $1.muscle.label : $0.sets > $1.sets }
    }

    // MARK: - What to do next
    //
    // Not a programme. One sentence, from the last two times you did this lift,
    // and only when the answer is obvious enough to be worth saying.

    struct Suggestion: Equatable {
        let weight: Double
        let reps: Int
        let because: String
    }

    /// - Parameters:
    ///   - lastSession: working sets from the most recent day this lift was done.
    ///   - target: the plan's rep target.
    static func nextTarget(lastSession: [Set], target: Int,
                           step: Double = 5, assisted: Bool = false) -> Suggestion? {
        let working = workingSets(lastSession)
        // The hardest set you did. On an assisted machine that is the one with
        // the LEAST help, not the most weight — get this backwards and the app
        // progresses you off your easiest set.
        let anchor = assisted ? working.map(\.weight).min() : working.map(\.weight).max()
        guard let anchor, assisted || anchor > 0 else { return nil }
        let atWeight = working.filter { $0.weight == anchor }
        guard !atWeight.isEmpty else { return nil }

        // Every set hit the target: it gets harder. Which direction that is
        // depends on the machine — and assistance floors at zero, because
        // negative help is not a thing you can dial in.
        if atWeight.allSatisfy({ $0.reps >= target }) {
            let next = assisted ? max(0, anchor - step) : anchor + step
            if assisted && anchor == 0 {
                // Already unassisted. There is nowhere lower to go, and telling
                // someone to take off help they are not using is nonsense.
                return Suggestion(weight: 0, reps: target,
                                  because: "you're doing these unassisted — try the real thing")
            }
            return Suggestion(weight: next, reps: target,
                              because: "you hit every rep last time")
        }
        // Missed badly enough that changing it would be optimism.
        let best = atWeight.map(\.reps).max() ?? 0
        if best < target - 2 {
            return Suggestion(weight: anchor, reps: target,
                              because: "last time stalled at \(best) — same \(assisted ? "help" : "weight") again")
        }
        return Suggestion(weight: anchor, reps: target,
                          because: assisted ? "one more rep than last time and the help comes off"
                                            : "one more rep than last time and it goes up")
    }

    // MARK: - Cardio
    //
    // Deliberately a separate vocabulary rather than an extension of `Set`.
    // Tonnage is weight × reps and a treadmill has neither; folding cardio into
    // volume would put an invented number into the one figure on Today that is
    // supposed to be countable. A bout contributes MINUTES, and minutes are
    // reported as minutes.

    struct Bout: Equatable {
        var seconds: Int = 0
        var distance: Double = 0
        var incline: Double = 0
        var speed: Double = 0
        var resistance: Double = 0
        var heartRate: Int = 0

        /// Miles per hour actually achieved. The `speed` field is whatever the
        /// console read when you glanced at it; this is the whole bout.
        var averageSpeed: Double? {
            guard seconds > 0, distance > 0 else { return nil }
            return distance / (Double(seconds) / 3600)
        }
    }

    /// Total time on cardio. Minutes, because that is the unit every guideline
    /// about it is written in.
    static func cardioMinutes(_ bouts: [Bout]) -> Double {
        Double(bouts.reduce(0) { $0 + $1.seconds }) / 60
    }

    static func cardioDistance(_ bouts: [Bout]) -> Double {
        bouts.reduce(0) { $0 + $1.distance }
    }

    /// What a cardio bout beat.
    ///
    /// Three, and no more. Distance, time and average speed are the questions a
    /// treadmill answers; a "best incline" record would reward walking up a
    /// wall for ninety seconds, which is not a thing to be encouraged by an app.
    enum CardioRecord: Equatable {
        case farthest(Double)
        case longest(Int)
        case fastest(Double)

        var rank: Int {
            switch self {
            case .farthest: return 0
            case .fastest: return 1
            case .longest: return 2
            }
        }

        var headline: String {
            switch self {
            case .farthest(let mi): return "Furthest ever — \(Fmt.distance(mi)) mi"
            case .longest(let s): return "Longest ever — \(Fmt.minutes(s))"
            case .fastest(let mph): return "Fastest ever — \(Fmt.rate(mph)) mph"
            }
        }
    }

    /// `history` must NOT include the new bout. Same rule as lifting: ties are
    /// not records.
    static func cardioRecords(for candidate: Bout, history: [Bout]) -> [CardioRecord] {
        guard candidate.seconds > 0 || candidate.distance > 0 else { return [] }
        var found: [CardioRecord] = []

        let farthest = history.map(\.distance).max() ?? 0
        if candidate.distance > farthest && candidate.distance > 0 {
            found.append(.farthest(candidate.distance))
        }

        let longest = history.map(\.seconds).max() ?? 0
        if candidate.seconds > longest && candidate.seconds > 0 {
            found.append(.longest(candidate.seconds))
        }

        // Only against bouts that HAVE an average speed. A twenty-minute row
        // with no distance recorded is not evidence you have never gone faster.
        let comparable = history.compactMap(\.averageSpeed)
        if let mine = candidate.averageSpeed,
           mine > (comparable.max() ?? 0) + 0.05, !comparable.isEmpty {
            found.append(.fastest(mine))
        }

        return found.sorted { $0.rank < $1.rank }
    }

    static func cardioHeadline(for candidate: Bout, history: [Bout]) -> String? {
        cardioRecords(for: candidate, history: history).first?.headline
    }

    // MARK: - Showing up
    //
    // Deliberately NOT a streak, and the distinction is the whole design.
    //
    // `docs/RESEARCH.md` ruled streaks out for a good reason — they turn a
    // deload week into a failure state — and the reason survives scrutiny: a
    // counter that resets to zero is reported to make people abandon the habit
    // *harder* after one miss than no tracking at all, because the number does
    // not degrade, it detonates. Everything below is the same information with
    // that edge removed. There is no zero to fall to. A bad week moves a
    // percentage by a few points and rolls off the back in twelve.
    //
    // What makes it possible here and not in Duolingo or the Move ring: this
    // app KNOWS the schedule. `Rotation.Config` says which days you meant to
    // train, so a rest day is not an absence of training, it is the plan. The
    // denominator is what you intended, never the calendar.

    /// One week of the band.
    struct Week: Equatable, Identifiable {
        /// Start of the week in the user's own calendar, so it honours
        /// `firstWeekday` rather than assuming Monday.
        let start: Date
        /// Workouts the schedule asked for.
        let planned: Int
        /// Workouts you did.
        let done: Int
        /// The week `now` falls in. It cannot have been failed yet, so it is
        /// drawn differently and left out of the percentage — a Monday morning
        /// that reads "0 of 3" is the app telling you off for not having
        /// finished a week that has barely started.
        let inProgress: Bool

        var id: Date { start }

        var met: Bool { planned > 0 && done >= planned }

        /// 0…1, and capped on purpose: four sessions in a three-session week is
        /// a full week, not a week and a third.
        var fraction: Double {
            guard planned > 0 else { return 0 }
            return min(Double(done) / Double(planned), 1)
        }
    }

    /// Twelve weeks of showing up, and the one number underneath.
    struct Consistency: Equatable {
        /// Oldest first, so the strip reads left to right like a calendar.
        let weeks: [Week]
        /// Share of planned workouts actually done, over the FINISHED weeks.
        /// Nil until at least one week has finished — a percentage computed
        /// from a Tuesday is not a fact about anything.
        let adherence: Double?
        /// The two halves of that fraction, for a caption that can be checked.
        let credited: Int
        let planned: Int

        var isEmpty: Bool { weeks.isEmpty }
    }

    /// How many workouts a week the schedule asks for.
    ///
    /// Each mode answers differently because each means a different thing:
    /// a weekday split does every day it has; a rotation does its chosen days;
    /// every-N-days does not think in weeks at all, so it gets the floor —
    /// `every 2 days` is 3.5 a week and a 3-session week must not be a failure.
    static func weeklyTarget(_ config: Rotation.Config, plannedDays: Int) -> Int {
        switch config.mode {
        case .weekday:
            return plannedDays
        case .rotation:
            return config.trainingWeekdays.count
        case .everyNDays:
            return max(1, 7 / max(1, config.everyNDays))
        }
    }

    /// The band.
    ///
    /// - Parameter sessionDates: `Session.startedAt` for every workout — the
    ///   same input `Rotation.index` counts. **Sessions, not days**, which
    ///   matters for a two-a-day: two workouts on Saturday count twice here
    ///   because the plan asks for workouts, not attendances, and because
    ///   v0.3.1 already made the session the unit everywhere else. Two answers
    ///   to "how much did I train this week" in one app would be worse than
    ///   either answer alone.
    static func consistency(sessionDates: [Date],
                            config: Rotation.Config,
                            plannedDays: Int,
                            weeks limit: Int = 12,
                            now: Date = .now,
                            calendar: Calendar = .current) -> Consistency {
        let empty = Consistency(weeks: [], adherence: nil, credited: 0, planned: 0)
        let target = weeklyTarget(config, plannedDays: plannedDays)
        guard target > 0,
              limit > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        else { return empty }

        // Nothing before your first workout is a week you missed. A fresh
        // install opening on twelve grey marks is twelve failures you did not
        // earn, on the screen you see first.
        guard let firstSession = sessionDates.min(),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstSession)
        else { return empty }

        var starts: [Date] = []
        var cursor = thisWeek.start
        while starts.count < limit, cursor >= firstWeek.start {
            starts.append(cursor)
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor)
            else { break }
            cursor = previous
        }

        let weeks: [Week] = starts.reversed().map { start in
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let done = sessionDates.filter { $0 >= start && $0 < end }.count
            return Week(start: start, planned: target, done: done,
                        inProgress: start == thisWeek.start)
        }

        let finished = weeks.filter { !$0.inProgress }
        let planned = finished.reduce(0) { $0 + $1.planned }
        // Credited per week, capped at that week's target: a big week must not
        // pay for a missed one. Six sessions one week and none the next is not
        // the same as three and three, and a percentage that says it is has
        // stopped measuring consistency.
        let credited = finished.reduce(0) { $0 + min($1.done, $1.planned) }

        return Consistency(
            weeks: weeks,
            adherence: planned > 0 ? Double(credited) / Double(planned) : nil,
            credited: credited,
            planned: planned)
    }

    // MARK: - Comparing a session to the last one like it

    struct SessionComparison: Equatable {
        let volume: Double
        let previousVolume: Double?

        var delta: Double? { previousVolume.map { volume - $0 } }

        /// What to say under the tonnage. Nil when there is nothing to compare
        /// against — a first session should not be told it is up 100%.
        var line: String? {
            guard let previous = previousVolume, previous > 0, let delta else { return nil }
            if abs(delta) < previous * 0.01 { return "same as last time" }
            let percent = abs(delta) / previous * 100
            let direction = delta > 0 ? "more" : "less"
            return String(format: "%@ %@ than last time", pctText(percent), direction)
        }

        private func pctText(_ p: Double) -> String {
            p < 10 ? String(format: "%.0f%%", p) : String(format: "%.0f%%", p)
        }
    }
}


extension SetEntry {
    /// This row as a value `Tally` can reason about.
    ///
    /// Exists so nothing constructs a `Tally.Set` by hand. Nine call sites did,
    /// each spelling out weight/reps/kind, and every one of them silently
    /// defaulted `assisted` to false — which is exactly how a pull-up assist
    /// ends up counted as tonnage. One converter means adding a rule to the
    /// value is a change here and nowhere else.
    var tally: Tally.Set {
        Tally.Set(weight: weight, reps: reps, kind: setKind,
                  assisted: exercise?.assisted ?? false)
    }
}
