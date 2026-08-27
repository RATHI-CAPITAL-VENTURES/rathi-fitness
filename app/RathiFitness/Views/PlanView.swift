import SwiftUI
import SwiftData

/// The rotation: every day you train, and what is in it.
///
/// The plan shipped seeded and read-only, which made the app a log of someone
/// else's programme. Everything here is editable — days, their weekday, what is
/// in them, the targets, and the exercises themselves.
struct PlanView: View {
    /// Presented as a sheet from Today, so it brings its own stack. Settings
    /// pushes `PlanList` directly — a NavigationStack inside another one gives
    /// you two nav bars and a back button that does nothing.
    var body: some View {
        NavigationStack {
            PlanList(showsDone: true)
        }
    }
}

struct PlanList: View {
    var showsDone = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snapshots: SnapshotService

    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]
    @Query private var schedules: [Schedule]
    @State private var editing: PlannedDay?

    var body: some View {
        Group {
            // `List` survives here, and only here, because `onMove` and
            // `onDelete` are real features — reimplementing drag-to-reorder to
            // win a typeface is a bad trade. Everything the list would impose
            // is stripped: its background, its row fills, its separators and
            // its insets, so what is left is the app's own row on the app's own
            // ground at the app's own margin.
            List {
                ForEach(days) { day in
                    Button { editing = day } label: { row(day) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: deleteDays)
                .onMove(perform: moveDays)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(RFDesign.hairline)
                .listRowInsets(EdgeInsets(top: 0, leading: SettingsKit.margin,
                                          bottom: 0, trailing: SettingsKit.margin))

                // The action belongs to the `ActionRow`, not to a `Button`
                // wrapped around it. It was the other way round, with the row's
                // own action left empty and `.allowsHitTesting(false)` applied
                // to stop the two buttons fighting — which worked, in the sense
                // that neither of them fired. A label with no hit-testable
                // content leaves the outer `Button` nothing to hit, so "Add a
                // day" drew, highlighted, and did nothing at all.
                ActionRow(label: "Add a day", symbol: "plus", showsDivider: false) {
                    let day = PlannedDay(name: "New day", weekday: 0, order: days.count)
                    context.insert(day)
                    save()
                    editing = day
                }
                .accessibilityIdentifier("add-day")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: SettingsKit.margin,
                                          bottom: 0, trailing: SettingsKit.margin))

                Text("A day with no weekday is one you do when you feel like it — it will "
                     + "not open by itself, but you can pick it from the calendar button "
                     + "on Today.")
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: RFDesign.sm, leading: SettingsKit.margin,
                                              bottom: RFDesign.xl, trailing: SettingsKit.margin))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(RoomBackground())
            .navigationTitle("The plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .navigationDestination(item: $editing) { day in
                DayEditorView(day: day)
            }
        }
    }

    private func row(_ day: PlannedDay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(RFDesign.uiMedium(16))
                    .foregroundStyle(RFDesign.speech)
                Text(subtitle(day))
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RFDesign.labelDim)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func subtitle(_ day: PlannedDay) -> String {
        let items = day.orderedItems
        let sets = items.reduce(0) { $0 + $1.targetSets }
        let rotating = (schedules.first?.config.mode ?? .weekday) != .weekday
        let when = rotating ? "#\(day.order + 1) in the rotation"
                            : (Weekdays.name(day.weekday) ?? "unscheduled")
        if items.isEmpty { return "\(when) · nothing in it yet" }
        return "\(when) · \(items.count) exercises · \(sets) sets"
    }

    private func deleteDays(_ offsets: IndexSet) {
        for index in offsets { context.delete(days[index]) }
        save()
    }

    private func moveDays(_ source: IndexSet, _ destination: Int) {
        var reordered = days
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, day) in reordered.enumerated() { day.order = i }
        save()
    }

    private func save() {
        try? context.save()
        snapshots.setNeedsWrite(context)
    }
}

/// One day: what it's called, when it happens, and what's in it.
struct DayEditorView: View {
    @Bindable var day: PlannedDay

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @Query private var schedules: [Schedule]
    @Query private var allDays: [PlannedDay]
    @State private var addingExercise = false

    private var rotating: Bool { (schedules.first?.config.mode ?? .weekday) != .weekday }
    private var dayCount: Int { max(allDays.count, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.lg + 4) {
                SettingsSection(
                    title: rotating ? "Name and place in the rotation" : "Name and day",
                    footer: rotating
                        ? "You are on a rotation, so this workout is not pinned to a "
                        + "weekday — it comes up when the cycle reaches it. Drag the days "
                        + "on the previous screen to change the order."
                        : nil
                ) {
                    TextField("Push A", text: $day.name)
                        .font(RFDesign.uiMedium(16))
                        .foregroundStyle(RFDesign.speech)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Divider().overlay(RFDesign.hairline) }
                    if rotating {
                        SettingRow(label: "Position", showsDivider: false) {
                            SettingFigure(value: "\(day.order + 1)",
                                          unit: "of \(dayCount)")
                        }
                    } else {
                        ChoiceRow(label: "Weekday", value: day.weekday,
                                  options: [(0, "Unscheduled")]
                                      + Weekdays.all.map { ($0.number, $0.name) },
                                  showsDivider: false) { day.weekday = $0 }
                    }
                }

                SettingsSection(
                    title: "Exercises",
                    footer: "The order here is the order you do them in. Swipe to remove, "
                          + "drag to reorder — the pencil in the corner turns that on. Link "
                          + "two in a row into a superset and you go straight from one to "
                          + "the other; the cooldown waits until the end of the round."
                ) {
                    // Reordering matters more here than anywhere else in the
                    // app — the order IS the workout — so this stays a `List`,
                    // stripped of everything it would otherwise impose. It needs
                    // an explicit height because a `List` inside a `ScrollView`
                    // has no intrinsic one.
                    List {
                        ForEach(day.orderedItems) { item in
                            NavigationLink {
                                PlanItemEditorView(item: item)
                            } label: {
                                itemRow(item)
                            }
                        }
                        .onDelete(perform: deleteItems)
                        .onMove(perform: moveItems)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(RFDesign.hairline)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: max(1, CGFloat(day.orderedItems.count) * 62))

                    ActionRow(label: "Add an exercise", symbol: "plus",
                              showsDivider: false) { addingExercise = true }
                }
            }
            .padding(.horizontal, SettingsKit.margin)
            .padding(.top, RFDesign.sm)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground())
        .navigationTitle(day.name.isEmpty ? "New day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerView { exercise in
                // Your numbers, not 3 × 10 — see `PlanDefaults`. A treadmill
                // opened at "3 × 10 · 0 lb · 90s rest" is the app asking you to
                // fix it before you can use it, and so is a bench opened at a
                // rep target you never do.
                let defaults = PlanDefaults.current(in: context)
                let item = exercise.isCardio
                    ? PlanItem(order: day.orderedItems.count, exercise: exercise,
                               targetSets: 1, targetReps: 0, targetWeight: 0,
                               restSeconds: 0, targetSeconds: defaults.cardioSeconds)
                    : PlanItem(order: day.orderedItems.count, exercise: exercise,
                               targetSets: defaults.targetSets,
                               targetReps: defaults.targetReps,
                               targetWeight: suggestedWeight(for: exercise),
                               restSeconds: defaults.restSeconds)
                item.day = day
                context.insert(item)
                save()
            }
        }
        .onDisappear(perform: save)
    }

    private func itemRow(_ item: PlanItem) -> some View {
        HStack(spacing: 10) {
            if item.supersetGroup > 0 {
                Capsule().fill(RFDesign.ready).frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise?.name ?? "—")
                    .font(RFDesign.uiMedium(15.5))
                    .foregroundStyle(RFDesign.speech)
                Text(summaryLine(item))
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .padding(.vertical, 2)
    }

    /// One line describing the slot, in the vocabulary the exercise has.
    private func summaryLine(_ item: PlanItem) -> String {
        if item.exercise?.isCardio == true {
            var parts: [String] = []
            if item.targetSeconds > 0 { parts.append(Fmt.minutes(item.targetSeconds)) }
            if item.targetDistance > 0 { parts.append("\(Fmt.distance(item.targetDistance)) mi") }
            if item.targetIncline > 0 { parts.append("\(Fmt.rate(item.targetIncline))% grade") }
            if item.targetSpeed > 0 { parts.append("\(Fmt.rate(item.targetSpeed)) mph") }
            if item.targetResistance > 0 { parts.append("level \(Int(item.targetResistance))") }
            if item.targetSets > 1 {
                parts.append("\(item.targetSets) intervals · \(item.restSeconds)s between")
            }
            return parts.isEmpty ? "no target set" : parts.joined(separator: " · ")
        }
        let unit = item.exercise?.weightUnit ?? "lb"
        return "\(item.targetSets) × \(item.targetReps) · "
            + "\(Fmt.weight(item.targetWeight)) \(unit) · \(item.restSeconds)s rest"
            + (item.supersetGroup > 0 ? " · superset" : "")
    }

    /// Open a new slot on what he last lifted, not on zero.
    private func suggestedWeight(for exercise: Exercise) -> Double {
        let sets = (exercise.sets ?? []).sorted { $0.date > $1.date }
        return sets.first?.weight ?? (exercise.loadingKind == .barbell ? exercise.barWeight : 0)
    }

    private func deleteItems(_ offsets: IndexSet) {
        let items = day.orderedItems
        for index in offsets { context.delete(items[index]) }
        renumber()
    }

    private func moveItems(_ source: IndexSet, _ destination: Int) {
        var items = day.orderedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (i, item) in items.enumerated() { item.order = i }
        save()
    }

    private func renumber() {
        for (i, item) in day.orderedItems.enumerated() { item.order = i }
        save()
    }

    private func save() {
        try? context.save()
        snapshots.setNeedsWrite(context)
    }
}

/// The targets for one exercise on one day.
struct PlanItemEditorView: View {
    @Bindable var item: PlanItem

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService

    private var isCardio: Bool { item.exercise?.isCardio == true }

    /// Which figure the stepper is currently under. Nil until you tap one, so
    /// the screen opens as a readout rather than as a control panel.
    @State private var editing: Field?

    /// The numbers this slot has. A treadmill's are not a bench's, and neither
    /// has the other's — so the row is built from the exercise rather than from
    /// a fixed set of four.
    enum Field: Hashable {
        case sets, reps, weight, rest
        case cardio(CardioMetric)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RFDesign.lg + 4) {
                figures
                if !isCardio { pairing }
                links
            }
            .padding(.horizontal, SettingsKit.margin)
            .padding(.top, RFDesign.sm)
            .padding(.bottom, RFDesign.xl)
        }
        .scrollIndicators(.hidden)
        .background(RoomBackground())
        .navigationTitle(item.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? context.save()
            snapshots.setNeedsWrite(context)
        }
    }

    // MARK: the numbers
    //
    // Editing the plan is the same act as logging a set — you are setting a
    // number — so it gets the same treatment the set screen does: the figure is
    // the largest thing on the row, in the serif, and a thumb changes it in
    // place. The old version put these four behind a pushed Form, which made
    // the commonest edit in the app four screens deep.

    private var fields: [Field] {
        if isCardio {
            var out: [Field] = [.cardio(.duration)]
            out += (item.exercise?.metrics ?? [])
                .filter { $0 != .duration && $0 != .heartRate }
                .map(Field.cardio)
            out.append(.sets)          // intervals
            return out
        }
        return [.sets, .reps, .weight, .rest]
    }

    @ViewBuilder private var figures: some View {
        SettingsSection(
            title: "Target",
            footer: isCardio
                ? "Leave anything at zero to not prescribe it — it shows as a dash rather "
                + "than a target you missed. One interval means a single bout, which is "
                + "what most cardio is."
                : "Tap a number to put the stepper under it."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 18)],
                      alignment: .leading, spacing: 16) {
                ForEach(fields, id: \.self) { field in
                    figureCell(field)
                }
            }
            .padding(.vertical, 4)

            if let editing {
                Divider().overlay(RFDesign.hairline)
                stepper(for: editing)
            }
        }
    }

    private func figureCell(_ field: Field) -> some View {
        let active = editing == field
        return Button {
            withAnimation(RFDesign.quick) { self.editing = active ? nil : field }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: field)).rfEyebrow(active ? RFDesign.ready : RFDesign.labelDim,
                                                  size: 9.5)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(display(for: field))
                        .font(RFDesign.figure(27, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(active ? RFDesign.ready : RFDesign.speech)
                    if let unit = unit(for: field) {
                        Text(unit).rfEyebrow(RFDesign.labelDim, size: 9)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(for: field)), \(display(for: field))")
    }

    private func stepper(for field: Field) -> some View {
        HStack(spacing: RFDesign.lg) {
            nudge("minus") { adjust(field, by: -1) }
            VStack(spacing: 1) {
                Text(display(for: field))
                    .font(RFDesign.figure(40))
                    .monospacedDigit()
                    .foregroundStyle(RFDesign.ready)
                Text(title(for: field)).rfEyebrow()
            }
            .frame(minWidth: 110)
            nudge("plus") { adjust(field, by: 1) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RFDesign.md)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func nudge(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RFDesign.speech)
                .frame(width: 46, height: 46)
                .background(Circle().fill(RFDesign.surface))
                .overlay(Circle().stroke(RFDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Decrease" : "Increase")
    }

    private func title(for field: Field) -> String {
        switch field {
        case .sets: return isCardio ? "Intervals" : "Sets"
        case .reps: return "Reps"
        case .weight: return item.exercise?.assisted == true ? "Help" : "Weight"
        case .rest: return "Rest"
        case .cardio(let metric): return metric.label
        }
    }

    private func unit(for field: Field) -> String? {
        switch field {
        case .sets, .reps, .rest: return nil
        case .weight: return item.exercise?.assisted == true ? "lb help" : "lb"
        case .cardio(let metric): return metric == .duration ? nil : metric.unit
        }
    }

    private func display(for field: Field) -> String {
        switch field {
        case .sets: return String(item.targetSets)
        case .reps: return String(item.targetReps)
        case .weight: return Fmt.weight(item.targetWeight)
        case .rest: return item.restSeconds == 0 ? "—" : Fmt.clock(item.restSeconds)
        case .cardio(let metric):
            let value = cardioValue(metric)
            guard value > 0 else { return "—" }
            return metric == .duration ? Fmt.duration(Int(value)) : Fmt.metric(value, metric)
        }
    }

    private func cardioValue(_ metric: CardioMetric) -> Double {
        switch metric {
        case .duration: return Double(item.targetSeconds)
        case .distance: return item.targetDistance
        case .speed: return item.targetSpeed
        case .incline: return item.targetIncline
        case .resistance: return item.targetResistance
        case .heartRate: return 0
        }
    }

    /// One step of whatever this field measures.
    private func adjust(_ field: Field, by direction: Int) {
        switch field {
        case .sets:
            item.targetSets = min(20, max(1, item.targetSets + direction))
        case .reps:
            item.targetReps = min(50, max(1, item.targetReps + direction))
        case .weight:
            adjust(Double(direction) * 5)
        case .rest:
            // The same ladder the cooldown picker offered, so a plan cannot end
            // up with a rest nobody would choose.
            let ladder = [0, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]
            let index = ladder.firstIndex { $0 >= item.restSeconds } ?? 0
            item.restSeconds = ladder[min(ladder.count - 1, max(0, index + direction))]
        case .cardio(let metric):
            let stepped = max(0, cardioValue(metric) + metric.step * Double(direction))
            // Rounded to the step so repeated taps cannot land on 3.0999999.
            let value = (stepped / metric.step).rounded() * metric.step
            switch metric {
            case .duration: item.targetSeconds = Int(value)
            case .distance: item.targetDistance = value
            case .speed: item.targetSpeed = value
            case .incline: item.targetIncline = value
            case .resistance: item.targetResistance = value
            case .heartRate: break
            }
        }
    }

    // MARK: the rest of it

    @ViewBuilder private var pairing: some View {
        SettingsSection(
            title: "Pairing",
            footer: "You alternate between the linked exercises and rest once at the end of "
                  + "the round. Between them the timer gives you twenty seconds to walk "
                  + "over, not the full cooldown."
        ) {
            ToggleRow(label: "Superset with the next exercise",
                      isOn: supersetBinding.wrappedValue,
                      showsDivider: false) { supersetBinding.wrappedValue.toggle() }
        }
    }

    @ViewBuilder private var links: some View {
        if let exercise = item.exercise {
            SettingsSection(title: "Exercise") {
                DisclosureRow(label: exercise.name,
                              value: exercise.isCardio ? "cardio"
                                   : exercise.assisted ? "assisted"
                                   : exercise.loadingKind.rawValue) {
                    ExerciseEditorView(exercise: exercise)
                }
                DisclosureRow(label: "Machine settings",
                              value: exercise.settings.isEmpty
                                  ? "none" : "\(exercise.settings.count)",
                              showsDivider: false) {
                    MachineSettingsList(exercise: exercise)
                }
            }
        }
    }

    private var supersetBinding: Binding<Bool> {
        Binding(
            get: { item.supersetGroup > 0 },
            set: { linked in
                guard let day = item.day else { return }
                let items = day.orderedItems
                guard let index = items.firstIndex(where: {
                    $0.persistentModelID == item.persistentModelID
                }), index + 1 < items.count else { return }
                let next = items[index + 1]
                if linked {
                    let group = item.supersetGroup > 0 ? item.supersetGroup : item.order + 1
                    item.supersetGroup = group
                    next.supersetGroup = group
                } else {
                    let group = item.supersetGroup
                    item.supersetGroup = 0
                    // Only unlink the partner if nothing else shares the group.
                    if items.filter({ $0.supersetGroup == group }).count <= 1 {
                        next.supersetGroup = 0
                    }
                }
                try? context.save()
                snapshots.setNeedsWrite(context)
            })
    }

    /// Barbell weights step to something the rack can actually make.
    private func adjust(_ delta: Double) {
        guard let exercise = item.exercise else { return }
        item.targetWeight = exercise.loadingKind.showsPlateMath
            ? PlateMath.step(from: item.targetWeight, by: delta, bar: exercise.barWeight)
            : max(0, item.targetWeight + delta)
    }
}

/// Pick an exercise that already exists, or make one.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var search = ""
    var onPick: (Exercise) -> Void

    private func row(_ name: String, _ loading: String, _ muscle: MuscleGroup) -> some View {
        HStack {
            Text(name).foregroundStyle(RFDesign.speech)
            Spacer()
            Text(muscle == .other ? loading : "\(muscle.label) · \(loading)")
                .font(RFDesign.ui(12.5))
                .foregroundStyle(RFDesign.labelDim)
        }
    }

    private var matches: [Exercise] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? exercises : exercises.filter { $0.name.lowercased().contains(q) }
    }

    /// Catalogue movements not already in your library. This is the exercise
    /// library gap: adding a lift should be picking one, not describing one —
    /// and a lift picked here arrives knowing what it works and what bar it uses.
    private var catalogueMatches: [Catalogue.Entry] {
        let have = Set(exercises.map(\.slug))
        return Catalogue.search(search).filter { !have.contains(Exercise.slugify($0.name)) }
    }

    private var canCreate: Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }
        let slug = Exercise.slugify(q)
        return !exercises.contains { $0.slug == slug }
            && !catalogueMatches.contains { Exercise.slugify($0.name) == slug }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Section {
                        Button {
                            let name = search.trimmingCharacters(in: .whitespaces)
                            let exercise = Exercise(name: name)
                            Catalogue.enrich(exercise)   // in case it matches after all
                            context.insert(exercise)
                            try? context.save()
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Label("Create \"\(search.trimmingCharacters(in: .whitespaces))\"",
                                  systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("Anything already in the catalogue arrives knowing what it "
                             + "works and what bar it uses. Something invented here starts "
                             + "as a barbell lift — change it on the next screen.")
                    }
                }
                if !matches.isEmpty {
                    Section("In your log") {
                        ForEach(matches) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                row(exercise.name, exercise.loadingKind.rawValue,
                                    exercise.primary)
                            }
                        }
                    }
                }
                if !catalogueMatches.isEmpty {
                    Section("Catalogue") {
                        ForEach(catalogueMatches, id: \.name) { entry in
                            Button {
                                let exercise = Catalogue.exercise(from: entry)
                                context.insert(exercise)
                                try? context.save()
                                onPick(exercise)
                                dismiss()
                            } label: {
                                row(entry.name, entry.loading.rawValue, entry.primary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .searchable(text: $search, prompt: "Search or name a new one")
            .navigationTitle("Add an exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// What an exercise *is* — the bits that change how it is logged.
struct ExerciseEditorView: View {
    @Bindable var exercise: Exercise

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService

    private func metricBinding(_ metric: CardioMetric) -> Binding<Bool> {
        Binding(
            get: { exercise.metrics.contains(metric) },
            set: { on in
                var all = Set(exercise.metrics)
                if on { all.insert(metric) } else { all.remove(metric) }
                exercise.cardioMetrics = CardioMetric.allCases
                    .filter(all.contains).map(\.rawValue).joined(separator: ",")
            })
    }

    private func secondaryBinding(_ muscle: MuscleGroup) -> Binding<Bool> {
        Binding(
            get: { exercise.secondary.contains(muscle) },
            set: { on in
                var all = Set(exercise.secondary)
                if on { all.insert(muscle) } else { all.remove(muscle) }
                exercise.secondaryMuscles = all.map(\.rawValue).sorted().joined(separator: ",")
            })
    }

    var body: some View {
        SettingsScaffold(title: "Exercise") {
            SettingsSection(title: "Name") {
                TextField("Bench Press", text: $exercise.name)
                    .font(RFDesign.uiMedium(16))
                    .foregroundStyle(RFDesign.speech)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { Divider().overlay(RFDesign.hairline) }
            }

            SettingsSection(
                title: "Lifting or cardio",
                footer: "Cardio gets its own screen: a clock instead of a weight, and the "
                      + "numbers off the console rather than reps."
            ) {
                ChoiceRow(label: "Kind", value: exercise.modality,
                          options: Exercise.Modality.allCases.map { ($0.rawValue, $0.label) },
                          showsDivider: false) { exercise.modality = $0 }
            }

            if exercise.isCardio {
                SettingsSection(
                    title: "What this machine shows",
                    footer: "A rower has no incline and a treadmill has no damper. Only the "
                          + "ones you tick appear on the logging screen — offering every "
                          + "field on every machine is how a screen becomes one you skip."
                ) {
                    ForEach(Array(CardioMetric.allCases.enumerated()), id: \.offset) { i, metric in
                        ToggleRow(label: metric.label,
                                  isOn: exercise.metrics.contains(metric),
                                  showsDivider: i < CardioMetric.allCases.count - 1) {
                            metricBinding(metric).wrappedValue.toggle()
                        }
                    }
                }
            } else {
                SettingsSection(
                    title: "Which way the weight runs",
                    footer: "On an assisted pull-up or dip machine the stack counterweights "
                          + "you, so 100 lb of help is an easier set than 40 and progress is "
                          + "the number going DOWN.\n\n"
                          + "Turning this on flips everything that has an opinion about the "
                          + "number: a record becomes the least help you have ever needed, "
                          + "hitting your reps suggests taking help off rather than adding "
                          + "it, and the assistance stops counting as tonnage — otherwise "
                          + "the weaker you got, the better the totals looked."
                ) {
                    ToggleRow(label: "The weight makes it easier",
                              isOn: exercise.assisted,
                              showsDivider: false) { exercise.assisted.toggle() }
                }

                SettingsSection(
                    title: "How it's loaded",
                    footer: "Only barbell lifts get plate math. A cable stack has no plates "
                          + "to work out, and showing some would be a guess."
                ) {
                    ChoiceRow(label: "Loaded by", value: exercise.loading,
                              options: Exercise.Loading.allCases.map {
                                  ($0.rawValue, $0.rawValue.capitalized) },
                              showsDivider: exercise.loadingKind.showsPlateMath) {
                        exercise.loading = $0
                    }
                    if exercise.loadingKind.showsPlateMath {
                        ChoiceRow(label: "Bar", value: exercise.barWeight,
                                  options: [(45.0, "45 lb — standard"),
                                            (35.0, "35 lb — women's"),
                                            (15.0, "15 lb — technique"),
                                            (0.0, "None")],
                                  showsDivider: false) { exercise.barWeight = $0 }
                    }
                }
            }

            SettingsSection(
                title: "Muscles",
                footer: "Drives sets-per-muscle-per-week on Trends. The main mover counts as "
                      + "a whole set and each of the others as half. An exercise with none "
                      + "set is left out of that chart entirely rather than guessed at — "
                      + "which is why a lift you typed in yourself starts here."
            ) {
                ChoiceRow(label: "Mainly works", value: exercise.primaryMuscle,
                          options: MuscleGroup.allCases.map {
                              ($0.rawValue, $0 == .other ? "Not set" : $0.label) }) {
                    exercise.primaryMuscle = $0
                }
                let others = MuscleGroup.allCases.filter {
                    $0 != .other && $0 != exercise.primary
                }
                ForEach(Array(others.enumerated()), id: \.offset) { i, muscle in
                    ToggleRow(label: muscle.label,
                              isOn: exercise.secondary.contains(muscle),
                              showsDivider: i < others.count - 1) {
                        secondaryBinding(muscle).wrappedValue.toggle()
                    }
                }
            }
        }
        .onAppear {
            // A lift typed in before the catalogue existed can still be matched
            // to it — better than making him pick muscles the app already knows.
            if exercise.primary == .other { Catalogue.enrich(exercise) }
        }
        .onDisappear {
            // The slug is what the CLI and RIA refer to, so it follows the name.
            exercise.slug = Exercise.slugify(exercise.name)
            try? context.save()
            snapshots.setNeedsWrite(context)
        }
    }
}

/// Weekday numbers are `Calendar`'s (1 = Sunday). One place, so a picker and a
/// lookup cannot disagree about what 4 means.
enum Weekdays {
    static let all: [(number: Int, name: String)] = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
        (5, "Thursday"), (6, "Friday"), (7, "Saturday"),
    ]

    static func name(_ number: Int) -> String? {
        all.first { $0.number == number }?.name
    }
}


/// The machine settings for one exercise, reachable from the plan as well as
/// from the set screen — you set the seat standing at the machine, but you edit
/// the programme sitting at home.
struct MachineSettingsList: View {
    let exercise: Exercise

    var body: some View {
        SettingsScaffold(title: "Machine settings") {
            MachineSettingsEditor(exercise: exercise)
        }
    }
}
