//
//  iOSWorkoutObserver.swift
//  WorkoutApp
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import Combine
import HealthKit
import SwiftData

// MARK: - Mutable Workout Info for iOS UI

class iOSWorkoutInfo {
    var workoutName: String = ""
    var muscleGroup: Int = 0
    var isActive: Bool = false
}

// MARK: - iOS Workout Observer

/// Bridges workout sync functionality to iOS SwiftUI views via @EnvironmentObject.
@MainActor
class iOSWorkoutObserver: ObservableObject {

    // MARK: - Published Properties

    @Published var currentWorkout: iOSWorkoutInfo?
    @Published var isWorkoutActive: Bool = false
    @Published var isWorkoutPaused: Bool = false
    @Published var isWatchConnected: Bool = false
    /// True once WCSession activation reports the watch app is installed on the
    /// paired watch. Unlike `isWatchConnected`, this stays true even when the
    /// watch app is asleep — which is the state we need to *launch* it from.
    @Published var isWatchAppInstalled: Bool = false
    /// Latest heart rate streamed from the watch (0 when unknown).
    @Published var currentHeartRate: Double = 0
    /// Live elapsed time the watch reports (seconds). Updates roughly every
    /// 3 seconds while the watch's HK session is active. Lets the iOS UI
    /// show a visible "still running" signal even when the local iOS-side
    /// timer can't tick — e.g. during rep-based exercises where the iOS
    /// countdown is intentionally user-driven.
    @Published var watchElapsedTime: TimeInterval = 0
    /// User-facing error message set when waking the watch / starting a
    /// mirrored workout fails. Views can bind an `.alert` to this so the
    /// user understands why the watch didn't respond instead of getting
    /// silent failure. Reset to nil after presenting.
    @Published var lastError: String?
    /// The id of a workout started on the watch, when the iPhone has that
    /// workout (the watch lists the iPhone's workouts; its quick starts are
    /// none of them). The watch banner then opens it (`joinWatchWorkout`).
    @Published private(set) var watchStartedWorkoutID: String?
    /// True while `ActiveWorkoutView` runs the session on the phone. A
    /// watch-driven end then finishes that view, which saves the one
    /// `FinishedWorkout` (with the logged sets), instead of this observer
    /// saving a second, set-less copy.
    var phoneSessionOwnsSave = false
    /// Exercise update requested before the watch session started.
    private var pendingExercise: (workoutID: String, index: Int, remaining: Double, exerciseIDs: [String]?, reps: Int?)?
    /// True when the watch's last end was "Discard", so `ActiveWorkoutView`
    /// ends without saving as well.
    var lastWatchEndDiscarded = false

    /// The session the iPhone follows — the one it started, or the one the
    /// watch started — and when it began; nil after the name-only start.
    private var followedWorkout: (id: String, start: Date)?
    /// The watch has reported the followed session running. Only then does
    /// an inactive state from it mean the watch ended it (`watchEnded`).
    private var watchRanFollowedWorkout = false

    // MARK: - Private Properties

    private let connectivityManager = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var activeWorkout: Workout?
    private var modelContext: ModelContext?
    private var savedWatchFinishedWorkoutKeys = Set<String>()
    /// Throttle for per-tick state pushes from `updateWorkoutMetadata`. The
    /// iOS active-workout timer fires once per second; without this we'd
    /// broadcast the full WorkoutState across WCSession every second, which
    /// is wasteful and risked overwriting in-flight discrete events via
    /// updateApplicationContext (last-write-wins). Discrete events (start /
    /// pause / resume / end / exerciseStart) bypass this throttle.
    ///
    /// 10s sync interval is intentional: the watch ticks the displayed
    /// countdown locally (see `ControlsView` interpolation) between
    /// pushes, so the wrist UI updates every second regardless. iOS only
    /// needs to send periodic anchors to correct for drift.
    private var lastMetadataBroadcastAt: Date?
    private let metadataBroadcastInterval: TimeInterval = 10

    // MARK: - Initialization

    init() {
        connectivityManager.$isWatchReachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                self?.isWatchConnected = reachable
            }
            .store(in: &cancellables)

        connectivityManager.$isWatchAppInstalled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] installed in
                self?.isWatchAppInstalled = installed
                SettingsManager.shared.enableWatchIfInstalled(installed)
            }
            .store(in: &cancellables)

        // Mirror pause/resume + active state coming back from the watch
        // so the iPhone UI stays in sync. Only states received from the watch:
        // `$currentWorkoutState` also echoes the iPhone's own updates, and an
        // inactive one sent right at start was read as "the watch ended it",
        // closing the just-started workout while the watch kept running.
        connectivityManager.receivedWorkoutState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if self.isWorkoutPaused != state.isPaused {
                    self.isWorkoutPaused = state.isPaused
                }
                if state.isActive && Self.belongs(state, to: self.followedWorkout) {
                    self.watchRanFollowedWorkout = true
                }
                // Watch-initiated start: the watch app called
                // broadcastWorkoutStart and iOS now needs to know there's
                // a live session somewhere. Without this, the heart-rate
                // / elapsed-time mirror wouldn't render anywhere on iOS
                // because nothing flipped `isWorkoutActive` to true.
                if state.isActive && !self.isWorkoutActive {
                    self.isWorkoutActive = true
                    self.followedWorkout = (state.workoutId, state.startTime ?? .now)
                    self.watchRanFollowedWorkout = true
                    let info = iOSWorkoutInfo()
                    info.workoutName = state.workoutName
                    info.isActive = true
                    self.currentWorkout = info
                    self.watchStartedWorkoutID = self.modelContext
                        .flatMap { self.fetchWorkout(id: state.workoutId, in: $0) }?.id
                }
                // Watch may end the workout via its stop button. Guard against
                // the placeholder `WorkoutState()` a freshly-woken watch reports
                // while it's still launching to mirror an iOS-initiated workout
                // (e.g. its reply to our requestSync, sent before its own HK
                // session is up). That state has isActive=false with an empty
                // id/name; treating it as an "end" tore down the active workout
                // on iOS the instant the watch woke — dismissing ActiveWorkoutView
                // while the system's live workout banner appeared, with no way
                // back. A real watch-driven end always carries a workout id/name.
                // And it's for the session followed here, once the watch ran
                // it — see `watchEnded`.
                if self.isWorkoutActive,
                   Self.watchEnded(state, following: self.followedWorkout, watchRan: self.watchRanFollowedWorkout) {
                    let discarded = state.discarded ?? false
                    self.lastWatchEndDiscarded = discarded
                    // An interrupted iPhone workout for the same session is
                    // saved when the user resumes and finishes it; saving the
                    // watch's copy too left two history entries.
                    let resumable = SettingsManager.shared.resumeSnapshot?.workoutID == state.workoutId
                    if !self.phoneSessionOwnsSave && !discarded && !resumable {
                        self.saveFinishedWorkoutFromWatchIfNeeded(state)
                    }
                    self.isWorkoutActive = false
                    self.watchStartedWorkoutID = nil
                    self.followedWorkout = nil
                    self.watchRanFollowedWorkout = false
                    self.connectivityManager.phoneOwnsWorkout = false
                    self.currentWorkout?.isActive = false
                }
                // Mirror the watch's HK-driven elapsed time so iOS views
                // can show a live "still running" signal.
                if state.elapsedTime > self.watchElapsedTime {
                    self.watchElapsedTime = state.elapsedTime
                } else if !state.isActive {
                    self.watchElapsedTime = 0
                }
            }
            .store(in: &cancellables)

        // Pull heart rate (and other metrics) streamed from the watch.
        connectivityManager.$latestHealthMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.currentHeartRate = metrics.heartRate ?? 0
            }
            .store(in: &cancellables)
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Sync Methods

    func requestSync() {
        connectivityManager.requestSync()
    }

    func updateWorkoutMetadata(_ metadata: WorkoutMetadata) {
        let workoutId = activeWorkout?.id ?? currentWorkout?.workoutName ?? ""
        let total = activeWorkout?.exercisesSequenceID.count ?? 0
        let existing = connectivityManager.currentWorkoutState
        // Prefer the freshly-supplied exerciseName from metadata, but fall
        // back to whatever's already in the state so the per-second timer
        // tick doesn't blank out the exercise label on the watch between
        // explicit `updateCurrentExercise` calls.
        let exerciseName = metadata.exerciseName.isEmpty
            ? existing.currentExerciseName
            : metadata.exerciseName
        let state = WorkoutState(
            workoutId: workoutId,
            workoutName: metadata.workoutName,
            isActive: isWorkoutActive,
            isPaused: isWorkoutPaused,
            startTime: existing.startTime,
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: exerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: total,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: metadata.exerciseDuration,
            // Per-second rebuild — preserve the activity / location type
            // captured at workout-start so the watch keeps the right HK
            // session config. Without this the throttled forceSyncAllState
            // every 5s would silently revert the watch to strength training.
            workoutActivityType: existing.workoutActivityType,
            workoutLocationType: existing.workoutLocationType
        )
        connectivityManager.currentWorkoutState = state
        // Throttle the cross-device broadcast — iOS UI reads from the local
        // `currentWorkoutState` (which we just updated), so the watch doesn't
        // need a fresh full-state push every second.
        let now = Date()
        if lastMetadataBroadcastAt.map({ now.timeIntervalSince($0) >= metadataBroadcastInterval }) ?? true {
            lastMetadataBroadcastAt = now
            connectivityManager.forceSyncAllState()
        }
    }

    /// Reset the broadcast throttle — call when the workout starts/ends or
    /// the current exercise changes so the next per-tick update goes out
    /// immediately instead of waiting for the throttle window.
    private func resetMetadataBroadcastThrottle() {
        lastMetadataBroadcastAt = nil
    }

    func updateWorkoutDetails(workoutName: String, exerciseName: String, exerciseDuration: Double, muscleGroup: Int) {
        let metadata = WorkoutMetadata(
            workoutName: workoutName,
            exerciseName: exerciseName,
            exerciseDuration: exerciseDuration,
            muscleGroup: muscleGroup
        )
        updateWorkoutMetadata(metadata)
    }

    /// Push the current exercise (id + name + index) to the watch.
    ///
    /// `remainingSeconds` seeds the watch's per-exercise countdown so it can
    /// start ticking DOWN immediately. Sending 0 here made the wrist briefly
    /// show a counting-UP "elapsed" timer until the next throttled metadata
    /// push (up to `metadataBroadcastInterval` later) delivered the real
    /// remaining — this closes that gap on the discrete, guaranteed-delivery
    /// exerciseStart event.
    ///
    /// `sessionExerciseIDs` is the session's own exercise list when it differs
    /// from the workout's (an exercise swapped or added mid-session); `reps` is
    /// the current exercise's planned reps in this workout, which the watch
    /// shows instead of the exercise's library default.
    func updateCurrentExercise(workout: Workout, index: Int, remainingSeconds: Double = 0,
                               sessionExerciseIDs: [String]? = nil, reps: Int? = nil) {
        activeWorkout = workout
        // Before `startWorkout` there's no watch session to update, and an
        // inactive state carrying this workout's id reads as an end on both
        // devices. Remember it; `startWorkout` sends it once the session is on.
        guard isWorkoutActive else {
            pendingExercise = (workout.id, index, remainingSeconds, sessionExerciseIDs, reps)
            return
        }
        pendingExercise = nil
        let exerciseIDs = sessionExerciseIDs ?? workout.exercisesSequenceID
        let safeIndex = max(0, min(index, max(exerciseIDs.count - 1, 0)))
        let exerciseId = exerciseIDs[safe: safeIndex]
        // Resolve the exercise's display name on iOS — sending it inside the
        // workout state means the watch doesn't need its CloudKit-synced
        // SwiftData store to be populated to render the current exercise.
        let exerciseName: String? = {
            guard let exerciseId else { return nil }
            // The relationship can still be nil while iCloud delivers it.
            return (workout.exercises?.first(where: { $0.id == exerciseId }) ?? fetchExercise(id: exerciseId))?.displayName
        }()
        let existing = connectivityManager.currentWorkoutState
        let state = WorkoutState(
            workoutId: workout.id,
            workoutName: workout.displayName,
            isActive: isWorkoutActive,
            isPaused: isWorkoutPaused,
            startTime: existing.startTime ?? Date(),
            currentExerciseId: exerciseId,
            currentExerciseName: exerciseName,
            currentExerciseIndex: safeIndex,
            totalExercises: exerciseIDs.count,
            elapsedTime: existing.elapsedTime,
            estimatedCalories: existing.estimatedCalories,
            exerciseStartTime: Date(),
            exerciseElapsedTime: remainingSeconds,
            // Prefer the freshly-resolved activity / location from the
            // workout — if the workout-start state hasn't landed yet
            // (e.g. updateCurrentExercise called before startWorkout
            // completes) we still get the right values here.
            workoutActivityType: UInt(workout.workoutActivityType),
            workoutLocationType: workout.workoutSessionLocation,
            currentExerciseReps: reps
        )
        connectivityManager.currentWorkoutState = state
        // Treat exercise transitions as discrete events — use exerciseStart
        // (transferUserInfo-backed) so the watch doesn't miss them under
        // poor connectivity. Also flush a forceSync now so the watch sees
        // the new exercise immediately, not after the throttle window.
        connectivityManager.sendCurrentExerciseUpdate(state: state)
        resetMetadataBroadcastThrottle()
        connectivityManager.forceSyncAllState()
    }

    /// Mirror the inter-exercise REST period to the watch. iOS enters this
    /// state between exercises/sets (the blue rest countdown); the watch has
    /// no other way to know about it. Pushed immediately (discrete forceSync)
    /// so the wrist reflects rest without waiting for the metadata throttle.
    /// `remaining` is the full rest length at rest-start — the watch ticks it
    /// down locally, so we only send it once (and again with `false`/`0` to
    /// clear when the rest ends).
    func updateRestState(isResting: Bool, remaining: TimeInterval) {
        guard isWorkoutActive else { return }   // see updateCurrentExercise
        let existing = connectivityManager.currentWorkoutState
        let state = WorkoutState(
            workoutId: existing.workoutId,
            workoutName: existing.workoutName,
            isActive: isWorkoutActive,
            isPaused: isWorkoutPaused,
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
            isResting: isResting,
            restSecondsRemaining: remaining
        )
        connectivityManager.currentWorkoutState = state
        resetMetadataBroadcastThrottle()
        connectivityManager.forceSyncAllState()
    }

    /// The workout id in the shared watch state (the watch reports its
    /// session's id here, also after the iPhone app was relaunched).
    var currentWorkoutStateID: String { connectivityManager.currentWorkoutState.workoutId }

    func sendWorkoutDataToWatch() async {
        connectivityManager.forceSyncAllState()
    }

    /// Shows the workout the user is browsing on the watch. Skipped while a
    /// workout runs on either device: the browsed workout would otherwise
    /// replace the running one's name on the wrist.
    func previewWorkoutOnWatch(workoutName: String, exerciseName: String, exerciseDuration: Double, muscleGroup: Int) {
        guard !isWorkoutActive, watchElapsedTime == 0 else { return }
        updateWorkoutDetails(workoutName: workoutName, exerciseName: exerciseName,
                             exerciseDuration: exerciseDuration, muscleGroup: muscleGroup)
        connectivityManager.forceSyncAllState()
    }

    // MARK: - Watch end

    /// Whether a state from the watch means it ended the session the iPhone
    /// follows. Not another session's end: a freshly woken watch, or a
    /// `.workoutEnd` queued for guaranteed delivery while the devices were
    /// apart, can bring the previous workout's end right after a new one
    /// started — which closed a run the instant it began. And not before the
    /// watch has reported this session running. After the name-only start
    /// there's nothing to compare, so any end with an id or name counts.
    nonisolated static func watchEnded(_ state: WorkoutState, following followed: (id: String, start: Date)?,
                                       watchRan: Bool) -> Bool {
        guard !state.isActive, !state.workoutId.isEmpty || !state.workoutName.isEmpty else { return false }
        guard followed != nil else { return true }
        return watchRan && belongs(state, to: followed)
    }

    /// A state from the watch is about the followed session: the same id,
    /// started no earlier than it (30 s for the two clocks). A catalog
    /// workout keeps its id, so the id alone can't tell this run from the
    /// last one.
    nonisolated static func belongs(_ state: WorkoutState, to followed: (id: String, start: Date)?) -> Bool {
        guard let followed else { return true }
        guard state.workoutId == followed.id else { return false }
        if let started = state.startTime, started < followed.start.addingTimeInterval(-30) { return false }
        return true
    }

    // MARK: - Workout Lifecycle

    /// Start a workout and notify the watch via WCSession.
    func startWorkout(workout: Workout) async throws {
        activeWorkout = workout
        let info = iOSWorkoutInfo()
        info.workoutName = workout.displayName
        info.muscleGroup = workout.muscleGroup
        info.isActive = true
        currentWorkout = info
        isWorkoutActive = true
        isWorkoutPaused = false
        watchElapsedTime = 0
        followedWorkout = (workout.id, .now)
        watchRanFollowedWorkout = false
        connectivityManager.phoneOwnsWorkout = true
        resetMetadataBroadcastThrottle()

        // Push the workout-start state BEFORE waking the watch. This puts
        // the workout name + id into transferUserInfo / applicationContext
        // so it's already queued when watchOS activates WCSession during
        // launch — giving `WatchAppDelegate.handle(_:)` a much better chance
        // of seeing the real workout name instead of the "Workout" fallback.
        connectivityManager.startWorkout(workout: workout)
        // The active workout screen usually appears first and its exercise
        // update was held back (see updateCurrentExercise) — send it now.
        if let pending = pendingExercise, pending.workoutID == workout.id {
            updateCurrentExercise(workout: workout, index: pending.index, remainingSeconds: pending.remaining,
                                  sessionExerciseIDs: pending.exerciseIDs, reps: pending.reps)
        }

        // Then wake the watch app. WCSession messages alone cannot launch
        // a sleeping watch app; without this the workoutStart payload has
        // nothing to mirror to.
        do {
            try await connectivityManager.wakeWatchApp(for: workout)
        } catch {
            appLog("Failed to launch watch app for workout: \(error)")
            lastError = Self.userFacingMessage(forWakeError: error)
        }
    }

    /// Translate a `startWatchApp(toHandle:)` error into something the user
    /// can act on. HK error code 4 is `errorAuthorizationDenied` — the most
    /// common failure mode and the only one with a clear remediation path.
    private static func userFacingMessage(forWakeError error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "com.apple.healthkit" && nsError.code == 4 {
            return NSLocalizedString(
                "Apple Watch couldn't be reached because HealthKit access is off. Open Settings → Privacy & Security → Health → TrainingLab and enable Workouts.",
                comment: "iOS error: HealthKit workout share denied for watch wake"
            )
        }
        return String(
            format: NSLocalizedString(
                "Couldn't start the workout on your Apple Watch: %@",
                comment: "iOS error: generic watch wake failure"
            ),
            nsError.localizedDescription
        )
    }

    /// Backwards-compatible name-only entry point.
    func startWorkout(workoutName: String) async throws {
        let info = iOSWorkoutInfo()
        info.workoutName = workoutName
        info.isActive = true
        currentWorkout = info
        isWorkoutActive = true
        isWorkoutPaused = false
        followedWorkout = nil

        let state = WorkoutState(
            workoutName: workoutName,
            isActive: true,
            isPaused: false,
            startTime: Date()
        )
        connectivityManager.currentWorkoutState = state
        connectivityManager.forceSyncAllState()
    }

    func pauseWorkout() {
        isWorkoutPaused = true
        connectivityManager.pauseWorkout()
    }

    func resumeWorkout() {
        isWorkoutPaused = false
        connectivityManager.resumeWorkout()
    }

    /// `discard: true` tells the watch to throw its HealthKit workout away too.
    func endWorkout(discard: Bool = false) {
        isWorkoutActive = false
        watchStartedWorkoutID = nil
        followedWorkout = nil
        watchRanFollowedWorkout = false
        // Used to be reset by our own end state echoing through the watch
        // sink, which now only sees states from the watch.
        watchElapsedTime = 0
        pendingExercise = nil
        connectivityManager.phoneOwnsWorkout = false
        isWorkoutPaused = false
        currentWorkout?.isActive = false
        activeWorkout = nil
        resetMetadataBroadcastThrottle()
        // Notify the watch with a discrete end event. A plain force-sync only
        // updates the last application context and can be missed if the watch
        // app is not currently reachable.
        connectivityManager.endCurrentWorkout(discarded: discard)
    }

    /// Hands a workout started on the watch to the iPhone's workout screen.
    /// The iPhone drives the session from now on (exercises, rest, pause) as
    /// if it had started it, and the watch keeps recording. Returns the
    /// snapshot `ActiveWorkoutView` resumes from: the watch's start time and
    /// exercise.
    func joinWatchWorkout(_ workout: Workout) -> ResumeSnapshot {
        let state = connectivityManager.currentWorkoutState
        activeWorkout = workout
        watchStartedWorkoutID = nil
        currentWorkout?.workoutName = workout.displayName
        currentWorkout?.muscleGroup = workout.muscleGroup
        connectivityManager.phoneOwnsWorkout = true
        connectivityManager.joinWorkout()
        return ResumeSnapshot(
            workoutID: workout.id,
            workoutName: workout.displayName,
            exerciseIndex: state.currentExerciseIndex,
            setIndex: 0,
            setCount: Int(workout.setLength),
            startDate: state.startTime ?? Date().addingTimeInterval(-watchElapsedTime),
            loggedWeights: [:],
            loggedReps: [:]
        )
    }

    /// Start and end of a workout reported by the watch. The end message can
    /// arrive long after the workout ended (watch out of range), so the end is
    /// derived from the watch's own start + elapsed time, not the receive time.
    static func watchWorkoutInterval(for state: WorkoutState, now: Date = Date()) -> (start: Date, end: Date) {
        let elapsed = max(state.elapsedTime, 0)
        guard let start = state.startTime else {
            return (now.addingTimeInterval(-elapsed), now)
        }
        let end = elapsed > 0 ? min(start.addingTimeInterval(elapsed), now) : now
        return (start, max(end, start))
    }

    /// Ends a workout that runs on the watch without an iPhone workout screen
    /// (the "Live" banner). The watch saves its Health workout; the history
    /// entry is saved here, since a phone-requested end isn't echoed back.
    func endMirroredWorkoutFromPhone() {
        if !phoneSessionOwnsSave {
            saveFinishedWorkoutFromWatchIfNeeded(connectivityManager.currentWorkoutState)
        }
        endWorkout()
    }

    private func saveFinishedWorkoutFromWatchIfNeeded(_ state: WorkoutState) {
        guard !state.workoutId.isEmpty || !state.workoutName.isEmpty else { return }
        let (startDate, endDate) = Self.watchWorkoutInterval(for: state)
        let key = "\(state.workoutId)|\(Int(startDate.timeIntervalSince1970))|\(Int(state.elapsedTime))"
        guard !savedWatchFinishedWorkoutKeys.contains(key) else { return }
        guard let modelContext else {
            lastError = NSLocalizedString(
                "Apple Watch workout ended, but iPhone storage was not ready to save it.",
                comment: "iOS error: missing SwiftData context for watch finished workout"
            )
            return
        }

        let sourceWorkout = fetchWorkout(id: state.workoutId, in: modelContext)
        let finishedWorkout = FinishedWorkout(
            endDate: endDate,
            name: state.workoutName.isEmpty
                ? (sourceWorkout?.displayName ?? NSLocalizedString("Apple Watch workout", comment: "Finished workout name fallback"))
                : state.workoutName,
            startDate: startDate,
            muscleGroup: sourceWorkout?.muscleGroup ?? 100,
            workoutLocation: state.workoutLocationType,
            workoutType: Int(state.workoutActivityType),
            caloriesBurned: state.estimatedCalories,
            additionalData: .none,
            exercisesSequenceID: sourceWorkout?.exercisesSequenceID ?? [],
            exercises: sourceWorkout?.exercises ?? []
        )
        finishedWorkout.predictedDifficulty = sourceWorkout?.predictedDifficulty

        // A plan's next workout started on the watch counts toward that plan.
        var creditedPlans: [Plan] = []
        if sourceWorkout != nil {
            let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
            let existingIDs = Set(((try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []).map(\.id))
            creditedPlans = Plan.recordCompletion(ofWorkoutID: state.workoutId, in: plans, existingIDs: existingIDs)
        }

        modelContext.insert(finishedWorkout)
        PlanCredit.record(finishedWorkoutID: finishedWorkout.id, workoutID: state.workoutId, plans: creditedPlans)
        do {
            try modelContext.save()
            savedWatchFinishedWorkoutKeys.insert(key)
            // A plan may have moved on to its next workout.
            if !creditedPlans.isEmpty {
                connectivityManager.sendWorkoutLibrary(context: modelContext)
            }
            // This session may have just met a weekly goal — drop the pending
            // nudge rather than making the user wait for the next foreground.
            Task { await GoalReminderScheduler.shared.refresh(context: modelContext) }
        } catch {
            modelContext.delete(finishedWorkout)
            for plan in creditedPlans { plan.undoCompletion(ofWorkoutID: state.workoutId) }
            PlanCredit.latest = nil
            lastError = String(
                format: NSLocalizedString(
                    "Apple Watch workout ended, but iPhone could not save it: %@",
                    comment: "iOS error: failed to save watch finished workout"
                ),
                error.localizedDescription
            )
        }
    }

    private func fetchExercise(id: String) -> Exercise? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWorkout(id: String, in modelContext: ModelContext) -> Workout? {
        guard !id.isEmpty else { return nil }
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
