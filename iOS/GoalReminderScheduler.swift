//
//  GoalReminderScheduler.swift
//  Workout App (iOS)
//
//  The impure shell around `GoalReminderPlanner`: reads authorization, turns
//  planned reminders into `UNNotificationRequest`s, and keeps the pending set
//  in sync with the user's live progress.
//
//  Kept separate from `NotificationManager` on purpose. That type schedules
//  `Plan` reminders keyed by bare `UUID().uuidString`; everything here is
//  namespaced under `GoalReminderPlanner.idPrefix`, and cancellation is always
//  prefix-filtered, so the two features can never cancel each other.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
final class GoalReminderScheduler: ObservableObject {

    static let shared = GoalReminderScheduler()

    /// Mirrors the system state, for the editor's "notifications are off" row.
    /// Refreshed on every `refresh(...)` — never trusted from cache.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Foregrounding, a finished workout and For You's `load()` can all land
    /// within the same second. Serializing keeps them from interleaving a
    /// cancel with an add.
    private var refreshTask: Task<Void, Never>?

    private init() {}

    // MARK: - Authorization

    @discardableResult
    func refreshAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        return settings.authorizationStatus
    }

    /// Asks the system, but only when it will actually show a prompt. Once
    /// denied, iOS never shows it again — the editor links to Settings instead.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                // Matches what the plan-reminder flow already does in AddPlans.
                SettingsManager.shared.notifications = true
            }
            return granted
        } catch {
            appLog("Goal reminders: authorization request failed: \(error)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    // MARK: - Scheduling

    /// Convenience for call sites that have a context but no history in hand
    /// (workout-finish paths, scene activation, HealthKit background updates).
    func refresh(context: ModelContext) async {
        let history: [FinishedWorkout]
        do {
            history = try context.fetch(FetchDescriptor<FinishedWorkout>())
        } catch {
            appLog("Goal reminders: could not fetch history: \(error)")
            return
        }
        let external = await externalWorkoutsThisWeek()
        await refresh(goals: SettingsManager.shared.weeklyGoals, history: history, external: external)
    }

    /// `external`: other apps' HealthKit workouts this week
    /// (`externalWorkoutsThisWeek()`), which count toward goals too.
    func refresh(goals: [WeeklyGoal], history: [FinishedWorkout], external: [ExternalWorkout]) async {
        // Every path that changes goal progress funnels through here, so the
        // widget's snapshot is kept current from the same place.
        WeeklyGoalsWidgetSync.publish(goals: goals, history: history, external: external)
        await refreshTask?.value
        let task = Task { await performRefresh(goals: goals, history: history, external: external) }
        refreshTask = task
        await task.value
    }

    /// Removes every pending goal reminder and schedules nothing. Used by the
    /// master switch in Settings.
    func cancelAll() async {
        await refreshTask?.value
        await removePendingGoalReminders()
    }

    private func performRefresh(goals: [WeeklyGoal], history: [FinishedWorkout], external: [ExternalWorkout]) async {
        await removePendingGoalReminders()

        // The Settings toggle is the master switch, but it is *not* a proxy
        // for authorization — `AddPlans` sets it true on grant and nothing
        // ever sets it back when the user revokes access in iOS Settings. So
        // the live system status is checked every time.
        guard SettingsManager.shared.notifications else { return }

        let status = await refreshAuthorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let hour = SettingsManager.shared.goalReminderHour
            ?? GoalReminderPlanner.inferredHour(history: history)
        let minute = SettingsManager.shared.goalReminderMinute

        let planned = GoalReminderPlanner.plan(goals: goals,
                                               history: history,
                                               external: external,
                                               hour: hour,
                                               minute: minute)

        let center = UNUserNotificationCenter.current()
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            // Groups goal nudges together in Notification Centre and keeps
            // them from interleaving with plan reminders.
            content.threadIdentifier = "weeklyGoals"
            content.userInfo = ["kind": reminder.kind.rawValue]

            // `timeZone` and `calendar` are deliberately left unset so the
            // trigger resolves against the device's *current* calendar at fire
            // time. Pinning a captured zone here would drag the reminder along
            // when the user travels.
            let components: DateComponents
            if reminder.repeats {
                components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: reminder.fireDate)
            } else {
                components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: reminder.repeats)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                appLog("Goal reminders: could not schedule \(reminder.id): \(error)")
            }
        }

        appLog("Goal reminders: scheduled \(planned.count) — \(planned.map(\.kind.rawValue).joined(separator: ", "))")
    }

    /// Prefix-filtered on purpose. `removeAllPendingNotificationRequests()`
    /// would silently wipe every reminder in `Plan.notificationIDs`, which the
    /// app has no way to rebuild.
    private func removePendingGoalReminders() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(GoalReminderPlanner.idPrefix) }
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
