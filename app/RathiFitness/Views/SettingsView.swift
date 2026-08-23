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
    @Query(sort: \PlannedDay.order) private var days: [PlannedDay]

    private var demoCount: Int {
        allSets.filter(\.isDemo).count + allWeighIns.filter(\.isDemo).count
    }
    private var historyCount: Int { allSets.count + allWeighIns.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch health.status {
                    case .unsupported(let why):
                        Label(why, systemImage: "heart.slash")
                            .font(RFDesign.ui(13))
                            .foregroundStyle(RFDesign.labelDim)
                    case .notAsked:
                        Button {
                            Task { await connect() }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.fill")
                        }
                        .disabled(working)
                    case .denied:
                        Label("Health said no. Settings → Privacy → Health → Fitness "
                              + "to change it.", systemImage: "heart.slash")
                            .font(RFDesign.ui(13))
                            .foregroundStyle(RFDesign.labelDim)
                    case .connected:
                        Label("Connected", systemImage: "heart.fill")
                            .foregroundStyle(RFDesign.ready)
                        Button {
                            Task { await sync() }
                        } label: {
                            Label(working ? "Syncing…" : "Sync now",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(working)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Your scale writes to Health, so weigh-ins come from there rather "
                         + "than being typed. Finished sessions go back the other way as "
                         + "workouts, so they show in Fitness and on the watch.\n\n"
                         + "Workouts carry a duration and no calorie estimate — a guessed "
                         + "burn would land in the same ring as your watch's measured one.")
                }

                if health.lastSync != nil || health.lastError != nil {
                    Section("Last sync") {
                        if let when = health.lastSync {
                            LabeledContent("When", value: Fmt.weekdayDate(when))
                            LabeledContent("Weigh-ins brought in",
                                           value: String(health.importedCount))
                        }
                        if let error = health.lastError {
                            Text(error)
                                .font(RFDesign.ui(12.5))
                                .foregroundStyle(RFDesign.ember)
                        }
                    }
                }

                scheduleSection
                soundSection
                handsFreeSection
                musicSection

                Section {
                    if let files = exportFiles {
                        ShareLink(items: files) {
                            Label("Share sets and body CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        exportFiles = try? Export.write(from: context)
                    } label: {
                        Label(exportFiles == nil ? "Export to CSV" : "Rebuild the export",
                              systemImage: "tablecells")
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Every set with its type, RPE and note, plus body weight and "
                         + "measurements. The snapshot RIA reads is the machine-readable "
                         + "one; this is the version a spreadsheet can open — and the "
                         + "reason leaving is possible.")
                }

                Section {
                    if demoCount > 0 {
                        Button("Remove \(demoCount) sample entries") {
                            wipeResult = (try? Seed.removeDemoData(context))
                                .map { "Removed \($0) sample entries." }
                            snapshots.setNeedsWrite(context)
                        }
                    }
                    Button("Delete all history", role: .destructive) {
                        confirmingWipe = true
                    }
                    .disabled(historyCount == 0)
                    if let wipeResult {
                        Text(wipeResult)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("\(historyCount) logged entries. The first version of this app "
                         + "seeded six weeks of sample sessions so the charts had a shape, "
                         + "and those aren't yours — if this install predates the fix they "
                         + "aren't tagged, so \"delete all history\" is the clean way out. "
                         + "Your plan and passes are kept either way.")
                }

                Section {
                    NavigationLink {
                        PlanList()
                    } label: {
                        Label("Edit the plan", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("Your programme")
                } footer: {
                    Text("Days, what is in them, targets and rest.")
                }

                Section {
                    LabeledContent("Written", value: snapshots.lastWritten
                        .map(Fmt.weekdayDate) ?? "not yet")
                    if let where_ = snapshots.lastDestination {
                        Text(where_)
                            .font(RFDesign.ui(12))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                } header: {
                    Text("The snapshot RIA reads")
                } footer: {
                    Text("A copy of your log written to iCloud Drive so the Mac — and RIA — "
                         + "can read it. Gym pass codes are never included.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .confirmationDialog("Delete every logged set and weigh-in?",
                                isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("Delete \(historyCount) entries", role: .destructive) {
                    wipeResult = (try? Seed.deleteAllHistory(context))
                        .map { "Deleted \($0) entries. Starting clean." }
                    snapshots.setNeedsWrite(context)
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Your plan, exercises and passes are kept. This cannot be undone.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    /// The cooldown's two channels. Both are on by default and either can be
    /// turned off — a chime in a quiet gym and a buzz in a pocket are different
    /// kinds of rude, and which one bothers you is not something an app can guess.
    @ViewBuilder private var soundSection: some View {
        Section {
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(RFDesign.labelDim)
                Slider(value: $audio.volume, in: 0...1)
                    .tint(RFDesign.ready)
                Button {
                    audio.play(.restOver)
                    Haptics.shared.play(.restOver)
                } label: {
                    Text("Test").font(RFDesign.ui(13, bold: true))
                        .foregroundStyle(RFDesign.ready)
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: $audio.speaks) {
                Text("Say it out loud").font(RFDesign.ui(15))
            }
            .tint(RFDesign.ready)
        } header: {
            Text("The cooldown ping")
        } footer: {
            Text("Three ticks in the last three seconds, then a rising two-note chime and "
                 + "a haptic you can feel through a jacket. Both fire every time, because "
                 + "the phone is in a pocket and the AirPods might be out — either one "
                 + "alone is a cue you can miss.\n\n"
                 + "Spoken confirmations name the set that was logged and the lift you are "
                 + "walking back to, which only matters when you never looked at the screen.")
        }
    }

    /// The three AirPods gestures and what each one does.
    @ViewBuilder private var handsFreeSection: some View {
        Section {
            Toggle(isOn: $remote.enabled) {
                Text("Hands-free").font(RFDesign.ui(15))
            }
            .tint(RFDesign.ready)
            if remote.enabled {
                ForEach(RemoteControls.Gesture.allCases) { gesture in
                    Picker(gesture.label, selection: gestureBinding(gesture)) {
                        ForEach(RemoteControls.Action.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .font(RFDesign.ui(14))
                }
            }
        } header: {
            Text("AirPods")
        } footer: {
            Text("iOS gives an app three gestures — press, double, triple — and only to "
                 + "whichever app is currently playing audio. That is why this app plays "
                 + "your music itself rather than remote-controlling the Music app: it is "
                 + "the only way a squeeze reaches here at all.\n\n"
                 + "Triple-press logs the set by default because it is the one nobody does "
                 + "by accident. While the cooldown is already running there is no set to "
                 + "log, so the same squeeze skips the rest instead. Gestures only do "
                 + "workout things on a set screen; anywhere else they are music.")
        }
    }

    /// Music, and the one playlist a workout starts with.
    @ViewBuilder private var musicSection: some View {
        Section {
            switch music.status {
            case .ready:
                Label("Connected", systemImage: "music.note")
                    .foregroundStyle(RFDesign.ready)
                Toggle(isOn: $music.shuffle) {
                    Text("Shuffle").font(RFDesign.ui(15))
                }
                .tint(RFDesign.ready)
                Picker("Starts with", selection: favouriteBinding) {
                    Text("Newest playlist").tag("")
                    ForEach(music.playlistNames, id: \.self) { Text($0).tag($0) }
                }
            case .unknown:
                Button {
                    Task { await music.connect() }
                } label: {
                    Label("Connect Apple Music", systemImage: "music.note")
                }
            case .denied, .unavailable:
                Label(music.status.message, systemImage: "music.note.slash")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.labelDim)
            }
        } header: {
            Text("Music")
        } footer: {
            Text("Your library's playlists, played by this app. The Apple Music catalogue "
                 + "isn't searchable here on purpose — a gym app plays the list you already "
                 + "made, and browsing is what the phone you left in the locker is for.")
        }
    }

    private func gestureBinding(_ gesture: RemoteControls.Gesture) -> Binding<RemoteControls.Action> {
        Binding(get: { gesture.action }, set: { gesture.action = $0 })
    }

    private var favouriteBinding: Binding<String> {
        Binding(get: { music.favouritePlaylist ?? "" },
                set: { music.favouritePlaylist = $0.isEmpty ? nil : $0 })
    }

    /// When you train, and whether the workouts follow the weekday or rotate.
    @ViewBuilder private var scheduleSection: some View {
        let schedule = schedules.first
        Section {
            Picker("Schedule", selection: modeBinding) {
                ForEach(Rotation.Mode.allCases) { Text($0.label).tag($0) }
            }

            if schedule?.config.mode != .weekday {
                if schedule?.config.mode == .everyNDays {
                    Stepper("Every \(schedule?.everyNDays ?? 2) days",
                            value: everyNBinding, in: 1...14)
                } else {
                    ForEach(Weekdays.all, id: \.number) { day in
                        Toggle(day.name, isOn: weekdayBinding(day.number))
                            .font(RFDesign.ui(14))
                    }
                }
            }
        } header: {
            Text("When you train")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        guard let config = schedules.first?.config else { return "" }
        switch config.mode {
        case .weekday:
            return "Each workout belongs to a weekday, and that is the one you get. "
                 + "Right for a fixed weekly split."
        case .rotation, .everyNDays:
            let next = Rotation.index(on: .now,
                                      sessionDates: [], dayCount: max(days.count, 1))
            _ = next
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
                try? context.save()
                snapshots.setNeedsWrite(context)
            })
    }

    private var everyNBinding: Binding<Int> {
        Binding(
            get: { schedules.first?.everyNDays ?? 2 },
            set: { value in
                schedules.first?.everyNDays = value
                try? context.save()
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
                try? context.save()
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
