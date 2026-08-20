import Foundation

/// How much you moved, and whether it was the most you ever have.
///
/// Pure functions over sets, so every claim the app makes about progress is
/// testable without a database. The reinforcement is the point: a session is
/// four exercises and a lot of standing around, and "you moved 12,830 lb" is
/// the only number that makes the whole hour add up to something.
enum Progress {

    // MARK: - Volume

    struct Set: Equatable {
        let weight: Double
        let reps: Int
        var volume: Double { weight * Double(reps) }
    }

    /// Total load moved: every set's weight × reps.
    ///
    /// Bodyweight movements contribute nothing, which is honest rather than
    /// clever — guessing what fraction of you a push-up lifts would put an
    /// invented number into the one figure that is supposed to be countable.
    static func volume(_ sets: [Set]) -> Double {
        sets.reduce(0) { $0 + $1.volume }
    }

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
    static func records(for candidate: Set, history: [Set]) -> [Record] {
        guard candidate.weight > 0, candidate.reps > 0 else { return [] }
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
