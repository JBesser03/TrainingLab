//
//  ReorderableExerciseList.swift
//  TrainingLab (iOS)
//
//  A drag-to-reorder / swipe-to-remove list of a workout's exercises, bound to an
//  ordered `[Exercise]`. Rendered as `ForEach` rows (with `.onMove`/`.onDelete`) so
//  it drops into either a `Form` section (the workout editor) or a standalone
//  `List` (the detail-view reorder sheet). Reordering here is what the caller then
//  writes back to `workout.exercisesSequenceID`.
//

import SwiftUI
import SwiftData

struct ReorderableExerciseList: View {
    @Binding var exercises: [Exercise]
    /// Whether swipe-to-delete is offered (reorder sheets and the editor both allow it).
    var allowsDelete: Bool = true

    var body: some View {
        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.displayName.trimmingCharacters(in: .whitespaces).isEmpty
                         ? NSLocalizedString("Unnamed exercise", comment: "Finished workout: exercise without a name")
                         : exercise.displayName)
                        .font(.body.weight(.medium))
                    Text(WorkoutCategory.getCategoryName(from: exercise.muscleGroup))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let kg = exercise.targetWeightKg {
                    Label(SettingsManager.shared.weightUnit.format(kilograms: kg), systemImage: "scalemass")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onMove { indices, newOffset in
            exercises.move(fromOffsets: indices, toOffset: newOffset)
        }
        .onDelete(perform: allowsDelete ? { offsets in
            exercises.remove(atOffsets: offsets)
        } : nil)
    }
}

// MARK: - Reorder sheet

/// A dedicated, always-in-edit-mode sheet for reordering (and removing) a saved
/// workout's exercises. On Done it writes the new order to both the relationship
/// and `exercisesSequenceID` — the canonical order used by ActiveWorkoutView.
struct ReorderExercisesSheet: View {
    @Bindable var workout: Workout

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var ordered: [Exercise] = []

    var body: some View {
        NavigationStack {
            StyledList {
                if ordered.isEmpty {
                    Text("No exercises to reorder")
                        .foregroundStyle(.secondary)
                } else {
                    ReorderableExerciseList(exercises: $ordered)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear(perform: loadOrdered)
        }
    }

    private func loadOrdered() {
        let all = workout.exercises ?? []
        let sequence = workout.exercisesSequenceID
        ordered = sequence.isEmpty
            ? all
            : all.sorted { (sequence.firstIndex(of: $0.id) ?? Int.max) < (sequence.firstIndex(of: $1.id) ?? Int.max) }
    }

    private func save() {
        workout.exercises = ordered
        workout.exercisesSequenceID = ordered.map { $0.id }
        try? modelContext.save()
    }
}
