//
//  GeneratedPlanReviewView.swift
//  TrainingLab (iOS)
//
//  Review step shown after generating a multi-week gym plan. Lists every
//  generated workout; tapping one opens the full editor (`ChangeWorkoutView`)
//  to rename it and reorder/remove its exercises. "Save" keeps the plan;
//  "Discard" deletes the plan and all its generated workouts (shared Exercise
//  catalog rows are `.noAction`, so they're never removed).
//

import SwiftUI
import SwiftData

struct GeneratedPlanReviewView: View {
    let plan: Plan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Local, mutable copy so a workout deleted from within the editor drops out
    /// of the list immediately (rendering a deleted model would crash).
    @State private var workouts: [Workout]
    @State private var editTarget: EditTarget?

    private struct EditTarget: Identifiable, Hashable {
        let id: String
        let workout: Workout

        static func == (lhs: EditTarget, rhs: EditTarget) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    init(plan: Plan, workouts: [Workout]) {
        self.plan = plan
        _workouts = State(initialValue: workouts)
    }

    var body: some View {
        NavigationStack {
            StyledList(onPlanPage: true) {
                Section {
                    ForEach(workouts, id: \.id) { workout in
                        Button {
                            editTarget = EditTarget(id: workout.id, workout: workout)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(String(format: NSLocalizedString("%d exercises", comment: "Plan review: exercise count"),
                                                workout.exercisesSequenceID.count))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Generated workouts")
                } footer: {
                    Text("Tap a workout to rename it or reorder its exercises. Save to keep the plan, or discard it entirely.")
                }
            }
            .navigationTitle("Review plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) { discard() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { dismiss() }
                        .bold()
                }
            }
            .navigationDestination(item: $editTarget) { target in
                ChangeWorkoutView(workout: target.workout, onDelete: {
                    workouts.removeAll { $0.id == target.id }
                })
            }
        }
    }

    private func discard() {
        for workout in workouts {
            modelContext.delete(workout)
        }
        NotificationManager.shared.cancelReminders(for: plan)
        modelContext.delete(plan)
        try? modelContext.save()
        dismiss()
    }
}
