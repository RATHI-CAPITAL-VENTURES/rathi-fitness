import Foundation

/// The exercise library.
///
/// Hevy ships 400+; we shipped the 16 in the seeded plan, which meant every new
/// lift started with no muscle mapping and a guessed bar weight. This is the
/// working set of movements a commercial gym actually offers, with what each one
/// works — enough that adding an exercise is picking one, not describing one.
///
/// One row per movement. Loading and muscles are derived from it everywhere, so
/// a lift cannot be a barbell here and a cable somewhere else.
enum Catalogue {

    struct Entry {
        let name: String
        let loading: Exercise.Loading
        let primary: MuscleGroup
        let secondary: [MuscleGroup]
        var modality: Exercise.Modality = .strength
        /// Which console numbers this machine has. Empty on a lift, and empty
        /// on a cardio entry means "the common four" — see `Exercise.init`.
        var metrics: [CardioMetric] = []
        var bar: Double { loading == .barbell ? 45 : 0 }
    }

    static func make(_ name: String, _ loading: Exercise.Loading,
                     _ primary: MuscleGroup, _ secondary: [MuscleGroup] = []) -> Entry {
        Entry(name: name, loading: loading, primary: primary, secondary: secondary)
    }

    /// A cardio machine. Separate constructor rather than a defaulted argument
    /// on `make`, so the cardio block below reads as a different kind of thing —
    /// which it is: none of these has a bar weight or a rep.
    static func cardio(_ name: String, _ primary: MuscleGroup,
                       _ metrics: [CardioMetric],
                       _ secondary: [MuscleGroup] = []) -> Entry {
        Entry(name: name, loading: .machine, primary: primary, secondary: secondary,
              modality: .cardio, metrics: metrics)
    }

    static let all: [Entry] = [
        // Chest
        make("Bench Press", .barbell, .chest, [.triceps, .shoulders]),
        make("Incline Bench Press", .barbell, .chest, [.shoulders, .triceps]),
        make("Close-Grip Bench Press", .barbell, .triceps, [.chest]),
        make("Dumbbell Bench Press", .dumbbell, .chest, [.triceps, .shoulders]),
        make("Incline DB Press", .dumbbell, .chest, [.shoulders, .triceps]),
        make("Dumbbell Fly", .dumbbell, .chest, []),
        make("Cable Fly", .cable, .chest, []),
        make("Chest Press Machine", .machine, .chest, [.triceps]),
        make("Push-Up", .bodyweight, .chest, [.triceps, .core]),
        make("Dip", .bodyweight, .chest, [.triceps]),
        make("Pec Deck", .machine, .chest, []),

        // Back
        make("Deadlift", .barbell, .back, [.hamstrings, .glutes, .traps, .forearms]),
        make("Romanian Deadlift", .barbell, .hamstrings, [.glutes, .back]),
        make("Sumo Deadlift", .barbell, .glutes, [.hamstrings, .back]),
        make("Rack Pull", .barbell, .back, [.traps, .forearms]),
        make("Barbell Row", .barbell, .back, [.lats, .biceps]),
        make("Pendlay Row", .barbell, .back, [.lats, .biceps]),
        make("Dumbbell Row", .dumbbell, .lats, [.back, .biceps]),
        make("Chest-Supported Row", .machine, .back, [.lats, .biceps]),
        make("Seated Cable Row", .cable, .back, [.lats, .biceps]),
        make("Lat Pulldown", .machine, .lats, [.biceps]),
        make("Pull-Up", .bodyweight, .lats, [.biceps, .back]),
        make("Chin-Up", .bodyweight, .lats, [.biceps]),
        make("Straight-Arm Pulldown", .cable, .lats, []),
        make("Face Pull", .cable, .traps, [.shoulders]),
        make("Shrug", .barbell, .traps, [.forearms]),
        make("Dumbbell Shrug", .dumbbell, .traps, [.forearms]),
        make("Back Extension", .bodyweight, .back, [.glutes, .hamstrings]),

        // Shoulders
        make("Overhead Press", .barbell, .shoulders, [.triceps, .core]),
        make("Push Press", .barbell, .shoulders, [.triceps, .quads]),
        make("Seated DB Press", .dumbbell, .shoulders, [.triceps]),
        make("Arnold Press", .dumbbell, .shoulders, [.triceps]),
        make("Lateral Raise", .dumbbell, .shoulders, []),
        make("Cable Lateral Raise", .cable, .shoulders, []),
        make("Rear Delt Fly", .dumbbell, .shoulders, [.traps]),
        make("Upright Row", .barbell, .shoulders, [.traps, .biceps]),
        make("Shoulder Press Machine", .machine, .shoulders, [.triceps]),

        // Arms
        make("Barbell Curl", .barbell, .biceps, [.forearms]),
        make("EZ-Bar Curl", .barbell, .biceps, [.forearms]),
        make("Dumbbell Curl", .dumbbell, .biceps, [.forearms]),
        make("Hammer Curl", .dumbbell, .biceps, [.forearms]),
        make("Incline Curl", .dumbbell, .biceps, []),
        make("Preacher Curl", .machine, .biceps, []),
        make("Cable Curl", .cable, .biceps, [.forearms]),
        make("Concentration Curl", .dumbbell, .biceps, []),
        make("Triceps Pushdown", .cable, .triceps, []),
        make("Rope Pushdown", .cable, .triceps, []),
        make("Overhead Triceps Extension", .dumbbell, .triceps, []),
        make("Skull Crusher", .barbell, .triceps, []),
        make("Triceps Dip", .bodyweight, .triceps, [.chest]),
        make("Wrist Curl", .dumbbell, .forearms, []),
        make("Farmer's Walk", .dumbbell, .forearms, [.traps, .core]),

        // Legs
        make("Back Squat", .barbell, .quads, [.glutes, .core]),
        make("Front Squat", .barbell, .quads, [.core, .glutes]),
        make("Box Squat", .barbell, .quads, [.glutes]),
        make("Goblet Squat", .dumbbell, .quads, [.glutes, .core]),
        make("Hack Squat", .machine, .quads, [.glutes]),
        make("Leg Press", .machine, .quads, [.glutes, .hamstrings]),
        make("Bulgarian Split Squat", .dumbbell, .quads, [.glutes]),
        make("Walking Lunge", .dumbbell, .quads, [.glutes]),
        make("Step-Up", .dumbbell, .quads, [.glutes]),
        make("Leg Extension", .machine, .quads, []),
        make("Leg Curl", .machine, .hamstrings, []),
        make("Seated Leg Curl", .machine, .hamstrings, []),
        make("Nordic Curl", .bodyweight, .hamstrings, []),
        make("Good Morning", .barbell, .hamstrings, [.back, .glutes]),
        make("Hip Thrust", .barbell, .glutes, [.hamstrings]),
        make("Glute Bridge", .bodyweight, .glutes, [.hamstrings]),
        make("Cable Kickback", .cable, .glutes, []),
        make("Calf Raise", .machine, .calves, []),
        make("Seated Calf Raise", .machine, .calves, []),
        make("Standing Calf Raise", .bodyweight, .calves, []),

        // Core
        make("Plank", .bodyweight, .core, []),
        make("Hanging Leg Raise", .bodyweight, .core, [.forearms]),
        make("Cable Crunch", .cable, .core, []),
        make("Ab Wheel", .bodyweight, .core, []),
        make("Russian Twist", .dumbbell, .core, []),
        make("Pallof Press", .cable, .core, []),
        make("Sit-Up", .bodyweight, .core, []),
        make("Back Squat (Pause)", .barbell, .quads, [.glutes, .core]),

        // Cardio
        //
        // Each one declares the numbers ITS console actually shows. A rower has
        // no incline and a treadmill has no damper, and offering every field on
        // every machine is how a logging screen becomes something you skip.
        cardio("Treadmill", .quads, [.duration, .distance, .speed, .incline, .heartRate],
               [.hamstrings, .calves, .glutes]),
        cardio("Treadmill Walk", .quads, [.duration, .distance, .speed, .incline, .heartRate],
               [.calves, .glutes]),
        cardio("Stationary Bike", .quads, [.duration, .distance, .resistance, .heartRate],
               [.hamstrings, .calves]),
        cardio("Spin Bike", .quads, [.duration, .distance, .resistance, .heartRate],
               [.glutes, .calves]),
        cardio("Assault Bike", .quads, [.duration, .distance, .heartRate],
               [.shoulders, .core]),
        cardio("Elliptical", .quads, [.duration, .distance, .resistance, .incline, .heartRate],
               [.glutes, .hamstrings]),
        cardio("Rower", .back, [.duration, .distance, .resistance, .heartRate],
               [.lats, .quads, .biceps, .core]),
        cardio("Ski Erg", .lats, [.duration, .distance, .resistance, .heartRate],
               [.triceps, .core]),
        cardio("Stair Climber", .glutes, [.duration, .resistance, .heartRate],
               [.quads, .calves]),
        cardio("Jump Rope", .calves, [.duration, .heartRate], [.shoulders]),
        cardio("Outdoor Run", .quads, [.duration, .distance, .speed, .heartRate],
               [.hamstrings, .calves, .glutes]),
        cardio("Outdoor Walk", .quads, [.duration, .distance, .speed, .heartRate],
               [.calves, .glutes]),
        cardio("Swim", .lats, [.duration, .distance, .heartRate],
               [.shoulders, .back, .core]),
    ]

    static func entry(named name: String) -> Entry? {
        let wanted = Exercise.slugify(name)
        return all.first { Exercise.slugify($0.name) == wanted }
    }

    static func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q)
                         || $0.primary.rawValue.contains(q) }
    }

    /// Build the model object for a catalogue entry.
    static func exercise(from entry: Entry) -> Exercise {
        Exercise(name: entry.name, loading: entry.loading, barWeight: entry.bar,
                 primary: entry.primary, secondary: entry.secondary,
                 modality: entry.modality, metrics: entry.metrics)
    }

    /// Fill in what we know about an exercise created by typing a name.
    static func enrich(_ exercise: Exercise) {
        guard let entry = entry(named: exercise.name) else { return }
        exercise.loading = entry.loading.rawValue
        exercise.barWeight = entry.bar
        exercise.primaryMuscle = entry.primary.rawValue
        exercise.secondaryMuscles = entry.secondary.map(\.rawValue).joined(separator: ",")
        exercise.modality = entry.modality.rawValue
        exercise.cardioMetrics = (entry.metrics.isEmpty && entry.modality == .cardio
                                  ? CardioMetric.commonSet : entry.metrics)
            .map(\.rawValue).joined(separator: ",")
    }
}
