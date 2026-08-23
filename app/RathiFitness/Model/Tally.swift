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

        var volume: Double { kind.counts ? weight * Double(reps) : 0 }
        var counts: Bool { kind.counts }
    }

    /// Total load moved: every working set's weight × reps.
    ///
    /// Warm-ups do not count. Neither do bodyweight movements, which is honest
    /// rather than clever — guessing what fraction of you a push-up lifts would
    /// put an invented number into the one figure that is supposed to be
    /// countable.
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
        /// A better estimated max, without the weight itself being a record —
        /// 185 × 9 beats 185 × 8 and beats a lifetime best e1RM.
        case estimatedMax(Double)
        /// Most reps ever at this weight or above.
        case reps(Int, at: Double)

        /// Ranked, so one set announces one thing. Three badges for one set is
        /// confetti; the heaviest lift is the one that matters most.
        var rank: Int {
            switch self {
            case .heaviest: return 0
            case .estimatedMax: return 1
            case .reps: return 2
            }
        }

        var headline: String {
            switch self {
            case .heaviest(let w): return "Heaviest ever — \(Fmt.weight(w)) lb"
            case .estimatedMax(let e): return "Best estimated max — \(Fmt.weight(e.rounded())) lb"
            case .reps(let r, let w): return "Most reps at \(Fmt.weight(w)) — \(r)"
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
        guard candidate.counts, candidate.weight > 0, candidate.reps > 0 else { return [] }
        let history = workingSets(rawHistory)
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
                           step: Double = 5) -> Suggestion? {
        let working = workingSets(lastSession)
        guard let heaviest = working.map(\.weight).max(), heaviest > 0 else { return nil }
        let atWeight = working.filter { $0.weight == heaviest }
        guard !atWeight.isEmpty else { return nil }

        // Every set hit the target: the weight goes up.
        if atWeight.allSatisfy({ $0.reps >= target }) {
            return Suggestion(weight: heaviest + step, reps: target,
                              because: "you hit every rep last time")
        }
        // Missed badly enough that more weight would be optimism.
        let best = atWeight.map(\.reps).max() ?? 0
        if best < target - 2 {
            return Suggestion(weight: heaviest, reps: target,
                              because: "last time stalled at \(best) — same weight again")
        }
        return Suggestion(weight: heaviest, reps: target,
                          because: "one more rep than last time and it goes up")
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
