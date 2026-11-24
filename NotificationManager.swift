//
//  NotificationManager.swift
//  Workout App
//
//  Created by Justus Besser on 25.03.24.
//

import Foundation
import SwiftData
import UserNotifications

/// Plan reminders.
///
/// Plans sync through CloudKit but pending notifications are per device, so
/// reminders are never tracked through IDs stored on the plan. Instead each
/// device rebuilds its own set from the synced plans (`refreshPlanReminders`),
/// with identifiers derived from the plan: a plan edited or deleted on one
/// device then updates the reminders on every device the next time it opens.
@MainActor
class NotificationManager {

    static let shared = NotificationManager()

    static let planIDPrefix = "planreminder."

    // MARK: - Rebuild

    // Main actor: both read SwiftData models from the main context. Without
    // it these nonisolated async functions run on a background executor, and
    // touching the main context there corrupted memory (crashes in unrelated
    // views right after).
    @MainActor
    func refreshPlanReminders(context: ModelContext) async {
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        await refreshPlanReminders(plans: plans)
    }

    /// Replaces this device's plan reminders with the ones `plans` ask for.
    @MainActor
    func refreshPlanReminders(plans: [Plan]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        // Earlier versions used bare UUIDs for plan reminders; goal reminders
        // carry their own prefix, so both old and new plan IDs are recognizable.
        let stale = pending.map(\.identifier).filter {
            $0.hasPrefix(Self.planIDPrefix) || UUID(uuidString: $0) != nil
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        // Finished or retired plans don't need reminders any more.
        for plan in plans where !plan.isHidden && !Self.isFinished(plan) {
            for request in requests(for: plan) {
                do {
                    try await center.add(request)
                } catch {
                    appLog("Error scheduling plan reminder: \(error)")
                }
            }
        }
    }

    /// Removes a plan's reminders on this device right away, before the plan
    /// itself is deleted. Other devices drop theirs on their next refresh.
    func cancelReminders(for plan: Plan) {
        let ids = (1...7).map { reminderID(plan: plan, suffix: String($0)) }
            + [reminderID(plan: plan, suffix: "next")]
            + plan.notificationIDs
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func isFinished(_ plan: Plan) -> Bool {
        !plan.workoutsSequenceIDs.isEmpty
            && plan.firstIncompleteWorkoutID() == nil
    }

    // MARK: - Requests

    private func requests(for plan: Plan) -> [UNNotificationRequest] {
        switch plan.intervalType {
        case "fixedDates":
            return plan.interval.compactMap { day, time in
                guard let weekday = Self.weekdayNumber(for: day) else {
                    appLog("Plan reminder: unknown weekday '\(day)'")
                    return nil
                }
                let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
                var components = DateComponents()
                components.weekday = weekday
                components.hour = clock.hour
                components.minute = clock.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                return UNNotificationRequest(identifier: reminderID(plan: plan, suffix: String(weekday)),
                                             content: content(), trigger: trigger)
            }
        case "setAfterFinishedWorkout":
            guard let date = plan.interval["nextDate"], date > .now else { return [] }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .calendar, .timeZone], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return [UNNotificationRequest(identifier: reminderID(plan: plan, suffix: "next"),
                                          content: content(), trigger: trigger)]
        default:
            return []
        }
    }

    private func reminderID(plan: Plan, suffix: String) -> String {
        "\(Self.planIDPrefix)\(plan.id).\(suffix)"
    }

    private func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Reminder")
        content.body = String(localized: "Don't forget to work out!")
        content.sound = .default
        return content
    }

    // MARK: - Weekday keys

    /// `Calendar` weekday number (1 = Sunday) for a stored weekday key.
    ///
    /// Plans store the weekday under its translated name ("Monday", "Montag"),
    /// in whatever language the app ran in when the plan was set up. Matching
    /// only the current calendar's symbols broke reminders after a language
    /// change or on a synced device in another language.
    nonisolated static func weekdayNumber(for name: String) -> Int? {
        let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        var candidates = [Calendar.current.weekdaySymbols, english]
        for identifier in ["en", "de"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: identifier)
            candidates.append(calendar.weekdaySymbols)
        }
        candidates.append(english.map { NSLocalizedString($0, comment: "") })
        for symbols in candidates {
            if let index = symbols.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return index + 1
            }
        }
        return nil
    }
}
