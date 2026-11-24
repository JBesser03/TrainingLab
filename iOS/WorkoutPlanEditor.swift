//
//  WorkoutPlanEditor.swift
//  Workout App (iOS)
//
//  The exercise part of the add/edit workout forms: each exercise with its own
//  sets and reps, supersets of neighbouring exercises, drag to reorder, and
//  `ExercisePickerView` to add more. Also the defaults that follow the muscle
//  group (activity type, location, an estimated duration), so a gym workout
//  built by hand is recorded as strength training and counts toward the Gym
//  goal without the user touching those fields.
//

import SwiftUI
import HealthKit

/// One exercise as the workout editor holds it.
struct PlannedExercise: Identifiable {
    let exercise: Exercise
    var sets: Int
    /// `0` for a time-based exercise.
    var reps: Int
    var targetWeightKg: Double?
    /// The hold of a time-based exercise; nil for its own length.
    var seconds: Int?
    /// Forms a superset with the exercise after it.
    var linkedToNext = false

    var id: String { exercise.id }

    /// A newly added exercise: three sets of its usual reps.
    init(exercise: Exercise) {
        self.exercise = exercise
        sets = 3
        reps = exercise.repCount
        targetWeightKg = exercise.targetWeightKg
    }

    init(exercise: Exercise, plan: ExercisePlan, linkedToNext: Bool) {
        self.exercise = exercise
        sets = plan.sets
        reps = plan.reps
        targetWeightKg = plan.targetWeightKg
        seconds = plan.seconds
        self.linkedToNext = linkedToNext
    }

    /// `ordered`'s exercises with `workout`'s plans; neighbours in the same
    /// superset group come back linked.
    static func items(for workout: Workout, ordered: [Exercise]) -> [PlannedExercise] {
        let plans = ordered.map { workout.plan(for: $0) }
        return ordered.indices.map { i in
            let group = plans[i].supersetGroup
            let linked = group != nil && i + 1 < plans.count && plans[i + 1].supersetGroup == group
            return PlannedExercise(exercise: ordered[i], plan: plans[i], linkedToNext: linked)
        }
    }

    /// The plans to store, keyed by exercise id. A run of linked exercises
    /// shares a superset group (numbered by its first position).
    static func plans(_ items: [PlannedExercise]) -> [String: ExercisePlan] {
        var result: [String: ExercisePlan] = [:]
        var group: Int?
        for (i, item) in items.enumerated() {
            let startsOrContinues = item.linkedToNext && i + 1 < items.count
            if group == nil, startsOrContinues { group = i }
            result[item.id] = ExercisePlan(sets: item.sets, reps: item.reps,
                                           targetWeightKg: item.targetWeightKg, supersetGroup: group,
                                           seconds: item.reps > 0 ? nil : item.seconds)
            if !startsOrContinues { group = nil }
        }
        return result
    }
}

/// What a new workout's details default to, from its muscle group.
enum WorkoutDefaults {

    static func activityType(forMuscleGroup group: Int) -> HKWorkoutActivityType {
        switch WorkoutCategory(rawValue: group) {
        case .cardio:              return .mixedCardio
        case .hiit:                return .highIntensityIntervalTraining
        case .yoga:                return .yoga
        case .mobilityFlexibility: return .flexibility
        case .undefined, nil:      return .other
        default:                   return .traditionalStrengthTraining
        }
    }

    static func location(forMuscleGroup group: Int) -> HKWorkoutSessionLocationType {
        WorkoutCategory(rawValue: group) == .cardio ? .unknown : .indoor
    }

    /// About 2½ minutes per set, set-up and rest included, in steps of 5.
    static func estimatedMinutes(_ items: [PlannedExercise]) -> Int {
        let sets = items.reduce(0) { $0 + $1.sets }
        let minutes = Double(sets) * 2.5
        return min(max(Int((minutes / 5).rounded()) * 5, 10), 120)
    }
}

/// The form section listing a workout's exercises with their sets × reps.
struct PlannedExercisesSection: View {

    @Binding var items: [PlannedExercise]
    /// A strength workout: its timed exercises get a hold length. Yoga, mobility
    /// and circuits run them for the workout's own pose or interval length.
    var holdsTimedExercises = true
    let onAdd: () -> Void

    @State private var expandedID: String?

    var body: some View {
        Section {
            if items.isEmpty {
                Text(NSLocalizedString("No exercises yet", comment: ""))
                    .foregroundStyle(.secondary)
            }
            ForEach($items) { $item in
                row($item)
            }
            .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { items.remove(atOffsets: $0) }

            Button(action: onAdd) {
                Label(NSLocalizedString("Add exercises", comment: "Workout editor: open the exercise picker"),
                      systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("plannedExercises.add")
        } header: {
            HStack {
                Text(NSLocalizedString("Exercises", comment: ""))
                Spacer()
                if items.count > 1 {
                    EditButton()
                        .font(.callout)
                }
            }
        } footer: {
            if !items.isEmpty {
                Text(NSLocalizedString("Tap an exercise for its sets, reps and supersets. Tap Edit to reorder.",
                                       comment: "Workout editor: exercises footer"))
            }
        }
    }

    private func row(_ item: Binding<PlannedExercise>) -> some View {
        let index = items.firstIndex { $0.id == item.wrappedValue.id } ?? 0
        let isExpanded = expandedID == item.wrappedValue.id
        let inSuperset = item.wrappedValue.linkedToNext || (index > 0 && items[index - 1].linkedToNext)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { expandedID = isExpanded ? nil : item.wrappedValue.id }
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.wrappedValue.exercise.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.primary)
                        HStack(spacing: 6) {
                            Text(WorkoutCategory.getCategoryName(from: item.wrappedValue.exercise.muscleGroup))
                            if inSuperset {
                                Label(NSLocalizedString("Superset", comment: "Workout editor: exercise is part of a superset"),
                                      systemImage: "link")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.summary(sets: item.wrappedValue.sets, reps: item.wrappedValue.reps,
                                      seconds: holdsTimedExercises ? holdSeconds(item.wrappedValue) : nil))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // A plain button only takes taps on what it draws; this makes
                // the gap between the name and "3 × 10" tappable too.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plannedExercises.row.\(item.wrappedValue.id)")

            if isExpanded {
                Stepper(value: item.sets, in: 1...10) {
                    Text(String(format: NSLocalizedString("%d sets", comment: "Active workout: sets a11y"), item.wrappedValue.sets))
                }
                if item.wrappedValue.reps > 0 {
                    Stepper(value: item.reps, in: 1...50) {
                        Text(String(format: NSLocalizedString("%d reps", comment: ""), item.wrappedValue.reps))
                    }
                } else if holdsTimedExercises {
                    // How long each set is held.
                    Stepper(value: Binding(get: { holdSeconds(item.wrappedValue) },
                                           set: { item.wrappedValue.seconds = $0 }),
                            in: 5...600, step: 5) {
                        Text(String(format: NSLocalizedString("Hold %@", comment: "Workout editor: how long a timed exercise is held, e.g. 'Hold 0:45'"),
                                    ExercisePlan.holdText(holdSeconds(item.wrappedValue))))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("plannedExercises.hold.\(item.wrappedValue.id)")
                }
                if index < items.count - 1 {
                    Toggle(NSLocalizedString("Superset with next", comment: "Workout editor: alternate sets with the following exercise"),
                           isOn: item.linkedToNext)
                }
            }
        }
    }

    private func holdSeconds(_ item: PlannedExercise) -> Int {
        item.seconds ?? ExercisePlan.defaultHoldSeconds(for: item.exercise)
    }

    /// "3 × 10", "3 × 0:45" for a time-based exercise, or "3 × timed" when
    /// its length isn't known.
    static func summary(sets: Int, reps: Int, seconds: Int? = nil) -> String {
        if reps > 0 { return "\(sets) × \(reps)" }
        if let seconds { return "\(sets) × \(ExercisePlan.holdText(seconds))" }
        return String(format: NSLocalizedString("%d × timed", comment: "Sets of a time-based exercise, e.g. '3 × timed'"), sets)
    }
}
