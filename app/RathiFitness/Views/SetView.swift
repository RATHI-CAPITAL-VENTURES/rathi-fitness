import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// One exercise, mid-workout: what to lift, how far through you are, and how
/// long until you go again.
struct SetView: View {
    let item: PlanItem
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var rest: RestTimer

    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var editingWeight = false
    @State private var started = false
    @State private var record: String?

    private var calendar: Calendar { .current }

    private var mine: [SetEntry] { allSets.filter { $0.exercise?.slug == exercise.slug } }
    private var todays: [SetEntry] {
        mine.filter { calendar.isDate($0.date, inSameDayAs: .now) }
            .sorted { $0.setIndex < $1.setIndex }
    }
    private var nextSet: Int { todays.count + 1 }
    private var isFinished: Bool { todays.count >= item.targetSets }
    private var restingHere: Bool { rest.isResting && rest.exerciseName == exercise.name }

    private var loadout: PlateMath.Loadout {
        PlateMath.loadout(target: weight, bar: exercise.barWeight)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.md) {
                title
                hero
                statusLine
                recordBanner
                Divider().overlay(RFDesign.hairline)
                stepper
                if exercise.loadingKind.showsPlateMath {
                    HStack(spacing: 9) {
                        Text("Per side").rfEyebrow()
                        PlateChips(loadout: loadout, bar: exercise.barWeight)
                    }
                }
                actions
                Divider().overlay(RFDesign.hairline)
                history
            }
            .padding(.horizontal, 22)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground(hue: heroHue, energy: heroEnergy))
        .navigationTitle(item.day?.name ?? exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("Set \(min(nextSet, item.targetSets)) of \(item.targetSets)")
                    .rfEyebrow()
            }
        }
        .sheet(isPresented: $editingWeight) {
            WeightSheet(weight: weight, unitLabel: "lb") { weight = $0 }
        }
        .onAppear(perform: prime)
    }

    // MARK: hero

    private var heroProgress: Double { restingHere ? rest.progress() : 1 }
    private var heroHue: Double { RFDesign.coolHue(heroProgress) }
    private var heroEnergy: Double { restingHere ? RFDesign.roomGlowActive : RFDesign.roomGlow }

    private var title: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(exercise.name)
                .font(RFDesign.title(29))
                .foregroundStyle(RFDesign.speech)
            SetPips(total: item.targetSets, done: todays.count)
        }
        .padding(.top, RFDesign.xs)
    }

    /// The ring is always here, so nothing jumps when a rest starts. Idle it
    /// shows the rest you are about to take; running, it counts it down.
    private var hero: some View {
        TimelineView(.periodic(from: .now, by: restingHere ? 0.25 : 60)) { timeline in
            let now = timeline.date
            CooldownRing(
                progress: restingHere ? rest.progress(at: now) : 1,
                remaining: restingHere ? rest.remaining(at: now) : item.restSeconds,
                caption: restingHere ? "Cooldown" : (isFinished ? "Done" : "Ready"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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

    private var statusLine: some View {
        Group {
            if let last = todays.last {
                Text("Set \(last.setIndex) logged — ")
                    .foregroundStyle(RFDesign.label)
                + Text("\(Fmt.weight(last.weight)) × \(last.reps)")
                    .foregroundStyle(RFDesign.speech)
                + Text(comparison(to: last)).foregroundStyle(RFDesign.label)
            } else if let previous = lastSession.first {
                Text("Last time — ")
                    .foregroundStyle(RFDesign.label)
                + Text("\(Fmt.weight(previous.weight)) × \(previous.reps)")
                    .foregroundStyle(RFDesign.speech)
                + Text(" for \(lastSession.count) sets").foregroundStyle(RFDesign.label)
            } else {
                Text("First time on this one.").foregroundStyle(RFDesign.label)
            }
        }
        .font(RFDesign.ui(13))
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private func comparison(to entry: SetEntry) -> String {
        guard let prev = lastSession.first(where: { $0.setIndex == entry.setIndex }) else { return "." }
        if prev.weight == entry.weight && prev.reps == entry.reps { return ". Same as last week." }
        if entry.weight > prev.weight { return ". Up \(Fmt.weight(entry.weight - prev.weight)) lb." }
        if entry.reps > prev.reps { return ". \(entry.reps - prev.reps) more reps." }
        return "."
    }

    // MARK: input

    private var stepper: some View {
        HStack(spacing: 12) {
            stepButton("minus") { adjustWeight(-5) }
            Button { editingWeight = true } label: {
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.weight(weight))
                            .font(RFDesign.figure(64))
                            .monospacedDigit()
                            .foregroundStyle(RFDesign.speech)
                        Text("lb").rfEyebrow(RFDesign.labelDim, size: 14)
                    }
                    HStack(spacing: 10) {
                        Button { reps = max(1, reps - 1) } label: {
                            Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                        }
                        Text("× \(reps) reps")
                            .font(RFDesign.ui(13))
                            .monospacedDigit()
                        Button { reps += 1 } label: {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(RFDesign.labelDim)
                    .buttonStyle(.plain)
                }
            }
            .buttonStyle(.plain)
            stepButton("plus") { adjustWeight(5) }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(RFDesign.speech)
                .frame(width: 44, height: 44)
                .background(Circle().fill(RFDesign.surface))
                .overlay(Circle().stroke(RFDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// `+` never lands on a weight the rack cannot make.
    private func adjustWeight(_ delta: Double) {
        weight = exercise.loadingKind.showsPlateMath
            ? PlateMath.step(from: weight, by: delta, bar: exercise.barWeight)
            : max(0, weight + delta)
    }

    // MARK: actions

    private var actions: some View {
        HStack(spacing: 9) {
            if restingHere {
                SecondaryButton(title: "+30s") { rest.extend(by: 30) }
                PrimaryButton(title: isFinished ? "Done — back to today" : "Skip to set \(nextSet)",
                              tint: RFDesign.coolColor(rest.progress()),
                              filled: false) {
                    rest.stop()
                    if isFinished { dismiss() }
                }
            } else if isFinished {
                PrimaryButton(title: "Done — back to today",
                              tint: RFDesign.ready, filled: true) { dismiss() }
            } else {
                if !todays.isEmpty {
                    SecondaryButton(title: "Undo") { undoLast() }
                }
                PrimaryButton(title: "Log set \(nextSet)",
                              tint: RFDesign.ready, filled: true) { logSet() }
                    .accessibilityIdentifier("log-set")
            }
        }
        .padding(.top, 2)
    }

    // MARK: history

    /// The most recent day this exercise was done that ISN'T today.
    private var lastSession: [SetEntry] {
        let previous = mine.filter { !calendar.isDate($0.date, inSameDayAs: .now) }
        guard let day = previous.first?.date else { return [] }
        return previous.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.setIndex < $1.setIndex }
    }

    private var recentDays: [(date: Date, entries: [SetEntry])] {
        let previous = mine.filter { !calendar.isDate($0.date, inSameDayAs: .now) }
        let grouped = Dictionary(grouping: previous) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).prefix(3).map {
            ($0, (grouped[$0] ?? []).sorted { $0.setIndex < $1.setIndex })
        }
    }

    /// One prior session tells you what you did. Three tell you if you're stalling.
    private var history: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(exercise.name) · last three")
                .rfEyebrow()
                .padding(.bottom, RFDesign.xs)
            if recentDays.isEmpty {
                Text("No history yet.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
                    .padding(.vertical, 7)
            }
            ForEach(Array(recentDays.enumerated()), id: \.offset) { i, session in
                HStack {
                    Text(Fmt.weekdayDate(session.date))
                        .font(RFDesign.ui(13))
                        .foregroundStyle(RFDesign.label)
                    Spacer()
                    Text("\(Fmt.weight(session.entries.map(\.weight).max() ?? 0)) · "
                         + session.entries.map { String($0.reps) }.joined(separator: ", "))
                        .font(RFDesign.ui(13))
                        .monospacedDigit()
                        .foregroundStyle(RFDesign.speech)
                }
                .padding(.vertical, 7)
                if i < recentDays.count - 1 { Divider().overlay(RFDesign.hairline) }
            }
        }
    }

    // MARK: behaviour

    /// Open on the weight you are most likely to want: what you did last time,
    /// falling back to the plan.
    private func prime() {
        guard !started else { return }
        started = true
        weight = todays.last?.weight ?? lastSession.first?.weight ?? item.targetWeight
        reps = item.targetReps
    }

    private func logSet() {
        // Records are judged against history WITHOUT this set — including it
        // would make every set a record for beating itself.
        let history = mine.map { Progress.Set(weight: $0.weight, reps: $0.reps) }
        let candidate = Progress.Set(weight: weight, reps: reps)
        withAnimation(RFDesign.settle) {
            record = Progress.headline(for: candidate, history: history)
        }
        #if canImport(UIKit)
        if record != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        #endif

        let entry = SetEntry(exercise: exercise, weight: weight, reps: reps, setIndex: nextSet)
        context.insert(entry)
        try? context.save()
        snapshots.setNeedsWrite(context)
        // The rest runs even after the last set, because what follows it is
        // usually a walk to the next machine rather than leaving the gym.
        rest.start(seconds: item.restSeconds, exercise: exercise.name)
    }

    private func undoLast() {
        record = nil
        guard let last = todays.last else { return }
        context.delete(last)
        try? context.save()
        snapshots.setNeedsWrite(context)
    }
}

/// Type an exact weight, for the days the steppers are too slow.
struct WeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let unitLabel: String
    var onSave: (Double) -> Void

    init(weight: Double, unitLabel: String, onSave: @escaping (Double) -> Void) {
        _text = State(initialValue: Fmt.weight(weight))
        self.unitLabel = unitLabel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RFDesign.lg) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $text)
                        .font(RFDesign.figure(64))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(RFDesign.speech)
                    Text(unitLabel).rfEyebrow(RFDesign.labelDim, size: 14)
                }
                .padding(.horizontal, RFDesign.xl)
                Spacer()
            }
            .padding(.top, RFDesign.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RFDesign.ground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        if let v = Double(text.trimmingCharacters(in: .whitespaces)) { onSave(v) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
