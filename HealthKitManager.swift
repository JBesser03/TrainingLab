//
//  HealthKitManager.swift
//  WorkoutApp
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import HealthKit
import Combine

extension HKHealthStore {
    /// The app's single, long-lived HealthKit store. Apple recommends one
    /// instance per app: each store holds its own connection to the HealthKit
    /// daemon, so creating one per query or view is wasted setup. It's
    /// thread-safe, so every manager, view and query shares this one.
    static let shared = HKHealthStore()
}

/// Requests the app's HealthKit authorization. The reading and writing itself
/// lives where it's used: the watch's workout manager, `RunLocationManager`,
/// `PhoneWorkoutHealthWriter` and `RecoveryMetricsProvider`.
@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore.shared

    // Define the health data types we want to read
    // Only what each platform actually reads — App Review checks the prompt
    // against the usage text, and the watch's text only covers workout data.
    private let typesToRead: Set<HKObjectType> = {
        var set: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]
        #if os(iOS)
        set.insert(HKObjectType.quantityType(forIdentifier: .stepCount)!)
        // Recovery signals used by the workout-intelligence engine
        // (RecoveryEstimator). Read-only — the app never writes these.
        set.insert(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!)
        set.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        // Activity rings on the finished-workout summary.
        set.insert(HKObjectType.activitySummaryType())
        // Volume of bodyweight exercises (`BodyWeight`).
        set.insert(HKObjectType.quantityType(forIdentifier: .bodyMass)!)
        #endif
        return set
    }()
    
    // Define the health data types we want to write.
    // On watchOS, apps cannot write `.heartRate` or `.stepCount` — those are
    // produced by the sensors/system. Including them on the watch causes the
    // auth request to reject before the prompt is presented, which is why
    // `HKObjectType.workoutType()` was never getting registered and the app
    // never appeared in Settings → Privacy & Security → Health.
    private let typesToWrite: Set<HKSampleType> = {
        var set: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]
        #if os(iOS)
        // GPS routes for outdoor workouts (RunLocationManager).
        set.insert(HKSeriesType.workoutRoute())
        #endif
        return set
    }()
    
    /// Request authorization for HealthKit data access
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
        } catch {
            throw HealthKitError.authorizationFailed(error.localizedDescription)
        }
    }
}

// MARK: - Custom Error Types
enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device"
        case .authorizationFailed(let message):
            return "Authorization failed: \(message)"
        }
    }
}
