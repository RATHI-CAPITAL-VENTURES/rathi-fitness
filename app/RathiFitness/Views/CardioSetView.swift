import SwiftUI
import SwiftData

/// A treadmill, a bike, a rower — the screen for something you do for twenty
/// minutes rather than for eight reps.
///
/// A separate screen rather than a mode on `SetView`, because almost nothing is
/// shared: there is no plate math, no rep target, no e1RM, and the hero figure
/// is a clock rather than a weight. One screen doing both would have been a
/// column of `if exercise.isCardio` and two half-designs.
///
/// **It records; it does not time you.** The machine in front of you has a
/// clock, a distance and a grade on a display the size of a laptop, and an app
/// racing it would be a second number that disagrees. You copy the console over
/// when you step off — which is the actual gap this fills, because otherwise
/// that number exists nowhere ten seconds later.
struct CardioSetView: View {
    let item: PlanItem
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var rest: RestTimer
    @EnvironmentObject private var remote: RemoteControls

    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]

    @State private var values: [CardioMetric: Double] = [:]
    @State private var editing: CardioMetric?
    @State private var note = ""
    @State private var editingNote = false
    @State private var record: String?
    @State private var primed = false

    private var calendar: Calendar { .current }
    private var mine: [SetEntry] { allSets.filter { $0.exercise?.slug == exercise.slug } }
    private var todays: [SetEntry] {
        mine.filter { calendar.isDate($0.date, inSameDayAs: .now) }
            .sorted { $0.setIndex < $1.setIndex }
    }
    /// Cardio is usually one bout; intervals are the reason `targetSets` still
    /// means something here.
    private var isFinished: Bool { todays.count >= max(1, item.targetSets) }
    private var restingHere: Bool { rest.isResting && rest.exerciseName == exercise.name }

    /// The machine's own numbers, minus the clock, which is the hero.
    private var fields: [CardioMetric] {
        exercise.metrics.filter { $0 != .duration }
    }

    private var seconds: Int { Int(values[.duration] ?? 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.md) {
                title
                hero
                recordBanner
                MachineSettingsRow(exercise: exercise)
                Divider().overlay(RFDesign.hairline)
                metrics
                noteChip
                actions
                MusicBar()
                Divider().overlay(RFDesign.hairline)
                history
            }
            .padding(.horizontal, 22)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground(hue: roomHue, energy: roomEnergy))
        .navigationTitle(item.day?.name ?? exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { metric in
            MetricSheet(metric: metric, value: values[metric] ?? 0) { values[metric] = $0 }
        }
        .sheet(isPresented: $editingNote) { NoteSheet(note: note) { note = $0 } }
        .onAppear(perform: prime)
        .onAppear(perform: armHandsFree)
        .onDisappear(perform: disarmHandsFree)
    }

    private var roomHue: Double {
        restingHere ? RFDesign.coolHue(rest.progress()) : RFDesign.readyHue
    }
    private var roomEnergy: Double {
        restingHere ? RFDesign.roomGlowActive : RFDesign.roomGlow
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(exercise.name)
                .font(RFDesign.title(29))
                .foregroundStyle(RFDesign.speech)
            if item.targetSets > 1 {
                SetPips(total: item.targetSets, done: todays.count)
            } else {
                Text(planLine).rfEyebrow()
            }
        }
        .padding(.top, RFDesign.xs)
    }

    /// What the plan asked for, in one line, or what you did last time.
    private var planLine: String {
        var parts: [String] = []
        if item.targetSeconds > 0 { parts.append(Fmt.minutes(item.targetSeconds)) }
        if item.targetDistance > 0 { parts.append("\(Fmt.distance(item.targetDistance)) mi") }
        if item.targetIncline > 0 { parts.append("\(Fmt.rate(item.targetIncline))% grade") }
        if item.targetSpeed > 0 { parts.append("\(Fmt.rate(item.targetSpeed)) mph") }
        if parts.isEmpty, let last = lastBout {
            return "Last time — " + summary(of: last)
        }
        return parts.isEmpty ? "No target — whatever you feel like" : parts.joined(separator: " · ")
    }

    /// The clock, or the interval cooldown when one is running.
    @ViewBuilder private var hero: some View {
        if restingHere {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                CooldownRing(progress: rest.progress(at: timeline.date),
                             remaining: rest.remaining(at: timeline.date),
                             caption: "Between")
            }
            .frame(maxWidth: .infinity)
        } else {
            Button { editing = .duration } label: {
                VStack(spacing: 2) {
                    Text(Fmt.duration(seconds))
                        .font(RFDesign.figure(74))
                        .monospacedDigit()
                        .foregroundStyle(seconds > 0 ? RFDesign.speech : RFDesign.labelDim)
                    Text("Time on the clock").rfEyebrow()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RFDesign.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardio-duration")
        }
    }

    @ViewBuilder private var recordBanner: some View {
        if let record {
            HStack(spacing: 7) {
                Image(systemName: "trophy.fill").font(.system(size: 12))
                Text(record).font(RFDesign.ui(13, bold: true))
            }
            .foregroundStyle(RFDesign.ready)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RFDesign.ready.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    /// One row per number this machine actually has. A rower shows no incline
    /// and a treadmill no damper, which is `Exercise.metrics` doing its job.
    private var metrics: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element) { i, metric in
                HStack(spacing: 10) {
                    Text(metric.label)
                        .font(RFDesign.ui(14))
                        .foregroundStyle(RFDesign.label)
                    Spacer(minLength: 8)
                    stepButton("minus", of: metric.label) { nudge(metric, -1) }
                    Button { editing = metric } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.metric(values[metric] ?? 0, metric))
                                .font(RFDesign.figure(23, relativeTo: .title3))
                                .monospacedDigit()
                                .foregroundStyle((values[metric] ?? 0) > 0
                                                 ? RFDesign.speech : RFDesign.labelDim)
                            Text(metric.unit).rfEyebrow(RFDesign.labelDim, size: 10)
                        }
                        .frame(minWidth: 74)
                    }
                    .buttonStyle(.plain)
                    stepButton("plus", of: metric.label) { nudge(metric, 1) }
                }
                .padding(.vertical, 9)
                if i < fields.count - 1 { Divider().overlay(RFDesign.hairline) }
            }
        }
    }

    private var noteChip: some View {
        Button { editingNote = true } label: {
            Text(note.isEmpty ? "Note" : "Note ✓")
                .font(RFDesign.ui(12, bold: !note.isEmpty))
                .foregroundStyle(note.isEmpty ? RFDesign.label : RFDesign.ground)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(note.isEmpty ? Color.clear : RFDesign.label)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(note.isEmpty ? RFDesign.hairline : Color.clear,
                                        lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
    }

    /// `of:` is the dial being nudged. Without it these are two unlabelled
    /// glyphs — `SettingsKit.StepperRow` has always named its own pair and this
    /// one, which is the same control drawn again, never did. VoiceOver read
    /// both as "button", and so did the test that wanted to press one.
    private func stepButton(_ symbol: String, of label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RFDesign.speech)
                .frame(width: 34, height: 34)
                .background(Circle().fill(RFDesign.surface))
                .overlay(Circle().stroke(RFDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Decrease \(label)" : "Increase \(label)")
    }

    private var actions: some View {
        HStack(spacing: 9) {
            if restingHere {
                SecondaryButton(title: "+30s") { rest.extend(by: 30) }
                PrimaryButton(title: "Next interval",
                              tint: RFDesign.coolColor(rest.progress()),
                              filled: false) { rest.stop() }
            } else {
                if !todays.isEmpty {
                    SecondaryButton(title: "Undo") { undoLast() }
                }
                PrimaryButton(title: isFinished ? "Log another" : logTitle,
                              tint: RFDesign.ready, filled: true) { log() }
                    .disabled(!hasSomethingToLog)
                    .opacity(hasSomethingToLog ? 1 : 0.45)
                    .accessibilityIdentifier("log-cardio")
            }
        }
        .padding(.top, 2)
    }

    private var logTitle: String {
        item.targetSets > 1 ? "Log interval \(todays.count + 1)" : "Log it"
    }

    /// Nothing on the clock and nothing on the odometer is not a workout — and
    /// an all-zero row in the log is worse than no row, because it looks like
    /// you did nothing rather than like you forgot to write it down.
    private var hasSomethingToLog: Bool {
        seconds > 0 || (values[.distance] ?? 0) > 0
    }

    // MARK: history

    private var lastBout: SetEntry? {
        mine.first { !calendar.isDate($0.date, inSameDayAs: .now) }
    }

    private var recentBouts: [SetEntry] {
        Array(mine.filter { !calendar.isDate($0.date, inSameDayAs: .now) }.prefix(3))
    }

    private func summary(of entry: SetEntry) -> String {
        var parts: [String] = []
        if entry.seconds > 0 { parts.append(Fmt.minutes(entry.seconds)) }
        if entry.distance > 0 { parts.append("\(Fmt.distance(entry.distance)) mi") }
        if entry.incline > 0 { parts.append("\(Fmt.rate(entry.incline))%") }
        if let mph = entry.achievedSpeed { parts.append("\(Fmt.rate(mph)) mph") }
        else if entry.speed > 0 { parts.append("\(Fmt.rate(entry.speed)) mph") }
        if entry.resistance > 0 { parts.append("L\(Int(entry.resistance))") }
        if entry.averageHeartRate > 0 { parts.append("\(entry.averageHeartRate) bpm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(exercise.name) · last three")
                .rfEyebrow()
                .padding(.bottom, RFDesign.xs)
            if recentBouts.isEmpty {
                Text("No history yet.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
                    .padding(.vertical, 7)
            }
            ForEach(Array(recentBouts.enumerated()), id: \.offset) { i, entry in
                HStack(alignment: .top) {
                    Text(Fmt.weekdayDate(entry.date))
                        .font(RFDesign.ui(13))
                        .foregroundStyle(RFDesign.label)
                    Spacer(minLength: 10)
                    Text(summary(of: entry))
                        .font(RFDesign.ui(13))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(RFDesign.speech)
                }
                .padding(.vertical, 7)
                if i < recentBouts.count - 1 { Divider().overlay(RFDesign.hairline) }
            }
        }
    }

    // MARK: behaviour

    /// Open on what you are most likely to want: the plan's target, then last
    /// time's numbers, then blank. Incline and resistance carry over from last
    /// time even when the plan is silent — those are settings you keep, not
    /// results you beat.
    private func prime() {
        guard !primed else { return }
        primed = true
        let last = lastBout
        for metric in exercise.metrics {
            let target: Double
            switch metric {
            case .duration: target = Double(item.targetSeconds)
            case .distance: target = item.targetDistance
            case .speed: target = item.targetSpeed
            case .incline: target = item.targetIncline
            case .resistance: target = item.targetResistance
            case .heartRate: target = 0
            }
            if target > 0 {
                values[metric] = target
            } else if let last, metric == .incline || metric == .resistance || metric == .speed {
                values[metric] = last.value(for: metric)
            } else {
                values[metric] = 0
            }
        }
    }

    private func nudge(_ metric: CardioMetric, _ direction: Double) {
        let next = (values[metric] ?? 0) + metric.step * direction
        // Rounded to the step so repeated taps cannot drift onto 3.0999999.
        let stepped = (next / metric.step).rounded() * metric.step
        values[metric] = max(0, stepped)
    }

    private func log() {
        let candidate = bout(from: values)
        let history = recentAndTodayBouts
        withAnimation(RFDesign.settle) {
            record = Tally.cardioHeadline(for: candidate, history: history)
        }
        if record != nil {
            Haptics.shared.play(.record)
            AudioHub.shared.play(.record)
        } else {
            Haptics.shared.play(.logged)
            AudioHub.shared.play(.logged)
        }

        let entry = SetEntry(
            exercise: exercise, weight: 0, reps: 0, setIndex: todays.count + 1,
            kind: .working, note: note,
            seconds: seconds,
            distance: values[.distance] ?? 0,
            speed: values[.speed] ?? 0,
            incline: values[.incline] ?? 0,
            resistance: values[.resistance] ?? 0,
            averageHeartRate: Int(values[.heartRate] ?? 0))
        context.insert(entry)
        note = ""
        context.saveOrReport("logging a set")
        snapshots.setNeedsWrite(context)

        // Intervals rest; a single twenty-minute bout does not. Starting a
        // cooldown after the only thing you came to do would be the app asking
        // you to stand next to a treadmill for ninety seconds.
        if item.targetSets > 1 && item.restSeconds > 0 && todays.count < item.targetSets {
            rest.start(seconds: item.restSeconds, exercise: exercise.name)
        } else if isFinished {
            dismiss()
        }
    }

    /// Everything logged for this exercise except the bout being judged.
    private var recentAndTodayBouts: [Tally.Bout] {
        mine.map { entry in
            Tally.Bout(seconds: entry.seconds, distance: entry.distance,
                       incline: entry.incline, speed: entry.speed,
                       resistance: entry.resistance, heartRate: entry.averageHeartRate)
        }
    }

    private func bout(from values: [CardioMetric: Double]) -> Tally.Bout {
        Tally.Bout(seconds: Int(values[.duration] ?? 0),
                   distance: values[.distance] ?? 0,
                   incline: values[.incline] ?? 0,
                   speed: values[.speed] ?? 0,
                   resistance: values[.resistance] ?? 0,
                   heartRate: Int(values[.heartRate] ?? 0))
    }

    private func undoLast() {
        record = nil
        guard let last = todays.last else { return }
        context.delete(last)
        context.saveOrReport("undoing a set")
        snapshots.setNeedsWrite(context)
    }

    // MARK: hands-free

    private func armHandsFree() {
        remote.handlers = RemoteControls.Handlers(
            logSet: { if hasSomethingToLog { log() } },
            skipRest: { rest.stop() },
            extendRest: { rest.extend(by: 30) },
            describe: { announcement },
            isResting: { restingHere })
        remote.arm()
        remote.publishNowPlaying(title: exercise.name, subtitle: item.day?.name)
    }

    private func disarmHandsFree() {
        remote.handlers = RemoteControls.Handlers()
        remote.disarm()
    }

    private var announcement: String {
        if restingHere { return "\(rest.remaining()) seconds until the next interval." }
        return "\(exercise.name). \(Fmt.minutes(seconds)) on the clock."
    }
}

/// Type one cardio number. Minutes for the clock, because nobody thinks in
/// seconds about a treadmill; its own unit for everything else.
struct MetricSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: CardioMetric
    @State private var text: String
    var onSave: (Double) -> Void

    init(metric: CardioMetric, value: Double, onSave: @escaping (Double) -> Void) {
        self.metric = metric
        self.onSave = onSave
        let shown = metric == .duration ? value / 60 : value
        _text = State(initialValue: shown > 0 ? Fmt.weight(shown) : "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RFDesign.lg) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $text)
                        .font(RFDesign.figure(58))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(RFDesign.speech)
                    Text(metric == .duration ? "min" : metric.unit)
                        .rfEyebrow(RFDesign.labelDim, size: 14)
                }
                .padding(.horizontal, RFDesign.xl)
                Spacer()
            }
            .padding(.top, RFDesign.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle(metric.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        if let v = Double(text.trimmingCharacters(in: .whitespaces)) {
                            onSave(metric == .duration ? (v * 60).rounded() : v)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}
