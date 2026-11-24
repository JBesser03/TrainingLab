//
//  WatchConnectivityManager.swift
//  WorkoutApp
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import SwiftUI
import WatchConnectivity
import HealthKit
import Combine
import SwiftData

// MARK: - Message Types and Payloads

/// A WatchConnectivity dictionary handed from WatchConnectivity's queue to the
/// main actor. `@unchecked`: its values are property-list types, and nothing
/// mutates it after WatchConnectivity delivers it (or we build it to send).
struct WCPayload: @unchecked Sendable {
    let dictionary: [String: Any]
    init(_ dictionary: [String: Any]) { self.dictionary = dictionary }
}

/// Types of messages that can be sent between iOS and watchOS
enum WatchMessage: String, CaseIterable {
    case workoutStart = "workout_start"
    case workoutPause = "workout_pause"
    case workoutResume = "workout_resume"
    case workoutEnd = "workout_end"
    case exerciseStart = "exercise_start"
    case exerciseComplete = "exercise_complete"
    case timerSync = "timer_sync"
    case healthKitUpdate = "healthkit_update"
    case workoutState = "workout_state"
    case heartRateUpdate = "heart_rate_update"
    case caloriesUpdate = "calories_update"
    case requestSync = "request_sync"
    case authorizationStatus = "authorization_status"
    /// Watch → iPhone: skip / restart the current exercise. iOS is the
    /// source of truth for the exercise sequence during an iOS-initiated
    /// workout, so the watch proxies the user's intent.
    case exerciseControl = "exercise_control"
    /// iPhone → watch: the `WatchLibrary` the watch lists workouts from.
    case workoutLibrary = "workout_library"
    /// iPhone → watch: the iPhone opened its workout screen for the session
    /// the watch started, and drives it from now on (see `WatchWorkoutManager`).
    case workoutJoin = "workout_join"

    /// Discrete events that must reach the other side even if it's currently
    /// asleep/unreachable — backed up via `transferUserInfo`. Continuous
    /// updates like `.workoutState` / `.timerSync` are excluded because they
    /// fire every second and would flood the persistent transfer queue.
    var requiresGuaranteedDelivery: Bool {
        switch self {
        case .workoutStart, .workoutPause, .workoutResume, .workoutEnd,
             .exerciseStart, .exerciseComplete, .workoutJoin:
            return true
        default:
            return false
        }
    }
}

// MARK: - Remote payloads

/// Watch → iPhone exercise control. iOS owns the exercise sequence; the
/// watch fires one of these to ask iOS to advance or reset the current
/// exercise's countdown.
enum ExerciseControl: String, Codable {
    case skip
    case restart
}

/// Current workout state that can be synchronized between devices
struct WorkoutState: Codable {
    let workoutId: String
    let workoutName: String
    let isActive: Bool
    let isPaused: Bool
    let startTime: Date?
    let currentExerciseId: String?
    /// Display name of the current exercise. Sent directly so the watch
    /// doesn't have to look up the exercise via CloudKit-synced SwiftData
    /// — that lookup returns nil on a fresh install before CloudKit has
    /// finished syncing, which was leaving the watch with no exercise label.
    let currentExerciseName: String?
    let currentExerciseIndex: Int
    let totalExercises: Int
    let elapsedTime: TimeInterval
    let estimatedCalories: Double?
    let exerciseStartTime: Date?
    let exerciseElapsedTime: TimeInterval
    /// HK activity type for the workout (raw value of HKWorkoutActivityType).
    /// Without this, the watch defaults every mirrored session to
    /// `.functionalStrengthTraining` — recording running / cycling /
    /// HIIT workouts with the wrong activity type in HealthKit.
    let workoutActivityType: UInt
    /// HK session location type (raw value of HKWorkoutSessionLocationType).
    /// Indoor vs. outdoor changes calorie / distance accuracy on watchOS.
    let workoutLocationType: Int
    /// `true` while iOS is in the inter-exercise REST period (the blue
    /// rest countdown on the phone). Distinct from `isPaused`, which is a
    /// manual HK session pause. Optional so payloads encoded before this
    /// field existed still decode (synthesized Codable tolerates a missing
    /// optional); read as `?? false`.
    let isResting: Bool?
    /// Seconds of rest remaining when the rest period started. The watch
    /// interpolates this down locally (rest length is fixed), so iOS only
    /// pushes it once at rest-start instead of every tick.
    let restSecondsRemaining: TimeInterval?
    /// Set on a `.workoutEnd` when the user chose "End without saving", so the
    /// other device discards its side too instead of saving. Optional for the
    /// same backward-compatibility reason as `isResting`; read as `?? false`.
    let discarded: Bool?
    /// The current exercise's reps as planned in this workout, which can differ
    /// from the exercise's library default. Only the exercise-change update
    /// sets it — the watch keeps the last one per exercise. Optional for the
    /// same backward-compatibility reason as `isResting`.
    let currentExerciseReps: Int?

    init(workoutId: String = "",
         workoutName: String = "",
         isActive: Bool = false,
         isPaused: Bool = false,
         startTime: Date? = nil,
         currentExerciseId: String? = nil,
         currentExerciseName: String? = nil,
         currentExerciseIndex: Int = 0,
         totalExercises: Int = 0,
         elapsedTime: TimeInterval = 0,
         estimatedCalories: Double? = nil,
         exerciseStartTime: Date? = nil,
         exerciseElapsedTime: TimeInterval = 0,
         workoutActivityType: UInt = UInt(HKWorkoutActivityType.functionalStrengthTraining.rawValue),
         workoutLocationType: Int = HKWorkoutSessionLocationType.unknown.rawValue,
         isResting: Bool = false,
         restSecondsRemaining: TimeInterval = 0,
         discarded: Bool = false,
         currentExerciseReps: Int? = nil) {
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.isActive = isActive
        self.isPaused = isPaused
        self.startTime = startTime
        self.currentExerciseId = currentExerciseId
        self.currentExerciseName = currentExerciseName
        self.currentExerciseIndex = currentExerciseIndex
        self.totalExercises = totalExercises
        self.elapsedTime = elapsedTime
        self.estimatedCalories = estimatedCalories
        self.exerciseStartTime = exerciseStartTime
        self.exerciseElapsedTime = exerciseElapsedTime
        self.workoutActivityType = workoutActivityType
        self.workoutLocationType = workoutLocationType
        self.isResting = isResting
        self.restSecondsRemaining = restSecondsRemaining
        self.discarded = discarded
        self.currentExerciseReps = currentExerciseReps
    }
}

/// Health metrics that can be shared between devices
struct HealthMetrics: Codable {
    let heartRate: Double?
    let activeCalories: Double?
    let totalCalories: Double?
    let distance: Double?
    let steps: Int?
    let timestamp: Date
    
    init(heartRate: Double? = nil,
         activeCalories: Double? = nil,
         totalCalories: Double? = nil,
         distance: Double? = nil,
         steps: Int? = nil,
         timestamp: Date = Date()) {
        self.heartRate = heartRate
        self.activeCalories = activeCalories
        self.totalCalories = totalCalories
        self.distance = distance
        self.steps = steps
        self.timestamp = timestamp
    }
}

/// Timer information for exercise synchronization
struct TimerState: Codable {
    let isRunning: Bool
    let startTime: Date?
    let elapsedTime: TimeInterval
    let totalDuration: TimeInterval?
    let exerciseId: String?
    
    init(isRunning: Bool = false,
         startTime: Date? = nil,
         elapsedTime: TimeInterval = 0,
         totalDuration: TimeInterval? = nil,
         exerciseId: String? = nil) {
        self.isRunning = isRunning
        self.startTime = startTime
        self.elapsedTime = elapsedTime
        self.totalDuration = totalDuration
        self.exerciseId = exerciseId
    }
}

// MARK: - Watch workout library

/// What the watch needs to list and start one workout. Sent from the iPhone
/// so the watch doesn't depend on CloudKit-synced SwiftData, which often
/// never reaches the watch (the list then showed only the quick-start rows).
struct WatchWorkoutSummary: Codable, Equatable, Hashable {
    let id: String
    /// Already localized on the sending device (`Workout.displayName`).
    let name: String
    /// A built-in workout's level, localized — its name doesn't carry it
    /// (`CatalogName`), and the watch's row shows it next to the exercise
    /// count. Nil for the user's own workouts, and from an older iPhone app.
    var level: String?
    let activityType: UInt
    let locationType: Int
    let exerciseCount: Int
    let firstExerciseId: String?
    let firstExerciseName: String?

    init(workout: Workout) {
        let firstID = workout.exercisesSequenceID.first
        id = workout.id
        name = workout.displayName
        level = !workout.isUserGenerated && CatalogName.withoutLevel(workout.name) != nil ? workout.displayDifficulty : nil
        activityType = UInt(workout.workoutActivityType)
        locationType = workout.workoutSessionLocation
        exerciseCount = workout.exercisesSequenceID.count
        firstExerciseId = firstID
        firstExerciseName = workout.exercises?.first(where: { $0.id == firstID })?.displayName
    }
}

/// One of the user's plans in progress, with the workout to do next.
struct WatchPlanEntry: Codable, Equatable {
    let planId: String
    let planName: String
    let done: Int
    let total: Int
    let next: WatchWorkoutSummary
}

/// The workouts the watch lists: plans in progress, the user's own workouts
/// and a small catalog selection.
struct WatchLibrary: Codable, Equatable {
    var plans: [WatchPlanEntry]
    var own: [WatchWorkoutSummary]
    var catalog: [WatchWorkoutSummary]
    var generatedAt: Date

    static let maxOwn = 20
    static let maxCatalog = 6

    /// Catalog shelves the watch takes one workout from each, in this order.
    /// Raw `WorkoutCategory` values (that enum is iOS-only): upper body, legs,
    /// cardio, yoga / mobility. Running is matched by HK activity type, like
    /// the Running shelf in `WorkoutsView`.
    private static let catalogShelves: [@Sendable (Workout) -> Bool] = [
        { $0.muscleGroup == 2 },
        { $0.muscleGroup == 5 },
        { $0.muscleGroup == 9 || $0.muscleGroup == 10 },
        { $0.workoutActivityType == Int(HKWorkoutActivityType.running.rawValue) },
        { $0.muscleGroup == 11 || $0.muscleGroup == 12 },
    ]

    static func make(workouts: [Workout], plans: [Plan], now: Date = Date()) -> WatchLibrary {
        let sorted = workouts.sorted { $0.name < $1.name }
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The user's own (created or saved) plans that still have a workout
        // to do, each with that next workout.
        let planEntries: [WatchPlanEntry] = plans.sorted { $0.name < $1.name }.compactMap { plan in
            guard plan.isUserGenerated || plan.isSaved, !plan.isHidden,
                  let nextID = plan.firstIncompleteWorkoutID(existingIDs: Set(byID.keys)),
                  let next = byID[nextID] else { return nil }
            return WatchPlanEntry(planId: plan.id, planName: plan.displayName,
                                  done: plan.finishedWorkoutsSequence.count,
                                  total: plan.workoutsSequenceIDs.count,
                                  next: WatchWorkoutSummary(workout: next))
        }

        // The user's own workouts that aren't part of a plan. A generated plan
        // adds one workout per session; listing those crowded everything else
        // off the wrist, so plans get one row each instead. Hidden workouts
        // (For You sessions, retired presets) are left out.
        let planWorkoutIDs = Set(plans.flatMap(\.workoutsSequenceIDs))
        let own = sorted.filter {
            $0.isUserGenerated && !$0.isHidden && !planWorkoutIDs.contains($0.id)
        }

        // Catalog: saved ones first, then one per shelf. A plan's next workout
        // is already listed above.
        let nextIDs = Set(planEntries.map(\.next.id))
        let catalogPool = sorted.filter { !$0.isUserGenerated && !$0.isHidden && !nextIDs.contains($0.id) }
        var catalog = catalogPool.filter(\.isSaved)
        for shelf in catalogShelves {
            if let pick = catalogPool.first(where: { shelf($0) && !catalog.contains($0) }) {
                catalog.append(pick)
            }
        }

        return WatchLibrary(plans: planEntries,
                            own: own.prefix(maxOwn).map(WatchWorkoutSummary.init(workout:)),
                            catalog: catalog.prefix(maxCatalog).map(WatchWorkoutSummary.init(workout:)),
                            generatedAt: now)
    }
}

// MARK: - WatchConnectivityManager

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = WatchConnectivityManager()
    
    // MARK: - Published Properties
    
    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    @Published var connectionState: String = "Unknown"
    @Published var lastError: String?
    
    // Workout state synchronization
    @Published var currentWorkoutState = WorkoutState()
    /// Workout states that arrived from the other device (after the merge in
    /// `handleWorkoutStateMessage`). Unlike `$currentWorkoutState`, this never
    /// echoes this device's own changes, so observers can tell "the watch
    /// ended the workout" from a local update.
    let receivedWorkoutState = PassthroughSubject<WorkoutState, Never>()
    /// Watch: the workout id of a `.workoutJoin` from the iPhone.
    let phoneJoinedWorkout = PassthroughSubject<String, Never>()
    @Published var currentTimerState = TimerState()
    @Published var latestHealthMetrics = HealthMetrics()
    /// Most recent exercise control command (watch → iPhone). iOS observes
    /// this to advance or reset the active exercise. Reset to nil after
    /// processing so the same command can fire repeatedly.
    @Published var lastExerciseControl: ExerciseControl?
    /// Watch: the latest workout list from the iPhone, kept in UserDefaults
    /// so it is there on launch while the phone is out of range. nil until
    /// the first one arrives.
    @Published var workoutLibrary: WatchLibrary?
    private static let workoutLibraryDefaultsKey = "watchWorkoutLibrary"
    /// Watch: the accent the user chose on the iPhone (Settings → Appearance),
    /// kept like the library. nil until one arrives: the watch's own accent, the default style's.
    @Published var accentColor: Color?
    private static let accentDefaultsKey = "watchAccent"
    /// iOS: true while a workout started on the iPhone runs. The watch's
    /// periodic status then can't overwrite the iPhone's pause or exercise
    /// (see `handleWorkoutStateMessage`).
    var phoneOwnsWorkout = false
    /// When `lastExerciseControl` was pressed on the watch. Consumers ignore
    /// commands older than `exerciseControlMaxAge`.
    private(set) var lastExerciseControlAt: Date?
    static let exerciseControlMaxAge: TimeInterval = 10

    /// Whether the latest exercise control command is recent enough to act on.
    /// (`$lastExerciseControl` emits before the value is stored, so callers
    /// take the command from the publisher and only the age from here.)
    var isExerciseControlFresh: Bool {
        guard let at = lastExerciseControlAt else { return false }
        return Date().timeIntervalSince(at) < Self.exerciseControlMaxAge
    }
    
    // MARK: - Private Properties
    
    private let session = WCSession.default
    /// When each workout's last session ended, sent or received here. Queued
    /// copies (`transferUserInfo`, the application context) and the other
    /// device's periodic status can still arrive after the end. Taking one
    /// restarted the workout: the iPhone showed it again and sent it back,
    /// and the watch began a new session for it.
    private var endedWorkouts: [String: Date] = [:]
    private var messageQueue: [String: Any] = [:]
    private var pendingReplies: [String: (([String: Any]) -> Void)] = [:]
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        #if os(watchOS)
        if let data = UserDefaults.standard.data(forKey: Self.workoutLibraryDefaultsKey) {
            workoutLibrary = try? JSONDecoder().decode(WatchLibrary.self, from: data)
        }
        accentColor = Self.color(from: UserDefaults.standard.array(forKey: Self.accentDefaultsKey))
        #endif
        setupWatchConnectivity()
    }
    
    // MARK: - Setup Methods
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            connectionState = "Not Supported"
            return
        }
        
        session.delegate = self
        session.activate()
        connectionState = "Activating"
    }
    
    // MARK: - Public Methods
    
    /// Send a workout start message to the paired device
    func startWorkout(workout: Workout) {
        let workoutState = WorkoutState(
            workoutId: workout.id,
            workoutName: workout.displayName,
            isActive: true,
            isPaused: false,
            startTime: Date(),
            currentExerciseIndex: 0,
            totalExercises: workout.exercisesSequenceID.count,
            elapsedTime: 0,
            workoutActivityType: UInt(workout.workoutActivityType),
            workoutLocationType: workout.workoutSessionLocation
        )
        
        sendWorkoutState(workoutState, messageType: .workoutStart)
        currentWorkoutState = workoutState
    }

    #if os(iOS)
    /// Launches or wakes the companion watch app so it can receive workout state.
    /// WCSession messages cannot wake the watch app on their own — this is what
    /// actually surfaces the workout on the wrist when the user taps Start (or
    /// the dedicated "send to watch" button).
    func wakeWatchApp(for workout: Workout) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) ?? .functionalStrengthTraining
        configuration.locationType = HKWorkoutSessionLocationType(rawValue: workout.workoutSessionLocation) ?? .unknown

        try await HKHealthStore.shared.startWatchApp(toHandle: configuration)
    }
    #endif
    
    /// Send a workout pause message
    func pauseWorkout() {
        let existing = currentWorkoutState
        // Carry every field from the prior state — the rebuild used to
        // drop `currentExerciseName`, `workoutActivityType`, and
        // `workoutLocationType`, which silently reset every paused
        // workout's HK activity type back to strength training and
        // blanked the exercise name on the wrist.
        let updatedState = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: existing.isActive,
            isPaused: true,
            startTime: existing.startTime,
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: existing.exerciseElapsedTime,
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType,
            isResting: existing.isResting ?? false,
            restSecondsRemaining: existing.restSecondsRemaining ?? 0
        )

        sendWorkoutState(updatedState, messageType: .workoutPause)
        currentWorkoutState = updatedState
    }

    /// Send a workout resume message
    func resumeWorkout() {
        let existing = currentWorkoutState
        let updatedState = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: existing.isActive,
            isPaused: false,
            startTime: existing.startTime,
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: existing.exerciseElapsedTime,
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType,
            isResting: existing.isResting ?? false,
            restSecondsRemaining: existing.restSecondsRemaining ?? 0
        )

        sendWorkoutState(updatedState, messageType: .workoutResume)
        currentWorkoutState = updatedState
    }
    
    /// Send a workout end message
    func endWorkout(finishedWorkout: FinishedWorkout) {
        let endState = WorkoutState(
            workoutId: finishedWorkout.id,
            workoutName: finishedWorkout.name,
            isActive: false,
            isPaused: false,
            startTime: finishedWorkout.startDate,
            elapsedTime: finishedWorkout.duration,
            estimatedCalories: finishedWorkout.caloriesBurned
        )
        
        sendWorkoutState(endState, messageType: .workoutEnd)
        currentWorkoutState = WorkoutState() // Reset to empty state
    }
    
    /// Send a workout end message from summary data (used by watch session
    /// manager). `activityType` and `locationType` are the ended session's;
    /// without them, those of `currentWorkoutState`.
    func endWorkoutSession(workoutId: String, workoutName: String, startTime: Date?, duration: TimeInterval, calories: Double?,
                           activityType: UInt? = nil, locationType: Int? = nil, discarded: Bool = false) {
        let endState = WorkoutState(
            workoutId: workoutId,
            workoutName: workoutName,
            isActive: false,
            isPaused: false,
            startTime: startTime,
            elapsedTime: duration,
            estimatedCalories: calories,
            workoutActivityType: activityType ?? currentWorkoutState.workoutActivityType,
            workoutLocationType: locationType ?? currentWorkoutState.workoutLocationType,
            discarded: discarded
        )
        
        sendWorkoutState(endState, messageType: .workoutEnd)
        currentWorkoutState = WorkoutState()
    }

    /// End whichever workout is currently mirrored. This is used by the
    /// iPhone-side observer when no `FinishedWorkout` exists yet. Sending a
    /// discrete `.workoutEnd` matters because it also rides the
    /// `transferUserInfo` path when the watch is not immediately reachable.
    func endCurrentWorkout(discarded: Bool = false) {
        let existing = currentWorkoutState
        let endState = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: false,
            isPaused: false,
            startTime: existing.startTime,
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: existing.exerciseElapsedTime,
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType,
            discarded: discarded
        )

        sendWorkoutState(endState, messageType: .workoutEnd)
        currentWorkoutState = WorkoutState()
    }

    #if os(iOS)
    /// Tells the watch that the iPhone now drives the session the watch
    /// started (see `iOSWorkoutObserver.joinWatchWorkout`).
    func joinWorkout() {
        sendWorkoutState(currentWorkoutState, messageType: .workoutJoin)
    }
    #endif
    
    /// Push the current exercise (already encoded in `state`) as a discrete
    /// `.exerciseStart` event so it rides the guaranteed-delivery path. The
    /// caller is expected to have already updated `currentWorkoutState`.
    func sendCurrentExerciseUpdate(state: WorkoutState) {
        sendWorkoutState(state, messageType: .exerciseStart)
    }

    /// Broadcast the current `currentWorkoutState` to the other device as a
    /// `.workoutState` (non-guaranteed) message. Used by the watch to ack a
    /// phone-initiated mirror so iOS knows what state actually landed.
    func broadcastCurrentState() {
        sendWorkoutState(currentWorkoutState, messageType: .workoutState)
    }

    /// Watch → iPhone: announce a workout that was started **on the watch**.
    /// Sent as a discrete `.workoutStart` so it rides the guaranteed
    /// delivery path (transferUserInfo). Without this, iOS never learned
    /// that a watch-initiated workout existed.
    func broadcastWorkoutStart(state: WorkoutState) {
        currentWorkoutState = state
        sendWorkoutState(state, messageType: .workoutStart)
    }

    // MARK: - Exercise remote

    /// Watch → iPhone: ask iOS to skip / restart the active exercise. iOS
    /// owns the sequence index; the watch only knows the current exercise
    /// via the mirrored WorkoutState.
    func sendExerciseControl(_ command: ExerciseControl) {
        let payload: [String: Any] = [
            "exerciseControl": command.rawValue,
            "timestamp": Date()
        ]
        // Live-only: a late skip would skip an exercise of whatever workout
        // is running when it finally arrives.
        sendMessage(type: .exerciseControl, payload: payload, useContextFallback: false)
    }

    /// Start an exercise and sync timer
    func startExercise(exerciseId: String, duration: TimeInterval?) {
        let timerState = TimerState(
            isRunning: true,
            startTime: Date(),
            elapsedTime: 0,
            totalDuration: duration,
            exerciseId: exerciseId
        )
        
        let existing = currentWorkoutState
        let updatedWorkoutState = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: existing.isActive,
            isPaused: existing.isPaused,
            startTime: existing.startTime,
            currentExerciseId: exerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: Date(),
            exerciseElapsedTime: 0,
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType
        )

        sendTimerState(timerState)
        sendWorkoutState(updatedWorkoutState, messageType: .exerciseStart)

        currentTimerState = timerState
        currentWorkoutState = updatedWorkoutState
    }

    /// Complete an exercise
    func completeExercise() {
        let timerState = TimerState(
            isRunning: false,
            startTime: nil,
            elapsedTime: currentTimerState.elapsedTime,
            totalDuration: currentTimerState.totalDuration,
            exerciseId: currentTimerState.exerciseId
        )

        let existing = currentWorkoutState
        let updatedWorkoutState = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: existing.isActive,
            isPaused: existing.isPaused,
            startTime: existing.startTime,
            currentExerciseId: nil,
            currentExerciseName: nil,
            currentExerciseIndex: existing.currentExerciseIndex + 1,
            totalExercises: existing.totalExercises,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: nil,
            exerciseElapsedTime: 0,
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType
        )

        sendTimerState(timerState)
        sendWorkoutState(updatedWorkoutState, messageType: .exerciseComplete)

        currentTimerState = timerState
        currentWorkoutState = updatedWorkoutState
    }
    
    /// Update health metrics
    func updateHealthMetrics(_ metrics: HealthMetrics) {
        latestHealthMetrics = metrics
        sendHealthMetrics(metrics)
    }
    
    /// Request synchronization from the other device
    func requestSync() {
        sendMessage(type: .requestSync, payload: [:])
    }
    
    /// Send HealthKit authorization status
    func sendAuthorizationStatus(isAuthorized: Bool, details: [String: Any] = [:]) {
        var payload: [String: Any] = [
            "isAuthorized": isAuthorized,
            "timestamp": Date()
        ]
        payload.merge(details) { _, new in new }
        
        sendMessage(type: .authorizationStatus, payload: payload)
    }
    
    // MARK: - Private Sending Methods
    
    private func sendWorkoutState(_ state: WorkoutState, messageType: WatchMessage) {
        guard let data = try? JSONEncoder().encode(state) else {
            lastError = "Failed to encode workout state"
            return
        }
        if messageType == .workoutEnd {
            noteEnded(state)
        }

        var payload: [String: Any] = [
            "workoutState": data,
            "timestamp": Date()
        ]

        // Immediate delivery (when the other side is reachable) or
        // updateApplicationContext fallback (last-write-wins).
        sendMessage(type: messageType, payload: payload)

        // Queue via transferUserInfo ONLY for discrete state events. The
        // per-second `.workoutState` push fired by ActiveWorkoutView's timer
        // would otherwise enqueue a persistent transfer every second,
        // backlogging the queue and starving the events that actually matter.
        if messageType.requiresGuaranteedDelivery,
           session.activationState == .activated {
            payload["messageType"] = messageType.rawValue
            payload["sendTime"] = Date()
            session.transferUserInfo(payload)
        }
    }
    
    private func sendTimerState(_ state: TimerState) {
        guard let data = try? JSONEncoder().encode(state) else {
            lastError = "Failed to encode timer state"
            return
        }
        
        let payload: [String: Any] = [
            "timerState": data,
            "timestamp": Date()
        ]
        
        sendMessage(type: .timerSync, payload: payload)
    }
    
    private func sendHealthMetrics(_ metrics: HealthMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else {
            lastError = "Failed to encode health metrics"
            return
        }

        let payload: [String: Any] = [
            "healthMetrics": data,
            "timestamp": Date()
        ]

        // Heart rate / calories are continuous per-second updates.
        // We do NOT queue them via `transferUserInfo` (the persistent
        // in-order path) AND we do NOT fall back to
        // `updateApplicationContext` either. The application context
        // is a single-slot per-device dictionary: every state /
        // timer / metrics push lands in the same slot and overwrites
        // the previous one, so HR updates were silently clobbered by
        // workoutState pushes (and vice versa). Each context update
        // also makes WatchConnectivity ask the system to schedule a
        // background task, which is what spams the
        // `BGSystemTaskSchedulerErrorDomain Code=3` log line. Drop
        // the HR push if the other side isn't reachable — the next
        // tick will retry with a fresher value anyway.
        sendMessage(type: .healthKitUpdate, payload: payload, useContextFallback: false)
    }

    private func sendMessage(type: WatchMessage, payload: [String: Any], useContextFallback: Bool = true) {
        var message = payload
        message["messageType"] = type.rawValue
        message["sendTime"] = Date()

        // Try immediate delivery first. The handlers are `@Sendable`:
        // WatchConnectivity calls them on its own queue and doesn't annotate
        // them, so written in this main-actor class they'd be main-actor
        // isolated — a runtime crash in the Swift 6 language mode.
        if session.isReachable {
            let sent = WCPayload(message)
            session.sendMessage(message, replyHandler: { @Sendable reply in
                let reply = WCPayload(reply)
                DispatchQueue.main.async {
                    self.handleMessageReply(reply.dictionary)
                }
            }, errorHandler: { @Sendable error in
                DispatchQueue.main.async {
                    if useContextFallback {
                        self.handleMessageError(error, fallbackMessage: sent.dictionary)
                    } else {
                        self.lastError = "Message delivery failed: \(error.localizedDescription)"
                    }
                }
            })
        } else if useContextFallback {
            // Fallback to application context for non-immediate delivery
            do {
                try session.updateApplicationContext(message)
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Failed to send message: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Message Handling
    
    private func handleMessageReply(_ reply: [String: Any]) {
        // Handle acknowledgments or response data
        if let messageId = reply["messageId"] as? String,
           let replyHandler = pendingReplies.removeValue(forKey: messageId) {
            replyHandler(reply)
        }
    }
    
    private func handleMessageError(_ error: Error, fallbackMessage: [String: Any]) {
        lastError = "Message delivery failed: \(error.localizedDescription)"
        
        // Try context update as fallback
        do {
            try session.updateApplicationContext(fallbackMessage)
        } catch {
            lastError = "Both message and context update failed: \(error.localizedDescription)"
        }
    }
    
    private func processIncomingMessage(_ message: [String: Any]) {
        guard let messageTypeString = message["messageType"] as? String,
              let messageType = WatchMessage(rawValue: messageTypeString) else {
            return
        }
        
        switch messageType {
        case .workoutStart, .workoutPause, .workoutResume, .workoutEnd, .exerciseStart, .exerciseComplete:
            handleWorkoutStateMessage(message, type: messageType)
            
        case .timerSync:
            handleTimerSyncMessage(message)
            
        case .healthKitUpdate:
            handleHealthKitUpdateMessage(message)
            
        case .requestSync:
            handleSyncRequest()
            
        case .authorizationStatus:
            handleAuthorizationStatusMessage(message)
            
        case .workoutState:
            handleWorkoutStateMessage(message, type: messageType)
            
        case .heartRateUpdate, .caloriesUpdate:
            handleHealthMetricUpdate(message, type: messageType)

        case .exerciseControl:
            handleExerciseControlMessage(message)

        case .workoutLibrary:
            handleWorkoutLibraryMessage(message)

        case .workoutJoin:
            handleWorkoutJoinMessage(message)
        }
    }

    private func handleExerciseControlMessage(_ message: [String: Any]) {
        guard let raw = message["exerciseControl"] as? String,
              let command = ExerciseControl(rawValue: raw) else { return }
        lastExerciseControlAt = message["timestamp"] as? Date ?? Date()
        lastExerciseControl = command
    }

    private func handleWorkoutStateMessage(_ message: [String: Any], type: WatchMessage) {
        guard let workoutStateData = message["workoutState"] as? Data,
              let workoutState = try? JSONDecoder().decode(WorkoutState.self, from: workoutStateData) else {
            return
        }
        if type == .workoutEnd {
            noteEnded(workoutState)
        } else if Self.belongsToEndedSession(workoutState, endedAt: endedWorkouts[workoutState.workoutId]) {
            appLog("Ignoring state of ended workout \(workoutState.workoutId)")
            return
        }

        // The watch's periodic status (every few seconds) may have been sent
        // before a pause or exercise change the user just made on the iPhone.
        // While the iPhone runs the workout, take only the fields the watch
        // owns from it; discrete pause/resume/end events still apply in full.
        if type == .workoutState, phoneOwnsWorkout, workoutState.isActive {
            currentWorkoutState = Self.merging(watchStatus: workoutState, into: currentWorkoutState)
        } else {
            currentWorkoutState = workoutState
        }
        receivedWorkoutState.send(currentWorkoutState)
    }

    private func noteEnded(_ state: WorkoutState) {
        guard !state.workoutId.isEmpty else { return }
        endedWorkouts[state.workoutId] = Date()
    }

    /// Whether `state` reports a session as running that ended at `endedAt`.
    /// Every session of a workout has the same id, so the start time tells
    /// them apart: a session started after the end is a new one.
    nonisolated static func belongsToEndedSession(_ state: WorkoutState, endedAt: Date?) -> Bool {
        guard state.isActive, let endedAt else { return false }
        return (state.startTime ?? .distantPast) < endedAt
    }

    private func handleWorkoutJoinMessage(_ message: [String: Any]) {
        guard let data = message["workoutState"] as? Data,
              let state = try? JSONDecoder().decode(WorkoutState.self, from: data),
              !state.workoutId.isEmpty else { return }
        phoneJoinedWorkout.send(state.workoutId)
    }

    /// The phone's state with the watch's session metrics (elapsed time,
    /// calories) applied.
    nonisolated static func merging(watchStatus: WorkoutState, into local: WorkoutState) -> WorkoutState {
        WorkoutState(
            workoutId: local.workoutId,
            workoutName: local.workoutName,
            isActive: true,
            isPaused: local.isPaused,
            startTime: local.startTime ?? watchStatus.startTime,
            currentExerciseId: local.currentExerciseId,
            currentExerciseName: local.currentExerciseName,
            currentExerciseIndex: local.currentExerciseIndex,
            totalExercises: local.totalExercises,
            elapsedTime: watchStatus.elapsedTime,
            estimatedCalories: watchStatus.estimatedCalories ?? local.estimatedCalories,
            exerciseStartTime: local.exerciseStartTime,
            exerciseElapsedTime: local.exerciseElapsedTime,
            workoutActivityType: local.workoutActivityType,
            workoutLocationType: local.workoutLocationType,
            isResting: local.isResting ?? false,
            restSecondsRemaining: local.restSecondsRemaining ?? 0
        )
    }
    
    private func handleTimerSyncMessage(_ message: [String: Any]) {
        guard let timerStateData = message["timerState"] as? Data,
              let timerState = try? JSONDecoder().decode(TimerState.self, from: timerStateData) else {
            return
        }
        
        currentTimerState = timerState
    }
    
    private func handleHealthKitUpdateMessage(_ message: [String: Any]) {
        guard let healthMetricsData = message["healthMetrics"] as? Data,
              let healthMetrics = try? JSONDecoder().decode(HealthMetrics.self, from: healthMetricsData) else {
            return
        }
        
        latestHealthMetrics = healthMetrics
    }
    
    private func handleSyncRequest() {
        // Send current state to requesting device
        sendWorkoutState(currentWorkoutState, messageType: .workoutState)
        sendTimerState(currentTimerState)
        sendHealthMetrics(latestHealthMetrics)
        #if os(iOS)
        // The watch asks whenever its workout list appears.
        sendWorkoutLibrary(context: Workout_App.sharedContainer.mainContext)
        #endif
    }

    private func handleWorkoutLibraryMessage(_ message: [String: Any]) {
        #if os(watchOS)
        guard let data = message["library"] as? Data,
              let library = try? JSONDecoder().decode(WatchLibrary.self, from: data) else { return }
        // A queued transfer can arrive after a newer direct message.
        if let current = workoutLibrary, current.generatedAt > library.generatedAt { return }
        workoutLibrary = library
        UserDefaults.standard.set(data, forKey: Self.workoutLibraryDefaultsKey)
        if let components = message["accent"] as? [Double], let color = Self.color(from: components) {
            accentColor = color
            UserDefaults.standard.set(components, forKey: Self.accentDefaultsKey)
        }
        #endif
    }

    #if os(watchOS)
    /// Red, green and blue, 0…1, as `AppTheme.watchComponents` sends them.
    private static func color(from components: [Any]?) -> Color? {
        guard let rgb = components as? [Double], rgb.count == 3 else { return nil }
        return Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
    #endif

    #if os(iOS)
    /// Sends the watch the workouts it lists (see `WatchLibrary`). Sent
    /// directly when the watch is reachable, and always queued with
    /// `transferUserInfo` so it arrives once the watch app runs. Not via
    /// `updateApplicationContext`: the workout-state fallbacks share that one
    /// slot and would overwrite it.
    func sendWorkoutLibrary(context: ModelContext) {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let library = WatchLibrary.make(workouts: try context.fetch(FetchDescriptor<Workout>()),
                                            plans: try context.fetch(FetchDescriptor<Plan>()))
            let data = try JSONEncoder().encode(library)
            let message: [String: Any] = [
                "messageType": WatchMessage.workoutLibrary.rawValue,
                "library": data,
                // Rides along, so the watch has the user's accent whenever
                // it has the list.
                "accent": AppTheme.current.watchComponents
            ]
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil, errorHandler: nil)
            }
            for transfer in session.outstandingUserInfoTransfers
            where transfer.userInfo["messageType"] as? String == WatchMessage.workoutLibrary.rawValue {
                transfer.cancel()
            }
            session.transferUserInfo(message)
        } catch {
            appLog("Watch workout library not sent: \(error)")
        }
    }
    #endif
    
    private func handleAuthorizationStatusMessage(_ message: [String: Any]) {
        // Handle authorization status updates from the other device
        if let isAuthorized = message["isAuthorized"] as? Bool {
            // You can add specific handling here if needed
            appLog("Received authorization status: \(isAuthorized)")
        }
    }
    
    private func handleHealthMetricUpdate(_ message: [String: Any], type: WatchMessage) {
        switch type {
        case .heartRateUpdate:
            if let heartRate = message["heartRate"] as? Double {
                var updatedMetrics = latestHealthMetrics
                updatedMetrics = HealthMetrics(
                    heartRate: heartRate,
                    activeCalories: updatedMetrics.activeCalories,
                    totalCalories: updatedMetrics.totalCalories,
                    distance: updatedMetrics.distance,
                    steps: updatedMetrics.steps,
                    timestamp: Date()
                )
                latestHealthMetrics = updatedMetrics
            }
            
        case .caloriesUpdate:
            if let calories = message["calories"] as? Double {
                var updatedMetrics = latestHealthMetrics
                updatedMetrics = HealthMetrics(
                    heartRate: updatedMetrics.heartRate,
                    activeCalories: calories,
                    totalCalories: updatedMetrics.totalCalories,
                    distance: updatedMetrics.distance,
                    steps: updatedMetrics.steps,
                    timestamp: Date()
                )
                latestHealthMetrics = updatedMetrics
            }
            
        default:
            break
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if Watch app is available and reachable
    func checkWatchAvailability() -> Bool {
        #if os(iOS)
        return WCSession.isSupported() && session.isPaired && isWatchAppInstalled
        #else
        return WCSession.isSupported() && session.isReachable
        #endif
    }
    
    /// Get detailed connectivity status for debugging
    func getConnectivityStatus() -> [String: Any] {
        var status: [String: Any] = [
            "isSupported": WCSession.isSupported(),
            "isReachable": session.isReachable,
            "activationState": session.activationState.rawValue,
            "hasContentPending": session.hasContentPending
        ]
        
        #if os(iOS)
        status["isPaired"] = session.isPaired
        status["isWatchAppInstalled"] = session.isWatchAppInstalled
        status["isComplicationEnabled"] = session.isComplicationEnabled
        status["remainingComplicationUserInfoTransfers"] = session.remainingComplicationUserInfoTransfers
        #endif
        
        return status
    }
    
    /// Force sync all current state
    func forceSyncAllState() {
        sendWorkoutState(currentWorkoutState, messageType: .workoutState)
        sendTimerState(currentTimerState)
        sendHealthMetrics(latestHealthMetrics)
    }

    /// Diagnostic: round-trip ping. Returns the elapsed time the watch took to
    /// ack the sendMessage. Bypasses every workout-state codepath so the result
    /// only reflects the raw WCSession reply path.
    func pingWatch() async -> Result<TimeInterval, Error> {
        guard WCSession.isSupported() else {
            return .failure(NSError(domain: "WatchPing", code: 0, userInfo: [NSLocalizedDescriptionKey: "WCSession not supported"]))
        }
        guard session.activationState == .activated else {
            return .failure(NSError(domain: "WatchPing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not activated (\(session.activationState.rawValue))"]))
        }
        guard session.isReachable else {
            return .failure(NSError(domain: "WatchPing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Watch not reachable"]))
        }

        let start = Date()
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                ["messageType": "ping", "sendTime": start],
                // `@Sendable` for the same reason as in `sendMessage(type:…)`.
                replyHandler: { @Sendable _ in
                    continuation.resume(returning: .success(Date().timeIntervalSince(start)))
                },
                errorHandler: { @Sendable error in
                    continuation.resume(returning: .failure(error))
                }
            )
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isReachable = session.isReachable
        #if os(iOS)
        let isWatchAppInstalled = session.isWatchAppInstalled
        #endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error = error {
                self.connectionState = "Error: \(error.localizedDescription)"
                self.lastError = error.localizedDescription
            } else {
                switch activationState {
                case .activated:
                    self.connectionState = "Connected"
                    #if os(iOS)
                    self.isWatchAppInstalled = isWatchAppInstalled
                    #endif
                    self.isWatchReachable = isReachable
                case .inactive:
                    self.connectionState = "Inactive"
                case .notActivated:
                    self.connectionState = "Not Activated"
                @unknown default:
                    self.connectionState = "Unknown"
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        let payload = WCPayload(message)
        Task { @MainActor [weak self] in
            self?.processIncomingMessage(payload.dictionary)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // `nonisolated` is load-bearing: without it, this whole
        // method body is implicitly `@MainActor` (inherited from the
        // class), so the WC delegate queue has to wait for the main
        // actor before it can even call `replyHandler`. When main is
        // busy (SwiftData / CloudKit / SwiftUI at launch), that wait
        // exceeds WCSession's reply window and the sender sees
        // WCErrorCodeTransferTimedOut — which then back-pressures
        // every subsequent state / metric push.
        //
        // With `nonisolated`, the ack fires synchronously on the WC
        // queue, and only the actual message handling is hopped to
        // main.
        let reply: [String: Any] = [
            "status": "received",
            "timestamp": Date()
        ]
        replyHandler(reply)

        let payload = WCPayload(message)
        Task { @MainActor [weak self] in
            self?.processIncomingMessage(payload.dictionary)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        let payload = WCPayload(applicationContext)
        Task { @MainActor [weak self] in
            self?.processIncomingMessage(payload.dictionary)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        let payload = WCPayload(userInfo)
        Task { @MainActor [weak self] in
            self?.processIncomingMessage(payload.dictionary)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isWatchReachable = isReachable
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.connectionState = "Inactive"
            self?.isWatchReachable = false
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.connectionState = "Deactivated"
            self?.isWatchReachable = false
        }
        // Fires when the user switches to another paired watch. Without
        // reactivating, sync stays off until the app is relaunched.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isWatchAppInstalled = isWatchAppInstalled
            self.isWatchReachable = isReachable

            if isReachable {
                self.connectionState = "Connected"
            } else if isPaired {
                self.connectionState = "Paired (Not Reachable)"
            } else {
                self.connectionState = "Not Paired"
            }
        }
    }
    #endif
}
