//
//  ÜbungsItemManager.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 05.10.21.
//

import Foundation
import SwiftUI
import SwiftData

//MARK: - Exercise hinzufügen
@MainActor
class ExerciseItemManager {
        
    static let shared = ExerciseItemManager()
    private var modelContext: ModelContext?
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func addItem(fromDummy dummy: AddExerciseDummy) {
        guard let modelContext = modelContext else {
            appLog("Failed to access ModelContext in ExerciseItemManager")
            return
        }
        let exercise = Exercise(
            id: dummy.id,
            difficultyInt: dummy.difficultyInt,
            equipment: dummy.equipment,
            muscleGroup: dummy.muscleGroup,
            name: dummy.name
        )
        exercise.repCount = dummy.repCount
        exercise.targetWeightKg = dummy.targetWeightKg
        // Work duration (seconds) only matters for time-based exercises.
        exercise.duration = dummy.repCount == 0 ? dummy.duration : nil
        modelContext.insert(exercise)
        
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving exercise: \(error)")
        }
    }
    
    func delete(exercise: Exercise) {
        guard let modelContext = modelContext else {
            appLog("modelContext is not set up in ExerciseItemManager")
            return
        }
        // Workouts reference exercises by id too; a stale id shows up as
        // "Exercise not found" in the active workout.
        let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
        for workout in workouts where workout.exercisesSequenceID.contains(exercise.id) {
            workout.exercisesSequenceID.removeAll { $0 == exercise.id }
        }
        modelContext.delete(exercise)
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving after deleting Exercise: \(error)")
        }
    }
}

//MARK: - Workout hinzufügen
@MainActor
class WorkoutItemManager {
        
    static let shared = WorkoutItemManager()
    private var modelContext: ModelContext?
    private init() {}
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func addWorkout(fromDummy dummy: AddWorkoutDummy) {
        guard let modelContext = modelContext else {
            appLog("modelContext is not set up in WorkoutItemManager")
            return
        }
        
        let workout = Workout(
            id: UUID().uuidString,
            infoText: dummy.infoText,
            isUserGenerated: dummy.isUserGenerated,
            muscleGroup: dummy.muscleGroup,
            setLength: dummy.setLength,
            straightSets: false,
            difficultyInt: dummy.workoutDifficultyInt,
            name: dummy.workoutName,
            duration: Int(dummy.workoutDuration), // Convert to Int
            exercisesSequenceID: dummy.exercisesSequenceID,
            finishedExercisesSequence: [],
            workoutActivityType: Int(dummy.workoutActivityType),
            workoutSessionLocation: dummy.workoutSessionLocation
        )
        
        // Set exercises relationship
        workout.exercises = dummy.exercises ?? []
        workout.exercisePlans = dummy.exercisePlans
        // Seed rest-between-rounds from the user's default (only matters for
        // cardio/HIIT; strength workouts never rest).
        workout.restSeconds = max(SettingsManager.shared.pauseTime, 0)
        
        modelContext.insert(workout)
        
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving workout: \(error)")
        }
    }
    
    func delete(workout: Workout) {
        guard let modelContext = modelContext else {
            appLog("modelContext not set up in delete in WorkoutItemManager")
            return
        }
        // Plans reference workouts by id; a stale id leaves the plan stuck on
        // a workout that can't be started.
        let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
        for plan in plans {
            plan.removeWorkoutID(workout.id)
        }
        modelContext.delete(workout)
        do {
            try modelContext.save()
        } catch {
            appLog("Error deleting workout: \(error)")
        }
    }
}

// MARK: - Add Plan
@MainActor
class PlanItemManager {
        
    static let shared = PlanItemManager()
    private var modelContext: ModelContext?
    private init() {}
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func addPlan(withName name: String,
                 difficultyInt: Int,
                 difficulty: String,
                 goal: Int,
                 muscleGroup: Int,
                 infoText: String,
                 workoutsInPlan: [Workout],
                 isUserGenerated: Bool,
                 interval: [String: Date],
                 intervalType: String,
                 notificationIDs: [String],
                 testStrings: [String]) {
        
        guard let modelContext = modelContext else {
            appLog("modelContext not set up in PlanItemManager")
            return
        }
        
        let plan = Plan(
            goal: goal,
            infoText: infoText,
            muscleGroup: muscleGroup,
            name: name,
            difficultyInt: difficultyInt,
            interval: interval,
            intervalType: intervalType,
            notificationIDs: notificationIDs,
            isUserGenerated: isUserGenerated,
            finishedWorkoutsSequence: []
        )
        
        plan.workouts = workoutsInPlan
        
        modelContext.insert(plan)
        
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving plan: \(error)")
        }
    }
    
    func delete(plan: Plan) {
        guard let modelContext = modelContext else {
            appLog("modelContext not set up in delete in PlanItemManager")
            return
        }
        NotificationManager.shared.cancelReminders(for: plan)
        modelContext.delete(plan)
        
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving after deleting plan: \(error)")
        }
    }
}
