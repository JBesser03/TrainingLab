//
//  Workout_MultiplatformApp.swift
//  Shared
//
//  Created by Justus Besser on 22.01.22.
//

import SwiftUI
import SwiftData
import HealthKit
import CloudKit

@main
struct Workout_App: App {
    
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var workoutObserver: iOSWorkoutObserver
    @StateObject private var activityManager: ActivityManager
    @StateObject private var syncManager: WorkoutSyncManager
    @State private var showTemporaryStoreAlert = false

    /// Set when neither the CloudKit nor the local store could be opened and
    /// the app runs on an in-memory store; nothing entered is kept on quit.
    private(set) static var isUsingTemporaryStore = false

    static let sharedContainer: ModelContainer = {
        #if DEBUG
        // Screenshot demo data stays on the device, never in iCloud.
        if ProcessInfo.processInfo.arguments.contains("-UITestSeedDemoData"),
           let local = try? ModelContainer(
               for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
               configurations: ModelConfiguration(cloudKitDatabase: .none)
           ) {
            return local
        }
        #endif
        do {
            appLog("🔄 Creating CloudKit model container...")
            let config = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.traininglab")
            )
            let container = try ModelContainer(
                for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
                configurations: config
            )
            appLog("✅ CloudKit model container created successfully")
            return container
        } catch {
            appLog("❌ CloudKit failed (\(error)), creating local container...")
            do {
                // `.none` explicitly: the default (`.automatic`) picks up the
                // iCloud container from the entitlements and retries CloudKit.
                let localConfig = ModelConfiguration(cloudKitDatabase: .none)
                let localContainer = try ModelContainer(
                    for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
                    configurations: localConfig
                )
                appLog("✅ Local model container created successfully")
                return localContainer
            } catch {
                appLog("❌ Local container failed (\(error)), falling back to in-memory store")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                    isUsingTemporaryStore = true
                    return try ModelContainer(
                        for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
                        configurations: memoryConfig
                    )
                } catch {
                    fatalError("Cannot create any model container: \(error)")
                }
            }
        }
    }()
    
    init() {
        // Register transformers BEFORE any SwiftData operations
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        
        appLog("✅ Value transformers registered")

        // Seeding, migrations and duplicate cleanup run here, before any view
        // exists: they delete records, and a view that already fetched one of
        // them crashes SwiftData on its next read. (This used to run from
        // TabBarView.onAppear, after the tabs had already queried.)
        firstLaunch(modelContext: Self.sharedContainer.mainContext)
        #if DEBUG
        DemoData.seedIfRequested(into: Self.sharedContainer.mainContext)
        #endif
        Theme.applyNavigationBarFonts(.current)
        _showTemporaryStoreAlert = State(initialValue: Self.isUsingTemporaryStore)

        // Create all managers as proper single instances
        let hkManager = HealthKitManager()
        let observer = iOSWorkoutObserver()
        _healthKitManager = StateObject(wrappedValue: hkManager)
        _workoutObserver = StateObject(wrappedValue: observer)
        _activityManager = StateObject(wrappedValue: ActivityManager())
        _syncManager = StateObject(wrappedValue: WorkoutSyncManager(healthKitManager: hkManager))
        
        // Configure managers with the shared container's main context.
        // Synchronously (App.init runs on the main actor): from a Task, a watch
        // workout ending right at launch could reach the observer before it
        // had a context, and was then dropped instead of saved.
        ExerciseItemManager.shared.configure(with: Self.sharedContainer.mainContext)
        WorkoutItemManager.shared.configure(with: Self.sharedContainer.mainContext)
        PlanItemManager.shared.configure(modelContext: Self.sharedContainer.mainContext)
        observer.configure(modelContext: Self.sharedContainer.mainContext)
        appLog("✅ Item managers configured")

        // Workouts other apps save to HealthKit count toward weekly goals; this
        // keeps the widget and reminders current when one arrives in the
        // background.
        HealthGoalObserver.start(container: Self.sharedContainer)
    }
    
    var body: some Scene {
        WindowGroup {
            TabBarView()
                .modelContainer(Self.sharedContainer)
                .environmentObject(healthKitManager)
                .environmentObject(workoutObserver)
                .environmentObject(activityManager)
                .environmentObject(syncManager)
                .alert(
                    NSLocalizedString("Your data couldn't be loaded", comment: "Alert title: persistent store failed to open"),
                    isPresented: $showTemporaryStoreAlert
                ) {
                    Button(NSLocalizedString("OK", comment: "Alert dismiss"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("TrainingLab is running without saving. Anything you add now is lost when the app closes. Restart the app or free up storage, then try again.", comment: "Alert message: persistent store failed to open"))
                }
                .task {
                    // Without this, HKHealthStore.startWatchApp(toHandle:) throws
                    // "not authorized" on the very first run because HK auth was
                    // never requested on iOS — it used to only happen from the
                    // Settings screen.
                    // UI tests pass -UITestSkipHealthKit: the system sheet can't
                    // be dismissed reliably from XCUITest and covers every screen.
                    #if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("-UITestSkipHealthKit") else { return }
                    #endif
                    // A new install asks on the setup's Health page, with
                    // the reasons next to it.
                    guard !Onboarding.shouldShow else { return }
                    do {
                        try await healthKitManager.requestAuthorization()
                        // On the first launch the observer started in init
                        // ran before access was granted.
                        HealthGoalObserver.start(container: Self.sharedContainer)
                    } catch {
                        appLog("iOS HealthKit authorization failed: \(error)")
                    }
                }
        }
    }
}


// MARK: - Color Extensions
// The chosen style's text colors and accent (see `Theme`), so
// `Color.primary`, `Color.secondary` and `Color.accentColor` use them.
extension Color {
    static var primary: Color { Theme.primaryText }
    static var secondary: Color { Theme.secondaryText }
    static var accentColor: Color { Theme.accent }
}
