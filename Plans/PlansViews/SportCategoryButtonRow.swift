//
//  SportCategoryButtonRow.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 20.05.26.
//

import SwiftUI
import HealthKit

enum SportCategory: String, CaseIterable, Identifiable {
    case all
    case running
    case cycling
    case swimming
    case gym
    case yoga
    case hiit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:      return NSLocalizedString("All", comment: "Sport category, all")
        case .running:  return NSLocalizedString("Running", comment: "Sport category, running")
        case .cycling:  return NSLocalizedString("Cycling", comment: "Sport category, cycling")
        case .swimming: return NSLocalizedString("Swimming", comment: "Sport category, swimming")
        case .gym:      return NSLocalizedString("Gym", comment: "Sport category, gym")
        case .yoga:     return NSLocalizedString("Yoga", comment: "Sport category, yoga")
        case .hiit:     return NSLocalizedString("HIIT", comment: "Sport category, HIIT")
        }
    }

    var symbolName: String {
        switch self {
        case .all:      return "square.grid.2x2.fill"
        case .running:  return "figure.run"
        case .cycling:  return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .gym:      return "dumbbell.fill"
        case .yoga:     return "figure.yoga"
        case .hiit:     return "flame.fill"
        }
    }

    /// HealthKit activity types that belong to this sport category.
    var activityTypes: [UInt] {
        switch self {
        case .all:
            return []
        case .running:
            return [HKWorkoutActivityType.running.rawValue]
        case .cycling:
            return [HKWorkoutActivityType.cycling.rawValue]
        case .swimming:
            return [HKWorkoutActivityType.swimming.rawValue]
        case .gym:
            return [
                HKWorkoutActivityType.traditionalStrengthTraining.rawValue,
                HKWorkoutActivityType.functionalStrengthTraining.rawValue
            ]
        case .yoga:
            return [HKWorkoutActivityType.yoga.rawValue]
        case .hiit:
            return [HKWorkoutActivityType.highIntensityIntervalTraining.rawValue]
        }
    }

    func matches(workout: Workout) -> Bool {
        if self == .all { return true }
        return activityTypes.contains(UInt(workout.workoutActivityType))
    }

    /// Plan muscle groups that should be considered a primary match for this sport,
    /// preventing cross-category leaks from plans that happen to include a one-off workout
    /// of a different discipline (e.g. a cardio plan with a yoga cool-down).
    private var primaryPlanMuscleGroups: Set<Int>? {
        switch self {
        case .yoga:
            return [WorkoutCategory.yoga.rawValue, WorkoutCategory.mobilityFlexibility.rawValue]
        case .hiit:
            return [WorkoutCategory.hiit.rawValue]
        case .gym:
            return Set(WorkoutCategory.fullbody.rawValue...WorkoutCategory.shoulders.rawValue)
        case .running, .cycling, .swimming, .all:
            return nil
        }
    }

    func matches(plan: Plan) -> Bool {
        if self == .all { return true }
        if let primaryGroups = primaryPlanMuscleGroups {
            return primaryGroups.contains(plan.muscleGroup)
        }
        guard let workouts = plan.workouts else { return false }
        return workouts.contains(where: { matches(workout: $0) })
    }
}

struct SportCategoryButtonRow: View {

    @Binding var selected: SportCategory
    var categories: [SportCategory] = SportCategory.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        withAnimation(.snappy) {
                            selected = category
                        }
                    } label: {
                        Chip(title: category.displayName, systemImage: category.symbolName,
                             isSelected: selected == category)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == category ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

#Preview {
    StatefulPreviewWrapper(SportCategory.all) { binding in
        SportCategoryButtonRow(selected: binding)
    }
}

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
