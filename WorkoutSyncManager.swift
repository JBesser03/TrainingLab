//
//  WorkoutSyncManager.swift
//  WorkoutApp
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation

// MARK: - Workout Metadata Structure

struct WorkoutMetadata {
    let workoutName: String
    let exerciseName: String
    let exerciseDuration: Double
    let muscleGroup: Int
}

// MARK: - WorkoutSyncManager

/// Thin iOS-side facade over `WatchConnectivityManager` for views that need
/// the watch's reachability or want to request a state sync.
///
/// The workout session itself runs in `ActiveWorkoutView` and
/// `iOSWorkoutObserver`. This class used to carry a second, parallel session
/// engine (its own timers and HealthKit session) that nothing called; it was
/// removed so there is only one source of truth for a running workout.
@MainActor
class WorkoutSyncManager: ObservableObject {

    private let connectivity = WatchConnectivityManager.shared

    init(healthKitManager: HealthKitManager) {
        // Pull the watch's current state once at launch, as before.
        Task { @MainActor [connectivity] in
            if connectivity.checkWatchAvailability() {
                connectivity.requestSync()
            }
        }
    }

    var isWatchReachable: Bool {
        connectivity.isWatchReachable
    }

    func requestWorkoutSync() {
        connectivity.requestSync()
    }
}
