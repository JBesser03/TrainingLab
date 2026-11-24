//
//  HealthGoalObserver.swift
//  Workout App (iOS)
//
//  Keeps weekly goal progress — the widget and the reminders — current when
//  another app (Apple's Workout app, Strava, Garmin…) saves a workout to
//  HealthKit while TrainingLab isn't open. HealthKit background delivery wakes
//  the app for each new workout, and the observer runs the same refresh a
//  workout finished in the app does. Without it, a swim recorded on the watch
//  would only count once TrainingLab is next opened, and a reminder could
//  still fire for a goal that's already met.
//

import HealthKit
import SwiftData

@MainActor
enum HealthGoalObserver {

    private static var query: HKObserverQuery?

    /// Registers the observer, replacing a previous one. Called from
    /// `Workout_App.init` — background deliveries only reach an observer set
    /// up during launch — and again once HealthKit access was requested, since
    /// on the very first launch the query fails until the user has answered.
    static func start(container: ModelContainer, healthStore: HKHealthStore = .shared) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if let query { healthStore.stop(query) }

        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completionHandler, error in
            let done = CompletionHandler(call: completionHandler)
            if let error {
                appLog("Goal observer: \(error.localizedDescription)")
                done.call()
                return
            }
            Task { @MainActor in
                await GoalReminderScheduler.shared.refresh(context: container.mainContext)
                done.call()
            }
        }
        healthStore.execute(query)
        self.query = query

        healthStore.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { success, error in
            if !success {
                appLog("Goal observer: background delivery not enabled: \(error?.localizedDescription ?? "unknown")")
            }
        }
    }
}

/// HealthKit's observer completion block isn't annotated `Sendable`, but it's
/// documented as callable from any thread — and it has to be called after the
/// main-actor refresh, or HealthKit stops waking the app.
private struct CompletionHandler: @unchecked Sendable {
    let call: () -> Void
}
