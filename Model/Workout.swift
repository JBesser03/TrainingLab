//
//  Workout.swift
//  Workout App
//
//  Created by Justus Besser on 28.02.24.
//
//

import Foundation
import SwiftData
import HealthKit

@Model public class Workout {
    public var id: String = UUID().uuidString
    /// When the workout was created, in seconds since 1970 (see `createdAt`).
    /// The name is historical: it was an unused field already in the CloudKit
    /// schema, so storing the date here needs no schema deploy.
    var index: Double? = 0.0
    var infoText: String = ""
    var isUserGenerated: Bool = false
    var isNew: Bool = true
    var isSaved: Bool = false
    /// Retires a preset workout from discovery surfaces (Browse, For You,
    /// muscle-group lists, search) without deleting it, so existing custom-plan
    /// membership and `isSaved` bookmarks keep resolving. Defaulted so it's
    /// CloudKit-migration-safe (additive schema change). Never filter on this
    /// outside a discovery query — detail/active-workout views must ignore it.
    var isHidden: Bool = false
    var muscleGroup: Int = 100
    var setLength: Double = 3 //1...8
    /// Rest between rounds/exercises in seconds. Only used by cardio/HIIT
    /// (circuit) workouts — strength/straight-set workouts never rest. Defaulted
    /// so it's CloudKit-migration-safe (additive schema change).
    var restSeconds: Int = 30
    /// Deprecated: no longer used. The active-workout engine derives straight-set
    /// vs circuit behavior from the workout category (cardio/HIIT = circuit,
    /// everything else = straight sets). Retained because the field already exists
    /// in the CloudKit schema (which is additive-only).
    var straightSets: Bool = false
    var shortInfo: String = ""
    var workoutActivityType: Int = Int(HKWorkoutActivityType.other.rawValue)
    /// Unused — see `displayDifficulty`. Kept as a stored property because
    /// removing it from this `@Model` would be a CloudKit schema migration.
    var difficulty: String = ""
    var difficultyInt: Int = 2
    var duration: Int = 10 //in minutes
    var name: String = ""
    var workoutSessionLocation: Int = HKWorkoutSessionLocationType.unknown.rawValue
    /// The difficulty (1…5) `WorkoutDifficultyPredictor` showed for this
    /// session when it was generated, carried onto the `FinishedWorkout` so it
    /// can be compared with how hard it actually felt. Optional, so it's
    /// CloudKit-migration-safe (additive schema change).
    var predictedDifficulty: Double?

    /// When the workout was created; nil for workouts from before 1.2, whose
    /// `index` still holds its old value (0, or 1 from a removed view).
    var createdAt: Date? {
        guard let index, index > 1 else { return nil }
        return Date(timeIntervalSince1970: index)
    }

    /// Newest first; workouts without a creation date keep a stable
    /// alphabetical order behind the dated ones.
    static func newestFirst(_ lhs: Workout, _ rhs: Workout) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// User-facing, localized workout title.
    /// `name` stores a localization key for seeded workouts (e.g. "StarterWorkout")
    /// or the raw text for user-generated ones. `NSLocalizedString` returns the input
    /// unchanged when it isn't a catalog key, so this is safe for both cases.
    /// A built-in "Push — Advanced" shows as "Push": its level is shown on
    /// its own (`displayDifficulty`). See `CatalogName`.
    var displayName: String {
        let shown = isUserGenerated ? name : CatalogName.withoutLevel(name) ?? name
        return NSLocalizedString(shown, comment: "Workout name")
    }

    /// User-facing, localized workout description. See `displayName`.
    var displayInfoText: String { NSLocalizedString(infoText, comment: "Workout description") }

    /// User-facing, localized subtitle. Catalog tiers store "Template · Tier"
    /// (see `CatalogWorkoutBuilder`), so each component is localized on its own
    /// and reuses the existing template/tier translations.
    var displayShortInfo: String {
        shortInfo
            .components(separatedBy: " · ")
            .map { NSLocalizedString($0, comment: "Workout short info") }
            .joined(separator: " · ")
    }

    /// User-facing, localized difficulty, derived from `difficultyInt`.
    ///
    /// Use this, never the stored `difficulty` string: no initializer accepts
    /// that property and nothing ever assigns it, so it is always "" and every
    /// view that rendered it showed a blank label.
    var displayDifficulty: String { DifficultyLevel.name(for: difficultyInt) }
    
    // Handle exercisesSequenceID manually
    @Attribute
    private var exercisesSequenceIDData: Data = Data()
    
    var exercisesSequenceID: [String] {
        get {
            guard !exercisesSequenceIDData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String].self, from: exercisesSequenceIDData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                exercisesSequenceIDData = encoded
            } else {
                exercisesSequenceIDData = Data()
            }
        }
    }
    
    // Handle finishedExercisesSequence manually
    @Attribute
    private var finishedExercisesSequenceData: Data = Data()
    
    var finishedExercisesSequence: [String] {
        get {
            guard !finishedExercisesSequenceData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String].self, from: finishedExercisesSequenceData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                finishedExercisesSequenceData = encoded
            } else {
                finishedExercisesSequenceData = Data()
            }
        }
    }
    
    /// Per-exercise sets, reps, target weight and superset grouping, keyed by
    /// exercise id — so 5×5 squats and 3×12 curls can share a workout. An
    /// exercise without an entry uses the workout's `setLength` and its own
    /// `repCount`/`targetWeightKg` (see `plan(for:)`), which is how every
    /// workout from before per-exercise plans keeps behaving. Data-backed
    /// like `exercisesSequenceID`, so it's CloudKit-safe.
    @Attribute
    private var exercisePlansData: Data = Data()

    var exercisePlans: [String: ExercisePlan] {
        get {
            guard !exercisePlansData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: ExercisePlan].self, from: exercisePlansData)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                exercisePlansData = encoded
            } else {
                exercisePlansData = Data()
            }
        }
    }

    /// The plan for `exercise` in this workout, with the pre-plan fallbacks.
    func plan(for exercise: Exercise) -> ExercisePlan {
        exercisePlans[exercise.id] ?? ExercisePlan(sets: max(Int(setLength), 1),
                                                   reps: exercise.repCount,
                                                   targetWeightKg: exercise.targetWeightKg)
    }

    @Relationship(deleteRule: .noAction, inverse: \Exercise.workouts)
    var exercises: [Exercise]?
    
    @Relationship(deleteRule: .noAction)
    var plan: [Plan]?
    
    public init(id: String = UUID().uuidString, infoText: String, isUserGenerated: Bool, isNew: Bool = true, isSaved: Bool = false, muscleGroup: Int, setLength: Double, straightSets: Bool, difficultyInt: Int, name: String, duration: Int, exercisesSequenceID: [String], finishedExercisesSequence: [String], exercises: [Exercise] = [], plan: [Plan] = [], workoutActivityType: Int, workoutSessionLocation: Int) {
        self.id = id
        self.infoText = infoText
        self.isUserGenerated = isUserGenerated
        self.isNew = isNew
        self.isSaved = isSaved
        self.muscleGroup = muscleGroup
        self.setLength = setLength
        self.difficultyInt = difficultyInt
        self.name = name
        self.duration = duration
        self.exercisesSequenceID = exercisesSequenceID // This will trigger the setter
        self.finishedExercisesSequence = finishedExercisesSequence // This will trigger the setter
        self.exercises = exercises
        self.plan = plan
        self.straightSets = straightSets
        self.workoutActivityType = workoutActivityType
        self.workoutSessionLocation = workoutSessionLocation
        self.index = Date().timeIntervalSince1970
    }
}

/// The difficulty scale plans, workouts and exercises share (`difficultyInt`),
/// named with the same words as the catalog's workouts ("Push · Beginner").
enum DifficultyLevel: Int, CaseIterable, Identifiable {
    case beginner = 1, intermediate, advanced

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .beginner:     NSLocalizedString("Beginner", comment: "Difficulty level")
        case .intermediate: NSLocalizedString("Intermediate", comment: "Difficulty level")
        case .advanced:     NSLocalizedString("Advanced", comment: "Difficulty level")
        }
    }

    /// Any other stored value reads as intermediate.
    static func name(for difficultyInt: Int) -> String {
        (DifficultyLevel(rawValue: difficultyInt) ?? .intermediate).name
    }
}

/// How one exercise is done within a workout.
struct ExercisePlan: Codable, Hashable {
    var sets: Int
    /// `0` means time-based, like `Exercise.repCount`.
    var reps: Int
    var targetWeightKg: Double?
    /// Exercises sharing a group are a superset: their sets alternate.
    var supersetGroup: Int?
    /// How long a time-based exercise is held, in seconds; nil for the
    /// exercise's own length (`defaultHoldSeconds`).
    var seconds: Int?

    /// A time-based exercise's length when its plan doesn't set one: the
    /// exercise's own duration, else 45 s — a plank, not the workout-length
    /// slice a circuit uses.
    static func defaultHoldSeconds(for exercise: Exercise) -> Int {
        if let duration = exercise.duration, duration > 0 { return Int(duration) }
        return 45
    }

    /// "1:30" for a hold length.
    static func holdText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// The set count most plans in `plans` use — what `Workout.setLength`
    /// keeps holding for readers that predate per-exercise plans.
    static func commonSetCount(_ plans: [ExercisePlan], fallback: Int = 3) -> Int {
        let counts = Dictionary(grouping: plans.map(\.sets), by: { $0 }).mapValues(\.count)
        return counts.max { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }?.key ?? fallback
    }
}

/// Built-in workouts and plans store their level in their name — "Push —
/// Advanced", "Push Pull Legs — Beginner" — which the screens don't show, as
/// the level has a place of its own. The stored name stays: it's the catalog
/// key the deduplication (`deduplicateWorkouts`, `deduplicatePlans`) groups
/// by, also in released versions on a user's other devices, so three tiers
/// renamed to one "Push" would be merged into one there.
enum CatalogName {
    private static let levels = ["Beginner", "Intermediate", "Advanced"]

    /// "Push — Advanced" → "Push"; nil for a name without a level.
    static func withoutLevel(_ name: String) -> String? {
        for level in levels where name.hasSuffix(" — " + level) {
            return String(name.dropLast(level.count + 3))
        }
        return nil
    }
}
