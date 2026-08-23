import SwiftUI
import SwiftData

/// Where you set the machine, on the screen where you are standing in front of
/// it.
///
/// "2 on the leg press" is the thing you re-derive every single week by sitting
/// down and finding out it is wrong. It belongs to the exercise, not to a set —
/// so it is entered once and then it is just *there*, at the top of the screen,
/// every time you come back.
struct MachineSettingsRow: View {
    let exercise: Exercise
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            if exercise.settings.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    Text("Machine settings")
                }
                .font(RFDesign.ui(12.5))
                .foregroundStyle(RFDesign.labelDim)
            } else {
                HStack(spacing: 7) {
                    ForEach(exercise.settings) { setting in
                        HStack(spacing: 4) {
                            Text(setting.setting.label)
                                .foregroundStyle(RFDesign.labelDim)
                            Text(setting.value)
                                .foregroundStyle(RFDesign.speech)
                                .monospacedDigit()
                        }
                        .font(RFDesign.ui(12.5))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RFDesign.surface,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $editing) { MachineSettingsSheet(exercise: exercise) }
        .accessibilityIdentifier("machine-settings")
    }
}

/// Add, edit and remove the dials.
///
/// The list of dials is `MachineSettingKind` rather than free text, so you
/// cannot end up with "seat" and "Seat height" as two different things — which
/// is exactly how a notes field for this would have decayed.
struct MachineSettingsSheet: View {
    let exercise: Exercise
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var snapshots: SnapshotService

    @State private var adding: MachineSettingKind?
    @State private var draft = ""

    /// Dials not already recorded for this exercise.
    private var available: [MachineSettingKind] {
        let used = Set(exercise.settings.map(\.setting))
        return MachineSettingKind.allCases.filter { !used.contains($0) || $0 == .other }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if exercise.settings.isEmpty {
                        Text("Nothing recorded yet.")
                            .font(RFDesign.ui(13.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                    ForEach(exercise.settings) { setting in
                        HStack {
                            Text(setting.setting.label)
                                .font(RFDesign.ui(15))
                                .foregroundStyle(RFDesign.speech)
                            Spacer()
                            TextField(setting.setting.hint, text: binding(for: setting))
                                .multilineTextAlignment(.trailing)
                                .font(RFDesign.ui(15))
                                .foregroundStyle(RFDesign.ready)
                                .frame(maxWidth: 130)
                        }
                    }
                    .onDelete(perform: remove)
                } header: {
                    Text(exercise.name).rfEyebrow()
                } footer: {
                    Text("Kept with the exercise, not with a set — the seat does not "
                         + "change between Tuesday and Thursday. It rides along to the "
                         + "Mac in the snapshot, so RIA can tell you where the pin goes "
                         + "before you get there.")
                        .font(RFDesign.ui(12))
                        .foregroundStyle(RFDesign.labelDim)
                }

                Section {
                    ForEach(available) { kind in
                        Button {
                            add(kind)
                        } label: {
                            Label(kind.label, systemImage: "plus")
                                .font(RFDesign.ui(15))
                        }
                    }
                } header: {
                    Text("Add a setting").rfEyebrow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle("Machine settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } }
            }
        }
    }

    private func binding(for setting: MachineSetting) -> Binding<String> {
        Binding(get: { setting.value },
                set: { setting.value = $0; setting.updatedAt = .now })
    }

    private func add(_ kind: MachineSettingKind) {
        let setting = MachineSetting(kind: kind, value: "", exercise: exercise)
        context.insert(setting)
        save()
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets { context.delete(exercise.settings[index]) }
        save()
    }

    private func save() {
        // A blank dial is one you started adding and thought better of; keeping
        // it would put an empty chip on the set screen forever.
        for setting in exercise.settings
        where setting.value.trimmingCharacters(in: .whitespaces).isEmpty {
            context.delete(setting)
        }
        try? context.save()
        snapshots.setNeedsWrite(context)
    }
}
