import SwiftUI
import SwiftData

@main
struct RathiFitnessApp: App {
    private let container = Store.makeContainer()
    @StateObject private var snapshots = SnapshotService()
    @StateObject private var rest = RestTimer()
    @StateObject private var health = HealthBridge()


    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(snapshots)
                .environmentObject(rest)
                .environmentObject(health)
                .preferredColorScheme(.dark)
                .tint(RFDesign.ready)
                .task {
                    let context = container.mainContext
                    try? Seed.runIfNeeded(context)
                    // If Health is already connected, it is the source of truth
                    // for body mass — pull before writing the snapshot so the
                    // Mac sees this morning's weigh-in without anyone typing it.
                    if health.status.isConnected {
                        await health.importWeighIns(into: context)
                        await health.exportWorkouts(from: context)
                    }
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
