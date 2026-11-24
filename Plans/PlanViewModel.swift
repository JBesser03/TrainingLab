//
//  MatchedGeometryViewModel.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 20.01.24.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - AddPlanViewModel
class AddPlanViewModel: ObservableObject {
    
    @Published var name: String = ""
    @Published var difficultyInt: Int = 2
    @Published var goal = PlanGoal.other.rawValue
    @Published var muscleGroup = WorkoutCategory.undefined.rawValue
    @Published var infoText = ""
    @Published var interval: [String: Date] = [:]
    @Published var intervalType: String = ""
    
    @Published var selectedWorkoutForDetail: Workout? = nil
    @Published var showDetail = false
    @Published var workoutsSequenceIDs: [String] = []
    @Published var workouts: [Workout] = []
    
    func removeWorkoutSelection(id string: String, atIndex index: Int) {
        if workoutsSequenceIDs[index] == string {
            workoutsSequenceIDs.remove(at: index)
        } else {
            appLog("String not at given index; string: \(string), index: \(index)")
        }
    }
    
    func addWorkoutSelection(_ string: String) {
        workoutsSequenceIDs.append(string)
    }
    
    func showWorkoutDetail(_ workout: Workout) {
        if !showDetail {
            selectedWorkoutForDetail = workout
            withAnimation {
                showDetail = true
            }
        }
    }
}

// MARK: - EditPlanViewModel
class EditPlanViewModel: ObservableObject {
        
    @Published var unEditedName = ""
    
    @Published var name = ""
    @Published var difficultyInt: Int = 2
    @Published var goal = PlanGoal.other.rawValue
    @Published var muscleGroup = WorkoutCategory.undefined.rawValue
    @Published var infoText = ""
    @Published var interval: [String: Date] = [:]
    @Published var intervalType: String = ""
    @Published var workoutsSequenceIDs: [String] = []
    @Published var showDeletePlanAlert = false
    
    @Published var selectedWorkoutForDetail: Workout? = nil
    
    @Published var showDetail = false
    @Published var showNameAlreadyExisting = false
    
    func removeWorkoutSelection(id string: String, atIndex index: Int) {
        if workoutsSequenceIDs[index] == string {
            workoutsSequenceIDs.remove(at: index)
        } else {
            appLog("String not at given index; string: \(string), index: \(index)")
        }
    }
    
    func addWorkoutSelection(_ string: String) {
        workoutsSequenceIDs.append(string)
    }
    
    func showWorkoutDetail(_ workout: Workout) {
        if !showDetail {
            selectedWorkoutForDetail = workout
            withAnimation {
                showDetail = true
            }
        }
    }
    
    func initValues(_ plan: Plan) {
        unEditedName = plan.name
        
        name = plan.name
        difficultyInt = plan.difficultyInt
        goal = plan.goal
        muscleGroup = plan.muscleGroup
        infoText = plan.infoText
        interval = plan.interval
        intervalType = plan.intervalType
        workoutsSequenceIDs = plan.workoutsSequenceIDs
    }
}
