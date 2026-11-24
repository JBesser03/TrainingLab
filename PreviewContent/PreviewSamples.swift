//
//  PreviewSamples.swift
//  WorkoutApp (iOS)
//
//  Created by Justus Besser on 11.05.25.
//

import Foundation
import HealthKit

extension Exercise {
    @MainActor
    static let samples: [Exercise] = [
        Exercise(id: "id1", difficultyInt: 2, equipment: [], muscleGroup: 2, name: "Exercise1Name"),
        Exercise(id: "id2", difficultyInt: 2, equipment: [], muscleGroup: 4, name: "Exercise2Name"),
        Exercise(id: "id3", difficultyInt: 2, equipment: [], muscleGroup: 1, name: "Exercise3Name"),
        Exercise(id: "id4", difficultyInt: 2, equipment: [], muscleGroup: 3, name: "Exercise4Name")
    ]
}

extension Workout {
    @MainActor
    static let samples: [Workout] = [
        Workout(id: "id1", infoText: "infoText", isUserGenerated: false, isNew: true, isSaved: true, muscleGroup: 2, setLength: 3, straightSets: false, difficultyInt: 2, name: "Workout1Name", duration: 5, exercisesSequenceID: [], finishedExercisesSequence: [], exercises: [], plan: [], workoutActivityType: Int(HKWorkoutActivityType.other.rawValue), workoutSessionLocation: HKWorkoutSessionLocationType.unknown.rawValue),
        Workout(id: "id2", infoText: "infoTextlonger", isUserGenerated: false, isNew: false, isSaved: false, muscleGroup: 4, setLength: 3, straightSets: false, difficultyInt: 2, name: "Workout2Name", duration: 5, exercisesSequenceID: [], finishedExercisesSequence: [], exercises: [], plan: [], workoutActivityType: Int(HKWorkoutActivityType.other.rawValue), workoutSessionLocation: HKWorkoutSessionLocationType.unknown.rawValue),
        Workout(id: "id3", infoText: "infoText", isUserGenerated: true, isNew: false, isSaved: true, muscleGroup: 1, setLength: 2, straightSets: false, difficultyInt: 3, name: "Workout3Name", duration: 25, exercisesSequenceID: [], finishedExercisesSequence: [], exercises: [], plan: [], workoutActivityType: Int(HKWorkoutActivityType.other.rawValue), workoutSessionLocation: HKWorkoutSessionLocationType.unknown.rawValue)
    ]
}

extension Plan {
    @MainActor
    static let samples: [Plan] = [
        Plan(goal: PlanGoal.other.rawValue, infoText: "intofText", muscleGroup: 2, name: "Plan1Name", interval: [:], intervalType: ""),
        Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "intofText", muscleGroup: 4, name: "Plan2NameLongName", interval: [:], intervalType: ""),
        Plan(goal: PlanGoal.strengthTraining.rawValue, infoText: "intofTextLongInfoText", muscleGroup: 1, name: "Plan3Name", interval: [:], intervalType: ""),
        Plan(goal: PlanGoal.overallHealthAndWellness.rawValue, infoText: "intofTextLongInfoText", muscleGroup: 3, name: "Plan4NameLongNane", interval: [:], intervalType: ""),
    ]
}


extension FinishedWorkout {
    @MainActor
    static let samples: [FinishedWorkout] = [
        FinishedWorkout(endDate: Date(), name: "finishedWorkout1Name", startDate: Date(), muscleGroup: 100, exercisesSequenceID: [Exercise.samples[0].id]),
        FinishedWorkout(endDate: Date(), name: "finishedWorkout2Name", startDate: Date(), muscleGroup: 100, exercisesSequenceID: []),
        FinishedWorkout(endDate: Date(), name: "finishedWorkout3Name", startDate: Date(), muscleGroup: 100, exercisesSequenceID: [Exercise.samples[0].id, Exercise.samples[1].id]),
        FinishedWorkout(endDate: Date(), name: "finishedWorkout4Name", startDate: Date(), muscleGroup: 100, exercisesSequenceID: [Exercise.samples[0].id, Exercise.samples[1].id])
    ]
    
    @MainActor
    static let notFoundFinishedWorkout: FinishedWorkout = FinishedWorkout(endDate: Date(), name: "Workout not found", startDate: Date(), muscleGroup: 100, exercisesSequenceID: [])
}
