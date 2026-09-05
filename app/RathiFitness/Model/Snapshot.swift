import Foundation
import SwiftData

/// The bridge out of the phone.
///
/// A CloudKit *private* database has no Mac command-line read path — there is no
/// app context to authenticate as — so `gym today` on the Mac would have nothing
/// to talk to and RIA would be blind. The app therefore writes this JSON into an
/// iCloud Drive ubiquity container, which on macOS is an ordinary file at
///
///     ~/Library/Mobile Documents/iCloud~com~rathi~fitness/Documents/snapshot.json
///
/// that syncs itself. That file is the entire contract with the CLI. Do not
/// "simplify" this away by having the CLI talk to CloudKit; it cannot.
///
/// **Pass codes are deliberately absent.** The snapshot lands in a folder any
/// process on the Mac can read, and a scannable gym credential sitting in
/// cleartext there is the same mistake as an access code in a commit message.
/// The CLI is told a pass *exists* and what state it is in, never what it says.
struct Snapshot: Codable {
    /// Bump when a field changes meaning. The CLI refuses versions it does not
    /// know rather than silently misreading them.
    /// **2** — set kinds arrived. `volume`, `top_weight` and `sets_done` now
    /// mean *working* sets: a warm-up contributes to none of them. The numbers
    /// are unchanged for logs recorded before set kinds existed (everything was
    /// a working set then), but the definition changed, and the rule in
    /// docs/SNAPSHOT.md is that a changed meaning bumps this.
    /// **4** — assisted machines. `assisted: true` on an exercise inverts what
    /// its numbers MEAN: `working_weight` is how much help you needed, so a
    /// smaller one is better and `change_30d` is progress when it is negative.
    /// Assistance is excluded from `volume` for the same reason bodyweight is —
    /// counting it made needing more help look like moving more weight. A
    /// reader that does not know the flag will congratulate you for getting
    /// weaker, which is why this is a bump and not an addition.
    /// **3** — cardio and machine settings. Two additions and one changed
    /// meaning, which is what forces the bump rather than a minor version:
    /// `exercises` may now be `modality: "cardio"`, in which case `volume` and
    /// `working_weight` are **zero and mean nothing** — a treadmill has no
    /// tonnage, and a reader that averages it in is reporting a fiction.
    /// Cardio lives in `cardio` blocks and `minutes`; `machine_settings` says
    /// where the seat goes.
    static let currentSchema = 6

    var schema: Int = Snapshot.currentSchema
    var generatedAt: String
    var appVersion: String
    var bodyWeight: BodyWeight
    var today: Today?
    var exercises: [ExerciseSummary]
    var plan: [PlanDay]
    var passes: [PassSummary]
    var sessions: [Session]
    /// Stretches he declared himself away for. The Mac needs these for the same
    /// reason the band does: a fortnight abroad is not a fortnight of not
    /// bothering, and anything reading `sessions[]` to judge consistency will
    /// draw the wrong conclusion without them.
    var timeAway: [Away]

    struct BodyWeight: Codable {
        var unit: String = "lb"
        var current: Double?
        var currentDate: String?
        var change30d: Double?
        var trendPerWeek: Double?
        var history: [Point]
        struct Point: Codable { var date: String; var lb: Double }

        /// Spelled out because `convertToSnakeCase` breaks on capitals, not on
        /// digits: `change30d` would otherwise ship as `change30d` sitting next
        /// to `trend_per_week`, and a contract that is inconsistent in one field
        /// is a contract every reader has to check twice.
        enum CodingKeys: String, CodingKey {
            case unit, current
            case currentDate = "current_date"
            case change30d = "change_30d"
            case trendPerWeek = "trend_per_week"
            case history
        }
    }

    struct Today: Codable {
        var date: String
        var day: String
        var setsDone: Int
        var setsPlanned: Int
        var exercisesDone: Int
        var exercisesPlanned: Int
        /// Total load moved today: every set's weight × reps.
        var volume: Double
        var items: [Item]
        struct Item: Codable {
            var slug: String
            var name: String
            var targetSets: Int
            var targetReps: Int
            var targetWeight: Double
            var restSeconds: Int
            /// Working sets done. Warm-ups are counted separately and do not
            /// move you toward the target.
            var setsDone: Int
            var warmupSets: Int
            var done: Bool
            var volume: Double
            var performed: [Performed]
            /// `strength` or `cardio`. Present on every item so a reader never
            /// has to infer it from a zero weight.
            var modality: String = Exercise.Modality.strength.rawValue
            /// What the plan asks for on a cardio slot. Absent on a lift, and
            /// absent field-by-field: a plan can prescribe twenty minutes at 3%
            /// and leave the speed to how you feel.
            var cardioTarget: CardioTarget?
            /// What the console said, summed over the bouts done today.
            var cardio: CardioDone?
        }

        struct CardioTarget: Codable {
            var seconds: Int?
            var distance: Double?
            var speed: Double?
            var incline: Double?
            var resistance: Double?
        }

        struct CardioDone: Codable {
            var bouts: Int
            var seconds: Int
            var distance: Double
            /// Average over the bouts, weighted by their time — an eight-minute
            /// warm-up walk must not drag a thirty-minute run's grade down as
            /// if the two were equal.
            var averageIncline: Double?
            var averageSpeed: Double?
        }
        struct Performed: Codable {
            var weight: Double
            var reps: Int
            /// `warmup` | `working` | `drop` | `failure`.
            var kind: String
            /// RPE 6–10, or absent when it was not recorded — which is not the
            /// same as easy, and is why this is nullable rather than 0.
            var rpe: Double?
            var note: String?
            /// The console. Every field nullable for the same reason RPE is:
            /// zero incline is a real answer and "not recorded" is a different
            /// one, and a reader cannot tell them apart from a 0.
            var seconds: Int?
            var distance: Double?
            var speed: Double?
            var incline: Double?
            var resistance: Double?
            var heartRate: Int?
        }
    }

    struct ExerciseSummary: Codable {
        var slug: String
        var name: String
        var loading: String
        /// What it mainly works, for sets-per-muscle questions. `other` means
        /// nobody has said yet — treat it as unknown, not as a muscle.
        var primaryMuscle: String
        var secondaryMuscles: [String]
        var workingWeight: Double?
        var lastPerformed: String?
        var best: Best?
        var change30d: Double?
        var recent: [SessionLine]
        /// `strength` or `cardio`. On a cardio exercise `workingWeight`, `best`
        /// and every `volume` below are zero and carry no meaning.
        var modality: String = Exercise.Modality.strength.rawValue
        /// The weight makes it EASIER — an assisted pull-up or dip machine.
        /// When true, `workingWeight` is assistance: lower is better, a negative
        /// `change30d` is progress, and none of it is in `volume`.
        var assisted: Bool = false
        /// Where the machine goes — "seat: 2", "back pad: 4". The whole point
        /// of the feature reaching the Mac: RIA can tell you before you get
        /// there.
        var machineSettings: [MachineSettingLine]?
        /// Lifetime cardio bests, absent on a lift.
        var cardioBest: CardioBest?

        enum CodingKeys: String, CodingKey {
            case slug, name, loading, best, recent, modality, assisted
            case primaryMuscle = "primary_muscle"
            case secondaryMuscles = "secondary_muscles"
            case workingWeight = "working_weight"
            case lastPerformed = "last_performed"
            case change30d = "change_30d"
            case machineSettings = "machine_settings"
            case cardioBest = "cardio_best"
        }

        struct MachineSettingLine: Codable {
            /// A `MachineSettingKind` raw value.
            var kind: String
            var label: String
            var value: String
        }

        struct CardioBest: Codable {
            var farthest: Double?
            var longestSeconds: Int?
            var fastest: Double?
        }

        struct Best: Codable { var weight: Double; var reps: Int; var date: String }
        struct SessionLine: Codable {
            var date: String
            /// Heaviest WORKING set.
            var topWeight: Double
            /// Reps of the working sets, in order.
            var reps: [Int]
            var volume: Double
            var warmupSets: Int
            /// Mean RPE of the working sets that recorded one.
            var averageRpe: Double?
            /// Cardio for that day, absent on a lift.
            var cardio: Today.CardioDone?
        }
    }

    struct PlanDay: Codable {
        var name: String
        var weekday: Int
        var items: [PlanEntry]
        struct PlanEntry: Codable {
            var slug: String; var name: String
            var sets: Int; var reps: Int; var weight: Double; var restSeconds: Int
            var modality: String = Exercise.Modality.strength.rawValue
            var cardioTarget: Today.CardioTarget?
        }
    }

    /// Metadata only — see the note on `Snapshot`. `hasCode` is the whole truth
    /// the CLI gets about the payload.
    struct PassSummary: Codable {
        var name: String
        var location: String
        var symbology: String
        var memberIdMasked: String
        var state: String?
        var expires: String?
        var expired: Bool
        var primary: Bool
        var hasCode: Bool
    }

    /// A declared trip. `to` is INCLUSIVE — a one-day trip has `from == to`.
    struct Away: Codable {
        let from: String
        let to: String
        let note: String?
    }

    struct Session: Codable {
        var date: String
        var day: String?
        /// When the workout began and ended, `HH:mm`. Two workouts on one date
        /// share a `date` and are told apart by these — the reason schema 5
        /// exists. Absent on a workout still in progress.
        var startedAt: String?
        var endedAt: String?
        /// Which workout of that day this was, counting from 1. `1` on the
        /// overwhelming majority of days; the field is always present so a
        /// reader never has to infer it from ordering.
        var ordinal: Int = 1
        var exercises: Int
        /// Working sets. Warm-ups are counted separately.
        var sets: Int
        var warmupSets: Int
        var volume: Double
        var topLifts: [String]
        /// Minutes of cardio in that session, and how far. Zero rather than
        /// absent: "no cardio" is a fact worth stating on a lifting day.
        var cardioMinutes: Double = 0
        var cardioDistance: Double = 0
    }
}

// MARK: - Building it

enum SnapshotBuilder {

    /// Binary floating point makes 176.4 - 178.2 into -1.799999999999983. Nobody
    /// weighed that, and it reaches RIA as a number she might read aloud.
    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    static func build(from context: ModelContext,
                      now: Date = .now,
                      appVersion: String = Bundle.main.appVersion) throws -> Snapshot {
        let cal = Calendar.current
        let weighIns = try context.fetch(
            FetchDescriptor<WeighIn>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let days = try context.fetch(FetchDescriptor<PlannedDay>())
        let passes = try context.fetch(FetchDescriptor<GymPass>())
        let schedules = try context.fetch(FetchDescriptor<Schedule>())
        let sessionRecords = try context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        let allSets = try context.fetch(
            FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        let trips = try context.fetch(
            FetchDescriptor<TimeAway>(sortBy: [SortDescriptor(\.startedAt, order: .forward)]))

        // Built once. Assisted work is valued at bodyweight minus the help,
        // and every section that reports tonnage has to agree about it — the
        // phone and `gym` reading different numbers for the same day is the
        // failure this whole file exists to prevent.
        let bodyWeightLog = Tally.BodyWeightLog(
            weighIns.map { (date: $0.date, pounds: $0.pounds) })

        return Snapshot(
            generatedAt: Fmt.iso(now),
            appVersion: appVersion,
            bodyWeight: bodyWeight(weighIns, now: now, cal: cal),
            today: today(days: days, sets: allSets, bodyWeightLog: bodyWeightLog,
                         sessions: sessionRecords,
                         schedule: schedules.first, now: now, cal: cal),
            exercises: exercises
                .map { summary($0, sets: allSets, bodyWeightLog: bodyWeightLog,
                               now: now, cal: cal) }
                .sorted { $0.name < $1.name },
            plan: days.sorted { ($0.weekday, $0.order) < ($1.weekday, $1.order) }.map(planDay),
            passes: passes
                .sorted { ($0.isPrimary ? 0 : 1, $0.name) < ($1.isPrimary ? 0 : 1, $1.name) }
                .map(passSummary),
            sessions: sessions(sessionRecords,
                               orphans: allSets.filter { $0.session == nil },
                               bodyWeightLog: bodyWeightLog,
                               cal: cal),
            timeAway: trips.map {
                Snapshot.Away(from: Fmt.day($0.startedAt), to: Fmt.day($0.endedAt),
                              note: $0.note.isEmpty ? nil : $0.note)
            })
    }

    // MARK: pieces

    private static func bodyWeight(_ w: [WeighIn], now: Date,
                                   cal: Calendar) -> Snapshot.BodyWeight {
        let history = w.map { Snapshot.BodyWeight.Point(date: Fmt.day($0.date), lb: $0.pounds) }
        guard let latest = w.last else {
            return .init(current: nil, currentDate: nil, change30d: nil,
                         trendPerWeek: nil, history: history)
        }
        let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let window = w.filter { $0.date >= cutoff }
        // Compare against the earliest reading INSIDE the window, not against
        // "30 days ago" exactly — you do not weigh yourself on a schedule.
        let base = window.first ?? latest
        let change = window.count > 1 ? latest.pounds - base.pounds : nil
        var perWeek: Double?
        if let change, window.count > 1 {
            let span = latest.date.timeIntervalSince(base.date) / 86_400
            if span >= 1 { perWeek = change / span * 7 }
        }
        return .init(current: latest.pounds, currentDate: Fmt.day(latest.date),
                     change30d: change.map(round1), trendPerWeek: perWeek.map(round1),
                     history: history)
    }

    /// What is up today, resolved the way the phone resolves it.
    ///
    /// This picked the planned day whose `weekday` matched, which is only right
    /// in `.weekday` mode. On a rotation the phone uses `Rotation.index` and the
    /// pairing drifts deliberately — so the app and the Mac gave different
    /// answers to "what am I doing today", and had since rotations shipped.
    /// `gym today` was confidently wrong within a fortnight of switching mode.
    ///
    /// The workout **in progress** wins over the rotation's guess: if a session
    /// is open, that is what you are doing, whatever the cycle says. It is also
    /// how a two-a-day reads correctly — the second workout is the current one.
    private static func today(days: [PlannedDay], sets: [SetEntry],
                              bodyWeightLog: Tally.BodyWeightLog,
                              sessions: [Session], schedule: Schedule?,
                              now: Date, cal: Calendar) -> Snapshot.Today? {
        let todaysSessions = sessions
            .filter { cal.isDate($0.startedAt, inSameDayAs: now) }
            .sorted { $0.startedAt < $1.startedAt }

        let day: PlannedDay?
        if let open = todaysSessions.last(where: \.isOpen), let planned = open.plannedDay {
            day = planned
        } else {
            let config = schedule?.config ?? Rotation.Config()
            switch config.mode {
            case .weekday:
                let weekday = cal.component(.weekday, from: now)
                day = days.first { $0.weekday == weekday }
            case .rotation, .everyNDays:
                // Sorted by `order`, because that IS the cycle. The fetch above
                // is unsorted and `TodayView` reads its days through
                // `@Query(sort: \PlannedDay.order)` — indexing into the raw
                // fetch here gave a different workout from the phone, which is
                // the exact class of disagreement this change exists to end.
                let cycle = days.sorted { $0.order < $1.order }
                let index = Rotation.index(on: now,
                                           sessionDates: sessions.map(\.startedAt),
                                           dayCount: cycle.count, calendar: cal)
                day = index.flatMap { cycle.indices.contains($0) ? cycle[$0] : cycle.first }
            }
        }
        guard let day else { return nil }

        // The sets that belong to the workout being described, not to the
        // calendar day — otherwise the second workout of a two-a-day is
        // reported as already half done.
        let todaysSets: [SetEntry]
        if let open = todaysSessions.last(where: \.isOpen) {
            todaysSets = open.orderedSets
        } else {
            todaysSets = sets.filter { cal.isDate($0.date, inSameDayAs: now) }
        }

        var items: [Snapshot.Today.Item] = []
        var done = 0
        for item in day.orderedItems {
            guard let ex = item.exercise else { continue }
            let performed = todaysSets
                .filter { $0.exercise?.slug == ex.slug }
                .sorted { $0.setIndex < $1.setIndex }
            // Warm-ups do not move you toward the target. Three warm-ups used to
            // mark an exercise done, which is the checklist lying to you.
            let working = performed.filter { $0.setKind.counts }
            // A cardio slot is done when its bouts are done. Judging it against
            // `targetSets` alone leaves the treadmill permanently unfinished.
            let isDone = ex.isCardio
                ? performed.count >= max(1, item.targetSets)
                : working.count >= item.targetSets
            if isDone { done += 1 }
            items.append(.init(
                slug: ex.slug, name: ex.name,
                targetSets: item.targetSets, targetReps: item.targetReps,
                targetWeight: item.targetWeight, restSeconds: item.restSeconds,
                setsDone: working.count,
                warmupSets: performed.count - working.count,
                done: isDone,
                volume: Tally.volume(performed.map {
                    $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
                }),
                performed: performed.map(performedLine),
                modality: ex.modality,
                cardioTarget: ex.isCardio ? cardioTarget(item) : nil,
                cardio: ex.isCardio ? cardioDone(performed) : nil))
        }
        // Kind-aware, so this agrees with what the phone shows.
        let moved = Tally.volume(todaysSets.map {
            $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
        })
        return .init(date: Fmt.day(now), day: day.name,
                     setsDone: items.reduce(0) { $0 + $1.setsDone },
                     setsPlanned: items.reduce(0) { $0 + $1.targetSets },
                     exercisesDone: done, exercisesPlanned: items.count,
                     volume: moved, items: items)
    }

    private static func performedLine(_ e: SetEntry) -> Snapshot.Today.Performed {
        .init(weight: e.weight, reps: e.reps, kind: e.kind,
              rpe: e.rpe > 0 ? e.rpe : nil,
              note: e.note.isEmpty ? nil : e.note,
              seconds: e.seconds > 0 ? e.seconds : nil,
              distance: e.distance > 0 ? round1(e.distance) : nil,
              speed: e.speed > 0 ? round1(e.speed) : nil,
              incline: e.incline > 0 ? round1(e.incline) : nil,
              resistance: e.resistance > 0 ? round1(e.resistance) : nil,
              heartRate: e.averageHeartRate > 0 ? e.averageHeartRate : nil)
    }

    private static func cardioTarget(_ item: PlanItem) -> Snapshot.Today.CardioTarget? {
        let target = Snapshot.Today.CardioTarget(
            seconds: item.targetSeconds > 0 ? item.targetSeconds : nil,
            distance: item.targetDistance > 0 ? round1(item.targetDistance) : nil,
            speed: item.targetSpeed > 0 ? round1(item.targetSpeed) : nil,
            incline: item.targetIncline > 0 ? round1(item.targetIncline) : nil,
            resistance: item.targetResistance > 0 ? round1(item.targetResistance) : nil)
        // Nothing prescribed at all is `null`, not an object of five nulls.
        if target.seconds == nil, target.distance == nil, target.speed == nil,
           target.incline == nil, target.resistance == nil { return nil }
        return target
    }

    /// The day's bouts, summed — with the averages weighted by TIME.
    ///
    /// A plain mean would let an eight-minute warm-up walk pull a thirty-minute
    /// run's grade down as though the two were the same amount of work. Nobody
    /// reading "average incline 1.5%" would guess it was computed that way.
    private static func cardioDone(_ entries: [SetEntry]) -> Snapshot.Today.CardioDone? {
        let bouts = entries.filter { $0.seconds > 0 || $0.distance > 0 }
        guard !bouts.isEmpty else { return nil }
        let seconds = bouts.reduce(0) { $0 + $1.seconds }
        let distance = bouts.reduce(0) { $0 + $1.distance }

        var incline: Double?
        let inclined = bouts.filter { $0.incline > 0 && $0.seconds > 0 }
        let inclinedTime = inclined.reduce(0) { $0 + $1.seconds }
        if inclinedTime > 0 {
            incline = inclined.reduce(0) { $0 + $1.incline * Double($1.seconds) }
                / Double(inclinedTime)
        }

        // Distance over time across the whole day, which is the only average
        // speed that survives being questioned.
        let speed = (seconds > 0 && distance > 0)
            ? distance / (Double(seconds) / 3600) : nil

        return .init(bouts: bouts.count, seconds: seconds, distance: round1(distance),
                     averageIncline: incline.map(round1), averageSpeed: speed.map(round1))
    }

    private static func summary(_ ex: Exercise, sets: [SetEntry],
                                bodyWeightLog: Tally.BodyWeightLog,
                                now: Date, cal: Calendar) -> Snapshot.ExerciseSummary {
        let mine = sets.filter { $0.exercise?.slug == ex.slug }
        let byDay = Dictionary(grouping: mine) { Fmt.day($0.date) }
        let lines = byDay.map { (date, entries) -> Snapshot.ExerciseSummary.SessionLine in
            let working = entries.filter { $0.setKind.counts }
            let rpes = working.map(\.rpe).filter { $0 > 0 }
            return .init(
                date: date,
                // The hardest set of that day: most weight normally, least help
                // on an assisted machine.
                topWeight: (ex.assisted ? working.map(\.weight).min()
                                        : working.map(\.weight).max()) ?? 0,
                reps: working.sorted { $0.setIndex < $1.setIndex }.map(\.reps),
                volume: Tally.volume(entries.map {
                    $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
                }),
                warmupSets: entries.count - working.count,
                averageRpe: rpes.isEmpty ? nil
                    : (rpes.reduce(0, +) / Double(rpes.count) * 10).rounded() / 10,
                cardio: ex.isCardio ? cardioDone(entries) : nil)
        }.sorted { $0.date > $1.date }

        // "Best" is the heaviest set, ties broken by reps — a heavier single
        // beats a lighter set of eight for this purpose, which is what a
        // working-weight number is for.
        // A warm-up is not a personal best, here as on the phone.
        //
        // On an assisted machine "best" is the LEAST help, so the comparison
        // flips. Leaving it as `max` would export the day you needed most help
        // as your personal best, which is the whole bug in one field.
        let counted = mine.filter { $0.setKind.counts }
        let best = ex.assisted
            ? counted.min { a, b in a.weight == b.weight ? a.reps > b.reps : a.weight < b.weight }
            : counted.max { a, b in a.weight == b.weight ? a.reps < b.reps : a.weight < b.weight }
        let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let older = lines.first { ($0.date) <= Fmt.day(cutoff) }
        let change = (lines.first?.topWeight).flatMap { latest in
            older.map { latest - $0.topWeight }
        }

        let settings = ex.settings
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Snapshot.ExerciseSummary.MachineSettingLine(
                kind: $0.kind, label: $0.setting.label, value: $0.value) }

        return .init(
            slug: ex.slug, name: ex.name, loading: ex.loading,
            primaryMuscle: ex.primaryMuscle,
            secondaryMuscles: ex.secondary.map(\.rawValue),
            workingWeight: ex.isCardio ? nil : lines.first?.topWeight,
            lastPerformed: lines.first?.date,
            best: ex.isCardio ? nil
                : best.map { .init(weight: $0.weight, reps: $0.reps, date: Fmt.day($0.date)) },
            change30d: ex.isCardio ? nil : change.map(round1),
            recent: Array(lines.prefix(12)),
            modality: ex.modality,
            assisted: ex.assisted,
            machineSettings: settings.isEmpty ? nil : settings,
            cardioBest: ex.isCardio ? cardioBest(mine) : nil)
    }

    /// Lifetime cardio bests. Nil rather than zeros when nothing qualifies —
    /// "furthest ever: 0 mi" is not a fact anyone wants read back to them.
    private static func cardioBest(_ entries: [SetEntry]) -> Snapshot.ExerciseSummary.CardioBest? {
        let bouts = entries.filter { $0.seconds > 0 || $0.distance > 0 }
        guard !bouts.isEmpty else { return nil }
        let farthest = bouts.map(\.distance).max() ?? 0
        let longest = bouts.map(\.seconds).max() ?? 0
        let fastest = bouts.compactMap(\.achievedSpeed).max() ?? 0
        return .init(farthest: farthest > 0 ? round1(farthest) : nil,
                     longestSeconds: longest > 0 ? longest : nil,
                     fastest: fastest > 0 ? round1(fastest) : nil)
    }

    private static func planDay(_ d: PlannedDay) -> Snapshot.PlanDay {
        .init(name: d.name, weekday: d.weekday,
              items: d.orderedItems.compactMap { item in
                  item.exercise.map { ex in
                      .init(slug: ex.slug, name: ex.name, sets: item.targetSets,
                            reps: item.targetReps, weight: item.targetWeight,
                            restSeconds: item.restSeconds,
                            modality: ex.modality,
                            cardioTarget: ex.isCardio ? cardioTarget(item) : nil)
                  }
              })
    }

    private static func passSummary(_ p: GymPass) -> Snapshot.PassSummary {
        .init(name: p.name, location: p.location, symbology: p.symbology,
              memberIdMasked: mask(p.memberID), state: p.stateLine,
              expires: p.expires.map(Fmt.day), expired: p.isExpired,
              primary: p.isPrimary, hasCode: !p.code.isEmpty)
    }

    /// Last four digits only, and only if there are more than four.
    static func mask(_ id: String) -> String {
        let digits = id.filter { !$0.isWhitespace }
        guard digits.count > 4 else { return digits.isEmpty ? "" : "••••" }
        return "•••• " + String(digits.suffix(4))
    }

    /// One row per **workout**, not per day.
    ///
    /// Grouped by `Fmt.day` until schema 5, with the name guessed from the
    /// weekday — which was wrong twice over on a two-a-day: the two workouts
    /// merged into one row, and the row was labelled with whichever planned day
    /// happened to sit on that weekday. Sessions carry their own name, recorded
    /// when they were performed.
    private static func sessions(_ records: [Session], orphans: [SetEntry],
                                 bodyWeightLog: Tally.BodyWeightLog,
                                 cal: Calendar) -> [Snapshot.Session] {
        // A set with no session still happened.
        //
        // The launch backfill gives every historical set a workout, but it is
        // not the only writer: CloudKit can deliver rows from a device still on
        // an older build, and those arrive with `session == nil`. Dropping them
        // would lose a day of training from the Mac's view silently, which is
        // the failure mode this app keeps having to design against. They are
        // grouped by day — the assumption the old code made — and carry no
        // `day` name, because inventing one is what the guessing used to do.
        var groups: [(date: String, started: Date, ended: Date?,
                      name: String?, sets: [SetEntry])] = records.map {
            (Fmt.day($0.startedAt), $0.startedAt, $0.endedAt,
             $0.dayName.isEmpty ? nil : $0.dayName, $0.orderedSets)
        }
        for (date, sets) in Dictionary(grouping: orphans, by: { Fmt.day($0.date) }) {
            let ordered = sets.sorted { $0.date < $1.date }
            guard let first = ordered.first, let last = ordered.last else { continue }
            groups.append((date, first.date, last.date, nil, ordered))
        }

        let byDay = Dictionary(grouping: groups) { $0.date }
        return groups
            .map { group -> Snapshot.Session in
                let date = group.date
                let entries = group.sets
                let ordinal = (byDay[date] ?? [])
                    .sorted { $0.started < $1.started }
                    .firstIndex { $0.started == group.started }
                    .map { $0 + 1 } ?? 1
                let byExercise = Dictionary(grouping: entries) { $0.exercise?.slug ?? "?" }
                let top = byExercise
                    .compactMap { _, e -> (String, Double)? in
                        // Assisted machines are excluded alongside cardio:
                        // "Assisted Pull-Up 100" would top the list on the day
                        // you needed the most help.
                        guard let exercise = e.first?.exercise,
                              !exercise.isCardio, !exercise.assisted,
                              let w = e.filter({ $0.setKind.counts })
                                  .map(\.weight).max(), w > 0 else { return nil }
                        return (exercise.name, w)
                    }
                    // Ties broken by name. Without it, two lifts at the same
                    // weight swap places between writes — Swift's Dictionary
                    // iteration order is seeded per process — and the snapshot
                    // churns in iCloud for no reason at all.
                    .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                    .prefix(3)
                    .map { "\($0.0) \(Fmt.weight($0.1))" }
                let working = entries.filter { $0.setKind.counts }
                return .init(
                    date: date,
                    day: group.name,
                    startedAt: Fmt.timeOfDay(group.started),
                    endedAt: group.ended.map(Fmt.timeOfDay),
                    ordinal: ordinal,
                    exercises: byExercise.count,
                    sets: working.count,
                    warmupSets: entries.count - working.count,
                    volume: Tally.volume(entries.map {
                        $0.tally(bodyWeight: bodyWeightLog.pounds(on: $0.date))
                    }),
                    topLifts: Array(top),
                    cardioMinutes: round1(Tally.cardioMinutes(entries.map {
                        Tally.Bout(seconds: $0.seconds, distance: $0.distance)
                    })),
                    cardioDistance: round1(entries.reduce(0) { $0 + $1.distance }))
            }
            .sorted {
                $0.date == $1.date ? $0.ordinal > $1.ordinal : $0.date > $1.date
            }
    }
}

// MARK: - Writing it out

enum SnapshotWriter {
    static let containerID = "iCloud.com.rathi.fitness"
    static let filename = "snapshot.json"

    enum Destination {
        case iCloud(URL)
        /// No ubiquity container: not signed into iCloud, or an unsigned build.
        /// Still writes, so the CLI can be pointed at it with `GYM_SNAPSHOT`.
        case local(URL)

        var url: URL {
            switch self { case .iCloud(let u), .local(let u): return u }
        }
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Resolve where the snapshot goes. Touches the filesystem, so never call
    /// this on the main thread — `url(forUbiquityContainerIdentifier:)` blocks.
    static func destination(fileManager fm: FileManager = .default) -> Destination {
        if let container = fm.url(forUbiquityContainerIdentifier: containerID) {
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return .iCloud(docs.appendingPathComponent(filename))
        }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return .local(docs.appendingPathComponent(filename))
    }

    @discardableResult
    static func write(_ snapshot: Snapshot,
                      to destination: Destination? = nil) throws -> Destination {
        let dest = destination ?? self.destination()
        let data = try encoder().encode(snapshot)

        // Atomic AND coordinated. Atomic alone is what we had, and it is only
        // half the problem: it writes a temp file and renames it over the old
        // one, which gives the reader a whole file or nothing — good — but also
        // produces a NEW inode every time, which iCloud sees as delete-then-
        // create. Without an `NSFileCoordinator` telling the daemon that this
        // is one deliberate replacement, the Mac side can be left holding a
        // reference to a file that no longer exists, or an unmaterialised
        // placeholder it never gets told to download. Which is exactly the
        // "cloud file locked" the Mac reported.
        //
        // Coordination is not optional in a ubiquity container; it was simply
        // missing. Local writes get the same path so there is one code route
        // rather than two, and the coordinator is cheap on a plain file.
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest.url,
                                       options: .forReplacing,
                                       error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) }
            catch { writeError = error }
        }
        if let writeError { throw writeError }
        if let coordinationError { throw coordinationError }
        return dest
    }
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
