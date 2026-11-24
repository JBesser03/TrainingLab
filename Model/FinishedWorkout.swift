//
//  FinishedWorkout.swift
//  Workout App
//
//  Created by Justus Besser on 28.02.24.
//
//

import Foundation
import SwiftData
import HealthKit

@Model public class FinishedWorkout: Hashable {
    public var id: String = UUID().uuidString
    var duration: Double = 0.0
    var endDate: Date = Date()
    var name: String = ""
    var startDate: Date = Date()
    var muscleGroup: Int = 100
    var workoutLocation: Int = Int(HKWorkoutSessionLocationType.unknown.rawValue)
    var workoutType: Int = Int(HKWorkoutActivityType.other.rawValue)
    var healthKitWorkoutUUID: UUID?
    var caloriesBurned: Double?
    /// How hard the session felt, 1 (very easy) … 10 (maximal effort), as
    /// rated by the user on the summary screen. Nil until they rate it.
    var perceivedEffort: Int?
    /// The predicted difficulty (1…5) shown before the session, when it came
    /// from the For You generator. Paired with `perceivedEffort` to calibrate
    /// future predictions. Both optional → CloudKit-migration-safe.
    var predictedDifficulty: Double?

    @Attribute
    var additionalDataStorage: Data = Data()
    
    var additionalData: WorkoutAdditionalData {
        get {
            guard !additionalDataStorage.isEmpty,
            let decoded = try? JSONDecoder().decode(WorkoutAdditionalData.self, from: additionalDataStorage)
            else { return .none }
            
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                additionalDataStorage = encoded
            } else {
                additionalDataStorage = Data()
            }
        }
    }
    
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
    
    // Per-set weights logged during the session, stored as a JSON blob keyed by
    // exercise id → the weight of each set (in kilograms). Follows the same
    // Data-backed pattern as `exercisesSequenceID` so it's CloudKit-safe.
    @Attribute
    private var setWeightsData: Data = Data()

    var setWeights: [String: [Double]] {
        get {
            guard !setWeightsData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: [Double]].self, from: setWeightsData)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                setWeightsData = encoded
            } else {
                setWeightsData = Data()
            }
        }
    }

    // Reps performed per set, keyed by exercise id and index-aligned with
    // `setWeights`. Stored as a separate blob so existing records (weights only)
    // keep decoding; missing reps simply read back as empty. CloudKit-safe.
    @Attribute
    private var setRepsData: Data = Data()

    var setReps: [String: [Int]] {
        get {
            guard !setRepsData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: [Int]].self, from: setRepsData)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                setRepsData = encoded
            } else {
                setRepsData = Data()
            }
        }
    }

    // What else was logged: the kind of each set (warm-up, drop) and its reps
    // in reserve, index-aligned with `setWeights`, plus notes. A separate blob
    // like `setRepsData`, so records without it read back as plain working
    // sets with no notes. CloudKit-safe.
    @Attribute
    private var loggingDetailsData: Data = Data()

    var loggingDetails: SessionLog {
        get {
            guard !loggingDetailsData.isEmpty,
                  let decoded = try? JSONDecoder().decode(SessionLog.self, from: loggingDetailsData)
            else { return SessionLog() }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                loggingDetailsData = encoded
            } else {
                loggingDetailsData = Data()
            }
        }
    }

    @Relationship(deleteRule: .noAction, inverse: \Exercise.finishedWorkouts)
    var exercises: [Exercise]?
    
    public init(id: String = UUID().uuidString, endDate: Date, name: String, startDate: Date, muscleGroup: Int, workoutLocation: Int = HKWorkoutSessionLocationType.unknown.rawValue, workoutType: Int = Int(HKWorkoutActivityType.other.rawValue), healthKitWorkout: UUID? = nil, caloriesBurned: Double? = nil, additionalData: WorkoutAdditionalData = .none, exercisesSequenceID: [String], exercises: [Exercise] = []) {
        self.id = id
        self.endDate = endDate
        self.name = name
        self.startDate = startDate
        self.muscleGroup = muscleGroup
        self.workoutLocation = workoutLocation
        self.workoutType = workoutType
        self.healthKitWorkoutUUID = healthKitWorkout
        self.duration = endDate.timeIntervalSince(startDate)
        self.caloriesBurned = caloriesBurned
        self.additionalData = additionalData
        self.exercisesSequenceID = exercisesSequenceID // This will trigger the setter
        self.exercises = exercises
    }
}

/// What a logged set was. Only working sets count toward volume, PRs and
/// the weight the next session starts from.
enum SetKind: String, Codable, Hashable {
    case working, warmup, drop
}

/// Extra facts about one logged set, index-aligned with `setWeights`.
struct SetDetail: Codable, Hashable {
    var kind: SetKind = .working
    /// How many more reps were left in the tank (RIR); nil when not rated.
    var repsInReserve: Int?
    /// How long a timed set (a plank, a hang) was held, in seconds; nil for
    /// sets done by reps.
    var seconds: Int?
}

/// Everything a session logged besides weights and reps.
struct SessionLog: Codable, Hashable {
    var setDetails: [String: [SetDetail]] = [:]
    var exerciseNotes: [String: String] = [:]
    var sessionNote = ""
    /// The user's body weight on the day, from Apple Health or Settings.
    var bodyWeightKg: Double?
    /// Exercises done with the body's own weight: their volume counts
    /// `bodyWeightKg` on top of any weight added.
    var bodyweightExerciseIDs: Set<String> = []

    init(setDetails: [String: [SetDetail]] = [:], exerciseNotes: [String: String] = [:], sessionNote: String = "",
         bodyWeightKg: Double? = nil, bodyweightExerciseIDs: Set<String> = []) {
        self.setDetails = setDetails
        self.exerciseNotes = exerciseNotes
        self.sessionNote = sessionNote
        self.bodyWeightKg = bodyWeightKg
        self.bodyweightExerciseIDs = bodyweightExerciseIDs
    }

    // Tolerant of missing keys, so a later addition can't make older
    // records unreadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setDetails = try container.decodeIfPresent([String: [SetDetail]].self, forKey: .setDetails) ?? [:]
        exerciseNotes = try container.decodeIfPresent([String: String].self, forKey: .exerciseNotes) ?? [:]
        sessionNote = try container.decodeIfPresent(String.self, forKey: .sessionNote) ?? ""
        bodyWeightKg = try container.decodeIfPresent(Double.self, forKey: .bodyWeightKg)
        bodyweightExerciseIDs = try container.decodeIfPresent(Set<String>.self, forKey: .bodyweightExerciseIDs) ?? []
    }

    /// Weight moved in one set of `exerciseID`: what was on the bar, plus the
    /// body for a bodyweight exercise when the session knows it.
    func load(_ exerciseID: String, addedKg: Double) -> Double {
        guard bodyweightExerciseIDs.contains(exerciseID), let bodyWeightKg else { return addedKg }
        return addedKg + bodyWeightKg
    }

    /// The detail for set `index` of `exerciseID` — a working set when none
    /// was stored.
    func detail(_ exerciseID: String, _ index: Int) -> SetDetail {
        guard let details = setDetails[exerciseID], details.indices.contains(index) else { return SetDetail() }
        return details[index]
    }
}

public enum WorkoutAdditionalData: Codable, Hashable {
    case running(distance: Double)
    case swimming(swimmingDistance: Double)
    case cycling(distance: Double)
    case hiking(distance: Double, steps: Int)
    case rowing(distance: Double)
    case walking(distance: Double, steps: Int)
    case skiing(distance: Double)
    case none
    
    var description: String {
        switch self {
        case .running(distance: let distance):
            return "\(distance) km"
        case .swimming(swimmingDistance: let swimmingDistance):
            return "\(swimmingDistance) m"
        case .cycling(distance: let distance):
            return "\(distance) km"
        case .hiking(distance: let distance, steps: let steps):
            return "\(distance) km, \(steps) steps"
        case .rowing(distance: let distance):
            return "\(distance) km"
        case .walking(distance: let distance, steps: let steps):
            return "\(distance) km, \(steps) steps"
        case .skiing(distance: let distance):
            return "\(distance) km"
        case .none:
            return "No extra data"
        }
    }
    
    var hasContent: Bool {
        switch self {
        case .none:
            return false
        default:
            return true
        }
    }
}
