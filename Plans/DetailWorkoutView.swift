//
//  DetailWorkoutView.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 19.01.24.
//

import SwiftUI

struct DetailWorkoutView: View {
        
    @ObservedObject var addPlanModel: AddPlanViewModel
    
    var body: some View {
        ZStack {
            ThemedPanel()
                .padding()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        appLog("dismiss")
                        withAnimation {
                            addPlanModel.showDetail = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel(Text(NSLocalizedString("Close", comment: "")))
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                            .padding(.top)
                    }
                }
                ScrollView(.vertical) {
                    Text(addPlanModel.selectedWorkoutForDetail?.displayName ?? NSLocalizedString("not available", comment: "Workout detail fallback"))
                        .font(.title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .padding(10)
                    
                    
                    Text("Difficulty: \(addPlanModel.selectedWorkoutForDetail?.displayDifficulty ?? NSLocalizedString("not available", comment: "Workout detail fallback"))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Text("Duration: \(addPlanModel.selectedWorkoutForDetail?.duration ?? 0)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    if let workoutMuscleGroup = addPlanModel.selectedWorkoutForDetail?.muscleGroup {
                        Text("Muscle group: \(WorkoutCategory.getCategoryName(from: workoutMuscleGroup))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    
                    if let workout = addPlanModel.selectedWorkoutForDetail {
                        Text("Equipment: \(getEquipmentAsString(workout: workout))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal)
                    }
                    
                    Divider()
                    
                    Text("\(addPlanModel.selectedWorkoutForDetail?.displayInfoText ?? "no info text available")")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .padding(.horizontal)
                    
                    Divider()
                    
                    if let workout = addPlanModel.selectedWorkoutForDetail {
                        Text("Exercises: \(getExercisesAsString(workout: workout))")
                            .multilineTextAlignment(.leading)
                            .padding()
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 400)
    }
    
    func getEquipmentAsString(workout: Workout) -> String {
        var equipmentSet = Set<String>()
        if let exercises = workout.exercises {
            for exercise in exercises {
                for equipmentItem in exercise.equipment {
                    equipmentSet.insert(Equipment.getEquipmentName(from: equipmentItem))
                }
            }
        }
        let equipmentString = equipmentSet.joined(separator: ", ")
        
        return equipmentString
    }
    
    func getExercisesAsString(workout: Workout) -> String {
        var uniqueExercises = Set<String>()
        if let exercises = workout.exercises {
            for exercise in exercises {
                uniqueExercises.insert(exercise.displayName)
            }
        }
        let exercisesString = uniqueExercises.joined(separator: ", ")

        return exercisesString
    }
}

#Preview {
    DetailWorkoutView(addPlanModel: AddPlanViewModel())
}

struct EditPlanDetailWorkoutView: View {
        
    @ObservedObject var editplanModel: EditPlanViewModel
    
    var body: some View {
        ZStack {
            ThemedPanel()
                .padding()
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        appLog("dismiss")
                        withAnimation {
                            editplanModel.showDetail = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel(Text(NSLocalizedString("Close", comment: "")))
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                            .padding(.top)
                    }
                }
                ScrollView(.vertical) {
                    Text("\(editplanModel.selectedWorkoutForDetail?.displayName ?? "not available")")
                        .font(.title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .padding(10)

                    
                    Text("Difficulty: \(editplanModel.selectedWorkoutForDetail?.displayDifficulty ?? NSLocalizedString("not available", comment: "Workout detail: missing value"))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Text("Duration: \(editplanModel.selectedWorkoutForDetail?.duration ?? 0)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    if let workoutMuscleGroup = editplanModel.selectedWorkoutForDetail?.muscleGroup {
                        Text("Muscle group: \(WorkoutCategory.getCategoryName(from: workoutMuscleGroup))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    
                    if let workout = editplanModel.selectedWorkoutForDetail {
                        Text("Equipment: \(getEquipmentAsString(workout: workout))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal)
                    }
                    
                    Divider()
                    
                    Text("\(editplanModel.selectedWorkoutForDetail?.displayInfoText ?? "no info text available")")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .padding(.horizontal)
                                                       
                    Divider()
                                        
                    if let workout = editplanModel.selectedWorkoutForDetail {
                        Text("Exercises: \(getExercisesAsString(workout: workout))")
                            .multilineTextAlignment(.leading)
                            .padding()
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 400)
    }
    
    func getEquipmentAsString(workout: Workout) -> String {
        var equipmentSet = Set<String>()
        if let exercises = workout.exercises {
            for exercise in exercises {
                for equipmentItem in exercise.equipment {
                    equipmentSet.insert(Equipment.getEquipmentName(from: equipmentItem))
                }
            }
        }
        let equipmentString = equipmentSet.joined(separator: ", ")
        
        return equipmentString
    }
    
    func getExercisesAsString(workout: Workout) -> String {
        var uniqueExercises = Set<String>()
        if let exercises = workout.exercises {
            for exercise in exercises {
                uniqueExercises.insert(exercise.displayName)
            }
        }
        let exercisesString = uniqueExercises.joined(separator: ", ")

        return exercisesString
    }
}
