//
//  RunLocationManager.swift
//  Workout App (iOS)
//
//  Records the GPS route of outdoor distance workouts (running, walking,
//  cycling, hiking) and saves it to HealthKit as an HKWorkoutRoute when the
//  session ends, so the run shows up with a map in Apple's Fitness/Health apps.
//

import Foundation
import CoreLocation
import HealthKit
import Combine

/// Main actor: the view drives it, the location callbacks arrive on the main
/// thread (where the manager is created), and saving reads `coordinates`.
@MainActor
final class RunLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Route so far, for the live map. Only accuracy-filtered fixes land here.
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var isTracking = false
    /// True when the user has denied/restricted location access — the UI shows
    /// a hint instead of a map.
    @Published private(set) var permissionDenied = false

    private let manager = CLLocationManager()
    private let healthStore = HKHealthStore.shared
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var lastLocation: CLLocation?
    private(set) var totalDistanceMeters: Double = 0
    /// Set when `start()` ran before the user answered the permission prompt;
    /// tracking then begins from the authorization callback.
    private var startPendingAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Lifecycle

    /// Begin recording. Requests when-in-use permission on first use.
    func start() {
        guard !isTracking else { return }
        coordinates = []
        lastLocation = nil
        totalDistanceMeters = 0
        permissionDenied = false
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

        switch manager.authorizationStatus {
        case .notDetermined:
            startPendingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        default:
            permissionDenied = true
        }
    }

    /// Stop recording and save the route to HealthKit. When the watch recorded
    /// the session, the route is attached to the workout the watch saved
    /// (matched by activity type + start time); phone-only runs write their
    /// own HKWorkout. Runs detached so it survives the view dismissing.
    /// Returns false when there was no usable route (e.g. location denied),
    /// so the caller saves the workout to Health another way.
    @discardableResult
    func finish(activityType: HKWorkoutActivityType, start: Date, end: Date, watchRecorded: Bool) -> Bool {
        stopUpdates()
        guard coordinates.count >= 2, routeBuilder != nil else {
            discard()
            return false
        }
        Task { await finishAsync(activityType: activityType, start: start, end: end, watchRecorded: watchRecorded) }
        return true
    }

    /// Stop recording and drop everything (workout too short / no fixes).
    func discard() {
        stopUpdates()
        routeBuilder?.discard()
        routeBuilder = nil
    }

    private func beginUpdates() {
        startPendingAuthorization = false
        // Requires the "location" UIBackgroundModes entry — keeps the route
        // recording while the screen is off mid-run.
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate
    //
    // CoreLocation calls these on the thread that created the manager — the
    // main thread here — so they step onto the main actor synchronously.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                permissionDenied = false
                if startPendingAuthorization { beginUpdates() }
            case .denied, .restricted:
                permissionDenied = true
                startPendingAuthorization = false
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            record(locations)
        }
    }

    private func record(_ locations: [CLLocation]) {
        guard isTracking else { return }
        // Drop poor fixes so the route (and distance) isn't polluted by
        // cell-tower jumps while GPS is still locking on.
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !usable.isEmpty else { return }

        for location in usable {
            if let last = lastLocation {
                totalDistanceMeters += location.distance(from: last)
            }
            lastLocation = location
        }
        coordinates.append(contentsOf: usable.map(\.coordinate))

        // `@Sendable`: HealthKit calls this on a background queue, and the API
        // isn't annotated, so the closure would otherwise be main-actor
        // isolated — a runtime crash in the Swift 6 language mode.
        routeBuilder?.insertRouteData(usable) { @Sendable success, error in
            if let error { appLog("Route insert failed: \(error)") }
            _ = success
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        appLog("Location update failed: \(error)")
    }

    // MARK: - Saving

    private func finishAsync(activityType: HKWorkoutActivityType, start: Date, end: Date, watchRecorded: Bool) async {
        guard let routeBuilder else { return }

        // With a watch session, never write a second workout: if the watch's
        // hasn't synced yet, Health would show the run twice with the
        // distance counted double.
        let workout: HKWorkout?
        if watchRecorded {
            workout = await findMatchingWorkout(activityType: activityType, around: start)
        } else {
            do {
                workout = try await createWorkout(activityType: activityType, start: start, end: end)
            } catch {
                appLog("Writing the phone workout failed: \(error)")
                workout = nil
            }
        }
        guard let workout else {
            appLog("Route not saved: no HKWorkout to attach to")
            routeBuilder.discard()
            self.routeBuilder = nil
            return
        }

        do {
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
            appLog("Saved workout route (\(coordinates.count) points, \(Int(totalDistanceMeters)) m)")
        } catch {
            appLog("Failed to save workout route: \(error)")
        }
        self.routeBuilder = nil
    }

    /// Looks for a workout of the same activity type starting within ±3 min of
    /// ours — i.e. the HKWorkout the watch session wrote. Retries for about a
    /// minute: the watch → phone HealthKit sync often takes longer than a few
    /// seconds.
    private func findMatchingWorkout(activityType: HKWorkoutActivityType, around start: Date) async -> HKWorkout? {
        for attempt in 0..<12 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            if let workout = await queryWorkout(activityType: activityType, around: start) {
                return workout
            }
        }
        return nil
    }

    private func queryWorkout(activityType: HKWorkoutActivityType, around start: Date) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            let typePredicate = HKQuery.predicateForWorkouts(with: activityType)
            let datePredicate = HKQuery.predicateForSamples(
                withStart: start.addingTimeInterval(-180),
                end: start.addingTimeInterval(180),
                options: [])
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    /// Phone-only run: write our own HKWorkout (with the GPS distance) so the
    /// route has a workout to attach to.
    private func createWorkout(activityType: HKWorkoutActivityType, start: Date, end: Date) async throws -> HKWorkout? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        if totalDistanceMeters > 0, let distanceType = distanceType(for: activityType) {
            let quantity = HKQuantity(unit: .meter(), doubleValue: totalDistanceMeters)
            let sample = HKQuantitySample(type: distanceType, quantity: quantity, start: start, end: end)
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()
    }

    private func distanceType(for activityType: HKWorkoutActivityType) -> HKQuantityType? {
        switch activityType {
        case .cycling:
            return HKQuantityType.quantityType(forIdentifier: .distanceCycling)
        default:
            return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        }
    }
}
