import Foundation
import SwiftData

/// First-launch content.
///
/// **A plan, and no history.** The first version of this seeded six weeks of
/// plausible sessions so Trends would have a shape on day one, and that was
/// wrong: within an hour the app was showing lifts that never happened, on a
/// chart labelled with his name. A demo that cannot be told apart from your
/// data is not a demo, it is a lie with a graph.
///
/// So `runIfNeeded` installs the **rotation only** — a template you are meant to
/// edit, not a claim about your past. `loadDemoHistory` still exists for tests
/// and screenshots, and everything it writes is tagged `source: .demo` so it can
/// be removed wholesale and labelled wherever it is drawn.
///
/// Passes are deliberately NOT seeded either. A membership code is personal and
/// cannot be invented; the Pass tab ships with an empty state and a scanner.
enum Seed {

    struct Spec {
        let name: String
        let loading: Exercise.Loading
        let sets: Int, reps: Int
        let weight: Double
        let rest: Int
        /// Pounds added per week of the seeded history, so the trends have shape.
        let weeklyGain: Double
    }

    static let days: [(name: String, weekday: Int, items: [Spec])] = [
        ("Pull A", 2, [
            Spec(name: "Deadlift", loading: .barbell, sets: 3, reps: 5, weight: 315, rest: 180, weeklyGain: 0),
            Spec(name: "Barbell Row", loading: .barbell, sets: 4, reps: 8, weight: 155, rest: 120, weeklyGain: 2.5),
            Spec(name: "Lat Pulldown", loading: .machine, sets: 3, reps: 10, weight: 130, rest: 90, weeklyGain: 2.5),
            Spec(name: "Face Pull", loading: .cable, sets: 3, reps: 15, weight: 40, rest: 60, weeklyGain: 0),
            Spec(name: "Barbell Curl", loading: .barbell, sets: 3, reps: 10, weight: 65, rest: 60, weeklyGain: 1.25),
        ]),
        ("Push A", 4, [
            Spec(name: "Bench Press", loading: .barbell, sets: 4, reps: 8, weight: 185, rest: 150, weeklyGain: 2.5),
            Spec(name: "Incline DB Press", loading: .dumbbell, sets: 3, reps: 10, weight: 60, rest: 90, weeklyGain: 1.25),
            Spec(name: "Cable Fly", loading: .cable, sets: 3, reps: 12, weight: 30, rest: 60, weeklyGain: 0),
            Spec(name: "Overhead Press", loading: .barbell, sets: 4, reps: 6, weight: 115, rest: 120, weeklyGain: 1.25),
            Spec(name: "Lateral Raise", loading: .dumbbell, sets: 3, reps: 15, weight: 20, rest: 60, weeklyGain: 0),
            Spec(name: "Triceps Pushdown", loading: .cable, sets: 3, reps: 12, weight: 50, rest: 60, weeklyGain: 1.25),
        ]),
        ("Legs", 6, [
            Spec(name: "Back Squat", loading: .barbell, sets: 4, reps: 6, weight: 245, rest: 180, weeklyGain: 5),
            Spec(name: "Romanian Deadlift", loading: .barbell, sets: 3, reps: 8, weight: 185, rest: 120, weeklyGain: 2.5),
            Spec(name: "Leg Press", loading: .machine, sets: 3, reps: 12, weight: 360, rest: 90, weeklyGain: 5),
            Spec(name: "Leg Curl", loading: .machine, sets: 3, reps: 12, weight: 90, rest: 60, weeklyGain: 2.5),
            Spec(name: "Calf Raise", loading: .machine, sets: 4, reps: 15, weight: 180, rest: 45, weeklyGain: 0),
        ]),
    ]

    /// The plan only. Nothing here claims you have ever trained.
    static func runIfNeeded(_ context: ModelContext, now: Date = .now) throws {
        let existing = try context.fetchCount(FetchDescriptor<PlannedDay>())
        guard existing == 0 else { return }
        try run(context, now: now, weeksOfHistory: 0)
    }

    /// Sample data, for tests and for looking at a screen that has something in
    /// it. Everything written with `weeksOfHistory > 0` is tagged `.demo`.
    static func loadDemoHistory(_ context: ModelContext, now: Date = .now,
                                weeks: Int = 6) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let byName = Dictionary(exercises.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        try seedHistory(context, byName: byName, now: now, weeks: weeks,
                        cal: Calendar.current)
        try seedWeighIns(context, now: now, days: 42, cal: Calendar.current)
        try context.save()
    }

    /// Remove every row this file invented, and nothing else.
    @discardableResult
    static func removeDemoData(_ context: ModelContext) throws -> Int {
        var removed = 0
        for set in try context.fetch(FetchDescriptor<SetEntry>()) where set.isDemo {
            context.delete(set); removed += 1
        }
        for weighIn in try context.fetch(FetchDescriptor<WeighIn>()) where weighIn.isDemo {
            context.delete(weighIn); removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }

    /// Everything logged, demo or not. The plan and the passes survive.
    ///
    /// Exists because the build already on the phone wrote demo rows before they
    /// were tagged, so there is no way to single them out on that install.
    @discardableResult
    static func deleteAllHistory(_ context: ModelContext) throws -> Int {
        var removed = 0
        for set in try context.fetch(FetchDescriptor<SetEntry>()) {
            context.delete(set); removed += 1
        }
        for weighIn in try context.fetch(FetchDescriptor<WeighIn>()) {
            context.delete(weighIn); removed += 1
        }
        if removed > 0 { try context.save() }
        return removed
    }

    static func run(_ context: ModelContext, now: Date = .now, weeksOfHistory: Int = 6) throws {
        let cal = Calendar.current
        var byName: [String: Exercise] = [:]

        for (order, day) in days.enumerated() {
            let planned = PlannedDay(name: day.name, weekday: day.weekday, order: order)
            context.insert(planned)
            for (i, spec) in day.items.enumerated() {
                let ex: Exercise
                if let found = byName[spec.name] { ex = found }
                else {
                    ex = Exercise(name: spec.name, loading: spec.loading,
                                  barWeight: spec.loading == .barbell ? 45 : 0)
                    context.insert(ex)
                    byName[spec.name] = ex
                }
                let item = PlanItem(order: i, exercise: ex, targetSets: spec.sets,
                                    targetReps: spec.reps, targetWeight: spec.weight,
                                    restSeconds: spec.rest)
                item.day = planned
                context.insert(item)
            }
        }

        if weeksOfHistory > 0 {
            try seedHistory(context, byName: byName, now: now, weeks: weeksOfHistory, cal: cal)
            try seedWeighIns(context, now: now, days: 42, cal: cal)
        }
        try context.save()
    }

    /// Past sessions, working backwards from today. Reps decay across a session
    /// the way they actually do — 8, 8, 7, 6 — so "am I stalling" has something
    /// to read.
    private static func seedHistory(_ context: ModelContext, byName: [String: Exercise],
                                    now: Date, weeks: Int, cal: Calendar) throws {
        var rand = Deterministic(seed: 20_260_820)
        for week in stride(from: weeks, through: 1, by: -1) {
            for day in days {
                guard let date = mostRecent(weekday: day.weekday, before: now,
                                            weeksBack: week, cal: cal) else { continue }
                for spec in day.items {
                    guard let ex = byName[spec.name] else { continue }
                    let weight = spec.weight - spec.weeklyGain * Double(week - 1)
                    guard weight > 0 else { continue }
                    for setIndex in 1...spec.sets {
                        // Later sets lose a rep or two, with a little noise.
                        let fade = Int(Double(setIndex - 1) * 0.6 + rand.next() * 0.9)
                        let reps = max(1, spec.reps - fade)
                        let at = cal.date(byAdding: .minute,
                                          value: setIndex * 3, to: date) ?? date
                        context.insert(SetEntry(exercise: ex, weight: weight, reps: reps,
                                                setIndex: setIndex, date: at, source: .demo))
                    }
                }
            }
        }
    }

    private static func seedWeighIns(_ context: ModelContext, now: Date,
                                     days count: Int, cal: Calendar) throws {
        var rand = Deterministic(seed: 90_210)
        let start = 179.6, end = 176.4
        for i in stride(from: count - 1, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            // Weigh-ins are not daily. Skip about one morning in four.
            if i != 0 && rand.next() > 0.76 { continue }
            let t = Double(count - 1 - i) / Double(count - 1)
            let value = i == 0 ? end : start + (end - start) * t + (rand.next() - 0.5) * 0.9
            let at = cal.date(bySettingHour: 7, minute: 10, second: 0, of: date) ?? date
            context.insert(WeighIn(pounds: (value * 10).rounded() / 10, date: at,
                                   source: .demo))
        }
    }

    private static func mostRecent(weekday: Int, before now: Date,
                                   weeksBack: Int, cal: Calendar) -> Date? {
        let today = cal.component(.weekday, from: now)
        var delta = weekday - today
        if delta > 0 { delta -= 7 }
        guard let thisOne = cal.date(byAdding: .day, value: delta, to: now) else { return nil }
        let shifted = cal.date(byAdding: .day, value: -7 * (weeksBack - 1), to: thisOne)
        return shifted.flatMap {
            cal.date(bySettingHour: 6, minute: 45, second: 0, of: $0)
        }
    }

    /// A tiny LCG. Seeded so the demo history is identical on every install —
    /// a screenshot taken today should match one taken tomorrow.
    struct Deterministic {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 1_000_000) / 1_000_000
        }
    }
}
