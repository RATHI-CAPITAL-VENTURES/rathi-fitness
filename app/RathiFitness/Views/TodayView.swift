import SwiftUI
import SwiftData

/// The day as a list, and the list is the workout.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var rest: RestTimer
    @EnvironmentObject private var health: HealthBridge

    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]
    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]
    @Query(sort: \WeighIn.date, order: .reverse) private var weighIns: [WeighIn]
    @Query private var schedules: [Schedule]

    @State private var weighingIn = false
    @State private var overrideDay: PlannedDay?
    @State private var showingSettings = false
    @State private var showingPlan = false

    private var calendar: Calendar { .current }
    private var config: Rotation.Config { schedules.first?.config ?? Rotation.Config() }

    /// Every date a set was logged on — the input the rotation counts.
    private var sessionDates: [Date] { allSets.map(\.date) }

    private var lastSession: Date? {
        allSets.filter { !calendar.isDate($0.date, inSameDayAs: .now) }
            .map(\.date).max()
    }

    private var isTrainingDay: Bool {
        Rotation.isTrainingDay(.now, config: config, lastSession: lastSession,
                               calendar: calendar)
    }

    /// What is up today.
    ///
    /// Resolved on every read rather than assigned once at appear: the store may
    /// still be seeding when this view first draws, and a one-shot assignment
    /// then latches nil forever.
    private var today: PlannedDay? {
        if let chosen = overrideDay ?? launchArgumentDay { return chosen }
        switch config.mode {
        case .weekday:
            return days.first { $0.weekday == calendar.component(.weekday, from: .now) }
        case .rotation, .everyNDays:
            guard isTrainingDay else { return nil }
            return rotationDay
        }
    }

    /// The workout the rotation has reached, training day or not — so a rest day
    /// can still say what is coming.
    private var rotationDay: PlannedDay? {
        guard let index = Rotation.index(on: .now, sessionDates: sessionDates,
                                         dayCount: days.count, calendar: calendar)
        else { return nil }
        return days.indices.contains(index) ? days[index] : days.first
    }

    /// `-RFDay "Push A"` opens that day whatever the calendar says.
    ///
    /// Exists for the UI tests and for looking at a training day on a Thursday.
    /// It only ever selects a day the plan already contains, so the worst it can
    /// do is show you Legs on a Tuesday.
    private var launchArgumentDay: PlannedDay? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-RFDay"), i + 1 < args.count else { return nil }
        return days.first { $0.name == args[i + 1] }
    }
    private var todaysSets: [SetEntry] {
        allSets.filter { calendar.isDate($0.date, inSameDayAs: .now) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RFDesign.md + 2) {
                    LegacyDataBanner()
                    header
                    if let day = today {
                        progress(for: day)
                        rows(for: day)
                        moved(for: day)
                    } else {
                        restDay
                    }
                    MusicBar()
                    bodyWeight
                }
                .padding(.horizontal, 22)
                .padding(.bottom, RFDesign.xl)
            }
            .scrollIndicators(.hidden)
            .background(RoomBackground(hue: roomHue, energy: roomEnergy))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(RFDesign.label)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(days) { day in
                            Button(day.name) { overrideDay = day }
                        }
                        if overrideDay != nil {
                            Button("Back to today") { overrideDay = nil }
                        }
                        Divider()
                        Button {
                            showingPlan = true
                        } label: {
                            Label("Edit the plan", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "calendar")
                            .foregroundStyle(RFDesign.label)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingPlan) { PlanView() }
            .sheet(isPresented: $weighingIn) {
                WeighInSheet { pounds in
                    context.insert(WeighIn(pounds: pounds))
                    try? context.save()
                    snapshots.setNeedsWrite(context)
                    // Back out to Health, so it does not disagree with us about
                    // a number you typed here.
                    Task { await health.write(weighIn: pounds) }
                }
            }
        }
    }

    private var roomHue: Double {
        rest.isResting ? RFDesign.coolHue(rest.progress()) : RFDesign.readyHue
    }
    private var roomEnergy: Double {
        rest.isResting ? RFDesign.roomGlowActive : RFDesign.roomGlow
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headerEyebrow).rfEyebrow()
            Text(today?.name ?? "Rest day")
                .font(RFDesign.title(34))
                .foregroundStyle(RFDesign.speech)
            if let day = today {
                Text(subtitle(for: day))
                    .font(RFDesign.ui(13.5))
                    .foregroundStyle(RFDesign.label)
            }
        }
        .padding(.top, RFDesign.sm)
    }

    private var headerEyebrow: String {
        if overrideDay != nil || launchArgumentDay != nil { return "Doing out of order" }
        guard config.mode != .weekday, days.count > 1,
              let index = Rotation.index(on: .now, sessionDates: sessionDates,
                                         dayCount: days.count, calendar: calendar)
        else { return Fmt.weekdayDate(.now) }
        // "Thu 21 Aug · 3 of 4" — where you are in the cycle, which is the thing
        // a rotation makes hard to hold in your head.
        return "\(Fmt.weekdayDate(.now)) · \(index + 1) of \(days.count)"
    }

    private func subtitle(for day: PlannedDay) -> String {
        let items = day.orderedItems
        let sets = items.reduce(0) { $0 + $1.targetSets }
        let minutes = items.reduce(0) { $0 + $1.targetSets * ($1.restSeconds + 40) } / 60
        return "\(items.count) exercises · \(sets) sets · about \(minutes) min"
    }

    private func progress(for day: PlannedDay) -> some View {
        let items = day.orderedItems
        let done = items.filter { isDone($0) }.count
        return VStack(spacing: 7) {
            Rail(fraction: items.isEmpty ? 0 : Double(done) / Double(items.count))
            HStack {
                Text("\(done) of \(items.count) done").rfEyebrow()
                Spacer()
                if let first = todaysSets.last {
                    let mins = Int(Date.now.timeIntervalSince(first.date) / 60)
                    Text("\(mins) min in").rfEyebrow(RFDesign.ready)
                }
            }
        }
    }

    private func rows(for day: PlannedDay) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(day.orderedItems.enumerated()), id: \.element.persistentModelID) { i, item in
                if let exercise = item.exercise {
                    NavigationLink {
                        SetView(item: item, exercise: exercise)
                    } label: {
                        ExerciseRow(name: exercise.name,
                                    meta: meta(for: item),
                                    trailing: Fmt.weight(item.targetWeight),
                                    state: state(for: item))
                            .accessibilityIdentifier("row-\(exercise.slug)")
                    }
                    .buttonStyle(.plain)
                    if i < day.orderedItems.count - 1 {
                        Divider().overlay(RFDesign.hairline)
                    }
                }
            }
        }
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: RFDesign.sm) {
            EmptyNote(title: "Rest day.", message: restMessage)
            Button { showingPlan = true } label: {
                Label("Edit the plan", systemImage: "slider.horizontal.3")
                    .font(RFDesign.ui(14, bold: true))
                    .foregroundStyle(RFDesign.ready)
            }
            .buttonStyle(.plain)
        }
    }

    /// What the hour added up to.
    ///
    /// A session is four exercises and a lot of standing around; the tonnage is
    /// the only number that makes it countable. Shown only once there is
    /// something to show — a zero here would be a scoreboard telling you off.
    @ViewBuilder private func moved(for day: PlannedDay) -> some View {
        let sets = todaysSets.map {
            Tally.Set(weight: $0.weight, reps: $0.reps, kind: $0.setKind)
        }
        if !sets.isEmpty {
            let comparison = Tally.SessionComparison(
                volume: Tally.volume(sets),
                previousVolume: previousVolume(for: day))
            VStack(alignment: .leading, spacing: 5) {
                Text("Moved today").rfEyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Tally.volumeText(comparison.volume))
                        .font(RFDesign.figure(34, relativeTo: .title))
                        .foregroundStyle(RFDesign.ready)
                    if let line = comparison.line {
                        Text(line)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                }
            }
            .padding(.top, RFDesign.xs)
        }
    }

    /// The last time this same day was done — comparing Push A to Legs would be
    /// a number that moves for no reason.
    private func previousVolume(for day: PlannedDay) -> Double? {
        let slugs = Set(day.orderedItems.compactMap { $0.exercise?.slug })
        guard !slugs.isEmpty else { return nil }
        let past = allSets.filter {
            !calendar.isDate($0.date, inSameDayAs: .now)
            && slugs.contains($0.exercise?.slug ?? "")
        }
        let byDay = Dictionary(grouping: past) { calendar.startOfDay(for: $0.date) }
        guard let mostRecent = byDay.keys.max(), let entries = byDay[mostRecent] else {
            return nil
        }
        return Tally.volume(entries.map {
            Tally.Set(weight: $0.weight, reps: $0.reps, kind: $0.setKind)
        })
    }

    /// What is next and when — a rest day is still a place you look to find out
    /// what is coming, and "nothing scheduled" answers neither question.
    private var restMessage: String {
        guard config.mode != .weekday else {
            return "Pick a day from the calendar button to do one anyway, or change "
                 + "what happens on \(Fmt.weekdayDate(.now))."
        }
        var parts: [String] = []
        if let next = rotationDay { parts.append("Next up is \(next.name)") }
        if let when = Rotation.nextTrainingDay(
            from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now,
            config: config, lastSession: lastSession, calendar: calendar) {
            let weekday = DateFormatter()
            weekday.dateFormat = "EEEE"
            parts.append(calendar.isDateInTomorrow(when)
                         ? "tomorrow" : "on \(weekday.string(from: when))")
        }
        let line = parts.isEmpty ? "Nothing scheduled." : parts.joined(separator: ", ") + "."
        return line + " You train \(Rotation.describe(config)) — "
             + "the calendar button starts one early."
    }

    private var bodyWeight: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body weight").rfEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(weighIns.first.map { Fmt.bodyWeight($0.pounds) } ?? "—")
                    .font(RFDesign.figure(30, relativeTo: .title))
                    .foregroundStyle(RFDesign.speech)
                Text("lb").rfEyebrow(RFDesign.labelDim, size: 12)
                Spacer()
                if let delta = weekChange {
                    Text("\(Fmt.signed(delta)) this week")
                        .font(RFDesign.ui(12.5))
                        .foregroundStyle(delta <= 0 ? RFDesign.ready : RFDesign.label)
                }
                Button { weighingIn = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(RFDesign.ready)
                }
                .accessibilityLabel("Log today's weight")
            }
        }
        .padding(.top, RFDesign.sm)
    }

    private var weekChange: Double? {
        guard let latest = weighIns.first else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        guard let base = weighIns.first(where: { $0.date <= weekAgo }) else { return nil }
        return latest.pounds - base.pounds
    }

    // MARK: state

    private func performed(_ item: PlanItem) -> [SetEntry] {
        guard let slug = item.exercise?.slug else { return [] }
        return todaysSets.filter { $0.exercise?.slug == slug }
    }

    /// Sets that move you toward the target. Three warm-ups used to tick an
    /// exercise off — the checklist lying about the one thing it is for.
    private func working(_ item: PlanItem) -> [SetEntry] {
        performed(item).filter { $0.setKind.counts }
    }

    private func isDone(_ item: PlanItem) -> Bool {
        working(item).count >= item.targetSets
    }

    private func state(for item: PlanItem) -> ExerciseRow.State {
        if isDone(item) { return .done }
        if !performed(item).isEmpty { return .live }
        if rest.exerciseName != nil && rest.exerciseName == item.exercise?.name { return .live }
        return .pending
    }

    /// The plan and the deviation in the same breath.
    private func meta(for item: PlanItem) -> String {
        let done = working(item)
        let warmups = performed(item).count - done.count
        let plan = "\(item.targetSets) × \(item.targetReps) · \(Fmt.weight(item.targetWeight)) lb"
        if done.isEmpty {
            return warmups > 0 ? "\(plan) · \(warmups) warm-up done" : plan
        }
        if done.count >= item.targetSets {
            let reps = done.sorted { $0.setIndex < $1.setIndex }.map { String($0.reps) }
            let hitAll = done.allSatisfy { $0.reps >= item.targetReps }
            return hitAll ? "\(plan) · all \(done.count) hit"
                          : "\(plan) · got \(reps.joined(separator: ", "))"
        }
        if rest.isResting && rest.exerciseName == item.exercise?.name {
            return "set \(done.count) of \(item.targetSets) · resting \(Fmt.clock(rest.remaining()))"
        }
        return "set \(done.count) of \(item.targetSets) done"
            + (warmups > 0 ? " · +\(warmups) warm-up" : "")
    }
}

/// Logging the scale. One number, a big keypad, and out.
struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var onSave: (Double) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: RFDesign.lg) {
                Text("What did the scale say?")
                    .font(RFDesign.ui(15))
                    .foregroundStyle(RFDesign.label)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("176.4", text: $text)
                        .font(RFDesign.figure(64))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(RFDesign.speech)
                    Text("lb").rfEyebrow(RFDesign.labelDim, size: 14)
                }
                .padding(.horizontal, RFDesign.xl)
                Spacer()
            }
            .padding(.top, RFDesign.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RFDesign.ground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 {
                            onSave(v)
                        }
                        dismiss()
                    }
                    .disabled(Double(text.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}
