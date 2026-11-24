//
//  PhoneWorkoutHealthWriter.swift
//  Workout App (iOS)
//
//  Writes a workout the iPhone ran on its own (no Apple Watch session) to
//  Apple Health, so it shows up in Health / Fitness and counts toward the
//  Move ring. Watch sessions are written by the watch; outdoor GPS sessions
//  are written by `RunLocationManager` together with their route.
//

import Foundation
import HealthKit

enum PhoneWorkoutHealthWriter {

    /// Shorter sessions are accidental starts, not workouts worth logging.
    static let minimumDuration: TimeInterval = 60

    /// Rough active-energy estimate (kcal): the mean of the exercises' catalog
    /// burn rates over the session's duration. Nil when no exercise has a rate.
    static func estimatedEnergy(caloriesPerSecond rates: [Double], duration: TimeInterval) -> Double? {
        let known = rates.filter { $0 > 0 }
        guard !known.isEmpty, duration > 0 else { return nil }
        return known.reduce(0, +) / Double(known.count) * duration
    }

    /// The pauses inside `start...end`, clipped to it, sorted and with
    /// overlaps merged, so they can be subtracted and sent to HealthKit as is.
    static func normalizedPauses(_ pauses: [DateInterval], start: Date, end: Date) -> [DateInterval] {
        let clipped = pauses
            .map { (max($0.start, start), min($0.end, end)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for pause in clipped {
            if let last = merged.last, pause.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, pause.1)
            } else {
                merged.append(pause)
            }
        }
        return merged.map { DateInterval(start: $0.0, end: $0.1) }
    }

    /// The time actually spent working out: `start...end` without the pauses.
    static func activeDuration(start: Date, end: Date, pauses: [DateInterval]) -> TimeInterval {
        let paused = normalizedPauses(pauses, start: start, end: end).reduce(0) { $0 + $1.duration }
        return max(end.timeIntervalSince(start) - paused, 0)
    }

    /// Saves the workout in the background; failures (e.g. Health access
    /// denied) are logged, never surfaced — the history entry is already saved.
    /// `pauses` become pause/resume events, so Health counts only the active
    /// time; `energyKcal` should be estimated over that same active time.
    static func save(activityType: HKWorkoutActivityType,
                     locationType: HKWorkoutSessionLocationType,
                     start: Date,
                     end: Date,
                     pauses: [DateInterval] = [],
                     energyKcal: Double?) {
        let pauses = normalizedPauses(pauses, start: start, end: end)
        guard activeDuration(start: start, end: end, pauses: pauses) >= minimumDuration else { return }
        Task.detached {
            do {
                let store = HKHealthStore.shared
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = activityType
                configuration.locationType = locationType

                let builder = HKWorkoutBuilder(healthStore: store,
                                               configuration: configuration,
                                               device: .local())
                try await builder.beginCollection(at: start)

                // Optional extras: Workouts and Active Energy are granted
                // separately, and a failed extra must not lose the workout.
                if let energyKcal, energyKcal > 0,
                   let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                   store.authorizationStatus(for: energyType) == .sharingAuthorized {
                    let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal)
                    let sample = HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
                    do { try await builder.addSamples([sample]) }
                    catch { appLog("Adding the energy estimate to the phone workout failed: \(error)") }
                }
                let events = pauses.flatMap { pause -> [HKWorkoutEvent] in
                    var events = [HKWorkoutEvent(type: .pause,
                                                 dateInterval: DateInterval(start: pause.start, duration: 0),
                                                 metadata: nil)]
                    // A pause that lasted until the end has no resume.
                    if pause.end < end {
                        events.append(HKWorkoutEvent(type: .resume,
                                                     dateInterval: DateInterval(start: pause.end, duration: 0),
                                                     metadata: nil))
                    }
                    return events
                }
                if !events.isEmpty {
                    do { try await builder.addWorkoutEvents(events) }
                    catch { appLog("Adding pauses to the phone workout failed: \(error)") }
                }

                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
                appLog("Saved phone workout to Health")
            } catch {
                appLog("Saving phone workout to Health failed: \(error)")
            }
        }
    }
}
