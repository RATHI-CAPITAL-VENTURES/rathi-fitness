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
    @Query private var sessions: [Session]
    @EnvironmentObject private var remote: RemoteControls

    @Query(sort: \SetEntry.date, order: .reverse) private var allSets: [SetEntry]

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var editingWeight = false
    @State private var started = false
    @State private var record: String?
    @State private var kind: SetKind = .working
    @State private var rpe: Double = 0
    @State private var note: String = ""
    @State private var editingNote = false

    private var calendar: Calendar { .current }

    private var mine: [SetEntry] { allSets.filter { $0.exercise?.slug == exercise.slug } }
    /// This workout's sets, not today's.
    ///
    /// Day-scoped, an evening bench continued the morning's numbering: set 5 of
    /// 4, pips overflowing, and a record judged against a bout that finished
    /// eight hours earlier. Scoped to the open session, a second workout starts
    /// at set 1 the way it actually did.
    private var todays: [SetEntry] {
        guard let session = currentSession else { return [] }
        return mine
            .filter { $0.session?.persistentModelID == session.persistentModelID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    /// The workout in progress for this plan item's day, if one is open.
    private var currentSession: Session? {
        sessions.first {
            $0.isOpen
                && calendar.isDate($0.startedAt, inSameDayAs: .now)
                && $0.plannedDay?.persistentModelID == item.day?.persistentModelID
        }
    }
    /// Sequential, so a warm-up is set 1 and the numbering matches what you did.
    private var nextSet: Int { todays.count + 1 }
    /// Progress toward the target counts working sets only.
    private var workingToday: [SetEntry] { todays.filter { $0.setKind.counts } }
    private var nextWorkingSet: Int { workingToday.count + 1 }
    private var isFinished: Bool { workingToday.count >= item.targetSets }
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
                MachineSettingsRow(exercise: exercise)
                Divider().overlay(RFDesign.hairline)
                stepper
                setControls
            if exercise.loadingKind.showsPlateMath {
                    HStack(spacing: 9) {
                        Text("Per side").rfEyebrow()
                        PlateChips(loadout: loadout, bar: exercise.barWeight)
                    }
                }
                actions
                MusicBar()
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
                Text("Set \(min(nextWorkingSet, item.targetSets)) of \(item.targetSets)")
                    .rfEyebrow()
            }
        }
        .sheet(isPresented: $editingNote) {
            NoteSheet(note: note) { note = $0 }
        }
        .sheet(isPresented: $editingWeight) {
            WeightSheet(weight: weight, unitLabel: exercise.weightUnit) { weight = $0 }
        }
        .onAppear(perform: prime)
        .onAppear(perform: armHandsFree)
        .onDisappear(perform: disarmHandsFree)
    }

    // MARK: hands-free
    //
    // This screen is the only place a squeeze can mean "log the set", because it
    // is the only place that knows which set. `RemoteControls` holds the wiring
    // and nothing else; the moment you navigate away the handlers go with you
    // and a squeeze is music again — an app that logs a phantom set from the
    // Trends tab would be worse than one with no gestures at all.

    private func armHandsFree() {
        remote.handlers = RemoteControls.Handlers(
            logSet: { logSet() },
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

    /// The answer to "where am I", for the announce gesture.
    private var announcement: String {
        if restingHere {
            return "\(rest.remaining()) seconds left on \(exercise.name)."
        }
        if isFinished { return "\(exercise.name) is done. \(workingToday.count) sets." }
        return "\(exercise.name). Set \(nextWorkingSet) of \(item.targetSets), "
             + "\(Fmt.spoken(weight)) for \(reps)."
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
            SetPips(total: item.targetSets, done: workingToday.count)
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
                caption: restingHere ? restForThisSet.caption
                                     : (isFinished ? "Done" : "Ready"))
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
            } else if let suggestion {
                Text(suggestionLine(suggestion))
                    .foregroundStyle(RFDesign.label)
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

    /// Built here rather than inline in the view.
    ///
    /// Inline, this was five `+` operands with a ternary in the middle, and
    /// Swift's type checker gave up on it — on Xcode 16.4, while the beta
    /// toolchain on this Mac compiled it happily. CI caught it on the first run
    /// it ever did, which is the entire argument for having CI on a machine
    /// that is not the one you write on.
    ///
    /// The return type is annotated for the same reason: a `String` built from
    /// concatenation is exactly what the inference engine struggles with.
    private func suggestionLine(_ suggestion: Tally.Suggestion) -> String {
        let weight: String = Fmt.weight(suggestion.weight)
        let unit: String = exercise.assisted ? " lb help" : ""
        return "Try \(weight)\(unit) × \(suggestion.reps) — \(suggestion.because)."
    }

    private func comparison(to entry: SetEntry) -> String {
        guard let prev = lastSession.first(where: { $0.setIndex == entry.setIndex }) else { return "." }
        if prev.weight == entry.weight && prev.reps == entry.reps { return ". Same as last week." }
        let delta = entry.weight - prev.weight
        if delta != 0 {
            // On an assisted machine the sentence has to name the direction
            // rather than assume it: "Up 10 lb" reads as progress, and on a
            // pull-up assist it is the opposite of progress.
            if exercise.assisted {
                return delta < 0 ? ". \(Fmt.weight(-delta)) lb less help."
                                 : ". \(Fmt.weight(delta)) lb more help."
            }
            if delta > 0 { return ". Up \(Fmt.weight(delta)) lb." }
        }
        if entry.reps > prev.reps { return ". \(entry.reps - prev.reps) more reps." }
        return "."
    }

    /// One sentence about what to do, from the last time you did this lift.
    /// Not a programme — see Tally.nextTarget.
    private var suggestion: Tally.Suggestion? {
        Tally.nextTarget(
            lastSession: lastSession.map {
                // No bodyweight: `nextTarget` reads weight and reps, never
                // volume. Saying so explicitly beats a default that hides it.
                $0.tally(bodyWeight: nil)
            },
            target: item.targetReps,
            step: exercise.loadingKind.showsPlateMath ? 5 : 5)
        // No `assisted:` here on purpose — `nextTarget` reads it off the sets,
        // which is what stops this call site getting it wrong again.
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
                        Text(exercise.weightUnit).rfEyebrow(RFDesign.labelDim, size: 14)
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

    /// Set type, effort and a note. Everything a serious logger records about a
    /// set beyond the two numbers — and the reason a 135 warm-up no longer
    /// inflates your tonnage and your records.
    private var setControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Set type", selection: $kind) {
                    ForEach(SetKind.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                chip(kind == .working ? "Working set" : kind.label,
                     tint: kind == .warmup ? RFDesign.labelDim : RFDesign.ready,
                     filled: kind != .working)
            }

            Menu {
                Button("Not recorded") { rpe = 0 }
                ForEach([6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button(rpeLabel(value)) { rpe = value }
                }
            } label: {
                chip(rpe == 0 ? "RPE" : "RPE \(Fmt.weight(rpe))",
                     tint: rpe >= 9 ? RFDesign.ember : RFDesign.label,
                     filled: rpe > 0)
            }

            Button { editingNote = true } label: {
                chip(note.isEmpty ? "Note" : "Note ✓",
                     tint: RFDesign.label, filled: !note.isEmpty)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func rpeLabel(_ value: Double) -> String {
        let reserve = 10 - value
        if reserve <= 0 { return "10 — nothing left" }
        if reserve < 1 { return "9.5 — half a rep left" }
        return "\(Fmt.weight(value)) — \(Fmt.weight(reserve)) rep\(reserve == 1 ? "" : "s") left"
    }

    private func chip(_ text: String, tint: Color, filled: Bool) -> some View {
        Text(text)
            .font(RFDesign.ui(12, bold: filled))
            .foregroundStyle(filled ? RFDesign.ground : tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(filled ? tint : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(filled ? Color.clear : RFDesign.hairline, lineWidth: 1)
                    }
            }
            // Unfilled is the DEFAULT state for all three of these — working
            // set, no RPE, no note — and unfilled means `Color.clear`, which
            // under `.buttonStyle(.plain)` means the chip is tappable only where
            // it is opaque: the glyphs and a one-point stroke. Same defect as
            // `PrimaryButton` had; see docs/DECISIONS.md.
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
                PrimaryButton(title: isFinished ? "Done — back to today"
                                                : "Skip to set \(nextWorkingSet)",
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
                PrimaryButton(title: kind == .warmup
                                ? "Log warm-up" : "Log set \(nextWorkingSet)",
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

    /// A past session in one line: the top WORKING weight and the reps that
    /// counted. Warm-ups are context, not results.
    private func summary(of entries: [SetEntry]) -> String {
        let working = entries.filter { $0.setKind.counts }
        let top = working.map(\.weight).max() ?? 0
        let reps = working.map { String($0.reps) }.joined(separator: ", ")
        let warmups = entries.count - working.count
        let tail = warmups > 0 ? "  (+\(warmups) warm-up)" : ""
        return "\(Fmt.weight(top)) · \(reps)\(tail)"
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
                    Text(summary(of: session.entries))
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
        weight = todays.last?.weight ?? suggestion?.weight ?? item.targetWeight
        reps = todays.last.map { _ in item.targetReps } ?? suggestion?.reps ?? item.targetReps
    }

    /// In a superset you walk to the next machine, you do not rest.
    ///
    /// Twenty seconds instead of the full cooldown, and the ring says "Move"
    /// rather than "Cooldown" — the whole reason the pairing has to exist in
    /// the model at all is that the timer is otherwise actively wrong here.
    private var restForThisSet: (seconds: Int, caption: String) {
        guard item.supersetGroup > 0, let day = item.day else {
            return (item.restSeconds, "Cooldown")
        }
        let group = day.orderedItems.filter { $0.supersetGroup == item.supersetGroup }
        let isLast = group.last?.persistentModelID == item.persistentModelID
        return isLast ? (item.restSeconds, "Cooldown") : (20, "Move")
    }

    private func logSet() {
        // Records are judged against history WITHOUT this set — including it
        // would make every set a record for beating itself.
        // Records compare weight and reps, never volume — so no bodyweight is
        // needed and none is invented.
        let history = mine.map {
            $0.tally(bodyWeight: nil)
        }
        let candidate = Tally.Set(weight: weight, reps: reps, kind: kind,
                                  assisted: exercise.assisted)
        withAnimation(RFDesign.settle) {
            record = Tally.headline(for: candidate, history: history)
        }
        // Two channels for every outcome: a record gets its own rising pattern
        // and its own rising tone, an ordinary set gets the short one. This is
        // the confirmation you get when the phone never left your pocket.
        if record != nil {
            Haptics.shared.play(.record)
            AudioHub.shared.play(.record)
        } else {
            Haptics.shared.play(.logged)
            AudioHub.shared.play(.logged)
        }

        let entry = SetEntry(exercise: exercise, weight: weight, reps: reps,
                             setIndex: nextSet, kind: kind, rpe: rpe, note: note)
        // Opened here, on the first set, rather than when the screen appears —
        // walking into a workout and walking out again without lifting should
        // not leave an empty session in your history.
        entry.session = Sessions.current(for: item.day, in: context)
        context.insert(entry)
        // The plan follows what you actually lift. Without this the row goes on
        // showing 45 after you have been doing 50 for a month — the suggestion
        // told you to move up, you moved up, and the checklist never noticed.
        if let advanced = Tally.advancedTarget(current: item.targetWeight,
                                               targetReps: item.targetReps,
                                               set: candidate) {
            item.targetWeight = advanced
        }
        note = ""              // notes are per set, not sticky
        if kind == .warmup { kind = .working }   // warm-ups come first, once
        context.saveOrReport("logging a set")
        snapshots.setNeedsWrite(context)
        // The rest runs even after the last set, because what follows it is
        // usually a walk to the next machine rather than leaving the gym.
        rest.start(seconds: restForThisSet.seconds, exercise: exercise.name)
    }

    private func undoLast() {
        record = nil
        guard let last = todays.last else { return }
        context.delete(last)
        // The session may now hold nothing. One left behind reads as an extra
        // workout on Today and advances the rotation.
        Sessions.pruneEmpty(in: context)
        context.saveOrReport("undoing a set")
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


/// A note about one set. Short by design — this is a thing you type between
/// sets, out of breath.
struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    var onSave: (String) -> Void

    init(note: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: note)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                TextField("Left shoulder clicked", text: $text, axis: .vertical)
                    .font(RFDesign.ui(16))
                    .lineLimit(3, reservesSpace: true)
                    .textFieldStyle(.plain)
                    .padding(RFDesign.md)
                    .background(RFDesign.surface,
                                in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
                Text("Kept with this set, and included in the CSV export.")
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
                Spacer()
            }
            .padding(RFDesign.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text); dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
