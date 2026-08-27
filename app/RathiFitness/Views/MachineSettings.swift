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
                // Scrolls rather than truncating: a leg press with four dials
                // recorded is exactly the case this feature exists for, and
                // dropping the fourth chip would hide the one you needed.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(exercise.settings) { setting in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(setting.setting.label)
                                    .font(RFDesign.ui(12))
                                    .foregroundStyle(RFDesign.labelDim)
                                // Fraunces, like every other number in the app —
                                // and it matches the editor you tap through to.
                                Text(setting.value)
                                    .font(RFDesign.figure(13.5, relativeTo: .footnote))
                                    .monospacedDigit()
                                    .foregroundStyle(RFDesign.speech)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RFDesign.surface,
                                        in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $editing) { MachineSettingsSheet(exercise: exercise) }
        .accessibilityIdentifier("machine-settings")
    }
}

/// Add, edit and remove the dials — one editor, used from both places you
/// reach it.
///
/// You set the seat standing in front of the machine, and you edit the
/// programme sitting at home, so this is presented two ways: as a sheet from
/// the chips on the set screen, and as a pushed screen from the plan. It was
/// briefly a pushed screen that only knew how to open the sheet, which meant a
/// modal on top of a push to change one number.
struct MachineSettingsEditor: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @FocusState private var focused: PersistentIdentifier?

    /// Queried, not walked from `exercise.machineSettings`.
    ///
    /// A relationship read does not reliably republish when the inverse side is
    /// inserted: on iOS 18 a dial added here did not appear until you left the
    /// screen and came back, while on iOS 26 it appeared at once. `SetView` and
    /// `CardioSetView` already query-and-filter for exactly this reason; this
    /// screen was the one place still traversing, and it was the one place with
    /// the bug.
    @Query private var allSettings: [MachineSetting]

    /// This exercise's dials, in the order `MachineSettingKind` declares.
    private var settings: [MachineSetting] {
        allSettings
            .filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { ($0.setting.order, $0.setting.label) < ($1.setting.order, $1.setting.label) }
    }

    /// Dials not already recorded. `other` stays available because a machine
    /// can have two odd ones.
    private var available: [MachineSettingKind] {
        let used = Set(settings.map(\.setting))
        return MachineSettingKind.allCases.filter { !used.contains($0) || $0 == .other }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RFDesign.lg + 4) {
            SettingsSection(
                title: "Where it's set",
                footer: "Kept with the exercise rather than with a set — the seat does not "
                      + "change between Tuesday and Thursday, and recording it per set "
                      + "would make you type it four times an evening.\n\n"
                      + "It rides along to the Mac in the snapshot, so `gym machines` can "
                      + "tell you where the pin goes before you leave the house."
            ) {
                if settings.isEmpty {
                    Text("Nothing recorded yet. Add the first dial below.")
                        .font(RFDesign.ui(13.5))
                        .foregroundStyle(RFDesign.labelDim)
                        .padding(.vertical, 13)
                } else {
                    ForEach(Array(settings.enumerated()), id: \.element.id) { i, setting in
                        row(setting, showsDivider: i < settings.count - 1)
                    }
                }
            }

            SettingsSection(
                title: "Add a setting",
                footer: "Chosen from a list rather than typed, so you cannot end up with "
                      + "\"seat\" and \"Seat height\" as two different things — which is "
                      + "exactly how a notes field for this would have decayed. The value "
                      + "is free text, because dials are not all numbers."
            ) {
                Menu {
                    ForEach(available) { kind in
                        Button(kind.label) { add(kind) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium)).frame(width: 18)
                        Text("Add a dial").font(RFDesign.uiMedium(15))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                    .foregroundStyle(RFDesign.ready)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
            }
        }
        .onDisappear(perform: save)
    }

    private func row(_ setting: MachineSetting, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(setting.setting.label)
                    .font(RFDesign.uiMedium(15))
                    .foregroundStyle(RFDesign.speech)
                Spacer(minLength: 8)
                TextField(setting.setting.hint, text: binding(for: setting))
                    .font(RFDesign.figure(19, relativeTo: .body))
                    .foregroundStyle(RFDesign.ready)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: setting.persistentModelID)
                    .frame(maxWidth: 120)
                Button { remove(setting) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(RFDesign.labelDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(setting.setting.label)")
            }
            .padding(.vertical, 7)
            if showsDivider { Divider().overlay(RFDesign.hairline) }
        }
    }

    private func binding(for setting: MachineSetting) -> Binding<String> {
        Binding(get: { setting.value },
                set: { setting.value = $0; setting.updatedAt = .now })
    }

    private func add(_ kind: MachineSettingKind) {
        let setting = MachineSetting(kind: kind, value: "", exercise: exercise)
        context.insert(setting)
        context.saveOrReport("adding a machine setting")
        // Straight into the field: adding a dial and then having to aim at it
        // is two taps for one intention.
        focused = setting.persistentModelID
    }

    private func remove(_ setting: MachineSetting) {
        context.delete(setting)
        save()
    }

    private func save() {
        // A blank dial is one you started adding and thought better of; keeping
        // it would put an empty chip on the set screen forever.
        for setting in settings
        where setting.value.trimmingCharacters(in: .whitespaces).isEmpty {
            context.delete(setting)
        }
        context.saveOrReport("saving the machine settings")
        snapshots.setNeedsWrite(context)
    }
}

/// From the set screen: a sheet, because you are mid-workout and going back is
/// one swipe.
struct MachineSettingsSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MachineSettingsEditor(exercise: exercise)
                    .padding(.horizontal, SettingsKit.margin)
                    .padding(.top, RFDesign.sm)
                    .padding(.bottom, RFDesign.xl)
            }
            .scrollIndicators(.hidden)
            .background(RoomBackground())
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
