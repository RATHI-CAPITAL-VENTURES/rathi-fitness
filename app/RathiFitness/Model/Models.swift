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
    /// Primary mover, as a `MuscleGroup` raw value. Drives sets-per-muscle-per
    /// week, which is the standard hypertrophy question and the one thing our
    /// Trends screen could not answer.
    var primaryMuscle: String = MuscleGroup.other.rawValue
    /// Comma-separated `MuscleGroup` raw values. Counted at half a set each,
    /// which is the usual convention and stated here so nobody has to guess
    /// why the numbers are fractional.
    var secondaryMuscles: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.exercise)
    var planItems: [PlanItem]? = []

    init(name: String, slug: String? = nil,
         loading: Loading = .barbell, barWeight: Double = 45,
         primary: MuscleGroup = .other, secondary: [MuscleGroup] = []) {
        self.name = name
        self.slug = slug ?? Exercise.slugify(name)
        self.loading = loading.rawValue
        self.barWeight = barWeight
        self.primaryMuscle = primary.rawValue
        self.secondaryMuscles = secondary.map(\.rawValue).joined(separator: ",")
        self.createdAt = .now
    }

    var primary: MuscleGroup { MuscleGroup(rawValue: primaryMuscle) ?? .other }
    var secondary: [MuscleGroup] {
        secondaryMuscles.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) }
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
    /// Items sharing a non-zero group are a superset: you alternate between
    /// them and rest once at the end of the round, not after each exercise.
    /// `0` means "on its own". Without this the cooldown ring is not merely
    /// missing for supersets, it is wrong — it would start after the first
    /// exercise of a pair you are meant to go straight through.
    var supersetGroup: Int = 0
    var exercise: Exercise?
    var day: PlannedDay?

    init(order: Int, exercise: Exercise, targetSets: Int, targetReps: Int,
         targetWeight: Double, restSeconds: Int = 90, supersetGroup: Int = 0) {
        self.supersetGroup = supersetGroup
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
    /// What kind of set this was. A warm-up is not a working set and must not
    /// count toward volume or records — this was the single biggest correctness
    /// gap against Hevy and Strong, because a 135 warm-up on bench day was
    /// silently inflating both.
    var kind: String = SetKind.working.rawValue
    /// Reps in reserve, expressed as RPE 6–10. `0` means not recorded, which is
    /// different from "easy" and is why this is not an enum with a default case.
    var rpe: Double = 0
    /// Anything you want to remember about it. "Left shoulder clicked."
    var note: String = ""
    /// `user` or `demo`. Demo rows are sample data and can be removed wholesale;
    /// see `Seed`. Without this there is no way to tell an invented set from one
    /// you actually did, and an app that cannot tell should not be drawing
    /// either of them on a chart labelled with your name.
    var source: String = Source.user.rawValue
    var exercise: Exercise?

    init(exercise: Exercise, weight: Double, reps: Int, setIndex: Int,
         date: Date = .now, kind: SetKind = .working, rpe: Double = 0,
         note: String = "", source: Source = .user) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.setIndex = setIndex
        self.date = date
        self.kind = kind.rawValue
        self.rpe = rpe
        self.note = note
        self.source = source.rawValue
    }

    var isDemo: Bool { source == Source.demo.rawValue }
    var setKind: SetKind { SetKind(rawValue: kind) ?? .working }
}

enum Source: String { case user, demo }

/// The set types every serious logger has and we did not.
enum SetKind: String, CaseIterable, Identifiable {
    case warmup, working, drop, failure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .working: return "Working"
        case .drop: return "Drop set"
        case .failure: return "To failure"
        }
    }

    /// One character for the set screen, where space is the scarce resource.
    var badge: String {
        switch self {
        case .warmup: return "W"
        case .working: return "•"
        case .drop: return "D"
        case .failure: return "F"
        }
    }

    /// Whether it counts toward tonnage and records.
    ///
    /// A warm-up does not. A drop set does — you moved the weight, and it is
    /// part of the working effort. A set to failure obviously does.
    var counts: Bool { self != .warmup }

    /// Warm-ups sit apart so the working sets read as a block.
    var isPreparation: Bool { self == .warmup }
}

/// Everything about the body that isn't a lift.
///
/// Body weight has its own model because it is the one measured daily and
/// charted everywhere. These are the others — waist and arms being the two
/// people actually keep — and they share one table because the list is
/// open-ended and a column per tape measure is how you end up migrating.
@Model
final class BodyMetric {
    var date: Date = Date.now
    var kind: String = MetricKind.waist.rawValue
    var inches: Double = 0
    var note: String = ""

    init(kind: MetricKind, inches: Double, date: Date = .now, note: String = "") {
        self.kind = kind.rawValue
        self.inches = inches
        self.date = date
        self.note = note
    }

    var metric: MetricKind { MetricKind(rawValue: kind) ?? .waist }
}

enum MetricKind: String, CaseIterable, Identifiable {
    case waist, chest, hips, thighLeft, thighRight, armLeft, armRight, calf, neck, shoulders

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .hips: return "Hips"
        case .thighLeft: return "Thigh (L)"
        case .thighRight: return "Thigh (R)"
        case .armLeft: return "Arm (L)"
        case .armRight: return "Arm (R)"
        case .calf: return "Calf"
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        }
    }
}

/// What a lift actually works. One list, so an exercise and a weekly total
/// cannot disagree about what "back" means.
enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest, back, lats, traps, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, core, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lats: return "Lats"
        case .other: return "Other"
        default: return rawValue.capitalized
        }
    }

    /// Grouped for the weekly chart, where twelve bars is a wall and six is a
    /// readable answer to "am I doing enough pulling".
    var region: String {
        switch self {
        case .chest, .shoulders, .triceps: return "Push"
        case .back, .lats, .traps, .biceps, .forearms: return "Pull"
        case .quads, .hamstrings, .glutes, .calves: return "Legs"
        case .core: return "Core"
        case .other: return "Other"
        }
    }
}

@Model
final class WeighIn {
    var date: Date = Date.now
    var pounds: Double = 0
    var source: String = Source.user.rawValue

    init(pounds: Double, date: Date = .now, source: Source = .user) {
        self.pounds = pounds
        self.date = date
        self.source = source.rawValue
    }

    var isDemo: Bool { source == Source.demo.rawValue }
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
