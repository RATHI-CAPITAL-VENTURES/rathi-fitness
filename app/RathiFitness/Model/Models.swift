import Foundation
import SwiftData

// CloudKit mirroring imposes three rules on every model below, and breaking any
// of them fails at container-build time rather than at compile time:
//   1. every stored property has a default value,
//   2. every relationship is optional,
//   3. no `@Attribute(.unique)` anywhere.
// That is why `slug` is a plain String with an index-by-convention rather than a
// unique attribute, and why de-duplication happens in code.

@Model
final class Exercise {
    var name: String = ""
    /// Stable identifier the CLI and RIA refer to. Lowercase, dashed.
    var slug: String = ""
    /// Drives plate math. A cable stack or a dumbbell has no plates to compute.
    var loading: String = Loading.barbell.rawValue
    var barWeight: Double = 45
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.exercise)
    var planItems: [PlanItem]? = []

    init(name: String, slug: String? = nil,
         loading: Loading = .barbell, barWeight: Double = 45) {
        self.name = name
        self.slug = slug ?? Exercise.slugify(name)
        self.loading = loading.rawValue
        self.barWeight = barWeight
        self.createdAt = .now
    }

    enum Loading: String, CaseIterable {
        case barbell, dumbbell, machine, cable, bodyweight
        var showsPlateMath: Bool { self == .barbell }
    }

    var loadingKind: Loading { Loading(rawValue: loading) ?? .barbell }

    static func slugify(_ s: String) -> String {
        let mapped = s.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}

/// One exercise slot inside a day's plan: what you intend to do.
@Model
final class PlanItem {
    var order: Int = 0
    var targetSets: Int = 3
    var targetReps: Int = 10
    var targetWeight: Double = 0
    var restSeconds: Int = 90
    var exercise: Exercise?
    var day: PlannedDay?

    init(order: Int, exercise: Exercise, targetSets: Int, targetReps: Int,
         targetWeight: Double, restSeconds: Int = 90) {
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
    }
}

/// A named day in the rotation — "Push A". `weekday` uses `Calendar`'s 1=Sunday.
@Model
final class PlannedDay {
    var name: String = ""
    var weekday: Int = 0
    var order: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.day)
    var items: [PlanItem]? = []

    init(name: String, weekday: Int, order: Int = 0) {
        self.name = name
        self.weekday = weekday
        self.order = order
    }

    /// Plan items in the order you do them.
    var orderedItems: [PlanItem] { (items ?? []).sorted { $0.order < $1.order } }
}

/// One set, as performed. The only record of what actually happened.
@Model
final class SetEntry {
    var date: Date = Date.now
    var weight: Double = 0
    var reps: Int = 0
    var setIndex: Int = 1
    var exercise: Exercise?

    init(exercise: Exercise, weight: Double, reps: Int, setIndex: Int, date: Date = .now) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.setIndex = setIndex
        self.date = date
    }
}

@Model
final class WeighIn {
    var date: Date = Date.now
    var pounds: Double = 0

    init(pounds: Double, date: Date = .now) {
        self.pounds = pounds
        self.date = date
    }
}

/// A stored gym pass. Every field a real card carries, because the alternative
/// is finding out at the turnstile that the one you needed wasn't modelled.
@Model
final class GymPass {
    var name: String = ""
    var location: String = ""
    /// The payload the scanner reads. Never logged, never exported in the clear.
    var code: String = ""
    var symbology: String = Symbology.qr.rawValue
    var memberID: String = ""
    var notes: String = ""
    var isPrimary: Bool = false
    var expires: Date?
    /// 0 means "not a limited-use pass".
    var usesLeft: Int = 0
    var punches: Int = 0
    var punchesNeeded: Int = 0
    var addedAt: Date = Date.now

    init(name: String, location: String = "", code: String,
         symbology: Symbology = .qr, memberID: String = "",
         isPrimary: Bool = false, expires: Date? = nil,
         usesLeft: Int = 0, punches: Int = 0, punchesNeeded: Int = 0) {
        self.name = name
        self.location = location
        self.code = code
        self.symbology = symbology.rawValue
        self.memberID = memberID
        self.isPrimary = isPrimary
        self.expires = expires
        self.usesLeft = usesLeft
        self.punches = punches
        self.punchesNeeded = punchesNeeded
    }

    /// The formats a gym door actually uses. All four are one CIFilter each —
    /// the reason to cover the set now is that discovering your gym uses
    /// Code 128 while standing at the turnstile is not a good time to find out.
    enum Symbology: String, CaseIterable, Identifiable {
        case qr, code128, pdf417, aztec
        var id: String { rawValue }
        var label: String {
            switch self {
            case .qr: return "QR"
            case .code128: return "Barcode (Code 128)"
            case .pdf417: return "PDF417"
            case .aztec: return "Aztec"
            }
        }
        /// Barcodes are wide and short; square codes are square.
        var isLinear: Bool { self == .code128 }
    }

    var format: Symbology { Symbology(rawValue: symbology) ?? .qr }

    /// What the card can still do, in words, or nil when there is nothing to say.
    var stateLine: String? {
        var parts: [String] = []
        if punchesNeeded > 0 { parts.append("\(punches) of \(punchesNeeded) punched") }
        if usesLeft > 0 { parts.append("\(usesLeft) use\(usesLeft == 1 ? "" : "s") left") }
        if let e = expires {
            let f = DateFormatter()
            f.dateFormat = "d MMM"
            parts.append((e < .now ? "Expired " : "Expires ") + f.string(from: e))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isExpired: Bool {
        if let e = expires, e < .now { return true }
        if punchesNeeded > 0 && punches >= punchesNeeded { return true }
        return false
    }
}
