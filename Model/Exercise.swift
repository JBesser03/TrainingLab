//
//  Exercise.swift
//  Workout App
//
//  Created by Justus Besser on 28.02.24.
//
//

import Foundation
import SwiftData
import HealthKit

// MARK: - Exercise Model (No Transformers)
@Model public class Exercise {
    public var id: String = UUID().uuidString
    /// Unused — the add-workout screen keeps its selection in view state.
    /// Kept as a stored property because removing it from this `@Model` would
    /// be a CloudKit schema migration.
    var addIsPartOfWorkout: Bool = false
    var caloriesPerSecond: Double? = 0.0
    var difficulty: String?
    var difficultyInt: Int = 2
    var duration: Double? = 0.0
    
    // Handle equipment array manually
    @Attribute
    private var equipmentData: Data = Data()
    
    var equipment: [Int] {
        get {
            guard !equipmentData.isEmpty,
                  let decoded = try? JSONDecoder().decode([Int].self, from: equipmentData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                equipmentData = encoded
            } else {
                equipmentData = Data()
            }
        }
    }
    
    var hasAnimation: Bool = false
    var isActive: Bool = false
    var isDone: Bool = false
    var isPartOfWorkout: Bool = false
    var muscleGroup: Int = 100
    var name: String = ""
    var symbol: String = ""

    /// User-facing, localized exercise name. `name` stores a localization key for seeded
    /// exercises (e.g. "Squats") or raw text for user-generated ones; `NSLocalizedString`
    /// returns the input unchanged when it isn't a catalog key.
    var displayName: String { NSLocalizedString(name, comment: "Exercise name") }
    /// Number of repetitions for strength-style exercises.
    /// `0` (the default) means the exercise is time-based and the workout timer drives it.
    var repCount: Int = 0

    /// Optional target weight for this exercise, **always stored in kilograms**.
    /// `nil` means no target has been set. Display/entry is converted to the user's
    /// unit via `WeightUnit`. Defaulted + optional to stay CloudKit-migration-safe.
    var targetWeightKg: Double? = nil

    /// Fields of a built-in exercise the user has changed ("name", "symbol",
    /// "equipment", "repCount", "difficulty", "muscleGroup"). The catalog sync
    /// and the workout generators leave those alone, so an edit sticks.
    /// Data-backed, so it's CloudKit-safe.
    @Attribute
    private var customizedFieldsData: Data = Data()

    var customizedFields: Set<String> {
        get {
            guard !customizedFieldsData.isEmpty,
                  let decoded = try? JSONDecoder().decode(Set<String>.self, from: customizedFieldsData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                customizedFieldsData = encoded
            } else {
                customizedFieldsData = Data()
            }
        }
    }

    /// User-facing, localized difficulty, derived from `difficultyInt`. The
    /// stored `difficulty` text was written in whatever language the app ran
    /// in when the exercise was seeded, so lists showed a mix of languages.
    var displayDifficulty: String { DifficultyLevel.name(for: difficultyInt) }

    /// Equipment that carries the logged load, as `Equipment` raw values
    /// (raw ints because `Equipment` isn't compiled into the watch target):
    /// dumbbells 2, kettlebells 3, barbells 6, medicine ball 10, EZ bar 18,
    /// cable machine 19, leg press 20, sled 26, Smith machine 27.
    static let loadingEquipment: Set<Int> = [2, 3, 6, 10, 18, 19, 20, 26, 27]

    /// Resistance bands 4 and pull-up bar 9, as `Equipment` raw values.
    static let resistanceBandsEquipment = 4
    static let pullUpBarEquipment = 9

    /// Done with the body's own weight: none of the `loadingEquipment`. A
    /// weight logged for it is weight *added* — a vest or a plate on a dip
    /// belt — and its volume counts the body on top.
    /// A band carries the load itself (a band curl or pull-apart lifts no
    /// body weight), unless the body hangs from a pull-up bar and the band
    /// only assists: a band-assisted pull-up still lifts the body.
    var isBodyweight: Bool {
        let items = Set(equipment)
        guard items.isDisjoint(with: Self.loadingEquipment) else { return false }
        if items.contains(Self.resistanceBandsEquipment) {
            return items.contains(Self.pullUpBarEquipment)
        }
        return true
    }

    @Relationship(deleteRule: .noAction)
    var workouts: [Workout]?
    
    @Relationship(deleteRule: .noAction)
    var finishedWorkouts: [FinishedWorkout]?
    
    public init(id: String = UUID().uuidString, difficultyInt: Int, equipment: [Int], muscleGroup: Int, name: String, workout: [Workout] = []) {
        self.id = id
        self.difficultyInt = difficultyInt
        self.equipment = equipment
        self.muscleGroup = muscleGroup
        self.name = name
        self.symbol = symbol
    }
}
