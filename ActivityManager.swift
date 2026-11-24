//
//  ActivityManager.swift
//  WorkoutApp
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import HealthKit
import Combine

// MARK: - Activity Ring Data

struct ActivityRingData {
    var moveProgress: Double = 0
    var exerciseProgress: Double = 0
    var standProgress: Double = 0
}

// MARK: - Activity Manager

/// Fetches HealthKit activity summary data for displaying activity rings.
@MainActor
class ActivityManager: ObservableObject {

    // MARK: - Published Properties

    @Published var activitySummary: HKActivitySummary?

    // MARK: - Private Properties

    private let healthStore: HKHealthStore

    // MARK: - Initialization

    init(healthStore: HKHealthStore = .shared) {
        self.healthStore = healthStore
    }

    // MARK: - Fetching

    func fetchActivityRings() {
        let calendar = Calendar.current
        let now = Date()

        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: startComponents)

        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, error in
            Task { @MainActor in
                if let summary = summaries?.first {
                    self?.activitySummary = summary
                }
            }
        }

        healthStore.execute(query)
    }
}
