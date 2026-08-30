import SwiftUI
import SwiftData

/// Where the app connects to things. Currently: Health.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthBridge
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var music: MusicController
    @EnvironmentObject private var remote: RemoteControls
    @EnvironmentObject private var audio: AudioHub

    @State private var working = false
    @State private var confirmingWipe = false
    @State private var wipeResult: String?
    @State private var exportFiles: [URL]?

    @Query private var allSets: [SetEntry]
    @Query private var allWeighIns: [WeighIn]
    @Query private var schedules: [Schedule]
    @Query private var planDefaults: [PlanDefaults]
    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]

    private var demoCount: Int {
        allSets.filter(\.isDemo).count + allWeighIns.filter(\.isDemo).count
    }
    private var historyCount: Int { allSets.count + allWeighIns.count }

    var body: some View {
        NavigationStack {
            SettingsScaffold(title: "Settings") {
                statusSection
                healthSection
                scheduleSection
                defaultsSection
                soundSection
                handsFreeSection
                musicSection
                exportSection
                dataSection
                programmeSection
                snapshotSection
            }
            .confirmationDialog("Delete every logged set and weigh-in?",
                                isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("Delete \(historyCount) entries", role: .destructive) {
                    wipeResult = reportingFailure("deleting your history") {
                        try Seed.deleteAllHistory(context)
                    }
                        .map { "Deleted \($0) entries. Starting clean." }
                    snapshots.setNeedsWrite(context)
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Your plan, exercises and passes are kept. This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            // Cheap, and it means opening Settings never shows a stale
            // "Connect Apple Health" for a connection that already exists.
            .task { await health.resume() }
        }
    }

    // MARK: - Right now
    //
    // Settings is eleven sections long and every one of them is something you
    // set once. The question you actually open this screen with is "is Health
    // still connected", so it is answered before anything you can change.

    @ViewBuilder private var statusSection: some View {
        SettingsSection(title: "Right now") {
            StatusLine(label: "Apple Health", value: healthStatusValue,
                       lit: health.status.isConnected)
            StatusLine(label: "Music", value: music.status.isReady ? "connected" : "off",
                       lit: music.status.isReady)
            StatusLine(label: "Hands-free",
                       value: remote.enabled
                           ? RemoteControls.Gesture.triple.action.shortLabel : "off",
                       lit: remote.enabled)
            StatusLine(label: "Snapshot",
                       value: snapshots.lastWritten.map(Fmt.timeOfDay) ?? "not yet",
                       lit: snapshots.lastWritten != nil,
                       showsDivider: demoCount > 0)
            if demoCount > 0 {
                StatusLine(label: "Sample data", value: "\(demoCount) entries",
                           lit: false, showsDivider: false)
            }
        }
    }

    private var healthStatusValue: String {
        switch health.status {
        case .connected:
            return health.lastSync.map { "synced " + Fmt.ago($0) } ?? "connected"
        case .notAsked: return "not connected"
        case .denied: return "declined"
        case .unsupported: return "unavailable"
        }
    }

    // MARK: - Sections

    @ViewBuilder private var healthSection: some View {
        SettingsSection(
            title: "Apple Health",
            footer: "Your scale writes to Health, so weigh-ins come from there rather than "
                  + "being typed. Finished sessions go back the other way as workouts, so "
                  + "they show in Fitness and on the watch. Cardio goes over as its own "
                  + "workout of its own type, with a distance.\n\n"
                  + "Workouts carry a duration and no calorie estimate — a guessed burn "
                  + "would land in the same ring as your watch's measured one."
        ) {
            switch health.status {
            case .unsupported(let why):
                SettingRow(label: why, showsDivider: false) { EmptyView() }
            case .notAsked:
                ActionRow(label: "Connect Apple Health", symbol: "heart.fill",
                          showsDivider: false) { Task { await connect() } }
                    .disabled(working)
            case .denied:
                SettingRow(label: "Health said no",
                           detail: "Settings → Privacy → Health → Fitness to change it.",
                           showsDivider: false) { EmptyView() }
            case .connected:
                SettingRow(label: "Connected",
                           detail: health.lastSync.map {
                               "Last sync \(Fmt.weekdayDate($0)) · "
                               + "\(health.importedCount) weigh-ins brought in" }) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(RFDesign.ready)
                }
                ActionRow(label: working ? "Syncing…" : "Sync now",
                          symbol: "arrow.triangle.2.circlepath",
                          showsDivider: false) { Task { await sync() } }
                    .disabled(working)
            }
            if let error = health.lastError {
                Text(error)
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.ember)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var exportSection: some View {
        SettingsSection(
            title: "Export",
            footer: "Every set with its type, RPE, note and cardio numbers, plus body "
                  + "weight, measurements and where each machine is set. The snapshot RIA "
                  + "reads is the machine-readable one; this is the version a spreadsheet "
                  + "can open — and the reason leaving is possible."
        ) {
            if let files = exportFiles {
                ShareLink(items: files) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium)).frame(width: 18)
                        Text("Share the three CSVs").font(RFDesign.uiMedium(15))
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(RFDesign.ready)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                Divider().overlay(RFDesign.hairline)
            }
            ActionRow(label: exportFiles == nil ? "Export to CSV" : "Rebuild the export",
                      symbol: "tablecells", showsDivider: false) {
                exportFiles = reportingFailure("exporting your data") {
                    try Export.write(from: context)
                }
            }
        }
    }

    @ViewBuilder private var dataSection: some View {
        SettingsSection(
            title: "Your data",
            footer: "\(historyCount) logged entries. The first version of this app seeded "
                  + "six weeks of sample sessions so the charts had a shape, and those "
                  + "aren't yours — if this install predates the fix they aren't tagged, so "
                  + "\"delete all history\" is the clean way out. Your plan and passes are "
                  + "kept either way."
        ) {
            if demoCount > 0 {
                ActionRow(label: "Remove \(demoCount) sample entries",
                          symbol: "wand.and.rays") {
                    wipeResult = reportingFailure("removing the sample data") {
                        try Seed.removeDemoData(context)
                    }
                        .map { "Removed \($0) sample entries." }
                    snapshots.setNeedsWrite(context)
                }
            }
            ActionRow(label: "Delete all history", symbol: "trash",
                      tint: RFDesign.ember, showsDivider: false) {
                confirmingWipe = true
            }
            .disabled(historyCount == 0)
            .opacity(historyCount == 0 ? 0.4 : 1)
            if let wipeResult {
                Text(wipeResult)
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var programmeSection: some View {
        SettingsSection(title: "Your programme",
                        footer: "Days, what is in them, targets and rest.") {
            DisclosureRow(label: "Edit the plan",
                          detail: "\(days.count) workouts",
                          showsDivider: false) { PlanList() }
        }
    }

    @ViewBuilder private var snapshotSection: some View {
        SettingsSection(
            title: "The snapshot RIA reads",
            footer: "A copy of your log written to iCloud Drive so the Mac — and RIA — can "
                  + "read it. Gym pass codes are never included."
        ) {
            SettingRow(label: "Written",
                       detail: snapshots.lastDestination,
                       showsDivider: false) {
                Text(snapshots.lastWritten.map(Fmt.weekdayDate) ?? "not yet")
                    .font(RFDesign.ui(14))
                    .foregroundStyle(RFDesign.label)
            }
        }
    }

    /// What a new exercise opens on.
    ///
    /// Hardcoded to 3 × 10 at 90 seconds until now, which meant correcting the
    /// same three numbers every time you added a lift. Deliberately does NOT
    /// touch anything already in the plan — a setting that silently rewrites
    /// your programme is a setting you stop trusting.
    @ViewBuilder private var defaultsSection: some View {
        let defaults = planDefaults.first
        SettingsSection(
            title: "New exercises open on",
            footer: "Applies to exercises you add from now on. Nothing already in the plan "
                  + "changes — edit those on the exercise itself.\n\n"
                  + "It follows the programme rather than the phone, so it is the same on "
                  + "every device you log from."
        ) {
            StepperRow(label: "Sets", value: defaults?.targetSets ?? 3,
                       range: 1...12) { setsBinding.wrappedValue = $0 }
            StepperRow(label: "Reps", value: defaults?.targetReps ?? 10,
                       range: 1...50) { repsBinding.wrappedValue = $0 }
            ChoiceRow(label: "Rest", value: defaults?.restSeconds ?? 90,
                      options: [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]
                          .map { ($0, Fmt.clock($0)) }) { restBinding.wrappedValue = $0 }
            ChoiceRow(label: "Cardio", value: defaults?.cardioSeconds ?? 20 * 60,
                      options: [10, 15, 20, 25, 30, 40, 45, 60]
                          .map { ($0 * 60, "\($0) min") },
                      showsDivider: false) { cardioBinding.wrappedValue = $0 }
        }
    }

    private func defaultsRow() -> PlanDefaults { PlanDefaults.current(in: context) }

    private func defaultsBinding<V>(_ keyPath: ReferenceWritableKeyPath<PlanDefaults, V>,
                                    fallback: V) -> Binding<V> {
        Binding(
            get: { planDefaults.first?[keyPath: keyPath] ?? fallback },
            set: { value in
                defaultsRow()[keyPath: keyPath] = value
                context.saveOrReport("changing your defaults")
            })
    }

    private var setsBinding: Binding<Int> { defaultsBinding(\.targetSets, fallback: 3) }
    private var repsBinding: Binding<Int> { defaultsBinding(\.targetReps, fallback: 10) }
    private var restBinding: Binding<Int> { defaultsBinding(\.restSeconds, fallback: 90) }
    private var cardioBinding: Binding<Int> { defaultsBinding(\.cardioSeconds, fallback: 20 * 60) }

    /// The cooldown's two channels. Both are on by default and either can be
    /// turned off — a chime in a quiet gym and a buzz in a pocket are different
    /// kinds of rude, and which one bothers you is not something an app can guess.
    @ViewBuilder private var soundSection: some View {
        SettingsSection(
            title: "The cooldown ping",
            footer: "Three ticks in the last three seconds, then a rising two-note chime "
                  + "and a haptic you can feel through a jacket. Both fire every time, "
                  + "because the phone is in a pocket and the AirPods might be out — "
                  + "either one alone is a cue you can miss.\n\n"
                  + "A ping and nothing else. The app does not read your sets back to you: "
                  + "a rest ending is one bit of information, and a sentence about it is "
                  + "the app talking over your music to say what the chime already said."
        ) {
            SettingRow(label: "Volume", showsDivider: false) {
                HStack(spacing: 12) {
                    Slider(value: $audio.volume, in: 0...1)
                        .tint(RFDesign.ready)
                        .frame(width: 130)
                    Button {
                        audio.play(.restOver)
                        Haptics.shared.play(.restOver)
                    } label: {
                        Text("Test")
                            .font(RFDesign.ui(13, bold: true))
                            .foregroundStyle(RFDesign.ready)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The three AirPods gestures and what each one does.
    @ViewBuilder private var handsFreeSection: some View {
        SettingsSection(
            title: "AirPods",
            footer: "iOS gives an app three gestures — press, double, triple — and only to "
                  + "whichever app is currently playing audio. That is why this app plays "
                  + "your music itself rather than remote-controlling the Music app: it is "
                  + "the only way a squeeze reaches here at all.\n\n"
                  + "Triple-press logs the set by default because it is the one nobody does "
                  + "by accident. While the cooldown is already running there is no set to "
                  + "log, so the same squeeze skips the rest instead. Gestures only do "
                  + "workout things on a set screen; anywhere else they are music."
        ) {
            ToggleRow(label: "Hands-free", isOn: remote.enabled,
                      showsDivider: remote.enabled) { remote.enabled.toggle() }
            if remote.enabled {
                ForEach(Array(RemoteControls.Gesture.allCases.enumerated()), id: \.offset) { i, gesture in
                    ChoiceRow(label: gesture.label,
                              value: gesture.action,
                              options: RemoteControls.Action.allCases.map { ($0, $0.label) },
                              showsDivider: i < RemoteControls.Gesture.allCases.count - 1) {
                        gesture.action = $0
                    }
                }
            }
        }
    }

    /// Music, and the one playlist a workout starts with.
    @ViewBuilder private var musicSection: some View {
        SettingsSection(
            title: "Music",
            footer: "Your library's playlists, played by this app. The Apple Music "
                  + "catalogue isn't searchable here on purpose — a gym app plays the list "
                  + "you already made, and browsing is what the phone you left in the "
                  + "locker is for."
        ) {
            switch music.status {
            case .ready:
                ToggleRow(label: "Shuffle", isOn: music.shuffle) { music.shuffle.toggle() }
                ChoiceRow(label: "Starts with",
                          value: music.favouritePlaylist ?? "",
                          options: [("", "Newest playlist")]
                              + music.playlistNames.map { ($0, $0) },
                          showsDivider: false) {
                    music.favouritePlaylist = $0.isEmpty ? nil : $0
                }
            case .unknown:
                ActionRow(label: "Connect Apple Music", symbol: "music.note",
                          showsDivider: false) { Task { await music.connect() } }
            case .denied, .unavailable:
                SettingRow(label: music.status.message, showsDivider: false) { EmptyView() }
            }
        }
    }

    /// When you train, and whether the workouts follow the weekday or rotate.
    @ViewBuilder private var scheduleSection: some View {
        let schedule = schedules.first
        let mode = schedule?.config.mode ?? .weekday
        SettingsSection(title: "When you train", footer: footerText) {
            ChoiceRow(label: "Schedule", value: mode,
                      options: Rotation.Mode.allCases.map { ($0, $0.label) },
                      showsDivider: mode != .weekday) { modeBinding.wrappedValue = $0 }

            if mode == .everyNDays {
                StepperRow(label: "Train every", value: schedule?.everyNDays ?? 2,
                           unit: "days", range: 1...14,
                           showsDivider: false) { everyNBinding.wrappedValue = $0 }
            } else if mode == .rotation {
                ForEach(Array(Weekdays.all.enumerated()), id: \.offset) { i, day in
                    ToggleRow(label: day.name,
                              isOn: schedule?.config.trainingWeekdays.contains(day.number) ?? false,
                              showsDivider: i < Weekdays.all.count - 1) {
                        let binding = weekdayBinding(day.number)
                        binding.wrappedValue.toggle()
                    }
                }
            }
        }
    }

    private var footerText: String {
        guard let config = schedules.first?.config else { return "" }
        switch config.mode {
        case .weekday:
            return "Each workout belongs to a weekday, and that is the one you get. "
                 + "Right for a fixed weekly split."
        case .rotation, .everyNDays:
            return "You train \(Rotation.describe(config)), and your "
                 + "\(days.count) workouts cycle in the order they appear in the plan. "
                 + "Three sessions a week through four workouts means the pairing drifts "
                 + "— which is the point, and why nothing here is pinned to a weekday.\n\n"
                 + "Where you are in the cycle is counted from the sessions you have "
                 + "actually logged, so skipping one picks up where you left off rather "
                 + "than losing your place."
        }
    }

    private var modeBinding: Binding<Rotation.Mode> {
        Binding(
            get: { schedules.first?.config.mode ?? .weekday },
            set: { mode in
                let schedule = schedules.first ?? {
                    let new = Schedule(); context.insert(new); return new
                }()
                var config = schedule.config
                config.mode = mode
                schedule.config = config
                context.saveOrReport("changing your schedule")
                snapshots.setNeedsWrite(context)
            })
    }

    private var everyNBinding: Binding<Int> {
        Binding(
            get: { schedules.first?.everyNDays ?? 2 },
            set: { value in
                schedules.first?.everyNDays = value
                context.saveOrReport("changing how often you train")
                snapshots.setNeedsWrite(context)
            })
    }

    private func weekdayBinding(_ number: Int) -> Binding<Bool> {
        Binding(
            get: { schedules.first?.config.trainingWeekdays.contains(number) ?? false },
            set: { on in
                guard let schedule = schedules.first else { return }
                var config = schedule.config
                if on { config.trainingWeekdays.insert(number) }
                else { config.trainingWeekdays.remove(number) }
                schedule.config = config
                context.saveOrReport("changing your training days")
                snapshots.setNeedsWrite(context)
            })
    }

    private func connect() async {
        working = true
        await health.connect()
        if health.status.isConnected { await sync() }
        working = false
    }

    private func sync() async {
        working = true
        await health.importWeighIns(into: context)
        await health.exportWorkouts(from: context)
        snapshots.setNeedsWrite(context)
        working = false
    }
}
