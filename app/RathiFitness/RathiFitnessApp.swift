import SwiftUI
import SwiftData

@main
struct RathiFitnessApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container = Store.makeContainer()
    @StateObject private var snapshots = SnapshotService()
    @StateObject private var rest = RestTimer()
    @StateObject private var health = HealthBridge()
    @StateObject private var music: MusicController
    /// Built from the music controller because a squeeze that means "play/pause"
    /// has to reach the thing that is playing. One owner, one wire — and the
    /// reason these two are constructed here rather than declared inline.
    @StateObject private var remote: RemoteControls
    @StateObject private var audio = AudioHub.shared
    /// The one that speaks up when a write does not land. `Saves.shared` rather
    /// than a fresh instance, because the reporter a `Binding` setter reaches
    /// for by default has to be the same one this view is observing.
    @StateObject private var saves = Saves.shared

    init() {
        let music = MusicController()
        _music = StateObject(wrappedValue: music)
        _remote = StateObject(wrappedValue: RemoteControls(music: music))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(snapshots)
                .environmentObject(rest)
                .environmentObject(health)
                .environmentObject(music)
                .environmentObject(remote)
                .environmentObject(audio)
                .environmentObject(saves)
                .preferredColorScheme(.dark)
                .tint(RFDesign.ready)
                .onChange(of: scenePhase) { _, phase in
                    // Coming back from the background is the other moment your
                    // Health data has moved: the scale wrote this morning while
                    // the app was closed. `.task` only fires on a cold launch,
                    // which on a phone can be weeks apart — this app had two
                    // weigh-ins on record and a scale that writes daily.
                    guard phase == .active else { return }
                    Task { await health.syncNow(container.mainContext) }
                }
                .task {
                    // Without a delegate iOS shows nothing while the app is
                    // frontmost, so the cooldown alert existed only for a
                    // backgrounded app — the opposite of when it is needed.
                    CueNotifications.install()
                    let context = container.mainContext
                    reportingFailure("setting up your plan") {
                        try Seed.runIfNeeded(context)
                    }
                    // Anything left open by a kill on a previous day is closed
                    // before it can collect today's sets.
                    Sessions.closeStale(in: context)
                    // A fresh install has nothing to warn about, so the legacy
                    // banner is answered before it can ever be shown.
                    if (try? context.fetchCount(FetchDescriptor<SetEntry>())) == 0,
                       (try? context.fetchCount(FetchDescriptor<WeighIn>())) == 0 {
                        UserDefaults.standard.set(true, forKey: "history.legacyAcknowledged")
                    }
                    // `-RFDemoHistory` loads the tagged sample sessions. Used by
                    // the UI tests and for looking at a populated screen — a real
                    // first launch has no history, on purpose.
                    if ProcessInfo.processInfo.arguments.contains("-RFDemoHistory"),
                       (try? context.fetchCount(FetchDescriptor<SetEntry>())) == 0 {
                        reportingFailure("loading the sample data") {
                            try Seed.loadDemoHistory(context)
                        }
                    }
                    // AFTER everything that can write sets, not before.
                    //
                    // It ran straight after the seed at first, which meant the
                    // demo history loaded below got no sessions at all — and a
                    // set with no session is invisible to the swipe-back pager
                    // and to Trends. The same ordering trap applies to any
                    // future writer that runs at launch: give it a session, or
                    // put it above this line. Idempotent, so it is a launch step
                    // rather than a one-shot flag that can be lost.
                    reportingFailure("grouping your history into workouts") {
                        try Sessions.backfill(in: context)
                    }
                    context.saveOrReport("grouping your history into workouts")
                    // Ask HealthKit whether we have already been through its
                    // sheet. Without this the app forgets between launches and
                    // this sync never runs — the permission is fine, nobody
                    // ever asked about it.
                    await health.resume()
                    // If Health is already connected, it is the source of truth
                    // for body mass — pull before writing the snapshot so the
                    // Mac sees this morning's weigh-in without anyone typing it.
                    await health.syncNow(context)
                    // Picks the player up if you have already granted access;
                    // never prompts here. The ask belongs to the first tap on
                    // the music bar, where it explains itself.
                    await music.refreshQuietly()
                    // Write once at launch so the Mac is never more than a
                    // cold start behind, even on a day you log nothing.
                    await snapshots.writeNow(context)
                }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService
    @EnvironmentObject private var rest: RestTimer
    @EnvironmentObject private var saves: Saves

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "list.bullet") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            PassView()
                .tabItem { Label("Pass", systemImage: "qrcode") }
        }
        .background(RoomBackground(hue: roomHue, energy: roomEnergy))
        // Over every tab, not on one screen: the save it is reporting could
        // have come from any of them, and the tab you are looking at when it
        // fails is not necessarily the tab you were on when you caused it.
        .overlay(alignment: .top) { SaveFailureBanner() }
        .animation(.easeOut(duration: 0.2), value: saves.failure)
        .onChange(of: rest.isResting) { _, _ in }
    }

    /// The tab bar sits over the same room the screens do, and the room takes
    /// the cooldown's colour — so the app is warm while you are recovering even
    /// if you have wandered off to Trends.
    private var roomHue: Double {
        rest.isResting ? RFDesign.coolHue(rest.progress()) : RFDesign.readyHue
    }
    private var roomEnergy: Double {
        rest.isResting ? RFDesign.roomGlowActive : RFDesign.roomGlow
    }
}
