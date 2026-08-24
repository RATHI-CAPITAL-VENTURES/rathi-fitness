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
    /// The weight on this machine makes the exercise **easier**, not harder.
    ///
    /// An assisted pull-up machine counterweights you: 100 lb of help is a much
    /// easier set than 40, and getting stronger means the number going DOWN.
    /// Every piece of arithmetic in the app assumed the opposite, and the
    /// failures were not cosmetic — a 100 lb assist registered as a
    /// heaviest-ever personal best, hitting all your reps suggested *adding*
    /// help next time, and the assistance was counted as tonnage moved, so the
    /// weaker you got the better the numbers looked.
    ///
    /// A flag rather than a signed weight: storing assistance as −100 would
    /// make every display, stepper and chart carry a minus sign it has to
    /// explain, and one forgotten `abs()` would put a negative into a total.
    var assisted: Bool = false

    /// Whether this is something you lift or something you run on.
    ///
    /// A separate axis from `loading`, which is about what goes on a bar. A
    /// treadmill has no loading style and a barbell has no incline, and folding
    /// the two into one enum would make every switch statement answer two
    /// questions at once.
    var modality: String = Modality.strength.rawValue
    /// Which cardio numbers this machine actually has, as comma-separated
    /// `CardioMetric` raw values. A rower has no incline; a treadmill has no
    /// damper. Empty on a strength lift.
    var cardioMetrics: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exercise)
    var sets: [SetEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.exercise)
    var planItems: [PlanItem]? = []

    /// Where you set the machine. See `MachineSetting`.
    @Relationship(deleteRule: .cascade, inverse: \MachineSetting.exercise)
    var machineSettings: [MachineSetting]? = []

    init(name: String, slug: String? = nil,
         loading: Loading = .barbell, barWeight: Double = 45,
         primary: MuscleGroup = .other, secondary: [MuscleGroup] = [],
         modality: Modality = .strength, metrics: [CardioMetric] = [],
         assisted: Bool = false) {
        self.assisted = assisted
        self.name = name
        self.slug = slug ?? Exercise.slugify(name)
        self.loading = loading.rawValue
        self.barWeight = barWeight
        self.primaryMuscle = primary.rawValue
        self.secondaryMuscles = secondary.map(\.rawValue).joined(separator: ",")
        self.modality = modality.rawValue
        // A cardio machine with no stated metrics gets the common four rather
        // than none — an exercise you cannot record anything against is worse
        // than one that offers a field you ignore.
        let resolved = metrics.isEmpty && modality == .cardio
            ? CardioMetric.commonSet : metrics
        self.cardioMetrics = resolved.map(\.rawValue).joined(separator: ",")
        self.createdAt = .now
    }

    enum Modality: String, CaseIterable, Identifiable {
        case strength, cardio
        var id: String { rawValue }
        var label: String { self == .strength ? "Lifting" : "Cardio" }
    }

    var kind: Modality { Modality(rawValue: modality) ?? .strength }
    var isCardio: Bool { kind == .cardio }

    /// What the big number on the set screen is measuring. "lb" on a bench,
    /// "lb help" on an assisted pull-up — the one place the distinction has to
    /// be visible rather than merely correct.
    var weightUnit: String { assisted ? "lb help" : "lb" }

    /// Whether a smaller number is the better one.
    var lowerIsBetter: Bool { assisted }

    /// The numbers this machine has, in a fixed order so two screens cannot
    /// show them in different sequences.
    var metrics: [CardioMetric] {
        let raw = Set(cardioMetrics.split(separator: ",").map(String.init))
        return CardioMetric.allCases.filter { raw.contains($0.rawValue) }
    }

    /// Machine settings in a stable order.
    var settings: [MachineSetting] {
        (machineSettings ?? []).sorted {
            ($0.setting.order, $0.setting.label) < ($1.setting.order, $1.setting.label)
        }
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
    /// Cardio targets. Zero means "not part of the plan for this one" — a
    /// treadmill slot can prescribe twenty minutes at 3% and leave the speed to
    /// how you feel, which is how people actually run.
    var targetSeconds: Int = 0
    var targetDistance: Double = 0
    var targetSpeed: Double = 0
    var targetIncline: Double = 0
    var targetResistance: Double = 0
    /// Items sharing a non-zero group are a superset: you alternate between
    /// them and rest once at the end of the round, not after each exercise.
    /// `0` means "on its own". Without this the cooldown ring is not merely
    /// missing for supersets, it is wrong — it would start after the first
    /// exercise of a pair you are meant to go straight through.
    var supersetGroup: Int = 0
    var exercise: Exercise?
    var day: PlannedDay?

    init(order: Int, exercise: Exercise, targetSets: Int, targetReps: Int,
         targetWeight: Double, restSeconds: Int = 90, supersetGroup: Int = 0,
         targetSeconds: Int = 0, targetDistance: Double = 0,
         targetSpeed: Double = 0, targetIncline: Double = 0,
         targetResistance: Double = 0) {
        self.targetSeconds = targetSeconds
        self.targetDistance = targetDistance
        self.targetSpeed = targetSpeed
        self.targetIncline = targetIncline
        self.targetResistance = targetResistance
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
    /// What a cardio piece records instead of weight × reps. All zero on a
    /// lift, and zero means "not recorded" rather than "zero minutes".
    var seconds: Int = 0
    /// Miles. The app is in pounds; mixing units inside one app is how you get
    /// a 5 that means two different distances.
    var distance: Double = 0
    /// Miles per hour.
    var speed: Double = 0
    /// Percent grade.
    var incline: Double = 0
    /// The machine's own resistance number — a bike level, a rower's damper.
    /// Unitless on purpose: it is a dial position, not a physical quantity, and
    /// it does not compare between machines.
    var resistance: Double = 0
    /// Average heart rate, bpm. Typed in from the console or the watch.
    var averageHeartRate: Int = 0
    /// `user` or `demo`. Demo rows are sample data and can be removed wholesale;
    /// see `Seed`. Without this there is no way to tell an invented set from one
    /// you actually did, and an app that cannot tell should not be drawing
    /// either of them on a chart labelled with your name.
    var source: String = Source.user.rawValue
    var exercise: Exercise?

    init(exercise: Exercise, weight: Double, reps: Int, setIndex: Int,
         date: Date = .now, kind: SetKind = .working, rpe: Double = 0,
         note: String = "", source: Source = .user,
         seconds: Int = 0, distance: Double = 0, speed: Double = 0,
         incline: Double = 0, resistance: Double = 0, averageHeartRate: Int = 0) {
        self.seconds = seconds
        self.distance = distance
        self.speed = speed
        self.incline = incline
        self.resistance = resistance
        self.averageHeartRate = averageHeartRate
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

    /// A cardio entry records time or distance and never weight × reps.
    var isCardio: Bool { seconds > 0 || distance > 0 }

    /// Average speed as actually achieved, when both halves are known. Preferred
    /// over the `speed` field for anything historical: `speed` is the number on
    /// the console when you glanced at it, this is what you did.
    var achievedSpeed: Double? {
        guard seconds > 0, distance > 0 else { return nil }
        return distance / (Double(seconds) / 3600)
    }

    func value(for metric: CardioMetric) -> Double {
        switch metric {
        case .duration: return Double(seconds)
        case .distance: return distance
        case .speed: return speed
        case .incline: return incline
        case .resistance: return resistance
        case .heartRate: return Double(averageHeartRate)
        }
    }
}

/// What a cardio machine measures.
///
/// The complete set a commercial gym's consoles show, so wrapping a new machine
/// is choosing from this list rather than adding a field. Anything absent is
/// absent on purpose: calories, because the console's guess and the watch's
/// measurement land in the same ring and disagree (the same argument that keeps
/// a burn out of the HealthKit export); watts and cadence, because no treadmill
/// or basic bike reports them and a field nothing fills teaches you to skip the
/// screen.
enum CardioMetric: String, CaseIterable, Identifiable {
    case duration, distance, speed, incline, resistance, heartRate

    var id: String { rawValue }

    /// The four every piece of cardio equipment in a normal gym has, used when
    /// nobody has said which ones a machine offers.
    static let commonSet: [CardioMetric] = [.duration, .distance, .speed, .incline]

    var label: String {
        switch self {
        case .duration: return "Time"
        case .distance: return "Distance"
        case .speed: return "Speed"
        case .incline: return "Incline"
        case .resistance: return "Resistance"
        case .heartRate: return "Heart rate"
        }
    }

    var unit: String {
        switch self {
        case .duration: return "min"
        case .distance: return "mi"
        case .speed: return "mph"
        case .incline: return "%"
        case .resistance: return "level"
        case .heartRate: return "bpm"
        }
    }

    /// How much one tap of the stepper moves it. Duration is in seconds because
    /// that is what the model stores; everything else is in its own unit.
    var step: Double {
        switch self {
        case .duration: return 60
        case .distance: return 0.1
        case .speed: return 0.1
        case .incline: return 0.5
        case .resistance: return 1
        case .heartRate: return 1
        }
    }

    /// Zero is "not recorded" for every one of these — nobody runs zero miles
    /// at zero incline and writes it down.
    func isRecorded(_ value: Double) -> Bool { value > 0 }
}

/// Where you set the machine.
///
/// "2 on the leg press" is a real thing you have to remember every week, and it
/// was nowhere in a set log. It belongs to the EXERCISE rather than to a set:
/// the seat does not change between Tuesday and Thursday, and recording it per
/// set would make you re-enter it four times an evening.
///
/// One row per dial, driven by `MachineSettingKind`, so adding "foot plate"
/// later is a case rather than a column.
@Model
final class MachineSetting {
    var kind: String = MachineSettingKind.seat.rawValue
    /// Free text, because machine dials are not one type. "2", "4", "12 in",
    /// "30°", "third notch". A number field would have forced a lie on half of
    /// them.
    var value: String = ""
    var updatedAt: Date = Date.now
    var exercise: Exercise?

    init(kind: MachineSettingKind, value: String, exercise: Exercise? = nil) {
        self.kind = kind.rawValue
        self.value = value
        self.exercise = exercise
        self.updatedAt = .now
    }

    var setting: MachineSettingKind { MachineSettingKind(rawValue: kind) ?? .other }
}

/// The dials a gym machine actually has.
///
/// Enumerated rather than free-form so two entries cannot be "seat" and "Seat
/// height", which would make the whole feature useless the first time you read
/// it back. The list is what a commercial gym floor offers; `other` is the
/// escape hatch.
enum MachineSettingKind: String, CaseIterable, Identifiable {
    case seat, back, seatDepth, chestPad, legPad, thighPad, footPlate
    case handle, grip, pulley, leverArm, rangeLimiter, benchAngle
    case rackPins, safetyBars, headrest, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seat: return "Seat"
        case .back: return "Back pad"
        case .seatDepth: return "Seat depth"
        case .chestPad: return "Chest pad"
        case .legPad: return "Leg pad"
        case .thighPad: return "Thigh pad"
        case .footPlate: return "Foot plate"
        case .handle: return "Handle"
        case .grip: return "Grip"
        case .pulley: return "Pulley"
        case .leverArm: return "Lever arm"
        case .rangeLimiter: return "Range limiter"
        case .benchAngle: return "Bench angle"
        case .rackPins: return "Rack pins"
        case .safetyBars: return "Safety bars"
        case .headrest: return "Headrest"
        case .other: return "Other"
        }
    }

    /// Display order — the ones you set most often, first.
    var order: Int { MachineSettingKind.allCases.firstIndex(of: self) ?? 99 }

    /// What the field looks like before you have typed in it. Concrete, because
    /// "value" as a placeholder says nothing about the shape of answer the
    /// machine wants.
    var hint: String {
        switch self {
        case .benchAngle: return "30°"
        case .rackPins, .safetyBars: return "hole 12"
        case .grip: return "wide"
        default: return "2"
        }
    }
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

/// How the programme is scheduled. One row, ever.
///
/// A model rather than `@AppStorage` because it belongs to the training plan and
/// should follow it between devices, not sit in the defaults of whichever phone
/// happened to set it.
@Model
final class Schedule {
    var mode: String = Rotation.Mode.weekday.rawValue
    /// Comma-separated `Calendar` weekday numbers, 1 = Sunday.
    var trainingWeekdays: String = "3,5,7"
    var everyNDays: Int = 2

    init() {}

    var config: Rotation.Config {
        get {
            Rotation.Config(
                mode: Rotation.Mode(rawValue: mode) ?? .weekday,
                trainingWeekdays: Set(trainingWeekdays.split(separator: ",")
                    .compactMap { Int($0) }),
                everyNDays: everyNDays)
        }
        set {
            mode = newValue.mode.rawValue
            trainingWeekdays = newValue.trainingWeekdays.sorted()
                .map(String.init).joined(separator: ",")
            everyNDays = newValue.everyNDays
        }
    }
}

/// What a new exercise opens on.
///
/// Every new plan slot was hardcoded to 3 × 10 at 90 seconds, which is a fine
/// guess for a stranger and wrong every single time for the person actually
/// using it — correcting the same three numbers on every exercise you add is
/// the app charging rent.
///
/// A model rather than `@AppStorage`, for the same reason `Schedule` is one:
/// this belongs to the training plan and should follow it between devices, not
/// sit in the defaults of whichever phone happened to set it.
@Model
final class PlanDefaults {
    var targetSets: Int = 3
    var targetReps: Int = 10
    var restSeconds: Int = 90
    /// Cardio opens on a single twenty-minute bout — a treadmill slot has no
    /// use for a rep target and needs a length instead.
    var cardioSeconds: Int = 20 * 60

    init() {}

    /// The one row, made on first use. Mirrors how `Schedule` is reached, and
    /// keeps every caller from having to decide what to do when it is missing.
    static func current(in context: ModelContext) -> PlanDefaults {
        if let existing = try? context.fetch(FetchDescriptor<PlanDefaults>()).first {
            return existing
        }
        let made = PlanDefaults()
        context.insert(made)
        return made
    }
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
