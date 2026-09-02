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
/// **One workout, not one day.** It took a `Date` and swept up everything logged
/// on it, which meant a two-a-day appeared as a single page with both workouts'
/// exercises run together and their volumes added. It takes the session now, so
/// the swipe-back goes through workouts in the order you did them.
///
/// What it was called is no longer guessed. The old version scored the logged
/// lifts against each planned day's contents — right, given no better
/// information, and wrong whenever you improvised or two workouts shared a
/// lift. The session recorded its name when you did it.
struct PastDayView: View {
    let session: Session

    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]

    private var calendar: Calendar { .current }

    /// The day this workout happened on. Still needed for the weigh-in and for
    /// "3 days ago", both of which really are day-scoped.
    private var date: Date { session.startedAt }

    private var entries: [SetEntry] { session.orderedSets }

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

    /// What the workout was called, as recorded. `nil` for one backfilled from
    /// history that matched no planned day — still better than a wrong label.
    private var dayName: String? {
        session.dayName.isEmpty || session.dayName == Session.unnamed
            ? nil : session.dayName
    }

    private var volume: Double {
        let log = Tally.BodyWeightLog(weighIns.map { (date: $0.date, pounds: $0.pounds) })
        return Tally.volume(entries.map { $0.tally(bodyWeight: log.pounds(on: $0.date)) })
    }
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
