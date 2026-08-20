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
    static let currentSchema = 1

    var schema: Int = Snapshot.currentSchema
    var generatedAt: String
    var appVersion: String
    var bodyWeight: BodyWeight
    var today: Today?
    var exercises: [ExerciseSummary]
    var plan: [PlanDay]
    var passes: [PassSummary]
    var sessions: [Session]

    struct BodyWeight: Codable {
        var unit: String = "lb"
        var current: Double?
        var currentDate: String?
        var change30d: Double?
        var trendPerWeek: Double?
        var history: [Point]
        struct Point: Codable { var date: String; var lb: Double }
    }

    struct Today: Codable {
        var date: String
        var day: String
        var setsDone: Int
        var setsPlanned: Int
        var exercisesDone: Int
        var exercisesPlanned: Int
        var items: [Item]
        struct Item: Codable {
            var slug: String
            var name: String
            var targetSets: Int
            var targetReps: Int
            var targetWeight: Double
            var restSeconds: Int
            var setsDone: Int
            var done: Bool
            var performed: [Performed]
        }
        struct Performed: Codable { var weight: Double; var reps: Int }
    }

    struct ExerciseSummary: Codable {
        var slug: String
        var name: String
        var loading: String
        var workingWeight: Double?
        var lastPerformed: String?
        var best: Best?
        var change30d: Double?
        var recent: [SessionLine]
        struct Best: Codable { var weight: Double; var reps: Int; var date: String }
        struct SessionLine: Codable {
            var date: String
            var topWeight: Double
            var reps: [Int]
            var volume: Double
        }
    }

    struct PlanDay: Codable {
        var name: String
        var weekday: Int
        var items: [PlanEntry]
        struct PlanEntry: Codable {
            var slug: String; var name: String
            var sets: Int; var reps: Int; var weight: Double; var restSeconds: Int
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

    struct Session: Codable {
        var date: String
        var day: String?
        var exercises: Int
        var sets: Int
        var volume: Double
        var topLifts: [String]
    }
}

// MARK: - Building it

enum SnapshotBuilder {

    static func build(from context: ModelContext,
                      now: Date = .now,
                      appVersion: String = Bundle.main.appVersion) throws -> Snapshot {
        let cal = Calendar.current
        let weighIns = try context.fetch(
            FetchDescriptor<WeighIn>(sortBy: [SortDescriptor(\.date, order: .forward)]))
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let days = try context.fetch(FetchDescriptor<PlannedDay>())
        let passes = try context.fetch(FetchDescriptor<GymPass>())
        let allSets = try context.fetch(
            FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.date, order: .forward)]))

        return Snapshot(
            generatedAt: Fmt.iso(now),
            appVersion: appVersion,
            bodyWeight: bodyWeight(weighIns, now: now, cal: cal),
            today: today(days: days, sets: allSets, now: now, cal: cal),
            exercises: exercises
                .map { summary($0, sets: allSets, now: now, cal: cal) }
                .sorted { $0.name < $1.name },
            plan: days.sorted { ($0.weekday, $0.order) < ($1.weekday, $1.order) }.map(planDay),
            passes: passes
                .sorted { ($0.isPrimary ? 0 : 1, $0.name) < ($1.isPrimary ? 0 : 1, $1.name) }
                .map(passSummary),
            sessions: sessions(allSets, days: days, cal: cal))
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
                     change30d: change, trendPerWeek: perWeek, history: history)
    }

    private static func today(days: [PlannedDay], sets: [SetEntry],
                              now: Date, cal: Calendar) -> Snapshot.Today? {
        let weekday = cal.component(.weekday, from: now)
        guard let day = days.first(where: { $0.weekday == weekday }) else { return nil }
        let todaysSets = sets.filter { cal.isDate($0.date, inSameDayAs: now) }

        var items: [Snapshot.Today.Item] = []
        var done = 0
        for item in day.orderedItems {
            guard let ex = item.exercise else { continue }
            let performed = todaysSets
                .filter { $0.exercise?.slug == ex.slug }
                .sorted { $0.setIndex < $1.setIndex }
            let isDone = performed.count >= item.targetSets
            if isDone { done += 1 }
            items.append(.init(
                slug: ex.slug, name: ex.name,
                targetSets: item.targetSets, targetReps: item.targetReps,
                targetWeight: item.targetWeight, restSeconds: item.restSeconds,
                setsDone: performed.count, done: isDone,
                performed: performed.map { .init(weight: $0.weight, reps: $0.reps) }))
        }
        return .init(date: Fmt.day(now), day: day.name,
                     setsDone: items.reduce(0) { $0 + $1.setsDone },
                     setsPlanned: items.reduce(0) { $0 + $1.targetSets },
                     exercisesDone: done, exercisesPlanned: items.count,
                     items: items)
    }

    private static func summary(_ ex: Exercise, sets: [SetEntry],
                                now: Date, cal: Calendar) -> Snapshot.ExerciseSummary {
        let mine = sets.filter { $0.exercise?.slug == ex.slug }
        let byDay = Dictionary(grouping: mine) { Fmt.day($0.date) }
        let lines = byDay.map { (date, entries) -> Snapshot.ExerciseSummary.SessionLine in
            .init(date: date,
                  topWeight: entries.map(\.weight).max() ?? 0,
                  reps: entries.sorted { $0.setIndex < $1.setIndex }.map(\.reps),
                  volume: entries.reduce(0) { $0 + $1.weight * Double($1.reps) })
        }.sorted { $0.date > $1.date }

        // "Best" is the heaviest set, ties broken by reps — a heavier single
        // beats a lighter set of eight for this purpose, which is what a
        // working-weight number is for.
        let best = mine.max { a, b in
            a.weight == b.weight ? a.reps < b.reps : a.weight < b.weight
        }
        let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let older = lines.first { ($0.date) <= Fmt.day(cutoff) }
        let change = (lines.first?.topWeight).flatMap { latest in
            older.map { latest - $0.topWeight }
        }

        return .init(
            slug: ex.slug, name: ex.name, loading: ex.loading,
            workingWeight: lines.first?.topWeight,
            lastPerformed: lines.first?.date,
            best: best.map { .init(weight: $0.weight, reps: $0.reps, date: Fmt.day($0.date)) },
            change30d: change,
            recent: Array(lines.prefix(12)))
    }

    private static func planDay(_ d: PlannedDay) -> Snapshot.PlanDay {
        .init(name: d.name, weekday: d.weekday,
              items: d.orderedItems.compactMap { item in
                  item.exercise.map {
                      .init(slug: $0.slug, name: $0.name, sets: item.targetSets,
                            reps: item.targetReps, weight: item.targetWeight,
                            restSeconds: item.restSeconds)
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

    private static func sessions(_ sets: [SetEntry], days: [PlannedDay],
                                 cal: Calendar) -> [Snapshot.Session] {
        Dictionary(grouping: sets) { Fmt.day($0.date) }
            .map { date, entries -> Snapshot.Session in
                let weekday = entries.first.map { cal.component(.weekday, from: $0.date) }
                let byExercise = Dictionary(grouping: entries) { $0.exercise?.slug ?? "?" }
                let top = byExercise
                    .compactMap { _, e -> (String, Double)? in
                        guard let name = e.first?.exercise?.name,
                              let w = e.map(\.weight).max() else { return nil }
                        return (name, w)
                    }
                    // Ties broken by name. Without it, two lifts at the same
                    // weight swap places between writes — Swift's Dictionary
                    // iteration order is seeded per process — and the snapshot
                    // churns in iCloud for no reason at all.
                    .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                    .prefix(3)
                    .map { "\($0.0) \(Fmt.weight($0.1))" }
                return .init(
                    date: date,
                    day: days.first { $0.weekday == weekday }?.name,
                    exercises: byExercise.count, sets: entries.count,
                    volume: entries.reduce(0) { $0 + $1.weight * Double($1.reps) },
                    topLifts: Array(top))
            }
            .sorted { $0.date > $1.date }
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
        // Atomic: the CLI may be reading while the app writes, and a half-written
        // JSON is a crash on the other end rather than a stale answer.
        try data.write(to: dest.url, options: .atomic)
        return dest
    }
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
