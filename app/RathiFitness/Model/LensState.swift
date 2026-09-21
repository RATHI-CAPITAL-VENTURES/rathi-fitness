import Foundation

/// What is in front of your right eye.
///
/// A plain value, deliberately: nothing here knows about Meta's SDK, SwiftData
/// or a view. The set screen describes itself as one of these, the renderer
/// turns it into Meta's vocabulary, and everything in between — what changed,
/// what is worth sending — is a comparison of two structs. That is also the
/// only part of this feature a test can reach, because Meta's mock device has
/// no display.
///
/// Four lines and at most two buttons is not modesty. The lens is 600 pixels
/// square, the SDK offers three sizes of text, and the input is a highlight and
/// a pinch. Anything that needs more than that is a job for the phone.
struct LensState: Equatable {

    /// Which of the three moments this is. It picks the colour of the big
    /// number and nothing else — the words are already in the fields below.
    ///
    /// A rest carries how far through it you are, because the colour is the
    /// signal: `RFDesign.coolHue` holds ember for three quarters of a rest and
    /// hands over to teal at the end, so you catch the change without reading
    /// the number. That was designed for a phone you are not looking at. A
    /// numeral floating in your peripheral vision is the better home for it.
    enum Tone: Equatable {
        case ready
        case resting(progress: Double)
        case done
    }

    /// The small capitals above everything: where you are in the workout.
    var eyebrow: String
    var title: String
    /// The one thing to read from across a rack: "185 × 8", or "1:12".
    var hero: String
    var detail: String
    var tone: Tone
    /// In order, and the order is a decision: the glasses light the FIRST
    /// button when a screen appears, so the first one is a single pinch and the
    /// rest cost a swipe. (Measured on the hardware — see docs/DECISIONS.md.)
    var actions: [LensAction]
}

/// What a pinch can mean. A registry, so the label the lens shows, the thing
/// the app does and the list Settings could one day offer are one table.
///
/// Every case lands on `RemoteControls`, the same place an AirPods squeeze
/// does. There is one implementation of "log the set" in this app and the lens
/// is its third caller, not a second copy.
enum LensAction: String, CaseIterable, Equatable {
    case logSet, skipRest, extendRest

    var label: String {
        switch self {
        case .logSet: return "Log set"
        case .skipRest: return "Skip"
        case .extendRest: return "+30 s"
        }
    }

    var remote: RemoteControls.Action {
        switch self {
        case .logSet: return .logSet
        case .skipRest: return .skipRest
        case .extendRest: return .extendRest
        }
    }
}

// MARK: - From a set screen

extension LensState {

    /// A cooldown as the lens needs it.
    ///
    /// Progress is derived from the whole seconds left rather than read off the
    /// clock, on purpose: two states built within the same second must compare
    /// equal, or the pacer sees a "change" on every call and the radio runs
    /// flat out to redraw a numeral that has not moved.
    struct Rest: Equatable {
        var remaining: Int
        var progress: Double

        init(remaining: Int, total: TimeInterval) {
            self.remaining = max(0, remaining)
            self.progress = total > 0 ? min(max(1 - Double(self.remaining) / total, 0), 1) : 1
        }
    }

    /// A lift. Mirrors what `SetView` would say out loud for the "where am I"
    /// gesture, which is the same question asked through a different sense.
    ///
    /// - Parameters:
    ///   - nextSet: the working set you are about to do, 1-based.
    ///   - resting: the cooldown, or nil when not resting here.
    static func strength(
        exercise: String, day: String?, nextSet: Int, of sets: Int,
        weight: Double, unit: String, reps: Int, resting: Rest?
    ) -> LensState {
        let finished = nextSet > sets
        let load = Self.load(weight: weight, unit: unit, reps: reps)

        if let resting {
            return LensState(
                eyebrow: "RESTING",
                title: exercise,
                hero: Fmt.clock(resting.remaining),
                // Resting after the last set is still a rest — you are getting
                // your breath back before the next exercise — but there is no
                // "then" to promise.
                detail: finished ? "That was the last set" : "Then set \(nextSet) of \(sets) · \(load)",
                tone: .resting(progress: resting.progress),
                actions: [.skipRest, .extendRest])
        }
        if finished {
            return LensState(
                eyebrow: (day ?? "Done").uppercased(), title: exercise,
                hero: "Done", detail: "\(sets) of \(sets) sets",
                tone: .done, actions: [])
        }
        return LensState(
            eyebrow: [day?.uppercased(), "SET \(nextSet) OF \(sets)"].compactMap { $0 }.joined(separator: " · "),
            title: exercise, hero: load, detail: "Rest starts when you log it",
            tone: .ready, actions: [.logSet])
    }

    /// A machine. One bout rather than sets, so the number is the clock.
    ///
    /// - Parameter canLog: false until there is something on the clock to log —
    ///   the same rule the cardio screen applies to its own button, so the lens
    ///   never offers a pinch that would do nothing.
    static func cardio(
        exercise: String, day: String?, seconds: Int, resting: Rest?, canLog: Bool
    ) -> LensState {
        if let resting {
            return LensState(
                eyebrow: "RESTING", title: exercise,
                hero: Fmt.clock(resting.remaining), detail: "Until the next interval",
                tone: .resting(progress: resting.progress), actions: [.skipRest, .extendRest])
        }
        return LensState(
            eyebrow: (day ?? "Cardio").uppercased(), title: exercise,
            hero: Fmt.minutes(seconds), detail: canLog ? "On the clock" : "Set the clock on your phone",
            tone: .ready, actions: canLog ? [.logSet] : [])
    }

    /// "185 × 8", or "12 reps" for a lift with nothing on the bar — "0 × 12"
    /// reads as a fault, and a push-up has no weight to show.
    private static func load(weight: Double, unit: String, reps: Int) -> String {
        weight > 0 ? "\(Fmt.weight(weight)) × \(reps)" : "\(reps) reps"
    }
}

// MARK: - When to send

/// Decides whether a screen is worth the radio.
///
/// Every send replaces the whole lens — Meta's SDK has no partial update — so
/// the rule is simply "did anything you can see change". A resting clock
/// changes every second and so is sent every second, which costs about 50 ms
/// as text and 155 ms with a drawn numeral; a *Ready* screen does not change
/// for a minute at a time and is sent once.
///
/// Except for the heartbeat. On the hardware a session survived thirty seconds
/// of complete silence, and thirty is only the longest gap anyone tried. Rather
/// than find out what happens at forty in the middle of somebody's workout, a
/// still screen is re-sent inside the envelope that is known to work.
struct LensPacer {
    static let heartbeat: TimeInterval = 20

    private(set) var lastSent: LensState?
    private(set) var lastSentAt: Date?

    func shouldSend(_ state: LensState, at now: Date = .now) -> Bool {
        guard let lastSent, let lastSentAt else { return true }
        if state != lastSent { return true }
        return now.timeIntervalSince(lastSentAt) >= Self.heartbeat
    }

    mutating func sent(_ state: LensState, at now: Date = .now) {
        lastSent = state
        lastSentAt = now
    }

    /// After a drop the glasses are showing nothing, whatever we last sent —
    /// so the next screen goes out even if it is identical to the last.
    mutating func forget() {
        lastSent = nil
        lastSentAt = nil
    }
}
