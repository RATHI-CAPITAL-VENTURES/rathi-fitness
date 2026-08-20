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
            List {
                Section {
                    ForEach(days) { day in
                        Button { editing = day } label: { row(day) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteDays)
                    .onMove(perform: moveDays)
                } footer: {
                    Text("A day with no weekday is one you do when you feel like it — "
                         + "it will not open by itself, but you can pick it from the "
                         + "calendar button on Today.")
                }

                Section {
                    Button {
                        let day = PlannedDay(name: "New day", weekday: 0, order: days.count)
                        context.insert(day)
                        save()
                        editing = day
                    } label: {
                        Label("Add a day", systemImage: "plus")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
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
        Form {
            Section {
                TextField("Push A", text: $day.name)
                    .font(RFDesign.uiMedium(16))
                if rotating {
                    LabeledContent("Position", value: "\(day.order + 1) of \(dayCount)")
                } else {
                    Picker("Weekday", selection: $day.weekday) {
                        Text("Unscheduled").tag(0)
                        ForEach(Weekdays.all, id: \.number) { d in
                            Text(d.name).tag(d.number)
                        }
                    }
                }
            } header: {
                Text(rotating ? "Name and place in the rotation" : "Name and day")
            } footer: {
                if rotating {
                    Text("You are on a rotation, so this workout is not pinned to a "
                         + "weekday — it comes up when the cycle reaches it. Drag the "
                         + "days on the previous screen to change the order.")
                }
            }

            Section {
                ForEach(day.orderedItems) { item in
                    NavigationLink {
                        PlanItemEditorView(item: item)
                    } label: {
                        itemRow(item)
                    }
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)

                Button {
                    addingExercise = true
                } label: {
                    Label("Add an exercise", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("The order here is the order you do them in. Swipe to remove, "
                     + "drag to reorder. Link two in a row into a superset and you "
                     + "go straight from one to the other — the cooldown waits "
                     + "until the end of the round.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(RFDesign.ground.ignoresSafeArea())
        .navigationTitle(day.name.isEmpty ? "New day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerView { exercise in
                let item = PlanItem(order: day.orderedItems.count, exercise: exercise,
                                    targetSets: 3, targetReps: 10,
                                    targetWeight: suggestedWeight(for: exercise),
                                    restSeconds: 90)
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
                Text("\(item.targetSets) × \(item.targetReps) · "
                     + "\(Fmt.weight(item.targetWeight)) lb · \(item.restSeconds)s rest"
                     + (item.supersetGroup > 0 ? " · superset" : ""))
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .padding(.vertical, 2)
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

    var body: some View {
        Form {
            Section("Target") {
                Stepper("Sets: \(item.targetSets)", value: $item.targetSets, in: 1...12)
                Stepper("Reps: \(item.targetReps)", value: $item.targetReps, in: 1...50)
                HStack {
                    Text("Weight")
                    Spacer()
                    Button { adjust(-5) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).foregroundStyle(RFDesign.ready)
                    Text("\(Fmt.weight(item.targetWeight)) lb")
                        .font(RFDesign.uiMedium(15))
                        .monospacedDigit()
                        .frame(minWidth: 78)
                        .multilineTextAlignment(.center)
                    Button { adjust(5) } label: { Image(systemName: "plus.circle") }
                        .buttonStyle(.plain).foregroundStyle(RFDesign.ready)
                }
            }

            Section {
                Toggle("Superset with the next exercise", isOn: supersetBinding)
            } header: {
                Text("Pairing")
            } footer: {
                Text("You alternate between the linked exercises and rest once at the "
                     + "end of the round. Between them the timer gives you twenty "
                     + "seconds to walk over, not the full cooldown.")
            }

            Section {
                Picker("Rest", selection: $item.restSeconds) {
                    ForEach([30, 45, 60, 75, 90, 120, 150, 180, 240, 300], id: \.self) { s in
                        Text(Fmt.clock(s)).tag(s)
                    }
                }
            } header: {
                Text("Cooldown")
            } footer: {
                Text("How long the ring counts down after each set of this exercise.")
            }

            if let exercise = item.exercise {
                Section("Exercise") {
                    NavigationLink {
                        ExerciseEditorView(exercise: exercise)
                    } label: {
                        LabeledContent(exercise.name, value: exercise.loadingKind.rawValue)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RFDesign.ground.ignoresSafeArea())
        .navigationTitle(item.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? context.save()
            snapshots.setNeedsWrite(context)
        }
    }

    /// Linking to the next exercise puts both in one group. Groups are numbered
    /// by the first item's order, so the number is stable when the day is
    /// reordered around them.
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
        Form {
            Section("Name") {
                TextField("Bench Press", text: $exercise.name)
            }
            Section {
                Picker("Loaded by", selection: $exercise.loading) {
                    ForEach(Exercise.Loading.allCases, id: \.rawValue) { kind in
                        Text(kind.rawValue.capitalized).tag(kind.rawValue)
                    }
                }
                if exercise.loadingKind.showsPlateMath {
                    Picker("Bar", selection: $exercise.barWeight) {
                        Text("45 lb — standard").tag(45.0)
                        Text("35 lb — women's").tag(35.0)
                        Text("15 lb — technique").tag(15.0)
                        Text("None").tag(0.0)
                    }
                }
            } header: {
                Text("How it's loaded")
            } footer: {
                Text("Only barbell lifts get plate math. A cable stack has no plates to "
                     + "work out, and showing some would be a guess.")
            }

            Section {
                Picker("Mainly works", selection: $exercise.primaryMuscle) {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Text(muscle == .other ? "Not set" : muscle.label).tag(muscle.rawValue)
                    }
                }
                ForEach(MuscleGroup.allCases.filter { $0 != .other }) { muscle in
                    if muscle != exercise.primary {
                        Toggle(muscle.label, isOn: secondaryBinding(muscle))
                            .font(RFDesign.ui(14))
                    }
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text("Drives sets-per-muscle-per-week on Trends. The main mover counts as "
                     + "a whole set and each of the others as half. An exercise with none "
                     + "set is left out of that chart entirely rather than guessed at — "
                     + "which is why a lift you typed in yourself starts here.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(RFDesign.ground.ignoresSafeArea())
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
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
