//
//  ExerciseCatalog.swift
//  Workout App (iOS)
//
//  Single source of truth for every seed exercise (gym-equipment and
//  bodyweight/cardio/yoga/mobility alike), plus the preset-catalog generator.
//
//  Two taxonomies live on every definition and they deliberately disagree:
//
//  * `muscleGroup` is the **browse** taxonomy — the filter a user taps in
//    MuscleGroupsView. A tricep pushdown lives under "Arms" there, because
//    that's where somebody looks for it.
//  * `bucket` is the **programming** taxonomy — which day of a split the
//    movement belongs on. That same tricep pushdown is a `.push` movement,
//    because triceps are trained with chest and shoulders, not with back.
//
//  Keeping only the first one is what used to put bicep curls on push day and
//  tricep pushdowns on pull day. `pattern` and `role` complete the picture:
//  `role` orders a session (heavy compounds while you're fresh, isolation
//  last) and `pattern` stops two near-identical lifts landing in one workout.
//
//  `GymSplit` stays in GymPlanGeneratorView.swift — still specific to that
//  interactive generator.
//

import Foundation
import SwiftData
import HealthKit

// MARK: - Programming classification

/// Which day of a push/pull/legs-style split a movement belongs on — the
/// *programming* taxonomy, as opposed to `muscleGroup`'s *browse* taxonomy.
enum TrainingBucket: Hashable {
    case push
    case pull
    case legs
    case core
    case conditioning
    case mobility
    /// Trains several buckets at once (deadlift-style carries, swings, Olympic
    /// lifts). Fits anywhere, anchors nothing.
    case fullBody
}

/// The movement pattern a lift trains. Used to keep a generated session from
/// stacking two near-identical lifts — two calf raises, two bicep curls.
enum MovementPattern: Hashable {
    case horizontalPress, verticalPress
    case horizontalPull, verticalPull
    case squat, hinge, lunge
    case chestFly, lateralRaise, rearDelt, shrug, pullover
    case bicepCurl, tricepExtension, forearm
    case quadIsolation, hamstringIsolation, gluteIsolation, calf
    case antiExtension, trunkFlexion, rotation, carry
    case conditioning, plyometric
    case mobility
}

/// How a movement is meant to be used inside a session. Drives ordering —
/// heavy multi-joint work first, while you're fresh; single-joint work last.
enum ExerciseRole: Int, Comparable {
    /// Heavy multi-joint anchor: squat, bench, deadlift, pull-up.
    case primary = 0
    /// Second multi-joint movement of the session: incline press, row, leg press.
    case secondary = 1
    /// Lighter multi-joint or single-limb work: lunge, bench dip, face pull.
    case accessory = 2
    /// Single-joint: curls, extensions, raises, calf work.
    case isolation = 3
    /// Continuous cardio or interval conditioning.
    case conditioning = 4
    /// Yoga poses, stretches, soft-tissue work.
    case mobility = 5

    static func < (lhs: ExerciseRole, rhs: ExerciseRole) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Exercise definition

struct GymExerciseDefinition {
    let id: String
    let name: String
    let muscleGroup: Int
    let equipment: [Int]
    let difficultyInt: Int
    /// Rough active-energy burn rate, in kcal per **minute** (yoga ≈ 1,
    /// burpees ≈ 8). `caloriesPerSecond` is what gets stored on `Exercise`.
    let kcalPerMinute: Double
    let symbol: String
    /// Reps to perform per set. `0` means the exercise is time-based and the workout
    /// timer drives it (e.g. plank, battle ropes, rowing).
    let repCount: Int
    /// Which day of a split this belongs on — see the file header.
    let bucket: TrainingBucket
    let pattern: MovementPattern
    let role: ExerciseRole
}

extension GymExerciseDefinition {
    /// Compact constructor for the catalog literal below — the memberwise
    /// initializer with eleven labels made each entry unreadable. `kcal` is
    /// kcal per minute.
    static func make(_ id: String, _ name: String, _ muscleGroup: WorkoutCategory,
                     _ equipment: [Equipment] = [],
                     difficulty: Int, kcal: Double, symbol: String, reps: Int,
                     bucket: TrainingBucket, pattern: MovementPattern,
                     role: ExerciseRole) -> GymExerciseDefinition {
        GymExerciseDefinition(id: id, name: name, muscleGroup: muscleGroup.rawValue,
                              equipment: equipment.map(\.rawValue), difficultyInt: difficulty,
                              kcalPerMinute: kcal, symbol: symbol, repCount: reps,
                              bucket: bucket, pattern: pattern, role: role)
    }

    /// The burn rate in kcal/s — the unit `Exercise.caloriesPerSecond` and
    /// `PhoneWorkoutHealthWriter.estimatedEnergy` use.
    var caloriesPerSecond: Double { kcalPerMinute / 60 }

    /// Localized easy/medium/hard label for this definition's difficulty.
    var difficultyLabel: String {
        switch difficultyInt {
        case 1: return NSLocalizedString("easy", comment: "easy Difficulty")
        case 3: return NSLocalizedString("hard", comment: "hard Difficulty")
        default: return NSLocalizedString("medium", comment: "medium Difficulty")
        }
    }

    /// Single source of truth for turning a catalog definition into a SwiftData
    /// `Exercise`: reuses an existing row with the same seed id (reconciling its
    /// rep count and equipment to the catalog unless the user changed them),
    /// otherwise creates and inserts a new one. Shared by every workout
    /// generator so the mapping stays consistent.
    func materialize(in context: ModelContext, existing: [Exercise]) -> Exercise {
        if let found = existing.first(where: { $0.id == id }) {
            // Only when they differ: assigning the same value still marks the
            // record changed and exports it to iCloud again, on every
            // generated workout.
            let customized = found.customizedFields
            if !customized.contains("repCount"), found.repCount != repCount { found.repCount = repCount }
            if !customized.contains("equipment"), found.equipment != equipment { found.equipment = equipment }
            // Not user-editable, so no `customizedFields` key: always the
            // catalog's rate (older installs stored per-minute numbers here).
            if found.caloriesPerSecond != caloriesPerSecond { found.caloriesPerSecond = caloriesPerSecond }
            return found
        }
        let exercise = Exercise(
            id: id,
            difficultyInt: difficultyInt,
            equipment: equipment,
            muscleGroup: muscleGroup,
            name: name
        )
        exercise.symbol = symbol
        exercise.difficulty = difficultyLabel
        exercise.repCount = repCount
        exercise.caloriesPerSecond = caloriesPerSecond
        context.insert(exercise)
        return exercise
    }
}

enum GymExerciseCatalog {

    /// The full exercise library: commercial-gym movements plus bodyweight,
    /// cardio/HIIT, yoga and mobility work. Each entry uses a stable seed-style
    /// ID so generated workouts (live or preset-catalog) reuse existing
    /// `Exercise` records instead of creating duplicates. IDs are permanent —
    /// renaming a movement is fine, changing its id orphans everybody's data.
    static let all: [GymExerciseDefinition] = [

        // MARK: Chest
        .make("seed-exercise-bench-press", "Bench Press", .chest, [.barbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "benchPressSymbol", reps: 8,
              bucket: .push, pattern: .horizontalPress, role: .primary),
        .make("seed-exercise-incline-bench-press", "Incline Bench Press", .chest, [.barbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "benchPressSymbol", reps: 8,
              bucket: .push, pattern: .horizontalPress, role: .primary),
        .make("seed-exercise-decline-bench-press", "Decline Bench Press", .chest, [.barbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "benchPressSymbol", reps: 8,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        .make("seed-exercise-dumbbell-bench-press", "Dumbbell Bench Press", .chest, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "benchPressSymbol", reps: 10,
              bucket: .push, pattern: .horizontalPress, role: .primary),
        .make("seed-exercise-incline-dumbbell-press", "Incline Dumbbell Press", .chest, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "benchPressSymbol", reps: 10,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        .make("seed-exercise-machine-chest-press", "Machine Chest Press", .chest, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "benchPressSymbol", reps: 10,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        .make("seed-exercise-machine-incline-chest-press", "Machine Incline Chest Press", .chest, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "benchPressSymbol", reps: 10,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        // Forward-leaning dip: chest-dominant. The upright, triceps-dominant
        // version is `seed-exercise-dips`, and the feet-on-floor regression is
        // `seed-exercise-tricep-dips` — three genuinely different exercises.
        .make("seed-exercise-chest-dip", "Chest Dip", .chest, [],
              difficulty: 3, kcal: 5, symbol: "tricepDipsSymbol", reps: 8,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        .make("seed-exercise-pushups", "Pushups", .chest, [],
              difficulty: 1, kcal: 5, symbol: "pushupsSymbol", reps: 12,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        .make("seed-exercise-diamond-push-up", "Diamond Push-Up", .chest, [],
              difficulty: 2, kcal: 5, symbol: "pushupsSymbol", reps: 10,
              bucket: .push, pattern: .horizontalPress, role: .accessory),
        .make("seed-exercise-dumbbell-fly", "Dumbbell Fly", .chest, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 4, symbol: "benchPressSymbol", reps: 12,
              bucket: .push, pattern: .chestFly, role: .isolation),
        .make("seed-exercise-cable-crossover", "Cable Crossover", .chest, [.cableMaschine],
              difficulty: 2, kcal: 4, symbol: "cableCrossover", reps: 12,
              bucket: .push, pattern: .chestFly, role: .isolation),
        .make("seed-exercise-pec-deck", "Pec Deck", .chest, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "pecDeckSymbol", reps: 12,
              bucket: .push, pattern: .chestFly, role: .isolation),
        .make("seed-exercise-dumbbell-pullover", "Dumbbell Pullover", .chest, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 4, symbol: "pulloverSymbol", reps: 12,
              bucket: .push, pattern: .pullover, role: .isolation),

        // MARK: Back
        .make("seed-exercise-deadlifts", "Deadlifts", .back, [.barbells],
              difficulty: 3, kcal: 6, symbol: "deadliftsSymbol", reps: 5,
              bucket: .pull, pattern: .hinge, role: .primary),
        .make("seed-exercise-sumo-deadlift", "Sumo Deadlift", .back, [.barbells],
              difficulty: 3, kcal: 6, symbol: "deadliftsSymbol", reps: 5,
              bucket: .pull, pattern: .hinge, role: .primary),
        .make("seed-exercise-trap-bar-deadlift", "Trap Bar Deadlift", .back, [.barbells],
              difficulty: 2, kcal: 6, symbol: "deadliftsSymbol", reps: 6,
              bucket: .pull, pattern: .hinge, role: .primary),
        .make("seed-exercise-rack-pull", "Rack Pull", .back, [.barbells],
              difficulty: 2, kcal: 5, symbol: "deadliftsSymbol", reps: 6,
              bucket: .pull, pattern: .hinge, role: .secondary),
        .make("seed-exercise-pull-ups", "Pull-ups", .back, [.pullUpBar],
              difficulty: 3, kcal: 6, symbol: "pullUpSymbol", reps: 8,
              bucket: .pull, pattern: .verticalPull, role: .primary),
        .make("seed-exercise-chin-ups", "Chin-Ups", .back, [.pullUpBar],
              difficulty: 3, kcal: 6, symbol: "pullUpSymbol", reps: 8,
              bucket: .pull, pattern: .verticalPull, role: .primary),
        .make("seed-exercise-assisted-pull-up", "Assisted Pull-Up", .back, [.cableMaschine],
              difficulty: 1, kcal: 5, symbol: "pullUpSymbol", reps: 10,
              bucket: .pull, pattern: .verticalPull, role: .secondary),
        .make("seed-exercise-lat-pulldown", "Lat Pulldown", .back, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "latPulldown", reps: 10,
              bucket: .pull, pattern: .verticalPull, role: .primary),
        .make("seed-exercise-barbell-row", "Barbell Row", .back, [.barbells],
              difficulty: 2, kcal: 5, symbol: "deadliftsSymbol", reps: 8,
              bucket: .pull, pattern: .horizontalPull, role: .primary),
        .make("seed-exercise-pendlay-row", "Pendlay Row", .back, [.barbells],
              difficulty: 3, kcal: 5, symbol: "deadliftsSymbol", reps: 6,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-t-bar-row", "T-Bar Row", .back, [.barbells],
              difficulty: 2, kcal: 5, symbol: "deadliftsSymbol", reps: 10,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-seated-cable-row", "Seated Cable Row", .back, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "figure.rower", reps: 10,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-machine-row", "Machine Row", .back, [.cableMaschine],
              difficulty: 1, kcal: 5, symbol: "figure.rower", reps: 10,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-dumbbell-row", "Dumbbell Row", .back, [.dumbbells, .weightBench],
              difficulty: 1, kcal: 4, symbol: "deadliftsSymbol", reps: 10,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-chest-supported-row", "Chest-Supported Row", .back, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 4, symbol: "deadliftsSymbol", reps: 10,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-inverted-row", "Inverted Row", .back, [.pullUpBar],
              difficulty: 1, kcal: 4, symbol: "invertedRowSymbol", reps: 12,
              bucket: .pull, pattern: .horizontalPull, role: .secondary),
        .make("seed-exercise-straight-arm-pulldown", "Straight-Arm Pulldown", .back, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "latPulldown", reps: 12,
              bucket: .pull, pattern: .pullover, role: .isolation),
        .make("seed-exercise-cable-pullover", "Cable Pullover", .back, [.cableMaschine],
              difficulty: 2, kcal: 4, symbol: "latPulldown", reps: 12,
              bucket: .pull, pattern: .pullover, role: .isolation),
        // Roman chair / back-extension bench. Tagged as bench equipment so it
        // can never be picked for a "no equipment" circuit.
        .make("seed-exercise-hyperextension", "Back Extension", .back, [.weightBench],
              difficulty: 1, kcal: 3, symbol: "supermanSymbol", reps: 12,
              bucket: .pull, pattern: .hinge, role: .accessory),
        .make("seed-exercise-good-morning", "Good Morning", .back, [.barbells],
              difficulty: 3, kcal: 5, symbol: "deadliftsSymbol", reps: 10,
              bucket: .legs, pattern: .hinge, role: .accessory),
        .make("seed-exercise-superman", "Superman", .back, [],
              difficulty: 1, kcal: 2, symbol: "supermanSymbol", reps: 12,
              bucket: .pull, pattern: .hinge, role: .isolation),
        // A rope is facility equipment rather than something a user owns, so
        // this stays "no equipment" — it is never programmed into a preset.
        .make("seed-exercise-rope-climb", "Rope Climb", .back, [],
              difficulty: 3, kcal: 7, symbol: "ropeClimb", reps: 0,
              bucket: .pull, pattern: .verticalPull, role: .conditioning),

        // MARK: Shoulders
        .make("seed-exercise-overhead-press", "Overhead Press", .shoulders, [.barbells],
              difficulty: 2, kcal: 4, symbol: "overheadPressSymbol", reps: 8,
              bucket: .push, pattern: .verticalPress, role: .primary),
        .make("seed-exercise-shoulder-press", "Shoulder Press", .shoulders, [.dumbbells],
              difficulty: 1, kcal: 4, symbol: "overheadPressSymbol", reps: 10,
              bucket: .push, pattern: .verticalPress, role: .primary),
        .make("seed-exercise-machine-shoulder-press", "Machine Shoulder Press", .shoulders, [.cableMaschine],
              difficulty: 1, kcal: 4, symbol: "overheadPressSymbol", reps: 10,
              bucket: .push, pattern: .verticalPress, role: .secondary),
        .make("seed-exercise-arnold-press", "Arnold Press", .shoulders, [.dumbbells],
              difficulty: 2, kcal: 4, symbol: "overheadPressSymbol", reps: 10,
              bucket: .push, pattern: .verticalPress, role: .secondary),
        .make("seed-exercise-push-press", "Push Press", .shoulders, [.barbells],
              difficulty: 3, kcal: 5, symbol: "overheadPressSymbol", reps: 6,
              bucket: .push, pattern: .verticalPress, role: .primary),
        .make("seed-exercise-landmine-press", "Landmine Press", .shoulders, [.barbells],
              difficulty: 2, kcal: 4, symbol: "overheadPressSymbol", reps: 10,
              bucket: .push, pattern: .verticalPress, role: .secondary),
        .make("seed-exercise-pike-push-up", "Pike Push-Up", .shoulders, [],
              difficulty: 2, kcal: 4, symbol: "pushupsSymbol", reps: 8,
              bucket: .push, pattern: .verticalPress, role: .secondary),
        .make("seed-exercise-lateral-raise", "Lateral Raise", .shoulders, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "lateralRaise", reps: 15,
              bucket: .push, pattern: .lateralRaise, role: .isolation),
        .make("seed-exercise-cable-lateral-raise", "Cable Lateral Raise", .shoulders, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "lateralRaise", reps: 15,
              bucket: .push, pattern: .lateralRaise, role: .isolation),
        .make("seed-exercise-machine-lateral-raise", "Machine Lateral Raise", .shoulders, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "lateralRaise", reps: 15,
              bucket: .push, pattern: .lateralRaise, role: .isolation),
        .make("seed-exercise-front-raise", "Front Raise", .shoulders, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "lateralRaise", reps: 12,
              bucket: .push, pattern: .lateralRaise, role: .isolation),
        // Rear-delt and trap work is pulling work, whatever filter it browses
        // under — hence `.pull`, so it lands on back day and not on press day.
        .make("seed-exercise-face-pull", "Face Pull", .shoulders, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "facePullSymbol", reps: 15,
              bucket: .pull, pattern: .rearDelt, role: .isolation),
        .make("seed-exercise-rear-delt-fly", "Rear Delt Fly", .shoulders, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "lateralRaise", reps: 15,
              bucket: .pull, pattern: .rearDelt, role: .isolation),
        .make("seed-exercise-reverse-pec-deck", "Reverse Pec Deck", .shoulders, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "pecDeckSymbol", reps: 15,
              bucket: .pull, pattern: .rearDelt, role: .isolation),
        .make("seed-exercise-upright-row", "Upright Row", .shoulders, [.barbells],
              difficulty: 2, kcal: 3, symbol: "figure.strengthtraining.traditional", reps: 12,
              bucket: .pull, pattern: .shrug, role: .accessory),
        .make("seed-exercise-shrugs", "Shrugs", .shoulders, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "figure.strengthtraining.traditional", reps: 15,
              bucket: .pull, pattern: .shrug, role: .isolation),

        // MARK: Arms
        // Biceps pull, triceps push — that split is what `bucket` exists for.
        .make("seed-exercise-bicep-curl", "Bicep Curl", .arms, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-hammer-curls", "Hammer Curls", .arms, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-barbell-curl", "Barbell Curl", .arms, [.barbells],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 10,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-preacher-curl", "Preacher Curl", .arms, [.ezBar, .weightBench],
              difficulty: 2, kcal: 3, symbol: "curlSymbol", reps: 10,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-incline-dumbbell-curl", "Incline Dumbbell Curl", .arms, [.dumbbells, .weightBench],
              difficulty: 2, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-concentration-curl", "Concentration Curl", .arms, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-cable-curl", "Cable Curl", .arms, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-machine-bicep-curl", "Machine Bicep Curl", .arms, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .bicepCurl, role: .isolation),
        .make("seed-exercise-reverse-curl", "Reverse Curl", .arms, [.ezBar],
              difficulty: 1, kcal: 3, symbol: "curlSymbol", reps: 12,
              bucket: .pull, pattern: .forearm, role: .isolation),
        .make("seed-exercise-wrist-curl", "Wrist Curl", .arms, [.dumbbells],
              difficulty: 1, kcal: 2, symbol: "curlSymbol", reps: 15,
              bucket: .pull, pattern: .forearm, role: .isolation),
        .make("seed-exercise-close-grip-bench-press", "Close-Grip Bench Press", .arms, [.barbells, .weightBench],
              difficulty: 2, kcal: 4, symbol: "benchPressSymbol", reps: 8,
              bucket: .push, pattern: .horizontalPress, role: .secondary),
        // Upright bar dip: triceps-dominant. See `seed-exercise-chest-dip`.
        .make("seed-exercise-dips", "Dips", .arms, [],
              difficulty: 3, kcal: 5, symbol: "tricepDipsSymbol", reps: 8,
              bucket: .push, pattern: .tricepExtension, role: .secondary),
        // Feet on the floor, hands behind you on a bench — the beginner
        // regression of a dip, not the same exercise as `seed-exercise-dips`.
        .make("seed-exercise-tricep-dips", "Bench Dips", .arms, [.weightBench],
              difficulty: 1, kcal: 4, symbol: "tricepDipsSymbol", reps: 12,
              bucket: .push, pattern: .tricepExtension, role: .accessory),
        .make("seed-exercise-skullcrushers", "Skullcrushers", .arms, [.ezBar, .weightBench],
              difficulty: 2, kcal: 4, symbol: "skullcrusher", reps: 10,
              bucket: .push, pattern: .tricepExtension, role: .isolation),
        .make("seed-exercise-tricep-pushdown", "Tricep Pushdown", .arms, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "tricepPushdownSymbol", reps: 12,
              bucket: .push, pattern: .tricepExtension, role: .isolation),
        .make("seed-exercise-overhead-tricep-extension", "Overhead Tricep Extension", .arms, [.dumbbells],
              difficulty: 1, kcal: 3, symbol: "overheadTricepSymbol", reps: 12,
              bucket: .push, pattern: .tricepExtension, role: .isolation),
        .make("seed-exercise-tricep-kickback", "Tricep Kickback", .arms, [.dumbbells],
              difficulty: 1, kcal: 2, symbol: "tricepKickbackSymbol", reps: 15,
              bucket: .push, pattern: .tricepExtension, role: .isolation),

        // MARK: Legs
        .make("seed-exercise-back-squat", "Back Squat", .legs, [.barbells],
              difficulty: 2, kcal: 6, symbol: "squatsSymbol", reps: 8,
              bucket: .legs, pattern: .squat, role: .primary),
        .make("seed-exercise-front-squat", "Front Squat", .legs, [.barbells],
              difficulty: 3, kcal: 6, symbol: "squatsSymbol", reps: 6,
              bucket: .legs, pattern: .squat, role: .primary),
        .make("seed-exercise-goblet-squat", "Goblet Squat", .legs, [.dumbbells],
              difficulty: 1, kcal: 5, symbol: "squatsSymbol", reps: 12,
              bucket: .legs, pattern: .squat, role: .primary),
        .make("seed-exercise-sumo-squat", "Sumo Squat", .legs, [.dumbbells],
              difficulty: 1, kcal: 5, symbol: "squatsSymbol", reps: 12,
              bucket: .legs, pattern: .squat, role: .secondary),
        .make("seed-exercise-leg-press", "Leg Press", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 5, symbol: "legPressMaschine", reps: 10,
              bucket: .legs, pattern: .squat, role: .primary),
        .make("seed-exercise-hack-squat", "Hack Squat", .legs, [.legPressMaschine],
              difficulty: 2, kcal: 5, symbol: "squatsSymbol", reps: 10,
              bucket: .legs, pattern: .squat, role: .secondary),
        .make("seed-exercise-smith-machine-squat", "Smith Machine Squat", .legs, [.smithMaschine],
              difficulty: 1, kcal: 6, symbol: "squatsSymbol", reps: 10,
              bucket: .legs, pattern: .squat, role: .primary),
        .make("seed-exercise-squats", "Squats", .legs, [],
              difficulty: 1, kcal: 5, symbol: "squatsSymbol", reps: 15,
              bucket: .legs, pattern: .squat, role: .secondary),
        .make("seed-exercise-pistol-squat", "Pistol Squat", .legs, [],
              difficulty: 3, kcal: 5, symbol: "pistolSquatSymbol", reps: 6,
              bucket: .legs, pattern: .squat, role: .accessory),
        .make("seed-exercise-wall-sits", "Wall Sits", .legs, [],
              difficulty: 2, kcal: 3, symbol: "wallSitSymbol", reps: 0,
              bucket: .legs, pattern: .quadIsolation, role: .accessory),
        .make("seed-exercise-romanian-deadlift", "Romanian Deadlift", .legs, [.barbells],
              difficulty: 2, kcal: 5, symbol: "deadliftsSymbol", reps: 8,
              bucket: .legs, pattern: .hinge, role: .primary),
        .make("seed-exercise-single-leg-rdl", "Single-Leg Romanian Deadlift", .legs, [.dumbbells],
              difficulty: 2, kcal: 4, symbol: "deadliftsSymbol", reps: 10,
              bucket: .legs, pattern: .hinge, role: .accessory),
        .make("seed-exercise-hip-thrust", "Hip Thrust", .legs, [.barbells, .weightBench],
              difficulty: 2, kcal: 5, symbol: "gluteBridgeSymbol", reps: 10,
              bucket: .legs, pattern: .gluteIsolation, role: .secondary),
        .make("seed-exercise-glute-bridge", "Glute Bridge", .legs, [],
              difficulty: 1, kcal: 3, symbol: "gluteBridgeSymbol", reps: 15,
              bucket: .legs, pattern: .gluteIsolation, role: .accessory),
        .make("seed-exercise-hip-abduction", "Hip Abduction", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 2, symbol: "hipAbductionSymbol", reps: 15,
              bucket: .legs, pattern: .gluteIsolation, role: .isolation),
        .make("seed-exercise-hip-adduction", "Hip Adduction", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 2, symbol: "hipAbductionSymbol", reps: 15,
              bucket: .legs, pattern: .gluteIsolation, role: .isolation),
        .make("seed-exercise-machine-glute-kickback", "Machine Glute Kickback", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 3, symbol: "gluteKickbackSymbol", reps: 12,
              bucket: .legs, pattern: .gluteIsolation, role: .isolation),
        .make("seed-exercise-lunges", "Lunges", .legs, [],
              difficulty: 1, kcal: 4, symbol: "lungesSymbol", reps: 12,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-walking-lunge", "Walking Lunge", .legs, [.dumbbells],
              difficulty: 2, kcal: 4, symbol: "lungesSymbol", reps: 12,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-reverse-lunge", "Reverse Lunge", .legs, [.dumbbells],
              difficulty: 1, kcal: 4, symbol: "lungesSymbol", reps: 12,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-lateral-lunge", "Lateral Lunge", .legs, [.dumbbells],
              difficulty: 2, kcal: 4, symbol: "lungesSymbol", reps: 10,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-bulgarian-split-squat", "Bulgarian Split Squat", .legs, [.dumbbells, .weightBench],
              difficulty: 3, kcal: 5, symbol: "lungesSymbol", reps: 10,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-step-ups", "Step-Ups", .legs, [.boxStepPlatform],
              difficulty: 2, kcal: 5, symbol: "figure.step.training", reps: 12,
              bucket: .legs, pattern: .lunge, role: .accessory),
        .make("seed-exercise-leg-extension", "Leg Extension", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 3, symbol: "legExtensionSymbol", reps: 12,
              bucket: .legs, pattern: .quadIsolation, role: .isolation),
        .make("seed-exercise-leg-curl", "Leg Curl", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 3, symbol: "legCurlSymbol", reps: 12,
              bucket: .legs, pattern: .hamstringIsolation, role: .isolation),
        .make("seed-exercise-nordic-curl", "Nordic Hamstring Curl", .legs, [.exerciseMat],
              difficulty: 3, kcal: 4, symbol: "nordicCurlSymbol", reps: 6,
              bucket: .legs, pattern: .hamstringIsolation, role: .isolation),
        .make("seed-exercise-calf-raise", "Calf Raise", .legs, [],
              difficulty: 1, kcal: 2, symbol: "calfRaise", reps: 15,
              bucket: .legs, pattern: .calf, role: .isolation),
        .make("seed-exercise-standing-calf-raise", "Standing Calf Raise", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 2, symbol: "calfRaise", reps: 15,
              bucket: .legs, pattern: .calf, role: .isolation),
        .make("seed-exercise-seated-calf-raise", "Seated Calf Raise", .legs, [.legPressMaschine],
              difficulty: 1, kcal: 2, symbol: "calfRaise", reps: 15,
              bucket: .legs, pattern: .calf, role: .isolation),

        // MARK: Core
        .make("seed-exercise-plank", "Plank", .core, [],
              difficulty: 1, kcal: 3, symbol: "plankSymbol", reps: 0,
              bucket: .core, pattern: .antiExtension, role: .accessory),
        .make("seed-exercise-side-plank", "Side Plank", .core, [],
              difficulty: 2, kcal: 2, symbol: "sidePlankSymbol", reps: 0,
              bucket: .core, pattern: .rotation, role: .accessory),
        .make("seed-exercise-hollow-body-hold", "Hollow Body Hold", .core, [.exerciseMat],
              difficulty: 2, kcal: 3, symbol: "figure.core.training", reps: 0,
              bucket: .core, pattern: .antiExtension, role: .accessory),
        .make("seed-exercise-dead-bug", "Dead Bug", .core, [.exerciseMat],
              difficulty: 1, kcal: 2, symbol: "figure.pilates", reps: 12,
              bucket: .core, pattern: .antiExtension, role: .accessory),
        .make("seed-exercise-bird-dog", "Bird Dog", .core, [.exerciseMat],
              difficulty: 1, kcal: 2, symbol: "birdDogSymbol", reps: 12,
              bucket: .core, pattern: .antiExtension, role: .accessory),
        .make("seed-exercise-ab-wheel-rollout", "Ab Wheel Rollout", .core, [],
              difficulty: 3, kcal: 4, symbol: "abWheelSymbol", reps: 10,
              bucket: .core, pattern: .antiExtension, role: .accessory),
        .make("seed-exercise-crunch", "Crunch", .core, [.exerciseMat],
              difficulty: 1, kcal: 2, symbol: "situpsSymbol", reps: 20,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-situps", "Situps", .core, [.exerciseMat],
              difficulty: 1, kcal: 3, symbol: "situpsSymbol", reps: 15,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-reverse-crunch", "Reverse Crunch", .core, [.exerciseMat],
              difficulty: 1, kcal: 3, symbol: "situpsSymbol", reps: 15,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-v-ups", "V-Ups", .core, [.exerciseMat],
              difficulty: 2, kcal: 3, symbol: "bicycleCrunchesSymbol", reps: 15,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-flutter-kicks", "Flutter Kicks", .core, [.exerciseMat],
              difficulty: 1, kcal: 3, symbol: "bicycleCrunchesSymbol", reps: 0,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-hanging-leg-raise", "Hanging Leg Raise", .core, [.pullUpBar],
              difficulty: 3, kcal: 4, symbol: "hangingLegRaiseSymbol", reps: 10,
              bucket: .core, pattern: .trunkFlexion, role: .accessory),
        .make("seed-exercise-hanging-knee-raise", "Hanging Knee Raise", .core, [.pullUpBar],
              difficulty: 2, kcal: 4, symbol: "hangingLegRaiseSymbol", reps: 12,
              bucket: .core, pattern: .trunkFlexion, role: .accessory),
        .make("seed-exercise-cable-crunch", "Cable Crunch", .core, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "cableCrunchSymbol", reps: 15,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-machine-crunch", "Machine Crunch", .core, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "situpsSymbol", reps: 15,
              bucket: .core, pattern: .trunkFlexion, role: .isolation),
        .make("seed-exercise-bicycle-crunches", "Bicycle Crunches", .core, [.exerciseMat],
              difficulty: 2, kcal: 3, symbol: "bicycleCrunchesSymbol", reps: 20,
              bucket: .core, pattern: .rotation, role: .isolation),
        .make("seed-exercise-russian-twists", "Russian Twists", .core, [.exerciseMat],
              difficulty: 2, kcal: 3, symbol: "russianTwistsSymbol", reps: 20,
              bucket: .core, pattern: .rotation, role: .isolation),
        .make("seed-exercise-rotary-torso", "Rotary Torso", .core, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "russianTwistsSymbol", reps: 15,
              bucket: .core, pattern: .rotation, role: .isolation),
        .make("seed-exercise-pallof-press", "Pallof Press", .core, [.cableMaschine],
              difficulty: 1, kcal: 3, symbol: "cableRotationSymbol", reps: 12,
              bucket: .core, pattern: .rotation, role: .accessory),
        .make("seed-exercise-cable-woodchopper", "Cable Woodchopper", .core, [.cableMaschine],
              difficulty: 2, kcal: 4, symbol: "cableRotationSymbol", reps: 12,
              bucket: .core, pattern: .rotation, role: .accessory),

        // MARK: Full body / loaded conditioning
        .make("seed-exercise-kettlebell-swing", "Kettlebell Swing", .fullbody, [.kettlebells],
              difficulty: 2, kcal: 5, symbol: "deadliftsSymbol", reps: 15,
              bucket: .fullBody, pattern: .hinge, role: .secondary),
        .make("seed-exercise-power-clean", "Power Clean", .fullbody, [.barbells],
              difficulty: 3, kcal: 7, symbol: "deadliftsSymbol", reps: 5,
              bucket: .fullBody, pattern: .hinge, role: .primary),
        .make("seed-exercise-clean-and-press", "Clean and Press", .fullbody, [.barbells],
              difficulty: 3, kcal: 7, symbol: "overheadPressSymbol", reps: 5,
              bucket: .fullBody, pattern: .verticalPress, role: .primary),
        .make("seed-exercise-thruster", "Thruster", .fullbody, [.dumbbells],
              difficulty: 3, kcal: 7, symbol: "overheadPressSymbol", reps: 10,
              bucket: .fullBody, pattern: .verticalPress, role: .secondary),
        .make("seed-exercise-turkish-get-up", "Turkish Get-Up", .fullbody, [.kettlebells],
              difficulty: 3, kcal: 5, symbol: "turkishGetUpSymbol", reps: 5,
              bucket: .fullBody, pattern: .carry, role: .accessory),
        .make("seed-exercise-farmers-carry", "Farmer's Carry", .fullbody, [.dumbbells],
              difficulty: 2, kcal: 6, symbol: "figure.strengthtraining.traditional", reps: 0,
              bucket: .fullBody, pattern: .carry, role: .accessory),
        .make("seed-exercise-sled-push", "Sled Push", .fullbody, [.sled],
              difficulty: 3, kcal: 8, symbol: "sledPushSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-wall-ball", "Wall Ball", .fullbody, [.medicineBall],
              difficulty: 2, kcal: 6, symbol: "overheadPressSymbol", reps: 15,
              bucket: .fullBody, pattern: .squat, role: .accessory),
        .make("seed-exercise-bear-crawl", "Bear Crawl", .fullbody, [],
              difficulty: 2, kcal: 5, symbol: "bearCrawlSymbol", reps: 0,
              bucket: .fullBody, pattern: .carry, role: .accessory),
        .make("seed-exercise-battle-ropes", "Battle Ropes", .upperbody, [.battleRopes],
              difficulty: 2, kcal: 6, symbol: "battleRopes", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),

        // MARK: Cardio
        .make("seed-exercise-jumping-jacks", "Jumping Jacks", .cardio, [],
              difficulty: 1, kcal: 6, symbol: "figure.mixed.cardio", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-high-knees", "High Knees", .cardio, [],
              difficulty: 1, kcal: 6, symbol: "highKneesSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-butt-kicks", "Butt Kicks", .cardio, [],
              difficulty: 1, kcal: 6, symbol: "highKneesSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-mountain-climbers", "Mountain Climbers", .cardio, [],
              difficulty: 2, kcal: 7, symbol: "mountainClimberSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-jump-rope", "Jump Rope", .cardio, [.jumpRope],
              difficulty: 1, kcal: 7, symbol: "jumpRopeSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-walking", "Brisk Walking", .cardio, [],
              difficulty: 1, kcal: 3, symbol: "figure.walk", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-running", "Running", .cardio, [],
              difficulty: 2, kcal: 7, symbol: "figure.run", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-sprint", "Sprint", .cardio, [],
              difficulty: 2, kcal: 8, symbol: "figure.run", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-cycling", "Cycling", .cardio, [.stationaryBike],
              difficulty: 1, kcal: 6, symbol: "figure.indoor.cycle", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-rowing", "Rowing", .cardio, [.rowingMaschine],
              difficulty: 2, kcal: 7, symbol: "figure.indoor.rowing", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-treadmill-run", "Treadmill Run", .cardio, [.treadmill],
              difficulty: 1, kcal: 6, symbol: "figure.run.treadmill", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-stair-climber", "Stair Climber", .cardio, [.stairClimber],
              difficulty: 2, kcal: 7, symbol: "figure.stair.stepper", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-elliptical", "Elliptical", .cardio, [.elliptical],
              difficulty: 1, kcal: 5, symbol: "figure.elliptical", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-ski-erg", "Ski Erg", .cardio, [.skiErg],
              difficulty: 2, kcal: 7, symbol: "figure.skiing.crosscountry", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        .make("seed-exercise-swimming", "Swimming", .cardio, [],
              difficulty: 2, kcal: 7, symbol: "figure.pool.swim", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),
        // Bagwork is conditioning, not an arm exercise — filing it under Arms is
        // what let it turn up as "accessory work" on a back day.
        .make("seed-exercise-boxing", "Boxing", .cardio, [.boxingGlovesPunchingBag],
              difficulty: 2, kcal: 6, symbol: "boxingSymbol", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),

        // MARK: HIIT / plyometrics
        .make("seed-exercise-burpees", "Burpees", .hiit, [],
              difficulty: 3, kcal: 8, symbol: "burpeesSymbol", reps: 10,
              bucket: .conditioning, pattern: .plyometric, role: .conditioning),
        .make("seed-exercise-burpees-with-pushups", "Burpees with Push-ups", .hiit, [],
              difficulty: 3, kcal: 8, symbol: "burpeesSymbol", reps: 10,
              bucket: .conditioning, pattern: .plyometric, role: .conditioning),
        .make("seed-exercise-squat-jumps", "Squat Jumps", .hiit, [],
              difficulty: 2, kcal: 7, symbol: "squatsSymbol", reps: 12,
              bucket: .conditioning, pattern: .plyometric, role: .conditioning),
        .make("seed-exercise-skater-jumps", "Skater Jumps", .hiit, [],
              difficulty: 2, kcal: 7, symbol: "lungesSymbol", reps: 20,
              bucket: .conditioning, pattern: .plyometric, role: .conditioning),
        .make("seed-exercise-box-jump", "Box Jump", .hiit, [.boxStepPlatform],
              difficulty: 2, kcal: 7, symbol: "figure.step.training", reps: 10,
              bucket: .conditioning, pattern: .plyometric, role: .conditioning),
        .make("seed-exercise-assault-bike-sprints", "Assault Bike Sprints", .hiit, [.stationaryBike],
              difficulty: 3, kcal: 9, symbol: "figure.indoor.cycle", reps: 0,
              bucket: .conditioning, pattern: .conditioning, role: .conditioning),

        // MARK: Yoga
        .make("seed-exercise-sun-salutation", "Sun Salutation", .yoga, [.exerciseMat],
              difficulty: 2, kcal: 1.5, symbol: "sunSalutationSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-cat-cow", "Cat-Cow", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1, symbol: "catCowSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-downward-facing-dog", "Downward Facing Dog", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1.5, symbol: "downwardFacingDogSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-warrior-two", "Warrior II", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1.5, symbol: "lungesSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-tree-pose", "Tree Pose", .yoga, [],
              difficulty: 1, kcal: 1.5, symbol: "treePoseSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-cobra-pose", "Cobra Pose", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1.5, symbol: "cobraPoseSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-bridge-pose", "Bridge Pose", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1.5, symbol: "gluteBridgeSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-pigeon-pose", "Pigeon Pose", .yoga, [.exerciseMat],
              difficulty: 2, kcal: 1, symbol: "pigeonPoseSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-childs-pose", "Child's Pose", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1, symbol: "childsPoseSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-seated-forward-bend", "Seated Forward Bend", .yoga, [.exerciseMat],
              difficulty: 1, kcal: 1.5, symbol: "seatedForwardBendSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),

        // MARK: Mobility & stretching
        // The Mobility/Flexibility browse filter had no exercises at all before
        // these — it was an empty category shipped in the UI.
        .make("seed-exercise-worlds-greatest-stretch", "World's Greatest Stretch", .mobilityFlexibility, [.exerciseMat],
              difficulty: 2, kcal: 2, symbol: "lungesSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-hip-flexor-stretch", "Hip Flexor Stretch", .mobilityFlexibility, [.exerciseMat],
              difficulty: 1, kcal: 1, symbol: "lungesSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-hamstring-stretch", "Hamstring Stretch", .mobilityFlexibility, [.exerciseMat],
              difficulty: 1, kcal: 1, symbol: "seatedForwardBendSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-quad-stretch", "Standing Quad Stretch", .mobilityFlexibility, [],
              difficulty: 1, kcal: 1, symbol: "figure.yoga", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-hip-ninety-ninety", "90/90 Hip Switch", .mobilityFlexibility, [.exerciseMat],
              difficulty: 2, kcal: 2, symbol: "hip9090Symbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-thoracic-rotation", "Thoracic Rotation", .mobilityFlexibility, [.exerciseMat],
              difficulty: 1, kcal: 1, symbol: "russianTwistsSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-shoulder-dislocates", "Shoulder Dislocates", .mobilityFlexibility, [.resistanceBands],
              difficulty: 1, kcal: 1, symbol: "figure.cooldown", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-couch-stretch", "Couch Stretch", .mobilityFlexibility, [.exerciseMat],
              difficulty: 2, kcal: 1, symbol: "lungesSymbol", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-foam-roll-back", "Foam Roll Upper Back", .mobilityFlexibility, [.foamRoller],
              difficulty: 1, kcal: 1, symbol: "figure.rolling", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility),
        .make("seed-exercise-foam-roll-quads", "Foam Roll Quads", .mobilityFlexibility, [.foamRoller],
              difficulty: 1, kcal: 1, symbol: "figure.rolling", reps: 0,
              bucket: .mobility, pattern: .mobility, role: .mobility)
    ]

    /// Lookup by stable seed id.
    static let byID: [String: GymExerciseDefinition] = Dictionary(
        all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Returns exercises matching the given muscle groups whose equipment requirements
    /// are entirely satisfied by `availableEquipment` (bodyweight exercises are always available).
    static func exercises(forMuscleGroups muscleGroups: [Int],
                          availableEquipment: Set<Int>) -> [GymExerciseDefinition] {
        let muscleSet = Set(muscleGroups)
        return all.filter { def in
            guard muscleSet.contains(def.muscleGroup) else { return false }
            if def.equipment.isEmpty { return true }
            return def.equipment.allSatisfy { availableEquipment.contains($0) }
        }
    }

    /// The pool for a push/pull/legs-style split. Unlike
    /// `exercises(forMuscleGroups:availableEquipment:)` — which answers the
    /// *browse* question, "show me everything filed under Arms" — this answers
    /// the *programming* question, "what belongs on this day". They differ
    /// exactly where `bucket` and `muscleGroup` disagree: a tricep pushdown is
    /// in the Arms pool but not in the pull-day pool.
    static func exercises(for split: GymSplit,
                          availableEquipment: Set<Int>) -> [GymExerciseDefinition] {
        let buckets = Set(split.trainingBuckets)
        return exercises(forMuscleGroups: split.targetedMuscleGroups,
                         availableEquipment: availableEquipment)
            .filter { buckets.contains($0.bucket) }
    }

    /// Shared exercise-selection algorithm used by the live "For You" generator.
    ///
    /// Session quality, not just coverage: it fills the heavy slots first (a
    /// session has to *start* with a compound while you're fresh), never takes
    /// two lifts of the same `MovementPattern`, and only then spreads the
    /// remaining slots across `targetGroups`. The old version picked one
    /// exercise per muscle group sorted by difficulty and topped up with
    /// whatever was easiest, which is how "Push day" came out as five curls and
    /// a shrug.
    ///
    /// `rotationSeed` varies the pick within each slot — date-derived for live
    /// generation, fixed for anything that has to be reproducible.
    static func select(from pool: [GymExerciseDefinition],
                       targetGroups: [Int],
                       count: Int,
                       maxDifficulty: Int,
                       rotationSeed: Int) -> [GymExerciseDefinition] {
        guard count > 0, !pool.isEmpty else { return [] }

        // Difficulty is a preference, not a hard filter: dropping every lift
        // above the cap is what used to leave beginners with nothing but
        // machine isolation work. Fall back to the full pool per slot instead.
        func candidates(_ source: [GymExerciseDefinition]) -> [GymExerciseDefinition] {
            let eligible = source.filter { $0.difficultyInt <= maxDifficulty }
            return eligible.isEmpty ? source : eligible
        }

        var picked: [GymExerciseDefinition] = []
        var usedPatterns: Set<String> = []
        var usedGroups: [Int: Int] = [:]

        func take(_ def: GymExerciseDefinition) {
            picked.append(def)
            usedPatterns.insert(String(describing: def.pattern))
            usedGroups[def.muscleGroup, default: 0] += 1
        }

        func pick(where predicate: (GymExerciseDefinition) -> Bool) -> Bool {
            let available = candidates(pool.filter { def in
                !picked.contains(where: { $0.id == def.id })
                    && !usedPatterns.contains(String(describing: def.pattern))
                    && predicate(def)
            })
            guard !available.isEmpty else { return false }
            // Sort for determinism, then rotate so repeated generations vary.
            let sorted = available.sorted { $0.id < $1.id }
            take(sorted[abs(rotationSeed &+ picked.count) % sorted.count])
            return true
        }

        // 1. Anchor the session with compounds — at least one, up to half the slots.
        let compoundSlots = max(1, min(count / 2 + 1, 3))
        for _ in 0..<compoundSlots {
            if picked.count >= count { break }
            _ = pick { $0.role <= .secondary }
        }

        // 2. Cover every targeted muscle group that isn't represented yet.
        for group in targetGroups {
            if picked.count >= count { break }
            guard usedGroups[group] == nil else { continue }
            _ = pick { $0.muscleGroup == group }
        }

        // 3. Fill what's left, preferring the least-trained group — but
        //    weighted by the split's own priority order, so a leg day (legs
        //    first, core second) finishes four-and-two rather than three-and-
        //    three. Without the weighting, strict round-robin gives a secondary
        //    group as many slots as the one the session is named after.
        while picked.count < count {
            let byNeed = targetGroups.enumerated().sorted { lhs, rhs in
                let lhsScore = Double(usedGroups[lhs.element] ?? 0) * Double(lhs.offset + 1)
                let rhsScore = Double(usedGroups[rhs.element] ?? 0) * Double(rhs.offset + 1)
                return lhsScore == rhsScore ? lhs.offset < rhs.offset : lhsScore < rhsScore
            }
            if byNeed.contains(where: { entry in pick(where: { $0.muscleGroup == entry.element }) }) { continue }
            if pick(where: { _ in true }) { continue }
            break
        }

        // 4. Heavy work first, isolation last — the order you'd actually train in.
        return picked.enumerated()
            .sorted { ($0.element.role.rawValue, $0.offset) < ($1.element.role.rawValue, $1.offset) }
            .map(\.element)
    }
}

// MARK: - Preset catalog templates

/// A template a preset catalog workout is generated from. Each pairs with a
/// `CatalogTier` to produce one workout's exercise selection, duration and
/// difficulty.
///
/// Unlike the live "For You" generator, preset content is **hand-authored**
/// (see `CatalogSessionBlueprints`) rather than algorithmically selected. A
/// selection algorithm can guarantee coverage, but it can't guarantee that a
/// session is worth doing — the previous algorithmic catalog produced a "Pull —
/// Beginner" of Superman, Hammer Curls and Bicep Curl, with no pulling
/// movement in it at all.
enum CatalogTemplate: String, CaseIterable {
    case push, pull, leg
    case fullBodyA, fullBodyB
    case upper
    case bodyweightCircuit, core, cardioHIIT

    /// Fixed English text used to build the workout's localization-key name.
    /// Must never change once shipped — it's the literal catalog key.
    var nameKeyComponent: String {
        switch self {
        case .push:               return "Push"
        case .pull:               return "Pull"
        case .leg:                return "Legs"
        case .fullBodyA:          return "Full Body A"
        case .fullBodyB:          return "Full Body B"
        case .upper:              return "Upper Body"
        case .bodyweightCircuit:  return "Bodyweight Circuit"
        case .core:               return "Core"
        case .cardioHIIT:         return "Cardio & HIIT"
        }
    }

    /// Reuses `GymSplit`'s existing localized names for push/pull/leg (same
    /// concept, same translations); the others get their own keys.
    var displayName: String {
        switch self {
        case .push:               return GymSplit.push.displayName
        case .pull:               return GymSplit.pull.displayName
        case .leg:                return GymSplit.leg.displayName
        case .fullBodyA:          return NSLocalizedString("Full Body A", comment: "Catalog template display name")
        case .fullBodyB:          return NSLocalizedString("Full Body B", comment: "Catalog template display name")
        case .upper:              return NSLocalizedString("Upper Body", comment: "Catalog template display name")
        case .bodyweightCircuit:  return NSLocalizedString("Bodyweight Circuit", comment: "Catalog template display name")
        case .core:               return NSLocalizedString("Core", comment: "Catalog template display name")
        case .cardioHIIT:         return NSLocalizedString("Cardio & HIIT", comment: "Catalog template display name")
        }
    }

    /// `Workout.muscleGroup` tag for the generated workout — the browse
    /// taxonomy `MuscleGroupsView`/`WorkoutsByMuscleGroup`/`PlansView` filter on.
    var primaryMuscleGroup: Int {
        switch self {
        case .push:               return WorkoutCategory.chest.rawValue
        case .pull:               return WorkoutCategory.back.rawValue
        case .leg:                return WorkoutCategory.legs.rawValue
        case .fullBodyA,
             .fullBodyB:          return WorkoutCategory.fullbody.rawValue
        case .upper:              return WorkoutCategory.upperbody.rawValue
        case .bodyweightCircuit:  return WorkoutCategory.fullbody.rawValue
        case .core:               return WorkoutCategory.core.rawValue
        case .cardioHIIT:         return WorkoutCategory.cardio.rawValue
        }
    }

    /// True for the templates whose sessions use nothing a user wouldn't have
    /// at home — asserted against the blueprints in the test suite.
    var requiresBodyweightOnly: Bool {
        switch self {
        case .bodyweightCircuit, .core, .cardioHIIT: return true
        default: return false
        }
    }

    /// Equipment treated as "always available" for bodyweight-style templates —
    /// a mat or jump rope are near-universal, unlike gym machines/free weights.
    static let bodyweightFriendlyEquipment: Set<Int> = [Equipment.exerciseMat.rawValue,
                                                        Equipment.jumpRope.rawValue]

    var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .push, .pull, .leg, .fullBodyA, .fullBodyB, .upper:
            return .traditionalStrengthTraining
        case .bodyweightCircuit, .core:
            return .functionalStrengthTraining
        case .cardioHIIT:
            return .highIntensityIntervalTraining
        }
    }

    /// Minutes budgeted per working set, including the rest that follows it.
    /// Strength work with heavy compounds genuinely needs ~2.5 min a set; a
    /// bodyweight circuit moves far faster. The old flat `exercises × 6` put a
    /// six-exercise barbell session at 36 minutes, which nobody has ever hit.
    var minutesPerSet: Double {
        switch self {
        case .push, .pull, .leg, .fullBodyA, .fullBodyB, .upper: return 2.5
        case .bodyweightCircuit:                                 return 1.5
        case .core:                                              return 1.2
        case .cardioHIIT:                                        return 1.2
        }
    }

    /// Short, fixed English focus phrase used to build each tier's `infoText`.
    var infoTextFocusPhrase: String {
        switch self {
        case .push:               return "push session targeting chest, shoulders and triceps"
        case .pull:               return "pull session targeting back and biceps"
        case .leg:                return "leg session built around squatting and hinging"
        case .fullBodyA:          return "full-body session built around a squat, a press and a pull"
        case .fullBodyB:          return "full-body session built around a hinge, a press and a pull"
        case .upper:              return "upper-body session covering chest, back, shoulders and arms"
        case .bodyweightCircuit:  return "full-body bodyweight circuit using no equipment"
        case .core:               return "core session using no equipment"
        case .cardioHIIT:         return "cardio and HIIT session using no equipment (a jump rope helps)"
        }
    }
}

/// Difficulty-based tier for the strength/bodyweight/cardio templates.
enum CatalogTier: Int, CaseIterable {
    case beginner = 1, intermediate = 2, advanced = 3

    var nameKeyComponent: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }
    var displayName: String { NSLocalizedString(nameKeyComponent, comment: "Catalog tier display name") }

    /// Working sets per exercise. Two sets (the previous beginner value) is
    /// below the volume threshold anything adapts to; three is the usual floor.
    var setLength: Double {
        switch self {
        case .beginner:     return 3
        case .intermediate: return 4
        case .advanced:     return 4
        }
    }
    /// The hardest movement this tier may program. Deliberately not
    /// `rawValue`: a dumbbell bench press is rated 2 for technical demand and
    /// is still squarely a beginner lift, so a ceiling of 1 would leave the
    /// beginner tiers with nothing but machine isolation work — which is
    /// exactly what the old algorithmic catalog produced. What a beginner must
    /// not meet is a *3*: deadlifts, pull-ups, pistol squats.
    var maxDifficulty: Int { self == .beginner ? 2 : 3 }
    var difficultyInt: Int { rawValue }
    /// Fixed, non-date-based rotation so anything algorithmic stays reproducible
    /// across devices/relaunches instead of varying by day like live generation.
    var rotationSeed: Int { rawValue }
}

/// Tier for the yoga/mobility templates. These are duration- and
/// purpose-tiered rather than difficulty-tiered: a deep stretch isn't a "hard"
/// version of a yoga flow, it's a different session.
enum YogaMobilityTier: CaseIterable {
    case short, full, mobility

    /// Stable component of the workout's seed id — never change it.
    var nameKeyComponent: String {
        switch self {
        case .short:    return "Short"
        case .full:     return "Full"
        case .mobility: return "Mobility"
        }
    }
    /// Full localization key for the generated workout's title. These tiers
    /// have no separate short display name — "Mobility" alone would collide
    /// with the existing `mobility` string key, and the full title is what
    /// every surface shows anyway.
    var nameKey: String {
        switch self {
        case .short:    return "Yoga Flow — Short"
        case .full:     return "Yoga Flow — Full"
        case .mobility: return "Mobility & Stretching"
        }
    }

    var infoTextKey: String {
        switch self {
        case .short:
            return "A short yoga flow to loosen up — good before bed or on a rest day."
        case .full:
            return "A full yoga flow through the major poses, for flexibility, balance and calm."
        case .mobility:
            return "A targeted mobility and stretching routine for hips, hamstrings and the upper back."
        }
    }

    var shortInfo: String {
        switch self {
        case .short:    return "A short yoga flow."
        case .full:     return "A full yoga flow."
        case .mobility: return "Mobility work and stretching."
        }
    }

    var muscleGroup: Int {
        switch self {
        case .short, .full: return WorkoutCategory.yoga.rawValue
        case .mobility:     return WorkoutCategory.mobilityFlexibility.rawValue
        }
    }

    /// How long each pose/stretch is held, in minutes — drives the duration.
    var minutesPerPose: Double { self == .mobility ? 1.5 : 2 }
}

// MARK: - Preset session blueprints

/// The hand-authored exercise sequence behind every preset workout.
///
/// Each entry is an ordered list of catalog ids, written the way the session
/// should actually be trained: the heaviest compound first, accessories in the
/// middle, isolation and core work at the end. Every one of them follows the
/// same rules a coach would apply — one anchor compound per session, a press
/// balanced by a pull, no two lifts hitting the same pattern, and nothing
/// above the tier's technical level.
///
/// Ids are validated against `GymExerciseCatalog` by the test suite, so a typo
/// or a removed movement fails the build rather than silently shipping a
/// three-exercise workout.
enum CatalogSessionBlueprints {

    static func exerciseIDs(for template: CatalogTemplate, tier: CatalogTier) -> [String] {
        switch (template, tier) {

        // MARK: Push — chest, shoulders, triceps
        case (.push, .beginner):
            return ["seed-exercise-dumbbell-bench-press",
                    "seed-exercise-machine-shoulder-press",
                    "seed-exercise-pec-deck",
                    "seed-exercise-tricep-pushdown"]
        case (.push, .intermediate):
            return ["seed-exercise-bench-press",
                    "seed-exercise-overhead-press",
                    "seed-exercise-incline-dumbbell-press",
                    "seed-exercise-lateral-raise",
                    "seed-exercise-tricep-pushdown"]
        case (.push, .advanced):
            return ["seed-exercise-bench-press",
                    "seed-exercise-overhead-press",
                    "seed-exercise-incline-bench-press",
                    "seed-exercise-dips",
                    "seed-exercise-lateral-raise",
                    "seed-exercise-skullcrushers"]

        // MARK: Pull — back, rear delts, biceps
        case (.pull, .beginner):
            return ["seed-exercise-lat-pulldown",
                    "seed-exercise-seated-cable-row",
                    "seed-exercise-face-pull",
                    "seed-exercise-bicep-curl"]
        case (.pull, .intermediate):
            return ["seed-exercise-barbell-row",
                    "seed-exercise-lat-pulldown",
                    "seed-exercise-face-pull",
                    "seed-exercise-shrugs",
                    "seed-exercise-hammer-curls"]
        case (.pull, .advanced):
            return ["seed-exercise-deadlifts",
                    "seed-exercise-pull-ups",
                    "seed-exercise-barbell-row",
                    "seed-exercise-seated-cable-row",
                    "seed-exercise-face-pull",
                    "seed-exercise-barbell-curl"]

        // MARK: Legs — squat, hinge, single leg, calves
        case (.leg, .beginner):
            return ["seed-exercise-leg-press",
                    "seed-exercise-romanian-deadlift",
                    "seed-exercise-leg-extension",
                    "seed-exercise-leg-curl",
                    "seed-exercise-calf-raise"]
        case (.leg, .intermediate):
            return ["seed-exercise-back-squat",
                    "seed-exercise-romanian-deadlift",
                    "seed-exercise-leg-press",
                    "seed-exercise-leg-curl",
                    "seed-exercise-seated-calf-raise"]
        case (.leg, .advanced):
            return ["seed-exercise-back-squat",
                    "seed-exercise-romanian-deadlift",
                    "seed-exercise-bulgarian-split-squat",
                    "seed-exercise-leg-extension",
                    "seed-exercise-leg-curl",
                    "seed-exercise-seated-calf-raise"]

        // MARK: Full Body A — squat-led
        case (.fullBodyA, .beginner):
            return ["seed-exercise-goblet-squat",
                    "seed-exercise-dumbbell-bench-press",
                    "seed-exercise-lat-pulldown",
                    "seed-exercise-plank"]
        case (.fullBodyA, .intermediate):
            return ["seed-exercise-back-squat",
                    "seed-exercise-bench-press",
                    "seed-exercise-barbell-row",
                    "seed-exercise-shoulder-press",
                    "seed-exercise-plank"]
        case (.fullBodyA, .advanced):
            return ["seed-exercise-back-squat",
                    "seed-exercise-bench-press",
                    "seed-exercise-pull-ups",
                    "seed-exercise-overhead-press",
                    "seed-exercise-romanian-deadlift",
                    "seed-exercise-hanging-leg-raise"]

        // MARK: Full Body B — hinge-led, so A and B don't repeat each other
        case (.fullBodyB, .beginner):
            return ["seed-exercise-leg-press",
                    "seed-exercise-machine-shoulder-press",
                    "seed-exercise-seated-cable-row",
                    "seed-exercise-dead-bug"]
        case (.fullBodyB, .intermediate):
            return ["seed-exercise-romanian-deadlift",
                    "seed-exercise-incline-dumbbell-press",
                    "seed-exercise-lat-pulldown",
                    "seed-exercise-walking-lunge",
                    "seed-exercise-cable-crunch"]
        case (.fullBodyB, .advanced):
            return ["seed-exercise-deadlifts",
                    "seed-exercise-incline-bench-press",
                    "seed-exercise-chin-ups",
                    "seed-exercise-bulgarian-split-squat",
                    "seed-exercise-lateral-raise",
                    "seed-exercise-ab-wheel-rollout"]

        // MARK: Upper body — the Upper half of an upper/lower split
        case (.upper, .beginner):
            return ["seed-exercise-dumbbell-bench-press",
                    "seed-exercise-lat-pulldown",
                    "seed-exercise-machine-shoulder-press",
                    "seed-exercise-seated-cable-row",
                    "seed-exercise-bicep-curl"]
        case (.upper, .intermediate):
            return ["seed-exercise-bench-press",
                    "seed-exercise-barbell-row",
                    "seed-exercise-overhead-press",
                    "seed-exercise-lat-pulldown",
                    "seed-exercise-lateral-raise",
                    "seed-exercise-hammer-curls"]
        case (.upper, .advanced):
            return ["seed-exercise-bench-press",
                    "seed-exercise-pull-ups",
                    "seed-exercise-overhead-press",
                    "seed-exercise-barbell-row",
                    "seed-exercise-face-pull",
                    "seed-exercise-barbell-curl",
                    "seed-exercise-skullcrushers"]

        // MARK: Bodyweight circuit — nothing but a floor
        case (.bodyweightCircuit, .beginner):
            return ["seed-exercise-squats",
                    "seed-exercise-pushups",
                    "seed-exercise-glute-bridge",
                    "seed-exercise-plank"]
        case (.bodyweightCircuit, .intermediate):
            return ["seed-exercise-squats",
                    "seed-exercise-pushups",
                    "seed-exercise-lunges",
                    "seed-exercise-superman",
                    "seed-exercise-side-plank"]
        case (.bodyweightCircuit, .advanced):
            return ["seed-exercise-dips",
                    "seed-exercise-diamond-push-up",
                    "seed-exercise-pistol-squat",
                    "seed-exercise-lunges",
                    "seed-exercise-hollow-body-hold",
                    "seed-exercise-v-ups"]

        // MARK: Core — braced work first, flexion after
        case (.core, .beginner):
            return ["seed-exercise-dead-bug",
                    "seed-exercise-plank",
                    "seed-exercise-side-plank",
                    "seed-exercise-crunch"]
        case (.core, .intermediate):
            return ["seed-exercise-plank",
                    "seed-exercise-side-plank",
                    "seed-exercise-bicycle-crunches",
                    "seed-exercise-reverse-crunch",
                    "seed-exercise-flutter-kicks"]
        case (.core, .advanced):
            return ["seed-exercise-hollow-body-hold",
                    "seed-exercise-ab-wheel-rollout",
                    "seed-exercise-side-plank",
                    "seed-exercise-v-ups",
                    "seed-exercise-russian-twists",
                    "seed-exercise-flutter-kicks"]

        // MARK: Cardio & HIIT — easiest movements first as a warm-up
        case (.cardioHIIT, .beginner):
            return ["seed-exercise-jumping-jacks",
                    "seed-exercise-high-knees",
                    "seed-exercise-butt-kicks",
                    "seed-exercise-mountain-climbers"]
        case (.cardioHIIT, .intermediate):
            return ["seed-exercise-jump-rope",
                    "seed-exercise-high-knees",
                    "seed-exercise-squat-jumps",
                    "seed-exercise-mountain-climbers",
                    "seed-exercise-skater-jumps"]
        case (.cardioHIIT, .advanced):
            return ["seed-exercise-jump-rope",
                    "seed-exercise-squat-jumps",
                    "seed-exercise-skater-jumps",
                    "seed-exercise-mountain-climbers",
                    "seed-exercise-burpees-with-pushups",
                    "seed-exercise-sprint"]
        }
    }

    static func exerciseIDs(for tier: YogaMobilityTier) -> [String] {
        switch tier {
        case .short:
            // Opens by mobilising the spine, ends seated — a real flow order.
            return ["seed-exercise-cat-cow",
                    "seed-exercise-downward-facing-dog",
                    "seed-exercise-cobra-pose",
                    "seed-exercise-childs-pose",
                    "seed-exercise-seated-forward-bend"]
        case .full:
            return ["seed-exercise-sun-salutation",
                    "seed-exercise-cat-cow",
                    "seed-exercise-downward-facing-dog",
                    "seed-exercise-warrior-two",
                    "seed-exercise-tree-pose",
                    "seed-exercise-cobra-pose",
                    "seed-exercise-bridge-pose",
                    "seed-exercise-pigeon-pose",
                    "seed-exercise-childs-pose",
                    "seed-exercise-seated-forward-bend"]
        case .mobility:
            // Soft tissue first, then the joints, then static stretching.
            return ["seed-exercise-foam-roll-back",
                    "seed-exercise-foam-roll-quads",
                    "seed-exercise-cat-cow",
                    "seed-exercise-thoracic-rotation",
                    "seed-exercise-worlds-greatest-stretch",
                    "seed-exercise-hip-ninety-ninety",
                    "seed-exercise-hip-flexor-stretch",
                    "seed-exercise-hamstring-stretch"]
        }
    }
}

// MARK: - Preset catalog builder

/// The blueprint a preset-catalog builder produces for one `(template, tier)`
/// pair. Mirrors `PersonalizedWorkoutPlan` but has no per-user recovery/history
/// dependency — preset content is fixed, not live user state.
struct CatalogWorkoutPlan {
    let nameKey: String
    let infoTextKey: String
    let shortInfo: String
    let exercises: [GymExerciseDefinition]
    let setLength: Double
    let straightSets: Bool
    let durationMinutes: Int
    let difficultyInt: Int
    let muscleGroup: Int
    let workoutActivityType: HKWorkoutActivityType
    let workoutSessionLocation: HKWorkoutSessionLocationType
}

enum CatalogWorkoutBuilder {

    /// Builds the workout for `template` at `tier` from its hand-authored
    /// blueprint. Deterministic by construction.
    static func strengthPlan(template: CatalogTemplate, tier: CatalogTier) -> CatalogWorkoutPlan? {
        let ids = CatalogSessionBlueprints.exerciseIDs(for: template, tier: tier)
        let picked = ids.compactMap { GymExerciseCatalog.byID[$0] }
        guard picked.count == ids.count, picked.count >= 3 else { return nil }

        let duration = durationMinutes(exerciseCount: picked.count,
                                       sets: tier.setLength,
                                       minutesPerSet: template.minutesPerSet)
        let nameKey = "\(template.nameKeyComponent) — \(tier.nameKeyComponent)"
        let infoTextKey = "\(tier.nameKeyComponent)-level \(template.infoTextFocusPhrase). "
            + "\(picked.count) exercises, about \(duration) min."

        return CatalogWorkoutPlan(
            nameKey: nameKey,
            infoTextKey: infoTextKey,
            shortInfo: "\(template.nameKeyComponent) · \(tier.nameKeyComponent)",
            exercises: picked,
            setLength: tier.setLength,
            // Circuit the conditioning work, straight sets for everything else —
            // you don't superset a heavy squat.
            straightSets: template != .cardioHIIT && template != .bodyweightCircuit,
            durationMinutes: duration,
            difficultyInt: tier.difficultyInt,
            muscleGroup: template.primaryMuscleGroup,
            workoutActivityType: template.workoutActivityType,
            workoutSessionLocation: .indoor)
    }

    /// Builds a yoga/mobility workout at `tier` from its hand-authored flow.
    static func yogaPlan(tier: YogaMobilityTier) -> CatalogWorkoutPlan? {
        let ids = CatalogSessionBlueprints.exerciseIDs(for: tier)
        let picked = ids.compactMap { GymExerciseCatalog.byID[$0] }
        guard picked.count == ids.count, picked.count >= 3 else { return nil }

        let duration = Int((Double(picked.count) * tier.minutesPerPose).rounded())

        return CatalogWorkoutPlan(
            nameKey: tier.nameKey,
            infoTextKey: tier.infoTextKey,
            shortInfo: tier.shortInfo,
            exercises: picked,
            setLength: 1,
            straightSets: true,
            durationMinutes: duration,
            difficultyInt: 1,
            muscleGroup: tier.muscleGroup,
            workoutActivityType: tier == .mobility ? .flexibility : .yoga,
            workoutSessionLocation: .indoor)
    }

    /// Session length in minutes, rounded to the nearest 5 so the catalog reads
    /// like a plan rather than a stopwatch reading.
    private static func durationMinutes(exerciseCount: Int, sets: Double, minutesPerSet: Double) -> Int {
        let raw = Double(exerciseCount) * sets * minutesPerSet
        return max(15, Int((raw / 5).rounded()) * 5)
    }
}

extension CatalogWorkoutPlan {
    /// Materializes this blueprint into a ready-to-insert `Workout`. Mirrors
    /// `PersonalizedWorkoutPlan.makeWorkout(in:existingExercises:name:)`.
    func makeWorkout(id: String, in context: ModelContext, existingExercises: [Exercise]) -> Workout {
        let entities: [Exercise] = exercises.map { $0.materialize(in: context, existing: existingExercises) }

        let workout = Workout(
            id: id,
            infoText: infoTextKey,
            isUserGenerated: false,
            isNew: false,
            muscleGroup: muscleGroup,
            setLength: setLength,
            straightSets: straightSets,
            difficultyInt: difficultyInt,
            name: nameKey,
            duration: durationMinutes,
            exercisesSequenceID: entities.map(\.id),
            finishedExercisesSequence: [],
            exercises: entities,
            plan: [],
            workoutActivityType: Int(workoutActivityType.rawValue),
            workoutSessionLocation: Int(workoutSessionLocation.rawValue))
        workout.shortInfo = shortInfo
        return workout
    }
}
