//
//  Workout_Watch_AppTests.swift
//  Workout Watch AppTests
//
//  Unit tests for the watch app. Uses Swift Testing per the project's
//  testing convention. Covers the WatchConnectivity message-classification
//  logic, all three sync payload types (WorkoutState / HealthMetrics /
//  TimerState), the lightweight watch-side value types, and the public
//  state of `WatchWorkoutManager` and `WorkoutSyncManager` before any
//  HealthKit interaction.
//

import Testing
import Foundation
@testable import Workout_Watch_App

// MARK: - WatchMessage delivery classification

@Suite("WatchMessage delivery classification")
struct WatchMessageDeliveryTests {

    /// Discrete state events must round-trip even if the other device is
    /// asleep. They ride `transferUserInfo` in addition to the immediate
    /// sendMessage / applicationContext path.
    @Test func discreteEventsRequireGuaranteedDelivery() {
        let discrete: [WatchMessage] = [
            .workoutStart, .workoutPause, .workoutResume, .workoutEnd,
            .exerciseStart, .exerciseComplete,
            // Without it, the iPhone's pause wouldn't reach a session it took over.
            .workoutJoin
        ]
        for message in discrete {
            #expect(
                message.requiresGuaranteedDelivery,
                "\(message.rawValue) should be guaranteed-delivered"
            )
        }
    }

    /// Continuous / per-tick updates must NOT enqueue a persistent transfer
    /// each time — that would flood `transferUserInfo` and backlog the
    /// guaranteed-delivery queue (an earlier regression where the per-second
    /// `.workoutState` push was queued every tick).
    @Test func continuousEventsDoNotRequireGuaranteedDelivery() {
        let continuous: [WatchMessage] = [
            .workoutState, .timerSync, .healthKitUpdate,
            .heartRateUpdate, .caloriesUpdate, .requestSync,
            .authorizationStatus,
            // Only meaningful while both devices are live; a queued copy
            // arriving later would replay a stale skip.
            .exerciseControl,
            // Queues its own transfer and cancels older ones
            // (`sendWorkoutLibrary`), so stale lists don't pile up.
            .workoutLibrary
        ]
        for message in continuous {
            #expect(
                !message.requiresGuaranteedDelivery,
                "\(message.rawValue) should NOT be guaranteed-delivered"
            )
        }
    }

    /// The set of cases the receiver decodes from `messageType` must stay
    /// stable — adding/removing a case without updating both sides is the
    /// fastest way to silently lose a message. `WatchMessage.allCases`
    /// catches that immediately.
    @Test func messageEnumExposesEveryWireValue() {
        // If a future PR adds a new case, this assertion forces the author
        // to think about whether it needs guaranteed delivery and to add
        // it to the corresponding delivery-classification test above.
        let allRaw = WatchMessage.allCases.map(\.rawValue)
        #expect(allRaw.count == 16, "Wire-message count drifted — update tests")
        // Sanity: all raw values are non-empty (would break message dispatch).
        for raw in allRaw {
            #expect(!raw.isEmpty)
        }
    }
}

// MARK: - WorkoutState Codable

@Suite("WorkoutState Codable round-trip")
struct WorkoutStateCodableTests {

    /// The whole sync subsystem depends on `WorkoutState` encoding and
    /// decoding cleanly across iOS ↔ watchOS. If anyone ever forgets to
    /// thread a new field through the initializer, this test catches it
    /// before it manifests as silently-dropped sync data on device.
    @Test func roundTripsAllFields() throws {
        let original = WorkoutState(
            workoutId: "workout-id-1",
            workoutName: "Upper Body",
            isActive: true,
            isPaused: false,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            currentExerciseId: "exercise-id-7",
            currentExerciseName: "Bench Press",
            currentExerciseIndex: 3,
            totalExercises: 6,
            elapsedTime: 432,
            estimatedCalories: 215.5,
            exerciseStartTime: Date(timeIntervalSince1970: 1_700_000_300),
            exerciseElapsedTime: 90
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: data)

        #expect(decoded.workoutId == original.workoutId)
        #expect(decoded.workoutName == original.workoutName)
        #expect(decoded.isActive == original.isActive)
        #expect(decoded.isPaused == original.isPaused)
        #expect(decoded.startTime == original.startTime)
        #expect(decoded.currentExerciseId == original.currentExerciseId)
        #expect(decoded.currentExerciseName == original.currentExerciseName)
        #expect(decoded.currentExerciseIndex == original.currentExerciseIndex)
        #expect(decoded.totalExercises == original.totalExercises)
        #expect(decoded.elapsedTime == original.elapsedTime)
        #expect(decoded.estimatedCalories == original.estimatedCalories)
        #expect(decoded.exerciseStartTime == original.exerciseStartTime)
        #expect(decoded.exerciseElapsedTime == original.exerciseElapsedTime)
    }

    /// Defaults must produce an "empty / inactive" state — the iOS observer
    /// uses this on workout end to signal teardown to the watch.
    @Test func defaultInitializerIsInactiveAndEmpty() {
        let state = WorkoutState()
        #expect(state.isActive == false)
        #expect(state.isPaused == false)
        #expect(state.workoutId.isEmpty)
        #expect(state.workoutName.isEmpty)
        #expect(state.currentExerciseId == nil)
        #expect(state.currentExerciseName == nil)
        #expect(state.currentExerciseIndex == 0)
        #expect(state.totalExercises == 0)
        #expect(state.elapsedTime == 0)
        #expect(state.estimatedCalories == nil)
    }

    /// A `nil` exercise name must survive Codable so the watch's
    /// "fall back to local SwiftData lookup" branch keeps working. If
    /// JSONEncoder ever started writing it as `""` we'd silently start
    /// dropping the fallback.
    @Test func nilExerciseNameRoundTripsAsNil() throws {
        let original = WorkoutState(
            workoutId: "id",
            workoutName: "Workout",
            isActive: true,
            currentExerciseId: "x",
            currentExerciseName: nil,
            currentExerciseIndex: 0,
            totalExercises: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: data)
        #expect(decoded.currentExerciseName == nil)
    }
}

// MARK: - HealthMetrics Codable

@Suite("HealthMetrics Codable round-trip")
struct HealthMetricsCodableTests {

    /// Heart rate / calorie updates from the watch ride through this
    /// payload. Anything that breaks Codable here results in metrics
    /// silently failing to reach iOS.
    @Test func roundTripsAllFields() throws {
        let original = HealthMetrics(
            heartRate: 142,
            activeCalories: 88,
            totalCalories: 120,
            distance: 1500,
            steps: 1800,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthMetrics.self, from: data)

        #expect(decoded.heartRate == original.heartRate)
        #expect(decoded.activeCalories == original.activeCalories)
        #expect(decoded.totalCalories == original.totalCalories)
        #expect(decoded.distance == original.distance)
        #expect(decoded.steps == original.steps)
        #expect(decoded.timestamp == original.timestamp)
    }

    /// The default initializer must produce a fully-nil-metric payload
    /// (used when the watch has no live HK session yet).
    @Test func defaultInitializerHasNoMetrics() {
        let metrics = HealthMetrics()
        #expect(metrics.heartRate == nil)
        #expect(metrics.activeCalories == nil)
        #expect(metrics.totalCalories == nil)
        #expect(metrics.distance == nil)
        #expect(metrics.steps == nil)
    }
}

// MARK: - TimerState Codable

@Suite("TimerState Codable round-trip")
struct TimerStateCodableTests {

    /// `TimerState` rides `.timerSync` between iOS and watch. The receiver
    /// decodes the same fields the sender wrote — silent drops here cause
    /// exercise-step timing to drift.
    @Test func roundTripsAllFields() throws {
        let original = TimerState(
            isRunning: true,
            startTime: Date(timeIntervalSince1970: 1_700_001_000),
            elapsedTime: 47,
            totalDuration: 60,
            exerciseId: "exercise-id"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerState.self, from: data)

        #expect(decoded.isRunning == original.isRunning)
        #expect(decoded.startTime == original.startTime)
        #expect(decoded.elapsedTime == original.elapsedTime)
        #expect(decoded.totalDuration == original.totalDuration)
        #expect(decoded.exerciseId == original.exerciseId)
    }

    @Test func defaultInitializerIsStopped() {
        let state = TimerState()
        #expect(state.isRunning == false)
        #expect(state.startTime == nil)
        #expect(state.elapsedTime == 0)
        #expect(state.totalDuration == nil)
        #expect(state.exerciseId == nil)
    }
}

// MARK: - Watch UI value types

@Suite("Watch lightweight value types")
struct WatchValueTypeTests {

    @Test func watchWorkoutInfoDefaultsToZeroAndUnpaused() {
        let info = WatchWorkoutInfo()
        #expect(info.elapsedTime == 0)
        #expect(info.isPaused == false)
    }

    @Test func watchMetricsDefaultsToNil() {
        let metrics = WatchMetrics()
        #expect(metrics.heartRate == nil)
        #expect(metrics.activeEnergyBurned == nil)
        #expect(metrics.distance == nil)
    }
}

// MARK: - WatchWorkoutManager singleton + initial state

@Suite("WatchWorkoutManager singleton and initial state")
@MainActor
struct WatchWorkoutManagerTests {

    /// `static let shared` must return the same instance every time —
    /// the `WatchAppDelegate.handle(_:)` callback and the SwiftUI
    /// `@StateObject` rely on this.
    @Test func sharedReturnsSameInstance() {
        let a = WatchWorkoutManager.shared
        let b = WatchWorkoutManager.shared
        #expect(a === b)
    }

    /// Before any workout starts the manager should report inactive state
    /// and no error. The UI relies on these defaults — for example
    /// `ContentView.hasActiveWorkout` reads `isActive` to decide which
    /// screen to render.
    @Test func initialStateIsClean() {
        let manager = WatchWorkoutManager.shared
        #expect(manager.isActive == false)
        #expect(manager.currentWorkout == nil)
        #expect(manager.lastError == nil)
        #expect(manager.currentMetrics.heartRate == nil)
        #expect(manager.currentMetrics.activeEnergyBurned == nil)
    }
}

// MARK: - WorkoutSyncManager singleton

@Suite("WorkoutSyncManager singleton")
@MainActor
struct WorkoutSyncManagerTests {

    @Test func sharedReturnsSameInstance() {
        let a = WorkoutSyncManager.shared
        let b = WorkoutSyncManager.shared
        #expect(a === b)
    }
}
