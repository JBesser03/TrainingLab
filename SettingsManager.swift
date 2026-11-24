//
//  SettingsManager.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 11.03.23.
//

import Foundation
import WidgetKit
import Combine
import UIKit

/// A lightweight, persisted snapshot of an in-progress workout so it can be
/// resumed after the app is backgrounded or killed. Stored as JSON in
/// UserDefaults (not SwiftData/CloudKit) — it's transient, device-local state.
struct ResumeSnapshot: Codable, Equatable {
    var workoutID: String
    var workoutName: String
    var exerciseIndex: Int
    var setIndex: Int
    var setCount: Int
    var startDate: Date
    var loggedWeights: [String: [Double]]
    var loggedReps: [String: [Int]]
    // The session's own exercise list and plans, and what else was logged.
    // Optional so snapshots saved before these existed still decode.
    var exerciseIDs: [String]?
    var sessionPlans: [String: ExercisePlan]?
    var completedSets: [String: Int]?
    var skippedExerciseIDs: Set<String>?
    var loggedDetails: [String: [SetDetail]]?
    var exerciseNotes: [String: String]?
    // Finished pauses, and when a pause still running began, so a resumed
    // session still leaves the paused time out of Health and its energy.
    var pauseIntervals: [DateInterval]?
    var pausedAt: Date?
}

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let userDefaults = UserDefaults.standard
    
    /// Loads each value into the property's storage, not through its setter:
    /// the setter's `didSet` writes it back to UserDefaults, which stored a
    /// value passed as a launch argument (as UI tests do) for good.
    private init() {
        if let data = userDefaults.data(forKey: "resumeSnapshot") {
            _resumeSnapshot = Published(wrappedValue: try? JSONDecoder().decode(ResumeSnapshot.self, from: data))
        }
        _notifications = Published(wrappedValue: userDefaults.bool(forKey: "notifications"))
        // firstLaunch() writes the defaults after this singleton has already
        // loaded, so register the fallback here or the first session gets 0.
        userDefaults.register(defaults: ["pauseTime": 5])
        _pauseTime = Published(wrappedValue: userDefaults.integer(forKey: "pauseTime"))
        _tryEnableHealthKit = Published(wrappedValue: userDefaults.bool(forKey: "tryEnableHealthKit"))
        _appIconMatchesStyle = Published(wrappedValue: userDefaults.bool(forKey: "appIconMatchesStyle"))
        _accessHealthKitSucceeded = Published(wrappedValue: userDefaults.bool(forKey: "accessHealthKitSucceeded"))
        _appleWatchUsage = Published(wrappedValue: userDefaults.bool(forKey: "appleWatchUsage"))
        _weightUnit = Published(wrappedValue: WeightUnit(rawValue: userDefaults.string(forKey: "weightUnit") ?? "") ?? .kilograms)
        _restTimerSeconds = Published(wrappedValue: userDefaults.integer(forKey: "restTimerSeconds"))
        _barbellWeightKg = Published(wrappedValue: userDefaults.object(forKey: "barbellWeightKg") as? Double ?? 20)
        _bodyWeightKg = Published(wrappedValue: userDefaults.object(forKey: "bodyWeightKg") as? Double)

        if let data = userDefaults.data(forKey: "weeklyGoals"),
           let decoded = try? JSONDecoder().decode([WeeklyGoal].self, from: data) {
            _weeklyGoals = Published(wrappedValue: decoded)
        }

        // `object(forKey:)`, not `integer(forKey:)` — the latter returns 0 for
        // a missing key, and 0 (midnight) is a perfectly valid hour. nil has
        // to stay distinguishable because it means "infer from my history".
        _goalReminderHour = Published(wrappedValue: userDefaults.object(forKey: "goalReminderHour") as? Int)
        _goalReminderMinute = Published(wrappedValue: userDefaults.integer(forKey: "goalReminderMinute"))

        if let raw = userDefaults.array(forKey: "availableGymEquipment") as? [Int] {
            _availableGymEquipment = Published(wrappedValue: Set(raw))
        } else {
            // Default to a sensible "well-equipped commercial gym" set so the user
            // can generate a plan without configuring anything first.
            _availableGymEquipment = Published(wrappedValue: Set(Equipment.allCases
                .filter { $0 != .other }
                .map { $0.rawValue }))
        }
    }
    
    @Published var notifications: Bool = false {
        didSet { userDefaults.setValue(notifications, forKey: "notifications") }
    }
    
    @Published var pauseTime: Int = 0 {
        didSet { userDefaults.set(pauseTime, forKey: "pauseTime") }
    }
    
    @Published var tryEnableHealthKit: Bool = false {
        didSet { userDefaults.set(tryEnableHealthKit, forKey: "tryEnableHealthKit") }
    }
    
    @Published var accessHealthKitSucceeded: Bool = false {
        didSet { userDefaults.set(accessHealthKitSucceeded, forKey: "accessHealthKitSucceeded") }
    }
    
    @Published var appleWatchUsage: Bool = false {
        didSet { userDefaults.set(appleWatchUsage, forKey: "appleWatchUsage") }
    }

    /// The Settings toggle, which also remembers that the user decided —
    /// from then on `enableWatchIfInstalled` leaves the setting alone.
    func setAppleWatchUsage(_ isOn: Bool) {
        userDefaults.set(true, forKey: "appleWatchUsageChosen")
        appleWatchUsage = isOn
    }

    /// Turns the watch on once a paired Apple Watch has the app, so nobody
    /// has to find a switch in Settings first. Not if the user turned it off.
    func enableWatchIfInstalled(_ installed: Bool) {
        guard installed, !appleWatchUsage,
              !userDefaults.bool(forKey: "appleWatchUsageChosen") else { return }
        appleWatchUsage = true
    }

    /// The app's style (Settings → Appearance). Kept in the App Group, where
    /// the widget reads it; `AppTheme.current` is the source of truth.
    @Published var appTheme: AppTheme = .current {
        didSet {
            AppTheme.store?.set(appTheme.rawValue, forKey: AppTheme.storageKey)
            AppIconSync.apply(theme: appTheme, enabled: appIconMatchesStyle)
            WidgetCenter.shared.reloadAllTimelines()
            // The accent travels with the watch's workout list.
            WatchConnectivityManager.shared.sendWorkoutLibrary(context: Workout_App.sharedContainer.mainContext)
        }
    }

    /// The home screen icon in the style's colors (Settings → Appearance).
    @Published var appIconMatchesStyle: Bool = false {
        didSet {
            userDefaults.set(appIconMatchesStyle, forKey: "appIconMatchesStyle")
            AppIconSync.apply(theme: appTheme, enabled: appIconMatchesStyle)
        }
    }

    /// How much of the app the style colors (Settings → Appearance). Kept
    /// beside the style in the App Group, where the widget and the Live
    /// Activity read it for their cards and backgrounds.
    @Published var colorIntensity: ColorIntensity = .current {
        didSet {
            AppTheme.store?.set(colorIntensity.rawValue, forKey: ColorIntensity.storageKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Rest between the sets of a strength workout; 0 = no rest timer.
    @Published var restTimerSeconds: Int = 0 {
        didSet { userDefaults.set(restTimerSeconds, forKey: "restTimerSeconds") }
    }

    /// The bar the plate calculator subtracts first.
    @Published var barbellWeightKg: Double = 20 {
        didSet { userDefaults.set(barbellWeightKg, forKey: "barbellWeightKg") }
    }

    /// Body weight typed in Settings, for when Apple Health has none.
    @Published var bodyWeightKg: Double? {
        didSet {
            if let bodyWeightKg {
                userDefaults.set(bodyWeightKg, forKey: "bodyWeightKg")
            } else {
                userDefaults.removeObject(forKey: "bodyWeightKg")
            }
        }
    }

    /// The first-run setup was finished or skipped. Installs from before it
    /// existed never see it (`firstLaunch` only offers it to new ones).
    var showsOnboarding: Bool {
        get { userDefaults.bool(forKey: "showsOnboarding") }
        set { userDefaults.set(newValue, forKey: "showsOnboarding") }
    }

    @Published var availableGymEquipment: Set<Int> = [] {
        didSet { userDefaults.set(Array(availableGymEquipment), forKey: "availableGymEquipment") }
    }

    /// Weekly training-frequency goals per activity (e.g. "Running ×2/week",
    /// "Gym ×2/week") — see `iOS/WeeklyGoals.swift`. Drives the goal-progress
    /// card and per-activity "start now" sessions on For You. An empty array
    /// means the user hasn't set any goals yet.
    @Published var weeklyGoals: [WeeklyGoal] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(weeklyGoals) {
                userDefaults.set(data, forKey: "weeklyGoals")
            }
        }
    }

    /// Hour of day for weekly-goal reminders, or `nil` for "Automatic" — the
    /// hour is then inferred from the user's own training history by
    /// `GoalReminderPlanner.inferredHour`. See `iOS/GoalReminders.swift`.
    @Published var goalReminderHour: Int? {
        didSet {
            if let goalReminderHour {
                userDefaults.set(goalReminderHour, forKey: "goalReminderHour")
            } else {
                userDefaults.removeObject(forKey: "goalReminderHour")
            }
        }
    }

    /// Minute within `goalReminderHour`. Only meaningful alongside an
    /// explicit hour; "Automatic" always lands on the hour.
    @Published var goalReminderMinute: Int = 0 {
        didSet { userDefaults.set(goalReminderMinute, forKey: "goalReminderMinute") }
    }

    /// Preferred unit for entering and displaying exercise weights. Weights are
    /// always stored in kilograms; this only affects the UI.
    @Published var weightUnit: WeightUnit = .kilograms {
        didSet { userDefaults.set(weightUnit.rawValue, forKey: "weightUnit") }
    }

    /// The in-progress workout to offer resuming, or `nil` when none. Persisted
    /// so a workout survives an app background/kill and can be re-entered from
    /// the Resume banner. Cleared when the workout is finished.
    @Published var resumeSnapshot: ResumeSnapshot? {
        didSet {
            if let snapshot = resumeSnapshot,
               let data = try? JSONEncoder().encode(snapshot) {
                userDefaults.set(data, forKey: "resumeSnapshot")
            } else {
                userDefaults.removeObject(forKey: "resumeSnapshot")
            }
        }
    }
}

/// The home screen icon: the style's (`AppIcon-Earth` and so on, Icon
/// Composer files registered as alternate icons) with "App icon in style
/// colors" on, otherwise the primary one (`AppIcon`, warm white, also the App
/// Store's and the watch's). iOS tells the user each time it changes.
@MainActor
enum AppIconSync {
    /// The alternate icon to set, or nil for the primary one.
    static func iconName(for theme: AppTheme, enabled: Bool) -> String? {
        enabled ? "AppIcon-" + theme.rawValue.capitalized : nil
    }

    static func apply(theme: AppTheme, enabled: Bool) {
        #if DEBUG
        // iOS's "You have changed the icon" alert blocks UI tests (and would
        // cover the App Store screenshots), so launches from them keep the icon
        // even if a test turns "App icon in style colors" on.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-UITest") }) { return }
        #endif
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let name = iconName(for: theme, enabled: enabled)
        guard app.alternateIconName != name else { return }
        // The async variant, not the completion handler: UIKit calls that on
        // a background queue, and a closure written here would be main-actor
        // isolated, which Swift 6 traps on.
        Task {
            do { try await app.setAlternateIconName(name) }
            catch { appLog("Couldn't change the app icon: \(error)") }
        }
    }
}
