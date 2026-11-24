//
//  WorkoutApp.swift
//  Workout Watch App
//
//  Created by Justus Besser on 26.08.23.
//

import SwiftUI
import SwiftData
import WatchKit
import HealthKit
import CloudKit

@main
struct Workout_Watch_App: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    
    /// Plain references, not `@StateObject`: on watchOS 10 (Series 4,
    /// arm64_32) a `@StateObject` built with Xcode 27 crashes the first
    /// SwiftUI graph update (SIGABRT in `swift_generic_initWithCopy`), so
    /// the app never launched there. Each manager still exists once (two
    /// shared singletons, one static instance) and the body only hands them
    /// to the views, reading none of their state, so nothing is lost.
    private let watchWorkoutManager = WatchWorkoutManager.shared
    private static let healthKitManager = HealthKitManager()
    private let syncManager = WorkoutSyncManager.shared

    /// Built exactly once. Previously the body called `createCloudModelContainer()`
    /// on every re-render, which created multiple `ModelContainer` instances
    /// pointing at the same iCloud store. The second instance failed to
    /// register its CloudKit export handler ("BUG IN CLIENT OF CLOUDKIT:
    /// Registering a handler ... already been registered"), CoreData tore the
    /// store down, and any `@Bindable` model held by a view immediately
    /// crashed with "This model instance was destroyed by calling
    /// ModelContext.reset".
    static let sharedContainer: ModelContainer = Self.makeCloudModelContainer()

    init() {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        _ = WorkoutSyncManager.shared
    }
    
    @SceneBuilder var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchWorkoutManager)
                .environmentObject(Self.healthKitManager)
                .environmentObject(syncManager)
                .modelContainer(Self.sharedContainer)
                .task {
                    await requestHealthKitAuthorization()
                }
        }
    }
    // MARK: - Helper Methods
    
    @MainActor
    private func requestHealthKitAuthorization() async {
        // Run the two authorization requests independently. The shared
        // HealthKitManager requests iOS-flavored types (e.g. heart-rate write)
        // that may not be valid on watchOS — if that call throws, we still
        // need the watch-specific request to fire so that
        // `HKObjectType.workoutType()` gets registered. Without that, the app
        // never appears under Settings → Privacy & Security → Health, and the
        // user has no toggle to enable.
        do {
            try await Self.healthKitManager.requestAuthorization()
        } catch {
            appLog("Watch shared HealthKit authorization failed: \(error)")
        }
        do {
            try await watchWorkoutManager.requestHealthKitAuthorization()
        } catch {
            appLog("Watch workout HealthKit authorization failed: \(error)")
        }
    }
    
    /// Graded fallback so the watch app never crashes on launch:
    ///   1. CloudKit-backed store (syncs across devices).
    ///   2. Plain on-disk store (keeps data locally if CloudKit is unavailable).
    ///   3. In-memory store as a last resort so the UI still launches.
    /// Previously the fallback used `try!`, turning a store-load failure into a
    /// launch crash.
    private static func makeCloudModelContainer() -> ModelContainer {
        // 1. Preferred: CloudKit private database.
        do {
            let config = ModelConfiguration(
                "iCloudModel",
                cloudKitDatabase: .private("iCloud.com.traininglab")
            )
            return try ModelContainer(
                for: Workout.self, Exercise.self, Plan.self, FinishedWorkout.self,
                configurations: config
            )
        } catch {
            appLog("CloudKit model container failed, trying local store: \(error)")
        }

        // 2. Local on-disk store — no sync, but data persists. Same store name
        //    as above, so whatever is saved here is still there once CloudKit
        //    works again (the unnamed default store would be orphaned).
        do {
            let local = ModelConfiguration("iCloudModel", cloudKitDatabase: .none)
            return try ModelContainer(
                for: Workout.self, Exercise.self, Plan.self, FinishedWorkout.self,
                configurations: local
            )
        } catch {
            appLog("Local model container failed, falling back to in-memory: \(error)")
        }

        // 3. In-memory — the app still opens instead of crashing.
        do {
            let memory = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(
                for: Workout.self, Exercise.self, Plan.self, FinishedWorkout.self,
                configurations: memory
            )
        } catch {
            fatalError("Unable to create any ModelContainer (even in-memory): \(error)")
        }
    }
}

// MARK: - WatchAppDelegate for watchOS

class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func applicationDidFinishLaunching() {
        _ = WorkoutSyncManager.shared

        // Kick off HealthKit authorization as early as possible. The scene's
        // `.task` doesn't fire until the SwiftUI view appears, which is too
        // late when iOS launched us via `startWatchApp(toHandle:)` — the
        // delegate's `handle(_:)` runs first and would try to create an
        // HKWorkoutSession against an unauthorized HealthStore. Log the
        // outcome instead of swallowing — when the prompt fails to appear,
        // this is the most useful signal we have.
        Task { @MainActor in
            do {
                try await WatchWorkoutManager.shared.requestHealthKitAuthorization()
                let status = HKHealthStore.shared.authorizationStatus(for: .workoutType())
                appLog("Watch HK eager auth completed. workoutType status: \(status.rawValue)")
            } catch {
                appLog("Watch HK eager auth threw: \(error)")
            }
        }
    }

    func applicationDidBecomeActive() {
        refreshWorkoutState()
    }

    /// watchOS relaunches the app with this after it crashed or was killed
    /// during a workout; without it that workout's data was lost.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            await WatchWorkoutManager.shared.recoverActiveWorkout()
        }
    }

    // MARK: - Workout Session Management

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            let mirroredName = WatchConnectivityManager.shared.currentWorkoutState.workoutName
            do {
                try await WatchWorkoutManager.shared.startWorkout(
                    configuration: workoutConfiguration,
                    workoutName: mirroredName.isEmpty ? "Workout" : mirroredName,
                    notifyPhone: false
                )
            } catch {
                appLog("Failed to handle iPhone workout launch: \(error)")
            }
        }
    }
    private func refreshWorkoutState() {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .appDidBecomeActive,
                object: nil
            )
        }
    }
    
    // MARK: - Background Refresh
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                handleBackgroundRefresh(backgroundTask)
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                handleSnapshotRefresh(snapshotTask)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                handleConnectivityRefresh(connectivityTask)
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                handleURLSessionRefresh(urlSessionTask)
            case let relevantShortcutTask as WKRelevantShortcutRefreshBackgroundTask:
                handleRelevantShortcutRefresh(relevantShortcutTask)
            case let intentDidRunTask as WKIntentDidRunRefreshBackgroundTask:
                handleIntentRefresh(intentDidRunTask)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
    
    private func handleBackgroundRefresh(_ task: WKApplicationRefreshBackgroundTask) {
        Task {
            await WorkoutSyncManager.shared.syncInBackground()
            task.setTaskCompletedWithSnapshot(false)
        }
    }
    
    private func handleSnapshotRefresh(_ task: WKSnapshotRefreshBackgroundTask) {
        task.setTaskCompleted(
                restoredDefaultState: true,
                estimatedSnapshotExpiration: Date.distantFuture,
                userInfo: nil
            )
    }
    
    private func handleConnectivityRefresh(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        Task { @MainActor in
            WatchConnectivityManager.shared.requestSync()
        }
        task.setTaskCompletedWithSnapshot(false)
    }
        
    private func handleURLSessionRefresh(_ task: WKURLSessionRefreshBackgroundTask) {
        task.setTaskCompletedWithSnapshot(false)
    }
        
    private func handleRelevantShortcutRefresh(_ task: WKRelevantShortcutRefreshBackgroundTask) {
        task.setTaskCompletedWithSnapshot(false)
    }
        
    private func handleIntentRefresh(_ task: WKIntentDidRunRefreshBackgroundTask) {
        task.setTaskCompletedWithSnapshot(false)
    }
}

extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")
}
