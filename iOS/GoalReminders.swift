//
//  GoalReminders.swift
//  Workout App (iOS)
//
//  Adaptive reminders for the weekly training goals in `WeeklyGoals.swift`.
//
//  The rule this file encodes: only nudge on the day where skipping *another*
//  day would make the week's goal unreachable. A user who is ahead of pace
//  hears nothing, and a user who has already met the week hears nothing at
//  all. That is deliberately different from `NotificationManager`'s existing
//  plan reminders, which fire on fixed weekdays regardless of progress.
//
//  Everything here is a pure function over values — no UserNotifications
//  import — so the rules can be unit-tested the same way `completedThisWeek`
//  is, without a notification center or a simulator.
//

import Foundation

// MARK: - Planned reminder

/// One reminder the scheduler wants pending. Turned into a
/// `UNNotificationRequest` by `GoalReminderScheduler`.
struct PlannedReminder: Equatable, Identifiable {

    enum Kind: String {
        /// Fired on the last day the user can still skip and make the goal.
        case pace
        /// Fired on the final day of the week while anything is still open.
        case lastChance
        /// Repeating kickoff on the first weekday. Also the week-rollover
        /// mechanism — see `GoalReminderPlanner.plan(...)`.
        case weekStart
    }

    let kind: Kind
    let fireDate: Date
    /// Only `weekStart` repeats; the other two are recomputed on every
    /// app foreground and every finished workout.
    let repeats: Bool
    let title: String
    let body: String

    /// Namespaced so cancelling goal reminders never touches the bare
    /// `UUID().uuidString` identifiers used by `Plan.notificationIDs`.
    var id: String { GoalReminderPlanner.idPrefix + kind.rawValue }
}

// MARK: - Planner

enum GoalReminderPlanner {

    /// Every identifier this feature owns starts with this. Cancellation is
    /// prefix-filtered so plan reminders survive untouched.
    static let idPrefix = "goalreminder."

    /// Fallback reminder hour when there isn't enough history to infer one.
    static let defaultHour = 18

    /// Earliest / latest hour an inferred reminder may land on, so a history
    /// of 5 a.m. runs never produces a 4 a.m. notification.
    static let earliestHour = 7
    static let latestHour = 21

    /// Reminders to have pending, given the user's goals and their history.
    ///
    /// - Parameters:
    ///   - external: other apps' HealthKit workouts this week, counted too.
    ///   - hour/minute: the time of day reminders fire, either the user's
    ///     override or `inferredHour(history:)`.
    ///   - now: injectable for tests.
    ///
    /// Returns an empty array when there are no goals at all — a user who
    /// hasn't opted in should never hear from this feature.
    static func plan(goals: [WeeklyGoal],
                     history: [FinishedWorkout],
                     external: [ExternalWorkout] = [],
                     now: Date = Date(),
                     hour: Int,
                     minute: Int = 0,
                     calendar: Calendar = .current) -> [PlannedReminder] {

        // A goal stepped back down to 0 is a deleted goal, not a zero target.
        let active = goals.filter { $0.targetPerWeek > 0 }
        guard !active.isEmpty,
              let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        let hour = min(max(hour, 0), 23)
        let minute = min(max(minute, 0), 59)

        let shortfalls = active.map { goal in
            Shortfall(category: goal.category,
                      completed: completedThisWeek(goal.category, history: history, external: external,
                                                   now: now, calendar: calendar),
                      target: goal.targetPerWeek)
        }
        let remaining = shortfalls.reduce(0) { $0 + $1.remaining }

        // The weekly kickoff repeats forever. Besides opening the new week
        // with the user's targets, it guarantees the app is prompted open at
        // least once a week — which is how the one-shot reminders below get
        // recomputed at all, since iOS gives this app no scheduled background
        // execution (only a wake-up when HealthKit gets a new workout).
        //
        // Its copy is deliberately progress-agnostic: a repeating trigger's
        // content is frozen when it's added, and iOS offers no delivery-time
        // hook for local notifications, so it can never quote a live count.
        // That's fine here — it fires at the start of the week, when nothing
        // has been done yet by definition.
        var reminders = [weekStartReminder(goals: active,
                                           hour: hour,
                                           minute: minute,
                                           calendar: calendar,
                                           now: now)]

        // Week already met — stay silent for the rest of it.
        guard remaining > 0 else { return reminders }

        let slots = remainingSlots(in: week, now: now, hour: hour, minute: minute, calendar: calendar)
        guard let lastSlot = slots.last else { return reminders }

        // `slack` is how many of the remaining days the user can still skip
        // and still finish the week. When it runs out, skipping costs them the
        // goal — that is the only day worth interrupting them on.
        let slack = slots.count - remaining
        let paceIndex = max(0, slack)

        // `paceIndex == slots.count - 1` means the pace day *is* the last day,
        // which `lastChance` already covers.
        if paceIndex < slots.count - 1 {
            let slot = slots[paceIndex]
            let daysLeftAtFire = slots.count - paceIndex
            // If the pace nudge would land on the same weekday and time as the
            // repeating kickoff, the kickoff already covers it.
            if calendar.component(.weekday, from: slot) != calendar.firstWeekday {
                reminders.append(PlannedReminder(
                    kind: .pace,
                    fireDate: slot,
                    repeats: false,
                    title: NSLocalizedString("Cutting it close", comment: "Goal reminder title: behind pace"),
                    body: String(format: NSLocalizedString("%1$@ — only %2$d days left. Fit one in today to stay on track.",
                                                           comment: "Goal reminder body: behind pace"),
                                 progressSummary(shortfalls), daysLeftAtFire)))
            }
        }

        reminders.append(PlannedReminder(
            kind: .lastChance,
            fireDate: lastSlot,
            repeats: false,
            title: NSLocalizedString("Last chance this week", comment: "Goal reminder title: final day"),
            body: String(format: NSLocalizedString("%1$@ — get one in today and the week still counts.",
                                                   comment: "Goal reminder body: final day"),
                         progressSummary(shortfalls))))

        return reminders
    }

    // MARK: Preferred hour

    /// The hour of day to remind at, inferred from when this user actually
    /// trains: the peak of a circular 3-hour window over recent start times,
    /// shifted an hour earlier so the nudge lands *before* their usual slot
    /// rather than during it, then clamped to waking hours.
    ///
    /// A plain mean would be wrong — 23:00 and 01:00 average to midday — and a
    /// plain median collapses a bimodal morning/evening history onto whichever
    /// side happens to hold the middle sample. Falls back to `defaultHour`
    /// until there's enough history to mean anything.
    static func inferredHour(history: [FinishedWorkout],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        let hours = history
            .filter { $0.startDate > cutoff && $0.startDate <= now }
            .sorted { $0.endDate > $1.endDate }
            .prefix(20)
            .map { calendar.component(.hour, from: $0.startDate) }

        guard hours.count >= 5, let peak = peakHour(hours: Array(hours)) else { return defaultHour }
        return min(max(peak - 1, earliestHour), latestHour)
    }

    /// The hour at the centre of the busiest 3-hour window, wrapping around
    /// midnight. Ties break toward the later hour — evening sessions are the
    /// ones people skip and need reminding about. `nil` for empty input.
    static func peakHour(hours: [Int]) -> Int? {
        guard !hours.isEmpty else { return nil }
        var best: (hour: Int, count: Int)?
        for candidate in 0...23 {
            let window: Set<Int> = [(candidate + 23) % 24, candidate, (candidate + 1) % 24]
            let count = hours.filter { window.contains($0) }.count
            if let current = best, count < current.count { continue }
            best = (candidate, count)
        }
        return best?.hour
    }

    // MARK: Helpers

    /// One category's standing this week.
    struct Shortfall: Equatable {
        let category: GoalCategory
        let completed: Int
        let target: Int
        var remaining: Int { max(0, target - completed) }
    }

    /// "Gym 0/2, Running 1/2" — only the categories still open. The `n/target`
    /// form deliberately sidesteps singular/plural rules in both en and de.
    ///
    /// Composed rather than looked up: the category name is already localized
    /// and the rest is numerals, so there is nothing here to translate. (A
    /// catalog key of pure format specifiers also fails the build — Xcode
    /// can't derive a Swift symbol from one.)
    static func progressSummary(_ shortfalls: [Shortfall]) -> String {
        shortfalls
            .filter { $0.remaining > 0 }
            .map { "\($0.category.displayName) \($0.completed)/\($0.target)" }
            .joined(separator: ", ")
    }

    /// "Gym 2×/week, Running 2×/week". Reuses the `%d×/week` key the goals
    /// editor already ships translated.
    static func targetSummary(_ goals: [WeeklyGoal]) -> String {
        goals
            .filter { $0.targetPerWeek > 0 }
            .map { goal in
                let count = String(format: NSLocalizedString("%d×/week", comment: "Weekly goal stepper value"),
                                   goal.targetPerWeek)
                return "\(goal.category.displayName) \(count)"
            }
            .joined(separator: ", ")
    }

    private static func weekStartReminder(goals: [WeeklyGoal],
                                          hour: Int,
                                          minute: Int,
                                          calendar: Calendar,
                                          now: Date) -> PlannedReminder {
        // The fire date is only a representative next occurrence — the
        // scheduler turns this into a repeating weekday + time trigger.
        let components = DateComponents(hour: hour, minute: minute, weekday: calendar.firstWeekday)
        let representative = calendar.nextDate(after: now,
                                               matching: components,
                                               matchingPolicy: .nextTime) ?? now

        return PlannedReminder(
            kind: .weekStart,
            fireDate: representative,
            repeats: true,
            title: NSLocalizedString("New week, fresh goals", comment: "Goal reminder title: week start"),
            body: String(format: NSLocalizedString("%@ — let's get the first one done.",
                                                   comment: "Goal reminder body: week start"),
                         targetSummary(goals)))
    }

    /// Every remaining `hour:minute` slot in `week` that is still in the
    /// future, earliest first. Today counts only if its slot hasn't passed.
    ///
    /// Built with calendar arithmetic rather than `+ 86400` so a week
    /// containing a DST transition still lands every reminder on `hour`.
    private static func remainingSlots(in week: DateInterval,
                                       now: Date,
                                       hour: Int,
                                       minute: Int,
                                       calendar: Calendar) -> [Date] {
        let lastDay = calendar.startOfDay(for: week.end.addingTimeInterval(-1))
        var day = calendar.startOfDay(for: max(now, week.start))
        var slots: [Date] = []

        while day <= lastDay {
            if let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               slot > now {
                slots.append(slot)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return slots
    }
}
