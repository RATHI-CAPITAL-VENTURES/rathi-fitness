import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
import SwiftData
import SwiftUI

/// The Apple Health seam.
///
/// Two directions, and they are not symmetric:
///
/// **In — body mass.** Once Health is connected it is the source of truth for
/// what you weigh, because that is where the scale writes. Typing a number into
/// this app becomes the fallback rather than the main path.
///
/// **Out — workouts and weigh-ins.** A finished session goes over as an
/// `HKWorkout` so it lands in Fitness and on the watch, and a weight typed here
/// goes back so Health does not disagree with us.
///
/// Like CloudKit, this needs an entitlement (`com.apple.developer.healthkit`)
/// that a wildcard team profile cannot carry — see the README. Under
/// `RF_LOCAL_ONLY` the whole thing reports itself unavailable rather than
/// failing at the permission sheet.
@MainActor
final class HealthBridge: ObservableObject {

    enum Status: Equatable {
        case unsupported(String)
        case notAsked
        case denied
        case connected

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var status: Status = .notAsked
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var importedCount: Int = 0

    /// Days already sent to Health, so a session is not written twice.
    @AppStorage("health.exportedDays") private var exportedDaysRaw: String = ""

    #if canImport(HealthKit)
    /// Lazy: constructing `HKHealthStore` opens an XPC connection, and on a
    /// build with no entitlement that logs "Missing com.apple.developer.healthkit
    /// entitlement" on every launch. Nothing breaks, but a console full of
    /// errors trains you to ignore the console.
    private lazy var store = HKHealthStore()
    private var bodyMass: HKQuantityType { HKQuantityType(.bodyMass) }
    #endif

    init() { status = Self.initialStatus() }

    static func initialStatus() -> Status {
        #if RF_LOCAL_ONLY
        return .unsupported("This build has no Health entitlement — see the README. "
                            + "Sign into Xcode and rebuild to turn it on.")
        #elseif canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unsupported("Health isn't available on this device.")
        }
        return .notAsked
        #else
        return .unsupported("Health isn't available on this platform.")
        #endif
    }

    // MARK: - Permission

    func connect() async {
        #if canImport(HealthKit) && !RF_LOCAL_ONLY
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(
                toShare: [bodyMass, HKObjectType.workoutType()],
                read: [bodyMass])
            // NOTE: HealthKit deliberately never tells you whether READ access
            // was granted — that itself would leak information about the user.
            // So "connected" here means "the sheet was answered", and an empty
            // import is not proof of refusal.
            status = .connected
            lastError = nil
        } catch {
            status = .denied
            lastError = error.localizedDescription
        }
        #endif
    }

    // MARK: - In: body mass

    /// Pull weigh-ins Health has that we do not, and insert them.
    @discardableResult
    func importWeighIns(into context: ModelContext, days: Int = 365) async -> Int {
        #if canImport(HealthKit) && !RF_LOCAL_ONLY
        guard status.isConnected else { return 0 }
        do {
            let samples = try await recentBodyMass(days: days)
            let existing = try context.fetch(FetchDescriptor<WeighIn>()).map(\.date)
            let wanted = HealthSync.samplesToImport(samples, existing: existing)
            for sample in wanted {
                context.insert(WeighIn(pounds: sample.pounds, date: sample.date))
            }
            if !wanted.isEmpty { try context.save() }
            importedCount = wanted.count
            lastSync = .now
            lastError = nil
            return wanted.count
        } catch {
            lastError = error.localizedDescription
            return 0
        }
        #else
        return 0
        #endif
    }

    #if canImport(HealthKit) && !RF_LOCAL_ONLY
    private func recentBodyMass(days: Int) async throws -> [HealthSync.Sample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMass, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                                   ascending: false)]
            ) { _, samples, error in
                if let error { return continuation.resume(throwing: error) }
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    HealthSync.Sample(
                        date: $0.endDate,
                        pounds: ($0.quantity.doubleValue(for: .pound()) * 10).rounded() / 10)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }
    #endif

    // MARK: - Out: weigh-ins and workouts

    func write(weighIn pounds: Double, at date: Date = .now) async {
        #if canImport(HealthKit) && !RF_LOCAL_ONLY
        guard status.isConnected else { return }
        let sample = HKQuantitySample(
            type: bodyMass,
            quantity: HKQuantity(unit: .pound(), doubleValue: pounds),
            start: date, end: date)
        do { try await store.save(sample) } catch { lastError = error.localizedDescription }
        #endif
    }

    /// Send finished sessions over as workouts. Whole past days only — see
    /// `HealthSync.sessionsReadyToExport`.
    func exportWorkouts(from context: ModelContext) async {
        #if canImport(HealthKit) && !RF_LOCAL_ONLY
        guard status.isConnected else { return }
        do {
            let sets = try context.fetch(FetchDescriptor<SetEntry>())
            let ready = HealthSync.sessionsReadyToExport(
                setDates: sets.map(\.date), alreadyExported: exportedDays)
            let calendar = Calendar.current
            for day in ready {
                let dates = sets.map(\.date).filter { calendar.isDate($0, inSameDayAs: day) }
                guard let bounds = HealthSync.bounds(forSetsAt: dates) else { continue }
                try await save(bounds)
                markExported(day)
            }
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    #if canImport(HealthKit) && !RF_LOCAL_ONLY
    private func save(_ bounds: HealthSync.WorkoutBounds) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration,
                                       device: .local())
        try await builder.beginCollection(at: bounds.start)
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: bounds.end)
        // No energy sample on purpose: an estimate would land in the same ring
        // as the watch's measured numbers. See HealthSync.bounds.
        _ = try await builder.finishWorkout()
    }
    #endif

    // MARK: - Which days have gone over

    private var exportedDays: Set<Date> {
        Set(exportedDaysRaw.split(separator: ",").compactMap {
            Double($0).map(Date.init(timeIntervalSince1970:))
        })
    }

    private func markExported(_ day: Date) {
        var all = exportedDays
        all.insert(day)
        // Keep it bounded; a year of training days is ~150 entries.
        let trimmed = all.sorted(by: >).prefix(400)
        exportedDaysRaw = trimmed.map { String($0.timeIntervalSince1970) }.joined(separator: ",")
    }
}
