import Foundation
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// The cooldown between sets.
///
/// Deadline-based rather than tick-counting: the phone goes in a pocket, the app
/// gets suspended, and a timer that counts ticks comes back wrong. Storing the
/// end date means returning to the app shows the truth, and a local notification
/// covers the case where you never look at it.
@MainActor
final class RestTimer: ObservableObject {
    @Published private(set) var endsAt: Date?
    @Published private(set) var total: TimeInterval = 90
    @Published private(set) var exerciseName: String?

    private var completion: Task<Void, Never>?
    private static let notificationID = "rest-over"

    var isResting: Bool { endsAt != nil }

    /// 0 = just racked the bar, 1 = recovered. The input to the whole colour idea.
    func progress(at now: Date = .now) -> Double {
        guard let endsAt, total > 0 else { return 1 }
        let remaining = endsAt.timeIntervalSince(now)
        return min(max(1 - remaining / total, 0), 1)
    }

    func remaining(at now: Date = .now) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    func start(seconds: Int, exercise: String?) {
        // Asked here rather than at launch: the first thing a new app should do
        // is not interrupt you with a permission sheet for a feature you have
        // not reached. By the time you finish a set, the ask explains itself.
        requestPermissionOnce()
        total = TimeInterval(max(1, seconds))
        endsAt = Date.now.addingTimeInterval(total)
        exerciseName = exercise
        scheduleNotification(in: total, exercise: exercise)
        armCompletion()
    }

    /// The honest direction. Named `extend`, not `snooze`.
    func extend(by seconds: Int) {
        guard let current = endsAt else { return }
        total += TimeInterval(seconds)
        endsAt = current.addingTimeInterval(TimeInterval(seconds))
        scheduleNotification(in: endsAt!.timeIntervalSinceNow, exercise: exerciseName)
        armCompletion()
    }

    func stop() {
        endsAt = nil
        exerciseName = nil
        completion?.cancel()
        completion = nil
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func armCompletion() {
        completion?.cancel()
        guard let endsAt else { return }
        let delay = endsAt.timeIntervalSinceNow
        completion = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finish() }
        }
    }

    private func finish() {
        #if canImport(UIKit)
        // A distinct pattern, because this fires while the phone is in a pocket
        // and it has to be tellable from a text message.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        endsAt = nil
        exerciseName = nil
    }

    // MARK: - Notifications

    private var askedForPermission = false

    private func requestPermissionOnce() {
        guard !askedForPermission else { return }
        askedForPermission = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(in seconds: TimeInterval, exercise: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        guard seconds > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = exercise.map { "\($0) — you're up" } ?? "You're up"
        content.body = "Rest is done."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(
            identifier: Self.notificationID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }
}
