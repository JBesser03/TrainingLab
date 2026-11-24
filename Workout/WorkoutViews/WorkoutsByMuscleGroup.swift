//
//  WorkoutsByMuscleGroup.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 02.04.23.
//

import SwiftUI
import SwiftData
import WorkoutKit

struct WorkoutsByMuscleGroup: View {

    @Query(filter: #Predicate<Workout> { !$0.isHidden }) var workouts: [Workout]

    var muscleGroup: Int
    @Namespace private var zoom

    var workoutsInMuscleGroup: [Workout] {
        workouts.filter { workout in
            !workout.isUserGenerated && workout.muscleGroup == muscleGroup
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                if !workoutsInMuscleGroup.isEmpty {
                    HStack {
                        Text("\(workoutsInMuscleGroup.count) workouts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    LazyVStack(spacing: 10) {
                        ForEach(workoutsInMuscleGroup, id: \.self) { workout in
                            NavigationLink {
                                WorkoutPreviewiOS(workout: workout)
                                    .navigationTransition(.zoom(sourceID: workout.id, in: zoom))
                            } label: {
                                MuscleGroupListView(workout: workout)
                                    .zoomSource(id: workout.id, in: zoom)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: WorkoutCategory.getSymbolName(from: muscleGroup))
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("No \(WorkoutCategory.getCategoryName(from: muscleGroup)) workouts yet")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("Create one or check back later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                }
            }
        }
        .pageTint()
        .navigationTitle(WorkoutCategory.getCategoryName(from: muscleGroup))
    }
}

struct WorkoutsByMuscleGroup_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutsByMuscleGroup(muscleGroup: 2)
    }
}
