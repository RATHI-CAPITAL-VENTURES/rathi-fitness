import SwiftUI
import SwiftData

/// A day you already did.
///
/// **Read-only on purpose, and this is the whole design.** Today is a live
/// checklist: tapping a row opens the set screen and logging writes
/// `Date.now`. Make yesterday swipeable in that same form and the first thing
/// that happens is a set logged into the wrong day — silently, because the
/// screen you were looking at said Tuesday. So a past day is a *summary*: what
/// you did, what it added up to, and no way to add to it.
///
/// Which day it was is worked out from the exercises, not from the weekday. The
/// programme rotates (see `Rotation`), so "Push A is Tuesday" is wrong within a
/// fortnight; matching the logged lifts against each planned day's contents is
/// right however the cycle has drifted.
struct PastDayView: View {
    let date: Date

    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]
    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]
    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]

    private var calendar: Calendar { .current }

    private var entries: [SetEntry] {
        allSets.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Grouped by exercise, in the order you did them.
    private var byExercise: [(exercise: Exercise, sets: [SetEntry])] {
        var order: [String] = []
        var buckets: [String: [SetEntry]] = [:]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard let slug = entry.exercise?.slug else { continue }
            if buckets[slug] == nil { order.append(slug) }
            buckets[slug, default: []].append(entry)
        }
        return order.compactMap { slug in
            guard let rows = buckets[slug], let exercise = rows.first?.exercise
            else { return nil }
            return (exercise, rows.sorted { $0.setIndex < $1.setIndex })
        }
    }

    /// The planned day whose contents best match what was actually logged.
    /// Nil when nothing lines up — an improvised session is not "Push A".
    private var dayName: String? {
        let done = Set(entries.compactMap { $0.exercise?.slug })
        guard !done.isEmpty else { return nil }
        let scored = days.map { day -> (String, Int) in
            let planned = Set(day.orderedItems.compactMap { $0.exercise?.slug })
            return (day.name, planned.intersection(done).count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    private var volume: Double { Tally.volume(entries.map(\.tally)) }
    private var cardioSeconds: Int { entries.reduce(0) { $0 + $1.seconds } }
    private var workingSets: Int { entries.filter { $0.setKind.counts && !$0.isCardio }.count }

    private var weighIn: WeighIn? {
        weighIns.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private var daysAgo: String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        let weeks = days / 7
        return weeks == 1 ? "Last week" : "\(weeks) weeks ago"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.md + 2) {
                header
                summary
                rows
                if let weighIn {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("On the scale").rfEyebrow()
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(Fmt.bodyWeight(weighIn.pounds))
                                .font(RFDesign.figure(28, relativeTo: .title))
                                .foregroundStyle(RFDesign.speech)
                            Text("lb").rfEyebrow(RFDesign.labelDim, size: 12)
                        }
                    }
                    .padding(.top, RFDesign.xs)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(daysAgo).rfEyebrow()
            Text(dayName ?? Fmt.weekdayDate(date))
                .font(RFDesign.title(34))
                .foregroundStyle(RFDesign.speech)
            Text(dayName == nil ? "Logged as you went" : Fmt.weekdayDate(date))
                .font(RFDesign.ui(13.5))
                .foregroundStyle(RFDesign.label)
        }
        .padding(.top, RFDesign.sm)
    }

    /// What the hour added up to. `said` rather than `ready` throughout — this
    /// is history, and history should not glow like the live screen does.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: RFDesign.lg) {
            if volume > 0 { figure(Tally.volumeText(volume), "moved") }
            if cardioSeconds > 0 { figure(Fmt.minutes(cardioSeconds), "cardio") }
            if workingSets > 0 {
                figure("\(workingSets)", workingSets == 1 ? "working set" : "working sets")
            }
            Spacer(minLength: 0)
        }
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(RFDesign.figure(24, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(RFDesign.said)
            Text(caption).rfEyebrow()
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if byExercise.isEmpty {
                EmptyNote(title: "Nothing logged.",
                          message: "This day has a weigh-in but no sets.")
            }
            ForEach(Array(byExercise.enumerated()), id: \.offset) { i, group in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.exercise.name)
                            .font(RFDesign.uiMedium(15))
                            .foregroundStyle(RFDesign.speech)
                        Text(detail(for: group.exercise, sets: group.sets))
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                    Spacer(minLength: 8)
                    Text(headline(for: group.exercise, sets: group.sets))
                        .font(RFDesign.figure(17, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(RFDesign.label)
                }
                .padding(.vertical, 13)
                if i < byExercise.count - 1 { Divider().overlay(RFDesign.hairline) }
            }
        }
    }

    /// The number on the right, in whatever unit that exercise answers in.
    private func headline(for exercise: Exercise, sets: [SetEntry]) -> String {
        if exercise.isCardio {
            return Fmt.minutes(sets.reduce(0) { $0 + $1.seconds })
        }
        let counted = sets.filter { $0.setKind.counts }
        // Least help on an assisted machine, most weight on everything else.
        let anchor = exercise.assisted ? counted.map(\.weight).min()
                                       : counted.map(\.weight).max()
        return Fmt.weight(anchor ?? 0)
    }

    private func detail(for exercise: Exercise, sets: [SetEntry]) -> String {
        if exercise.isCardio {
            var parts: [String] = []
            let miles = sets.reduce(0) { $0 + $1.distance }
            if miles > 0 { parts.append("\(Fmt.distance(miles)) mi") }
            if let incline = sets.map(\.incline).max(), incline > 0 {
                parts.append("\(Fmt.rate(incline))% grade")
            }
            return parts.isEmpty ? "on the clock" : parts.joined(separator: " · ")
        }
        let counted = sets.filter { $0.setKind.counts }
        let reps = counted.map { String($0.reps) }.joined(separator: ", ")
        let warmups = sets.count - counted.count
        var line = reps.isEmpty ? "warm-ups only" : reps
        if exercise.assisted { line += " · help" }
        if warmups > 0 { line += "  (+\(warmups) warm-up)" }
        return line
    }
}
