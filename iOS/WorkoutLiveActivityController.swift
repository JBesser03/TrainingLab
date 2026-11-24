//
//  WorkoutLiveActivityController.swift
//  Workout App (iOS)
//
//  Owns the `Activity` handle for the in-progress workout. App-target only —
//  the widget renders the state but never starts or ends it.
//
//  Update cadence is deliberately *transition-driven*, not per-second:
//  `ActiveWorkoutView` pushes a new state when the exercise, set, rest or
//  pause changes, and every countdown travels as an anchored end `Date` that
//  `Text(timerInterval:)` ticks on its own. That keeps a whole workout well
//  inside ActivityKit's update budget instead of burning it in the first few
//  minutes.
//

import Foundation
// ActivityKit's `Activity` isn't annotated `Sendable` yet; its update/end
// calls are safe from the main actor that owns it.
@preconcurrency import ActivityKit

@MainActor
final class WorkoutLiveActivityController {

    static let shared = WorkoutLiveActivityController()

    private var activity: Activity<WorkoutActivityAttributes>?

    private init() {}

    /// Whether the user has Live Activities enabled for the app at all. When
    /// false every call below is a silent no-op — a workout must run exactly
    /// the same with the feature switched off in iOS Settings.
    private var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(workoutName: String, startDate: Date, state: WorkoutActivityAttributes.ContentState) {
        guard isEnabled else { return }

        // A previous run can leave an Activity behind if the app was killed
        // mid-workout — ActivityKit outlives the process. Clear those before
        // requesting a new one, or the Lock Screen stacks two workouts.
        endOrphanedActivities()

        let attributes = WorkoutActivityAttributes(workoutName: workoutName, startDate: startDate)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate(for: state)),
                pushType: nil)
        } catch {
            // Throws when the user is at the system's concurrent-activity
            // limit, or when requested from the background. Not fatal: the
            // workout itself is unaffected.
            appLog("Live Activity: could not start: \(error)")
        }
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: staleDate(for: state)))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every workout activity, including ones left behind by a killed
    /// process. Called when the resume banner is discarded, and at launch when
    /// there's no interrupted workout the card could belong to.
    func endAll() {
        activity = nil
        endOrphanedActivities()
    }

    /// Marks the content stale a while after the current phase should have
    /// ended, so an app that died mid-workout shows a dimmed card instead of
    /// confidently displaying an exercise the user finished ten minutes ago.
    private func staleDate(for state: WorkoutActivityAttributes.ContentState) -> Date {
        let horizon = state.phaseEndDate ?? Date()
        return max(horizon, Date()).addingTimeInterval(15 * 60)
    }

    private func endOrphanedActivities() {
        for stale in Activity<WorkoutActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
