//
//  WorkoutLiveActivity.swift
//  Workout App
//
//  Shared between the iOS app and the widget extension — the app builds and
//  publishes the state, the widget renders it, and both need the same type
//  definitions. Keep the imports minimal (no SwiftData, no HealthKit, no
//  UIKit): everything here is compiled into the extension too, and the widget
//  has no business carrying the model layer.
//
//  Membership: "WorkoutApp (iOS)" AND "TrainingLabWidget-iOSExtension".
//

import Foundation
import ActivityKit
import AppIntents

// MARK: - Activity attributes

struct WorkoutActivityAttributes: ActivityAttributes {

    /// The parts of the session that change while it runs.
    struct ContentState: Codable, Hashable {
        var currentExerciseName: String
        /// `nil` on the last exercise — the Lock Screen then hides the NEXT row.
        var nextExerciseName: String?
        var exerciseIndex: Int
        var totalExercises: Int
        var setIndex: Int
        var totalSets: Int

        var isResting: Bool
        var isPaused: Bool
        /// Instant the session was paused, or `nil` while running. Feeds
        /// `Text(timerInterval:pauseTime:)` so the elapsed clock freezes
        /// instead of ticking on underneath a "Paused" label.
        var pausedAt: Date?

        /// Anchored *end instant* of the current phase rather than a remaining
        /// duration, because `Text(timerInterval:)` then counts down on its own
        /// without any further ActivityKit updates. This matters more than it
        /// looks: the app's `Timer.publish` stops while backgrounded — which is
        /// exactly when the Live Activity is on screen — so a pushed
        /// "secondsRemaining" would visibly freeze.
        ///
        /// `nil` for a rep-based exercise, which has no countdown at all.
        var phaseEndDate: Date?

        /// True only when tapping "Set done" would actually do something:
        /// `completeRepSet` is a no-op for time-based exercises (they advance
        /// on the timer) and while resting.
        var canCompleteSet: Bool

        /// Sets logged so far in this session, across all exercises.
        var loggedSetCount: Int

        /// SF Symbol for the workout's activity type. Must stay an SF Symbol:
        /// the widget has its own asset catalog and cannot see the app's.
        var symbolName: String
    }

    var workoutName: String
    var startDate: Date
}

// MARK: - Session bridge

/// Lets a Lock Screen button drive `ActiveWorkoutView` without extracting a
/// view model out of that ~1500-line file.
///
/// `ActiveWorkoutView` keeps the entire session in local `@State`, which an
/// intent cannot reach. Instead the view installs its own actions here on
/// appear and clears them when the workout ends, and the intents below call
/// through. Because `LiveActivityIntent.perform()` runs in the *app's*
/// process, the closures it finds are the live ones.
///
/// This type is compiled into the widget too, where nothing ever installs a
/// closure — harmless, and it keeps the intents free of app-only dependencies
/// so they need no compilation-condition tricks.
@MainActor
final class WorkoutLiveSession {

    static let shared = WorkoutLiveSession()

    var onCompleteSet: (() -> Void)?
    var onSkipExercise: (() -> Void)?

    private init() {}

    /// Both are deliberately silent when nothing is installed — that means the
    /// app was terminated while the Live Activity lingered, and resurrecting a
    /// half-restored session would be worse than doing nothing.
    func completeSet() { onCompleteSet?() }
    func skipExercise() { onSkipExercise?() }

    func clear() {
        onCompleteSet = nil
        onSkipExercise = nil
    }
}

// MARK: - Intents

/// `LiveActivityIntent`, not a plain `AppIntent`: that is what makes `perform()`
/// run in the app's process instead of the widget extension's, so it can reach
/// `WorkoutLiveSession`'s installed closures.
struct CompleteSetIntent: LiveActivityIntent {

    static var title: LocalizedStringResource { "Complete set" }
    static var description: IntentDescription {
        IntentDescription("Logs the current set and moves on to the next one.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutLiveSession.shared.completeSet()
        return .result()
    }
}

struct SkipExerciseIntent: LiveActivityIntent {

    static var title: LocalizedStringResource { "Skip exercise" }
    static var description: IntentDescription {
        IntentDescription("Jumps to the next exercise in the workout.")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutLiveSession.shared.skipExercise()
        return .result()
    }
}
