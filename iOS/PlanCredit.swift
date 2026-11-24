//
//  PlanCredit.swift
//  Workout App (iOS)
//
//  Which plans the workout that just ended counted toward, so the summary
//  can say so and offer an undo. Kept in memory only: the summary is shown
//  right after the save, and a stored field would need another CloudKit
//  schema deploy for a one-time note.
//

import Foundation

struct PlanCredit: Equatable {
    /// The history entry (`FinishedWorkout.id`) the credit belongs to.
    let finishedWorkoutID: String
    /// The workout that was marked done in the plans.
    let workoutID: String
    let planIDs: [String]

    @MainActor static var latest: PlanCredit?

    /// Records the credit for a just-saved history entry (nil when no plan counted it).
    @MainActor static func record(finishedWorkoutID: String, workoutID: String, plans: [Plan]) {
        latest = plans.isEmpty ? nil : PlanCredit(finishedWorkoutID: finishedWorkoutID,
                                                  workoutID: workoutID,
                                                  planIDs: plans.map(\.id))
    }
}
