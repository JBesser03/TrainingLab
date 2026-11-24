//
//  WeeklyGoals.swift
//  Workout App (iOS)
//
//  Flexible weekly training-frequency goals per activity (e.g. "Running
//  ×2/week", "Gym ×2/week") — the For You surface for users who want a
//  recurring cadence rather than a fixed multi-week program. Progress is
//  derived live from `FinishedWorkout` history plus other apps' HealthKit
//  workouts for the current calendar week, not from a persisted queue, so any
//  goal can be satisfied in any order: doing "Gym" today when "Running" was
//  also open is just as valid.
//

import Foundation
import SwiftData
import HealthKit

// MARK: - Goal category

/// What a weekly goal counts: the built-in Gym bundle, one sport from the
/// catalog, or a user-named group of sports. Workouts are matched purely by
/// HealthKit activity type, so a group or a sport picked from "All sports"
/// counts exactly like the built-ins.
struct GoalCategory: Codable, Hashable, Identifiable {
    /// "gym", "running", "type.<activity type raw value>" or "group.<UUID>".
    var id: String
    /// Groups only; everything else is named after its activity type.
    var customName: String?
    /// `HKWorkoutActivityType` raw values that count toward the goal.
    var activityTypes: [Int]

    static let gym = GoalCategory(id: "gym", customName: nil, activityTypes: [
        Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
        Int(HKWorkoutActivityType.functionalStrengthTraining.rawValue),
        Int(HKWorkoutActivityType.highIntensityIntervalTraining.rawValue)
    ])
    static let running = GoalCategory(id: "running", customName: nil,
                                      activityTypes: [Int(HKWorkoutActivityType.running.rawValue)])

    /// One activity type. Running maps to the built-in, so picking it from the
    /// full list can't create a second running goal.
    static func sport(_ type: HKWorkoutActivityType) -> GoalCategory {
        if type == .running { return .running }
        return GoalCategory(id: "type.\(type.rawValue)", customName: nil, activityTypes: [Int(type.rawValue)])
    }

    var isGroup: Bool { id.hasPrefix("group.") }

    var displayName: String {
        if let customName { return customName }
        switch id {
        case Self.gym.id:     return NSLocalizedString("Gym", comment: "Weekly goal category")
        case Self.running.id: return NSLocalizedString("Running", comment: "Weekly goal category")
        default:              return primaryType.name
        }
    }

    /// A group shows the symbol of its first sport.
    var symbolName: String {
        id == Self.gym.id ? "dumbbell.fill" : primaryType.symbolName
    }

    var sportTypes: [HKWorkoutActivityType] {
        activityTypes.compactMap { HKWorkoutActivityType(rawValue: UInt($0)) }
    }

    private var primaryType: HKWorkoutActivityType { sportTypes.first ?? .other }

    /// The catalog sports a group is made of, in the order they were picked.
    var groupSports: [GoalCategory] {
        let types = Set(activityTypes)
        func position(_ sport: GoalCategory) -> Int {
            sport.activityTypes.first.flatMap { activityTypes.firstIndex(of: $0) } ?? .max
        }
        return Self.allSports
            .filter { Set($0.activityTypes).isSubset(of: types) }
            .sorted { position($0) < position($1) }
    }

    func matches(_ finished: FinishedWorkout) -> Bool {
        activityTypes.contains(finished.workoutType)
    }

    func matches(_ external: ExternalWorkout) -> Bool {
        activityTypes.contains(external.activityType)
    }

    // MARK: Catalog

    /// Offered first in the goal picker.
    static let featured: [GoalCategory] = [
        .gym, .running, .sport(.cycling), .sport(.swimming),
        .sport(.walking), .sport(.hiking), .sport(.yoga), .sport(.rowing)
    ]

    /// Every sport a goal can track, alphabetical in the current language.
    /// The two strength types are left out: both are named "Strength
    /// Training", and Gym already counts them.
    static var allSports: [GoalCategory] {
        let covered: Set<HKWorkoutActivityType> = [.other, .traditionalStrengthTraining, .functionalStrengthTraining]
        return ([.gym] + HKWorkoutActivityType.selectable.filter { !covered.contains($0) }.map(sport))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    // MARK: Coding

    /// Goals saved before any sport could be picked stored a bare "gym" or
    /// "running"; they decode to the built-ins.
    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            self = legacy == Self.running.id ? .running : .gym
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        activityTypes = try container.decode([Int].self, forKey: .activityTypes)
    }

    init(id: String, customName: String?, activityTypes: [Int]) {
        self.id = id
        self.customName = customName
        self.activityTypes = activityTypes
    }
}

/// A user-configured weekly frequency target for one activity.
struct WeeklyGoal: Codable, Equatable, Identifiable {
    var category: GoalCategory
    var targetPerWeek: Int
    var id: String { category.id }
}

/// Count of workouts matching `category` that end within the calendar week
/// containing `now` (respects the device's locale first-weekday): the app's
/// own `history`, plus `external` workouts other apps saved to HealthKit.
///
/// `calendar` is injectable so the reminder planner can share *exactly* this
/// week definition under test — if the two drifted apart, a reminder could
/// fire for a goal the UI already shows as met.
func completedThisWeek(_ category: GoalCategory,
                       history: [FinishedWorkout],
                       external: [ExternalWorkout] = [],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> Int {
    let progress = goalProgressThisWeek(category, history: history, external: external, now: now, calendar: calendar)
    return progress.own + progress.external
}

/// `completedThisWeek`, split into the app's own sessions and those only
/// other apps recorded — so the goal card can say where a count came from.
func goalProgressThisWeek(_ category: GoalCategory,
                          history: [FinishedWorkout],
                          external: [ExternalWorkout] = [],
                          now: Date = Date(),
                          calendar: Calendar = .current) -> (own: Int, external: Int) {
    guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return (0, 0) }
    let own = history.filter { category.matches($0) && week.contains($0.endDate) }.count
    // A session another app also recorded (e.g. the Workout app running
    // alongside) is one workout, not two.
    let others = ExternalWorkout.distinct(external.filter { category.matches($0) && week.contains($0.end) },
                                          from: history).count
    return (own, others)
}

/// Workouts other apps saved to HealthKit during the calendar week containing
/// `now` — what goals count besides the app's own history. Empty without
/// HealthKit read access.
func externalWorkoutsThisWeek(now: Date = Date(), calendar: Calendar = .current) async -> [ExternalWorkout] {
    guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
    return await RecoveryMetricsProvider().externalWorkouts(from: week.start, to: now)
}

// MARK: - Running session generator

/// The three staple running session types — rotated so back-to-back "next
/// run" suggestions vary instead of always being the same easy jog.
enum RunningSessionKind: Int, CaseIterable {
    case easy = 1, tempo = 2, intervals = 3

    var nameKey: String {
        switch self {
        case .easy:      return "Easy Run"
        case .tempo:     return "Tempo Run"
        case .intervals: return "Interval Run"
        }
    }

    var infoTextKey: String {
        switch self {
        case .easy:      return "A relaxed, conversational-pace run to build your aerobic base."
        case .tempo:     return "A sustained, comfortably-hard effort to build your lactate threshold."
        case .intervals: return "Short, hard efforts with recovery jogs between — builds speed and power."
        }
    }

    var difficultyInt: Int { rawValue }
    var baseDurationMinutes: Int {
        switch self {
        case .easy:      return 25
        case .tempo:     return 30
        case .intervals: return 28
        }
    }
}

struct RunningSessionPlan {
    let kind: RunningSessionKind
    let durationMinutes: Int
}

enum RunningSessionBuilder {
    /// Rotates easy → tempo → intervals based on how many runs already
    /// happened this week (so consecutive sessions vary), and scales
    /// duration to today's readiness — the same recovery-band shape the gym
    /// generator already uses (`PersonalizedWorkoutGenerator`), just applied
    /// to minutes instead of exercise count. Low readiness always forces an
    /// easy run regardless of rotation.
    static func nextSession(completedThisWeek: Int, recovery: RecoveryEstimate) -> RunningSessionPlan {
        let rotation: [RunningSessionKind] = [.easy, .tempo, .intervals]
        var kind = rotation[completedThisWeek % rotation.count]
        if recovery.band == .rest { kind = .easy }

        let multiplier: Double
        switch recovery.band {
        case .ready:    multiplier = 1.2
        case .moderate: multiplier = 1.0
        case .rest:     multiplier = 0.7
        }
        let duration = max(Int((Double(kind.baseDurationMinutes) * multiplier).rounded()), 15)
        return RunningSessionPlan(kind: kind, durationMinutes: duration)
    }
}

extension RunningSessionPlan {
    /// Materializes this blueprint into a ready-to-insert `Workout`. No
    /// exercise catalog involvement — running never has one, matching
    /// `RunningPlanGeneratorView`'s existing generated sessions.
    func makeWorkout(uniqueName: String) -> Workout {
        let workout = Workout(
            id: UUID().uuidString,
            infoText: kind.infoTextKey,
            isUserGenerated: true,
            isNew: false,
            muscleGroup: WorkoutCategory.cardio.rawValue,
            setLength: 1.0,
            straightSets: false,
            difficultyInt: kind.difficultyInt,
            name: uniqueName,
            duration: durationMinutes,
            exercisesSequenceID: [],
            finishedExercisesSequence: [],
            exercises: [],
            plan: [],
            workoutActivityType: Int(HKWorkoutActivityType.running.rawValue),
            workoutSessionLocation: Int(HKWorkoutSessionLocationType.outdoor.rawValue))
        workout.shortInfo = NSLocalizedString(kind.nameKey, comment: "Running session kind")
        return workout
    }
}

// MARK: - Session for any other goal sport

/// A plain session for an open goal that has no generator of its own
/// (swimming, cycling, tennis, a group's sport…): no exercises, so the active
/// workout is a timer that's finished by hand — the same flow a run uses.
enum GoalSessionBuilder {

    static let durationMinutes = 30

    static func makeWorkout(type: HKWorkoutActivityType, uniqueName: String) -> Workout {
        let workout = Workout(
            id: UUID().uuidString,
            infoText: "",
            isUserGenerated: true,
            isNew: false,
            muscleGroup: muscleGroup(for: type).rawValue,
            setLength: 1.0,
            straightSets: false,
            difficultyInt: 2,
            name: uniqueName,
            duration: durationMinutes,
            exercisesSequenceID: [],
            finishedExercisesSequence: [],
            exercises: [],
            plan: [],
            workoutActivityType: Int(type.rawValue),
            workoutSessionLocation: location(for: type).rawValue)
        workout.shortInfo = type.name
        return workout
    }

    static func muscleGroup(for type: HKWorkoutActivityType) -> WorkoutCategory {
        switch type {
        case .yoga, .pilates, .mindAndBody, .taiChi, .barre: return .yoga
        case .flexibility, .preparationAndRecovery:           return .mobilityFlexibility
        case .highIntensityIntervalTraining:                  return .hiit
        default:                                              return .cardio
        }
    }

    /// Outdoor for the distance sports `ActiveWorkoutView` records a GPS route
    /// for; a pool swim is indoor.
    static func location(for type: HKWorkoutActivityType) -> HKWorkoutSessionLocationType {
        switch type {
        case .running, .walking, .cycling, .hiking: return .outdoor
        case .swimming:                             return .indoor
        default:                                    return .unknown
        }
    }
}
