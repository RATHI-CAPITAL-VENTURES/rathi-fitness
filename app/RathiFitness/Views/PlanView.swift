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
        let when = Weekdays.name(day.weekday) ?? "unscheduled"
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
    @State private var addingExercise = false

    var body: some View {
        Form {
            Section("Name and day") {
                TextField("Push A", text: $day.name)
                    .font(RFDesign.uiMedium(16))
                Picker("Weekday", selection: $day.weekday) {
                    Text("Unscheduled").tag(0)
                    ForEach(Weekdays.all, id: \.number) { d in
                        Text(d.name).tag(d.number)
                    }
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
                     + "drag to reorder.")
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
        VStack(alignment: .leading, spacing: 2) {
            Text(item.exercise?.name ?? "—")
                .font(RFDesign.uiMedium(15.5))
                .foregroundStyle(RFDesign.speech)
            Text("\(item.targetSets) × \(item.targetReps) · "
                 + "\(Fmt.weight(item.targetWeight)) lb · \(item.restSeconds)s rest")
                .font(RFDesign.ui(12.5))
                .foregroundStyle(RFDesign.labelDim)
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

    private var matches: [Exercise] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? exercises : exercises.filter { $0.name.lowercased().contains(q) }
    }

    private var canCreate: Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && !exercises.contains { $0.name.lowercased() == q.lowercased() }
    }

    var body: some View {
        NavigationStack {
            List {
                if canCreate {
                    Section {
                        Button {
                            let name = search.trimmingCharacters(in: .whitespaces)
                            let exercise = Exercise(name: name)
                            context.insert(exercise)
                            try? context.save()
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Label("Create \"\(search.trimmingCharacters(in: .whitespaces))\"",
                                  systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("New exercises start as a barbell lift with a 45 lb bar. "
                             + "Change that on the next screen if it isn't.")
                    }
                }
                Section {
                    ForEach(matches) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .foregroundStyle(RFDesign.speech)
                                Spacer()
                                Text(exercise.loadingKind.rawValue)
                                    .font(RFDesign.ui(12.5))
                                    .foregroundStyle(RFDesign.labelDim)
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
        }
        .scrollContentBackground(.hidden)
        .background(RFDesign.ground.ignoresSafeArea())
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
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
