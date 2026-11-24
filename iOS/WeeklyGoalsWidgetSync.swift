//
//  WeeklyGoalsWidgetSync.swift
//  Workout App (iOS)
//
//  Keeps the Weekly Goals widget's snapshot (`WeeklyGoalsSnapshot`) in step
//  with the user's goals and history. Driven from
//  `GoalReminderScheduler.refresh(goals:history:external:)`, which runs after
//  every finished workout, goal edit, app activation and new HealthKit workout.
//

import Foundation
import UIKit
import WidgetKit

enum WeeklyGoalsWidgetSync {

    /// The snapshot for `goals` over the calendar week containing `now`,
    /// counted with the same `completedThisWeek` the For You card uses. Names
    /// are resolved here, in the app's language, so the widget only renders.
    static func snapshot(goals: [WeeklyGoal],
                         history: [FinishedWorkout],
                         external: [ExternalWorkout] = [],
                         now: Date = Date(),
                         calendar: Calendar = .current) -> WeeklyGoalsSnapshot {
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        let rows = goals.map { goal in
            WeeklyGoalsSnapshot.Goal(id: goal.id,
                                     title: goal.category.displayName,
                                     symbolName: goal.category.symbolName,
                                     completed: completedThisWeek(goal.category, history: history, external: external,
                                                                  now: now, calendar: calendar),
                                     target: goal.targetPerWeek)
        }
        return WeeklyGoalsSnapshot(goals: rows, weekEnd: weekEnd)
    }

    /// Saves the current snapshot and asks WidgetKit to redraw.
    ///
    /// In the background a redraw comes out of the widget's daily budget, so
    /// it's only asked for when something changed. In the foreground it's
    /// free and asked for every time: a request made in the background can be
    /// deferred or dropped, and with "only when changed" the widget would then
    /// have stayed on the old numbers until the week ended, because every
    /// later refresh found the saved snapshot already current.
    @MainActor
    static func publish(goals: [WeeklyGoal], history: [FinishedWorkout],
                        external: [ExternalWorkout] = [], now: Date = Date()) {
        let current = snapshot(goals: goals, history: history, external: external, now: now)
        let changed = current != WeeklyGoalsSnapshot.load()
        if changed { current.save() }
        if changed || UIApplication.shared.applicationState == .active {
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyGoalsSnapshot.widgetKind)
        }
    }
}
