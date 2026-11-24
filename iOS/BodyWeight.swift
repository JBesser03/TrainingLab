//
//  BodyWeight.swift
//  Workout App (iOS)
//
//  The user's current body weight: Apple Health's latest reading from the
//  last few months, else what they typed in Settings. A session records it so
//  bodyweight exercises count toward its volume.
//

import Foundation
import HealthKit

enum BodyWeight {

    /// Readings older than this are too stale to count with.
    static let maxAge: TimeInterval = 90 * 86_400

    @MainActor
    static func current() async -> Double? {
        if let fromHealth = await latestFromHealth() { return fromHealth }
        return SettingsManager.shared.bodyWeightKg
    }

    static func latestFromHealth(now: Date = .now) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let recent = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-maxAge), end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: recent)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: HKHealthStore.shared).first else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
}
