import Foundation
import SwiftData
import SwiftUI

/// The model container, and the one place that knows how to degrade.
enum Store {

    static let schema = Schema([
        Exercise.self, PlanItem.self, PlannedDay.self,
        SetEntry.self, WeighIn.self, GymPass.self,
    ])

    /// CloudKit if we can have it, local if we cannot.
    ///
    /// An unsigned simulator build has no iCloud entitlement, and a container
    /// configured for CloudKit throws at init there. Crashing on launch because
    /// the developer is not signed into iCloud makes the app untestable, so the
    /// fallback is real behaviour rather than a debug convenience: the phone
    /// still works in a basement, it just does not sync.
    /// True while XCTest is loaded. Unit tests get their own in-memory store:
    /// a test that mutates the real database, or that waits on CloudKit setup,
    /// is a test that fails for reasons unrelated to what it is checking.
    static var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    /// UI tests drive the real app, so `XCTestCase` is not loaded in-process and
    /// `isRunningTests` is false there. Without this the suite writes into the
    /// actual database and every run starts from the last run's leftovers —
    /// which is exactly how a green test turns red on the fifth run for reasons
    /// that have nothing to do with the code.
    static var isUITest: Bool {
        ProcessInfo.processInfo.environment["RF_UITEST"] == "1"
    }

    /// Whether it is safe to ask SwiftData for a CloudKit-backed store.
    ///
    /// Learned the hard way, and worth writing down because the failure looks
    /// like a bug in your code: if the process has no iCloud entitlement — which
    /// is every unsigned simulator build, including the ones CI makes —
    /// `PFCloudKitContainerProvider containerWithIdentifier:` **traps** on a
    /// background queue during store setup. It is not a thrown error, so
    /// `try? ModelContainer(...)` cannot catch it and the app dies several
    /// hundred milliseconds after a launch that looked fine.
    ///
    /// `ubiquityIdentityToken` is the cheap proxy: nil when nobody is signed
    /// into iCloud, which is exactly the case where CloudKit was going to be
    /// useless anyway. `RF_NO_CLOUDKIT=1` forces it off for a signed-in
    /// simulator, where the entitlement is still absent.
    static var cloudKitIsUsable: Bool {
        if ProcessInfo.processInfo.environment["RF_NO_CLOUDKIT"] == "1" { return false }
        #if targetEnvironment(simulator)
        // A simulator build is never signed with the container entitlement, so
        // being signed into iCloud there is not enough to make this safe.
        return false
        #else
        return FileManager.default.ubiquityIdentityToken != nil
        #endif
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory || isRunningTests || isUITest {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: config)
        }
        if cloudKitIsUsable {
            let cloud = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(SnapshotWriter.containerID))
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                       cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        // Last resort: an in-memory store, so the app opens and says something
        // useful instead of dying on a black screen.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }
}

/// Writes the snapshot out, coalescing bursts.
///
/// Logging a set changes the model three times in a second; writing the whole
/// JSON three times is wasteful and, worse, makes the file churn in iCloud. So
/// edits mark it dirty and a short debounce does the actual write.
@MainActor
final class SnapshotService: ObservableObject {
    @Published private(set) var lastWritten: Date?
    @Published private(set) var lastDestination: String?
    @Published private(set) var lastError: String?

    private var pending: Task<Void, Never>?
    private let debounce: Duration

    init(debounce: Duration = .seconds(2)) { self.debounce = debounce }

    /// Call after any change worth telling the Mac about.
    func setNeedsWrite(_ context: ModelContext) {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            await self.writeNow(context)
        }
    }

    func writeNow(_ context: ModelContext) async {
        do {
            let snapshot = try SnapshotBuilder.build(from: context)
            // Resolving the ubiquity container blocks; keep it off the main actor.
            let dest = try await Task.detached(priority: .utility) {
                try SnapshotWriter.write(snapshot)
            }.value
            lastWritten = .now
            lastError = nil
            switch dest {
            case .iCloud: lastDestination = "iCloud Drive"
            case .local(let u): lastDestination = "on this device only — \(u.path)"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
