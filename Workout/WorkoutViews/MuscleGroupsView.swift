//
//  MuscleGroupsView.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 02.04.23.
//

import SwiftUI
import SwiftData

struct MuscleGroupsView: View {

    @Query(filter: #Predicate<Workout> { !$0.isHidden }) var workouts: [Workout]
    
    private let rows = [GridItem(.fixed(84)), GridItem(.fixed(84))]

    var body: some View {
        VStack {
            Text("Workout categories")
                .sectionTitleStyle()
                .padding(.horizontal)
                .padding(.top, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows) {
                    ForEach(WorkoutCategory.allCases, id: \.self) { muscleGroup in
                        NavigationLink {
                            WorkoutsByMuscleGroup(muscleGroup: muscleGroup.rawValue)
                        } label: {
                            MuscleGroupCellView(muscleGroup: muscleGroup.rawValue)
                                
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }
}

struct MuscleGroupCellView: View {
    
    var muscleGroup: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: WorkoutCategory.getSymbolName(from: muscleGroup))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.tone(WorkoutCategory.tone(from: muscleGroup)))
            Spacer(minLength: 8)
            Text(WorkoutCategory.getCategoryName(from: muscleGroup))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(width: 132, height: 84, alignment: .topLeading)
        .cardBackground()
    }
}



// MARK: - Muscle Group List View
struct MuscleGroupListView: View {

    var workout: Workout

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: WorkoutCategory.getSymbolName(from: workout.muscleGroup), tone: WorkoutCategory.tone(from: workout.muscleGroup))

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(workout.levelAndDuration)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }
}

#Preview {
    MuscleGroupListView(workout: Workout.samples[0])
}
