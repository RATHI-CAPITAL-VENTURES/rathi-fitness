import SwiftUI
import SwiftData

/// Where the app connects to things. Currently: Health.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthBridge
    @EnvironmentObject private var snapshots: SnapshotService

    @State private var working = false

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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
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
