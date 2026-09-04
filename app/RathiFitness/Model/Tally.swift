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

        /// What you weighed when you did this set, if it is known.
        ///
        /// Only assisted work reads it, and only to answer the question the
        /// machine is actually asking: a pull-up assist set moves **you**, less
        /// the help. `nil` means no weigh-in on or before that date.
        var bodyWeight: Double? = nil

        /// Assistance is not tonnage — but the load is not zero either.
        ///
        /// The original bug was counting the HELP as the load: 100 lb of
        /// assistance × 8 reps read as 800 lb "moved", so the more help you
        /// needed the better your session looked. That was fixed by excluding
        /// assisted work outright, on the argument that converting it "means
        /// storing a bodyweight per set and guessing for every day you did not
        /// weigh yourself".
        ///
        /// Half of that argument was right and half was an excuse. Guessing is
        /// still refused — no weigh-in, no tonnage, same as before. But when a
        /// weigh-in *is* known there is nothing to guess: an assisted pull-up
        /// moves `bodyweight − help`, which is a measured number, and dropping
        /// it meant three of this plan's exercises contributed nothing to the
        /// one figure on Today that is supposed to be countable.
        ///
        /// Floored at zero: help exceeding bodyweight is a typo, not negative
        /// work.
        var volume: Double {
            guard kind.counts else { return 0 }
            guard assisted else { return weight * Double(reps) }
            guard let bodyWeight else { return 0 }
            return max(0, bodyWeight - weight) * Double(reps)
        }
        var counts: Bool { kind.counts }
    }

    /// Total load moved: every working set's weight × reps.
    ///
    /// Warm-ups do not count. Neither do bodyweight movements, which is honest
    /// rather than clever — guessing what fraction of you a push-up lifts would
    /// put an invented number into the one figure that is supposed to be
    /// countable. Assisted machines do not count either, and for a sharper
    /// reason: their weight would count the wrong way round.
    /// Bodyweight as of a date, from the weigh-in history.
    ///
    /// Built once and asked many times, because the alternative is a linear
    /// scan of every weigh-in per set. "As of" means the most recent reading on
    /// or before that day — so an old session is valued at what you weighed
    /// then, not at what you weigh now. Using today's weight for all of history
    /// would make last month's tonnage move every time you step on the scale,
    /// which is a trend line that reports the scale rather than the training.
    struct BodyWeightLog {
        /// Ascending by date.
        private let readings: [(date: Date, pounds: Double)]

        init(_ readings: [(date: Date, pounds: Double)]) {
            self.readings = readings.sorted { $0.date < $1.date }
        }

        /// The most recent reading on or before `date`, or `nil` if you had not
        /// weighed yourself yet. `nil` is not a failure — it is the honest
        /// answer, and `volume` refuses to invent one.
        func pounds(on date: Date) -> Double? {
            readings.last { $0.date <= date }?.pounds
        }

        static let unknown = BodyWeightLog([])
    }

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
        // A tenth of a ton is 200 lb and reads as precision nobody has. Keep it
        // under a thousand, where it is a real distinction — "184.8 tons" — and
        // drop it above, where "2250.0 tons" is a decimal point pretending to
        // mean something and "2,250 tons" is the same number, read faster.
        let tons = pounds / 2000
        if tons >= 1_000 { return "\(grouped(Int(tons.rounded()))) tons" }
        let rounded = (tons * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(grouped(Int(rounded))) tons"
            : String(format: "%.1f tons", rounded)
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
                           step: Double = 5) -> Suggestion? {
        let working = workingSets(lastSession)
        // DERIVED, never passed in — and that is the fix, not a tidy-up.
        //
        // This arrived as `assisted: Bool = false`, and `SetView` never passed
        // it. So every assisted machine got the unassisted branch: hit all your
        // reps on the pull-up assist and the app told you to add MORE help,
        // which is the opposite of progress and the opposite of what the
        // branch below was carefully written to do. A default parameter made a
        // wrong answer the quiet one.
        //
        // `Tally.Set` has carried `assisted` since v0.2.0 for exactly this
        // reason — "every rule about it lives in one place and no caller can
        // forget to apply it" — and then this function asked for it separately
        // anyway. Now it does not.
        let assisted = working.contains(where: \.assisted)
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

    /// What the plan asked of a cardio slot.
    struct CardioTarget: Equatable {
        var seconds: Int = 0
        var distance: Double = 0
        var speed: Double = 0
        var incline: Double = 0

        var isEmpty: Bool {
            seconds == 0 && distance == 0 && speed == 0 && incline == 0
        }
    }

    /// One thing to try next time, on a treadmill.
    struct CardioSuggestion: Equatable {
        enum Dimension: Equatable { case duration, distance, speed, incline }
        let dimension: Dimension
        /// Seconds for `.duration`, miles for `.distance`, mph for `.speed`,
        /// percent for `.incline`.
        let value: Double
        let because: String
    }

    /// The cardio answer to "try 190, you hit 185 last time".
    ///
    /// Lifting had this and cardio did not, so a treadmill slot showed the same
    /// prescription for ever and progressive overload stopped at the weights.
    ///
    /// **One dimension at a time, and that is the design.** A treadmill offers
    /// four things to make harder — longer, further, faster, steeper — and
    /// raising several at once is not progression, it is a different workout
    /// that you cannot attribute anything to. So this picks exactly one, in the
    /// order the plan itself prescribes: distance if the plan asks for a
    /// distance, else duration, else speed, else grade. What the plan measures
    /// you by is what it should push.
    ///
    /// Increments are the ones a console actually offers rather than a
    /// percentage: 0.1 mi, a minute, 0.1 mph, 0.5% grade. A suggestion you
    /// cannot dial in is a suggestion you ignore.
    static func nextCardioTarget(lastBout: Bout?,
                                 target: CardioTarget) -> CardioSuggestion? {
        guard let last = lastBout, !target.isEmpty else { return nil }

        // Did last time meet what was asked? Only the measured dimensions get a
        // vote — a slot that prescribes twenty minutes and leaves the speed to
        // how you feel is not failed by running it slowly.
        var met = true
        if target.seconds > 0 { met = met && last.seconds >= target.seconds }
        if target.distance > 0 { met = met && last.distance >= target.distance - 0.001 }

        guard met else {
            let short: String
            if target.seconds > 0, last.seconds < target.seconds {
                short = "you got \(Fmt.minutes(last.seconds)) last time"
            } else {
                short = "you got \(Fmt.distance(last.distance)) mi last time"
            }
            if target.distance > 0 {
                return CardioSuggestion(dimension: .distance, value: target.distance,
                                        because: "\(short) — same again")
            }
            return CardioSuggestion(dimension: .duration, value: Double(target.seconds),
                                    because: "\(short) — same again")
        }

        if target.distance > 0 {
            return CardioSuggestion(dimension: .distance,
                                    value: ((target.distance + 0.1) * 10).rounded() / 10,
                                    because: "you covered the distance last time")
        }
        if target.seconds > 0 {
            return CardioSuggestion(dimension: .duration,
                                    value: Double(target.seconds + 60),
                                    because: "you ran the clock out last time")
        }
        if target.speed > 0 {
            return CardioSuggestion(dimension: .speed,
                                    value: ((target.speed + 0.1) * 10).rounded() / 10,
                                    because: "that pace held last time")
        }
        return CardioSuggestion(dimension: .incline,
                                value: ((target.incline + 0.5) * 10).rounded() / 10,
                                because: "that grade held last time")
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

    /// What the plan's target should become, given a set you just did.
    ///
    /// The Today row shows `PlanItem.targetWeight`, and nothing ever moved it.
    /// So the set screen said "try 50, you hit every rep", you did 50, and the
    /// checklist went on saying 45 — every row understating you by a notch, for
    /// ever, while `working_weight` in the snapshot already knew the truth.
    ///
    /// Advances only on **evidence you own the weight**: a working set (not a
    /// warm-up) that hit the rep target at a weight harder than the plan asks.
    /// Five reps at a heavier weight is not a new working weight, it is a hard
    /// set, and the plan should not move for it.
    ///
    /// Harder runs the other way on an assisted machine — less help, not more.
    /// `nil` means leave the plan alone.
    static func advancedTarget(current: Double,
                               targetReps: Int,
                               set: Set) -> Double? {
        guard set.counts, set.reps >= targetReps else { return nil }
        let harder = set.assisted ? set.weight < current : set.weight > current
        return harder ? set.weight : nil
    }

    /// The week a training log runs on: **Monday first, always.**
    ///
    /// Not `Calendar.current.firstWeekday`, which is Sunday in the US — so the
    /// heatmap and the consistency band both cut the week in the middle of a
    /// weekend, and a Saturday-and-Sunday pair landed in two different weeks.
    /// Nobody thinks of their training week that way.
    ///
    /// Applied INSIDE the two functions that group by week rather than left to
    /// the caller, because the failure is silent: pass a plain `Calendar` and
    /// everything still computes, just against the wrong seven days.
    /// `firstWeekday` is the only thing overridden — the timezone and the
    /// locale that came in are the user's and are none of this function's
    /// business.
    static func trainingWeek(_ calendar: Calendar) -> Calendar {
        var c = calendar
        c.firstWeekday = 2          // Monday
        return c
    }

    // MARK: - Everything you have ever lifted

    /// A thing that weighs a known amount, for the tonnage ladder.
    ///
    /// A **registry, not a branch per tier**: adding one is a row, and every
    /// derived thing — what you have passed, what is next, how far — is
    /// computed from the table rather than written out again.
    ///
    /// The masses are real and rounded, which is the honest version of a game
    /// mechanic: 330,000 lb is a blue whale because a blue whale weighs about
    /// that, not because it made a nice curve. Where a figure is a range in the
    /// real world the ladder takes a representative adult, and says so here
    /// rather than implying a precision it does not have.
    struct Milestone: Equatable, Identifiable {
        let pounds: Double
        let name: String
        /// Asset name in `Assets.xcassets/Milestones`. Generated artwork rather
        /// than an SF Symbol: a badge you have earned should look like a badge,
        /// and `tortoise.fill` was standing in for three different animals.
        let art: String

        var id: String { name }
    }

    /// Roughly doubling each step, so the ladder keeps giving you something to
    /// reach without a gap that takes a year to cross.
    static let milestones: [Milestone] = [
        .init(pounds: 250, name: "A grand piano's lid", art: "grand-piano-lid"),
        .init(pounds: 1_000, name: "A grand piano", art: "grand-piano"),
        .init(pounds: 2_000, name: "A horse", art: "horse"),
        .init(pounds: 2_900, name: "A Honda Civic", art: "car"),
        .init(pounds: 5_000, name: "A rhinoceros", art: "rhinoceros"),
        .init(pounds: 8_000, name: "A hippopotamus", art: "hippopotamus"),
        .init(pounds: 13_000, name: "An African elephant", art: "elephant"),
        .init(pounds: 25_000, name: "A school bus", art: "school-bus"),
        .init(pounds: 66_000, name: "A humpback whale", art: "humpback-whale"),
        .init(pounds: 140_000, name: "An M1 Abrams tank", art: "tank"),
        .init(pounds: 330_000, name: "A blue whale", art: "blue-whale"),
        .init(pounds: 450_000, name: "The Statue of Liberty", art: "statue-of-liberty"),
        .init(pounds: 875_000, name: "A Boeing 747", art: "airliner"),
        .init(pounds: 2_000_000, name: "The Eiffel Tower's iron", art: "eiffel-tower"),
        .init(pounds: 4_500_000, name: "A Space Shuttle at launch", art: "space-shuttle"),
    ]

    /// A tier, and the day you went past it.
    struct Crossing: Equatable, Identifiable {
        let milestone: Milestone
        /// `nil` while it is still ahead of you.
        let crossedOn: Date?
        var isPassed: Bool { crossedOn != nil }
        var id: String { milestone.name }
    }

    /// The whole ladder, with the date each passed tier was crossed.
    ///
    /// Walks your workouts in order and watches the running total go past each
    /// line. The date is the **session that took you past it**, which is the
    /// only honest answer — a tier is not crossed on the day you happened to
    /// look at the screen.
    ///
    /// Sessions, not sets, because a tier crossed mid-workout belongs to that
    /// workout. Splitting a session across a boundary would date a milestone to
    /// a set nobody remembers.
    static func journey(sessionVolumes: [(date: Date, volume: Double)],
                        ladder: [Milestone] = Tally.milestones) -> [Crossing] {
        let sorted = ladder.sorted { $0.pounds < $1.pounds }
        let workouts = sessionVolumes.sorted { $0.date < $1.date }
        var running: Double = 0
        var crossedAt: [String: Date] = [:]
        var next = 0
        for workout in workouts {
            running += workout.volume
            while next < sorted.count, sorted[next].pounds <= running {
                crossedAt[sorted[next].name] = workout.date
                next += 1
            }
        }
        return sorted.map { Crossing(milestone: $0, crossedOn: crossedAt[$0.name]) }
    }

    /// Where you are on the ladder.
    struct Legacy: Equatable {
        let total: Double
        /// Everything you have already lifted past, oldest first.
        let passed: [Milestone]
        /// The next one, or `nil` when the ladder is finished.
        let next: Milestone?

        /// 0…1 between the last one passed and the next. Measured from the
        /// milestone you passed rather than from zero, so late on the ladder
        /// the bar still moves — from 875,000 to 2,000,000 as a fraction of
        /// 2,000,000 would sit at 44% for a year.
        var fraction: Double {
            guard let next else { return 1 }
            let floor = passed.last?.pounds ?? 0
            let span = next.pounds - floor
            guard span > 0 else { return 0 }
            return min(max((total - floor) / span, 0), 1)
        }

        var remaining: Double? { next.map { max(0, $0.pounds - total) } }
    }

    static func legacy(total: Double,
                       ladder: [Milestone] = Tally.milestones) -> Legacy {
        let sorted = ladder.sorted { $0.pounds < $1.pounds }
        let passed = sorted.filter { $0.pounds <= total }
        let next = sorted.first { $0.pounds > total }
        return Legacy(total: total, passed: passed, next: next)
    }

    /// The numbers that only mean anything cumulatively.
    struct Lifetime: Equatable {
        let workouts: Int
        let volume: Double
        let reps: Int
        let records: Int
    }

    // MARK: - The record book

    /// A record, as it happened.
    struct Milestoned: Equatable, Identifiable {
        let date: Date
        let exercise: String
        let record: Record

        var id: String { "\(date.timeIntervalSince1970)-\(exercise)-\(record.headline)" }
    }

    /// Every record you have ever set, newest first.
    ///
    /// `records(for:history:)` answers "did THIS set beat anything", which is
    /// the question at the moment you log it — and then the answer is thrown
    /// away. Nothing kept a list, so the app could tell you a set was a record
    /// and never mention it again.
    ///
    /// Replays history per exercise in order, asking the same question of each
    /// set against only what came before it. One entry per set: the ranked best
    /// of what it beat, for the same reason `headline` picks one — three badges
    /// on one set is confetti.
    static func recordBook(_ sets: [(date: Date, exercise: String, set: Set)],
                           limit: Int = 50) -> [Milestoned] {
        var out: [Milestoned] = []
        let byExercise = Dictionary(grouping: sets, by: \.exercise)
        for (name, entries) in byExercise {
            let ordered = entries.sorted { $0.date < $1.date }
            var history: [Set] = []
            for entry in ordered {
                // The first set of a lift beats nothing, and `records` says
                // otherwise: with no history there is nothing heavier, so it
                // reports a personal best. That is fine at the moment you log
                // it — it IS your best — and wrong in a book, where it would
                // make adding an exercise worth a badge and a fresh install
                // worth thirty-seven of them. Same argument as the tie rule
                // already in `records`: a record you get for free teaches you
                // to disbelieve the rest.
                if !history.isEmpty,
                   let best = records(for: entry.set, history: history)
                    .min(by: { $0.rank < $1.rank }) {
                    out.append(Milestoned(date: entry.date, exercise: name, record: best))
                }
                history.append(entry.set)
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    // MARK: - The calendar

    /// One day on the activity grid.
    struct ActiveDay: Equatable, Identifiable {
        let day: Date
        let volume: Double
        var id: Date { day }
    }

    /// Volume per day over the last `weeks` weeks, oldest first, every day
    /// present — including the empty ones, because the gaps are the point.
    ///
    /// This is the honest version of a streak: it shows the shape of your
    /// training without a counter that resets, which `docs/RESEARCH.md` refused
    /// and this does not reintroduce. A blank fortnight is visible and is not
    /// a failure state.
    static func activity(_ sets: [(date: Date, volume: Double)],
                         weeks: Int = 26,
                         now: Date = .now,
                         calendar rawCalendar: Calendar = .current) -> [ActiveDay] {
        let calendar = trainingWeek(rawCalendar)
        guard weeks > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1),
                                        to: thisWeek.start)
        else { return [] }

        var totals: [Date: Double] = [:]
        for entry in sets {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= start else { continue }
            totals[day, default: 0] += entry.volume
        }

        var days: [ActiveDay] = []
        var cursor = start
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek.start) ?? now
        while cursor < end {
            days.append(ActiveDay(day: cursor, volume: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// One workout, as done — which one, and when.
    ///
    /// The name matters because the question is coverage, not attendance.
    struct Done: Equatable {
        let date: Date
        let workout: String

        init(date: Date, workout: String) {
            self.date = date
            self.workout = workout
        }
    }

    /// The band: how much of your plan you covered, week by week.
    ///
    /// **Coverage, not attendance, and that is the correction.** v0.4.0 counted
    /// sessions against a target derived from the schedule's training days, and
    /// it answered a question nobody asked. On a four-workout plan it sat near
    /// half whatever you did, because the target came from weekdays while the
    /// plan came from workouts, and a two-a-day scored two.
    ///
    /// The question is "did I get round to each of my workouts this week".
    /// So: **distinct workouts covered**, against the number in the plan.
    /// Shoulders twice on a Tuesday is one of four, not two — you have not
    /// done Legs by doing Shoulders again.
    ///
    /// Deliberately day-agnostic. Which weekday you did Legs on is not a fact
    /// about consistency, and a plan you finished on the wrong days is a plan
    /// you finished.
    ///
    /// - Parameter sessions: one entry per workout — `Session.startedAt` and
    ///   `Session.dayName`.
    /// - Parameter plannedWorkouts: how many workouts the plan contains.
    /// The weekly target as it was, week by week.
    ///
    /// One entry per schedule you have had, oldest first. A week is scored by
    /// whichever was in force while it was happening — see `ScheduleEpoch` for
    /// why that has to be historical rather than read live.
    struct Targets: Equatable {
        /// `(from:, weekly:)`, ascending by date.
        private let epochs: [(from: Date, weekly: Int)]

        init(_ epochs: [(from: Date, weekly: Int)]) {
            self.epochs = epochs.sorted { $0.from < $1.from }
        }

        /// A single unchanging target — the shape every caller had before
        /// schedules could change.
        init(constant: Int) { self.epochs = [(from: .distantPast, weekly: constant)] }

        /// What was being asked of you in the week starting `date`.
        ///
        /// The LAST epoch that had started by then. Falls back to the earliest
        /// known target for weeks before any epoch, because the alternative is
        /// scoring your oldest weeks against zero and calling them perfect.
        func weekly(on date: Date) -> Int {
            if let live = epochs.last(where: { $0.from <= date }) { return live.weekly }
            return epochs.first?.weekly ?? 0
        }

        var isEmpty: Bool { epochs.isEmpty }
        var highest: Int { epochs.map(\.weekly).max() ?? 0 }

        static func == (a: Targets, b: Targets) -> Bool {
            a.epochs.count == b.epochs.count
                && zip(a.epochs, b.epochs).allSatisfy { $0.from == $1.from && $0.weekly == $1.weekly }
        }
    }

    static func consistency(sessions: [Done],
                            targets: Targets,
                            weeks limit: Int = 12,
                            now: Date = .now,
                            calendar rawCalendar: Calendar = .current) -> Consistency {
        let calendar = trainingWeek(rawCalendar)
        let empty = Consistency(weeks: [], adherence: nil, credited: 0, planned: 0)
        guard !targets.isEmpty, targets.highest > 0,
              limit > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        else { return empty }

        // Nothing before your first workout is a week you missed. A fresh
        // install opening on twelve grey marks is twelve failures you did not
        // earn, on the screen you see first.
        guard let firstSession = sessions.map(\.date).min(),
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
            // DISTINCT workouts, not sessions. "How many times did I hit each
            // workout this week" is the question — so Shoulders twice on the
            // same day is one of the four covered, not two.
            // `Swift.Set`, spelled out: inside `Tally`, a bare `Set` is
            // `Tally.Set` — the set of a lift — and the collision compiles into
            // something quite different from a count of distinct names.
            let done = Swift.Set(sessions.filter { $0.date >= start && $0.date < end }
                                         .map(\.workout)).count
            // The target THIS week was asked to meet, not today's.
            return Week(start: start, planned: targets.weekly(on: start), done: done,
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
    /// - Parameter bodyWeight: what you weighed when this set was done, for
    ///   assisted work. **Required, with no default**, and that is deliberate:
    ///   `nextTarget` used to take `assisted` as a defaulted parameter and one
    ///   call site silently never passed it, which made the app suggest more
    ///   help for a good session. A defaulted `nil` here would fail the same
    ///   way — quietly, as a zero in the tonnage. Pass `nil` when the caller
    ///   genuinely does not need volume; the compiler will at least have asked.
    func tally(bodyWeight: Double?) -> Tally.Set {
        Tally.Set(weight: weight, reps: reps, kind: setKind,
                  assisted: exercise?.assisted ?? false,
                  bodyWeight: bodyWeight)
    }
}
