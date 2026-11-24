//
//  WatchWorkoutManager.swift
//  Workout Watch App
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import HealthKit
import WatchKit
import Combine

// MARK: - Lightweight Workout Info for Watch UI

struct WatchWorkoutInfo {
    var elapsedTime: TimeInterval = 0
    var isPaused: Bool = false
}

// MARK: - Lightweight Metrics for Watch UI

struct WatchMetrics {
    var heartRate: Double?
    /// Session-average heart rate, populated at end-of-workout from the
    /// HK builder's `averageQuantity`. Live (per-tick) heart rate stays in
    /// `heartRate` so the wrist UI keeps showing the current value.
    var averageHeartRate: Double?
    var activeEnergyBurned: Double?
    /// Meters covered during the session. Reads from `distanceCycling`
    /// when the active session is a cycling workout, otherwise from
    /// `distanceWalkingRunning`. Without the cycling read the metric
    /// stayed at 0 for cycling workouts even though HK was recording it.
    var distance: Double?
}

// MARK: - WatchWorkoutManager

@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    // MARK: - Published Properties

    @Published var isActive: Bool = false
    @Published var currentWorkout: WatchWorkoutInfo?
    @Published var currentMetrics = WatchMetrics()
    /// User-visible error message — set when the workout can't start, e.g.
    /// because HealthKit workout-type share is denied. ContentView shows this
    /// in an alert so the user understands they need to fix permissions
    /// (Settings → Privacy & Security → Health → TrainingLab) rather than
    /// thinking the app is broken.
    @Published var lastError: String?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore.shared
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartTime: Date?
    private var pauseAccumulated: TimeInterval = 0
    private var pauseStart: Date?
    private var timer: Timer?

    private let watchConnectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()
    /// Tracks the workoutId we last reacted to so we don't restart a session
    /// when the phone re-sends an unchanged state.
    private var lastSyncedWorkoutId: String?
    private var localWorkoutId: String = UUID().uuidString
    private var localWorkoutName: String = "Workout"
    /// Set before the first `await` in `startWorkout`, so a second caller
    /// arriving while the first is still authorizing doesn't start another session.
    private var isStarting = false
    /// The workoutId of a phone-requested start that hasn't finished starting.
    /// Set synchronously (before the start Task runs), so an end queued right
    /// behind the start isn't dropped while HealthKit is still authorizing.
    private var startingWorkoutId: String?
    /// An end for `startingWorkoutId` arrived mid-start; applied (discarding
    /// the session) as soon as the start completes.
    private var endRequestedDuringStart = false
    /// The phone session whose automatic start failed (e.g. Health access
    /// denied). The phone pushes its state every few seconds; retrying on each
    /// push failed again every time and showed the error alert over and over.
    /// Keyed by id *and* start time: the phone sends the same id for every
    /// session of a workout, and the next session must try again. Opening the
    /// workout screen still tries once more.
    private var failedAutoStart: (workoutId: String, startTime: Date?)?
    /// Phone start events older than this are a replay of a workout that ran
    /// while the watch app was closed, not a workout to join.
    private static let maxMirroredStartAge: TimeInterval = 4 * 3600

    /// Sports that lock the screen against splashes once started, as Apple's
    /// Workout app does.
    private static let waterSports: Set<HKWorkoutActivityType> = [
        .swimming, .waterFitness, .waterPolo, .waterSports, .surfingSports, .paddleSports
    ]

    /// A pool swim needs its pool and lap length or HealthKit rejects the
    /// session, and nothing that starts a workout (the iPhone, quick start, a
    /// synced workout) sets them — so a swim is taken to be in a 25 m pool.
    nonisolated static func prepared(_ configuration: HKWorkoutConfiguration) -> HKWorkoutConfiguration {
        guard configuration.activityType == .swimming,
              configuration.swimmingLocationType == .unknown,
              let copy = configuration.copy() as? HKWorkoutConfiguration else { return configuration }
        copy.swimmingLocationType = .pool
        copy.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
        return copy
    }
    /// True when the running session mirrors a workout started on the iPhone
    /// (`notifyPhone: false`), or the iPhone joined it (see `phoneJoined`);
    /// false when the user started it on the watch. The phone's state may
    /// rename or pause only a phone-driven session.
    private var sessionIsPhoneDriven = false
    /// Whether `localWorkoutId` holds the iPhone's id for the running
    /// phone-driven session (false while a `handle(_:)` start is still on
    /// its random fallback id).
    private var hasPhoneWorkoutId = false
    /// Set while `endWorkout` runs, so the session's own `.ended` callback
    /// isn't mistaken for the system ending it.
    private var isEnding = false
    /// The sport the running session records in Health, for the states sent
    /// to the iPhone, which saves its own copy of the workout as that sport.
    /// Not `currentWorkoutState`'s: every state the iPhone sends replaces
    /// that one, so a swim started here was saved as the strength training
    /// of whatever the iPhone had sent (and counted toward the Gym goal).
    private var sessionSport: (activityType: UInt, locationType: Int)? {
        workoutSession.map {
            ($0.workoutConfiguration.activityType.rawValue, $0.workoutConfiguration.locationType.rawValue)
        }
    }

    override init() {
        super.init()
        observePhoneState()
    }

    // MARK: - Phone → Watch bridge

    private func observePhoneState() {
        watchConnectivity.$currentWorkoutState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handlePhoneWorkoutState(state)
            }
            .store(in: &cancellables)

        watchConnectivity.phoneJoinedWorkout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workoutId in
                self?.phoneJoined(workoutId)
            }
            .store(in: &cancellables)
    }

    /// The iPhone opened its workout screen for the session started here. It
    /// drives the session from now on, as if it had started it: its pause and
    /// exercise changes apply, while the watch keeps recording.
    private func phoneJoined(_ workoutId: String) {
        guard isActive, !isEnding, workoutId == localWorkoutId else { return }
        sessionIsPhoneDriven = true
        hasPhoneWorkoutId = true
    }

    /// States of a session that already ended never get here:
    /// `WatchConnectivityManager` drops them.
    private func handlePhoneWorkoutState(_ state: WorkoutState) {
        // Keep our notion of the current workoutId aligned with the iPhone's
        // even when the session was started locally by
        // `WatchAppDelegate.handle(_:)` (which never sets this flag). Without
        // this, the very first WC state message tries to start a *second*
        // workout, hits the `!isActive` guard, and silently bails — leaving
        // `lastSyncedWorkoutId` nil so subsequent transitions are misread.
        // The iPhone also pushes state while the user just browses a workout
        // (WorkoutPreview/PlanPreview). Such a state must not rename, pause or
        // end a session it doesn't belong to.
        let acceptsPhoneState = !isActive || sessionIsPhoneDriven

        if state.isActive && !state.workoutId.isEmpty && acceptsPhoneState {
            lastSyncedWorkoutId = state.workoutId
        }

        // When iOS launches the watch via `startWatchApp(toHandle:)`, the
        // WatchAppDelegate's `handle(_:)` runs BEFORE the WCSession state
        // message lands — so the local workout is started with the
        // "Workout" fallback name. Once the real state arrives, adopt
        // its name / id so any UI that falls back to the local copy
        // (and the eventual end-of-workout broadcast) shows the right
        // workout title.
        if state.isActive && acceptsPhoneState {
            if !state.workoutName.isEmpty {
                localWorkoutName = state.workoutName
            }
            if !state.workoutId.isEmpty {
                localWorkoutId = state.workoutId
                if isActive { hasPhoneWorkoutId = true }
            }
        }

        // Active → start (only if we aren't already running a session).
        // Use the activity type sent by the iPhone — falling back to
        // functionalStrengthTraining only when the field is absent or
        // not representable as an HKWorkoutActivityType. Hardcoding it
        // here previously recorded every mirrored running / cycling
        // workout as strength training in HealthKit.
        if state.isActive && !isActive && !state.workoutId.isEmpty {
            guard startingWorkoutId == nil else { return }
            if let failed = failedAutoStart, failed.workoutId == state.workoutId, failed.startTime == state.startTime {
                return
            }
            if let start = state.startTime,
               Date().timeIntervalSince(start) > Self.maxMirroredStartAge {
                appLog("Ignoring stale start for workout \(state.workoutId)")
                return
            }
            let activity = HKWorkoutActivityType(rawValue: state.workoutActivityType)
                ?? .functionalStrengthTraining
            let location = HKWorkoutSessionLocationType(rawValue: state.workoutLocationType)
                ?? .unknown
            startingWorkoutId = state.workoutId
            endRequestedDuringStart = false
            Task { @MainActor in
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = activity
                configuration.locationType = location
                do {
                    try await self.startWorkout(
                        configuration: configuration,
                        workoutName: state.workoutName,
                        notifyPhone: false
                    )
                } catch {
                    self.failedAutoStart = (state.workoutId, state.startTime)
                }
                self.startingWorkoutId = nil
                if self.endRequestedDuringStart {
                    self.endRequestedDuringStart = false
                    if self.isActive {
                        appLog("Ending workout whose end arrived while it was starting")
                        try? await self.endWorkout(notifyPhone: false, discard: true)
                    }
                }
            }
            return
        }

        // End for a workout that is still starting: remember it instead of
        // dropping it (the `isActive` check below is still false).
        if !state.isActive, !isActive, let starting = startingWorkoutId,
           state.workoutId == starting {
            endRequestedDuringStart = true
            return
        }

        // Pause/resume mirroring from phone. Ack back so iOS sees the
        // watch's actual mirrored state — if our session had already ended
        // for any reason, the ack will report `isActive = false` and iOS
        // can resolve the divergence (see endWorkout observer logic).
        if state.isActive && acceptsPhoneState {
            if state.isPaused, currentWorkout?.isPaused == false {
                pauseLocalOnly()
                publishCurrentWorkoutState(isPaused: true)
                acknowledgeMirrorToPhone()
            } else if !state.isPaused, currentWorkout?.isPaused == true {
                resumeLocalOnly()
                publishCurrentWorkoutState(isPaused: false)
                acknowledgeMirrorToPhone()
            }
        }

        // End coming from phone — only for the session it belongs to. A
        // phone-driven session still on its fallback id accepts any real end.
        let endIsForThisSession = !state.workoutId.isEmpty
            && (state.workoutId == localWorkoutId || (sessionIsPhoneDriven && !hasPhoneWorkoutId))
        if !state.isActive && isActive && endIsForThisSession {
            lastSyncedWorkoutId = nil
            let discard = state.discarded ?? false
            Task { @MainActor in
                try? await self.endWorkout(notifyPhone: false, discard: discard)
            }
        }
    }

    // MARK: - HealthKit Authorization

    func requestHealthKitAuthorization() async throws {
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]
        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout(type: HKWorkoutActivityType, workoutName: String) async throws {
        try await startWorkout(type: type, workoutName: workoutName, notifyPhone: true)
    }

    /// Starts a workout from the iPhone's workout list (`WatchLibrary`). The
    /// iPhone looks the workout up by id, so the watch needn't have it.
    func startWorkout(summary: WatchWorkoutSummary) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: summary.activityType)
            ?? .functionalStrengthTraining
        configuration.locationType = HKWorkoutSessionLocationType(rawValue: summary.locationType)
            ?? .unknown

        let state = WorkoutState(
            workoutId: summary.id,
            workoutName: summary.name,
            isActive: false,
            isPaused: false,
            startTime: Date(),
            currentExerciseId: summary.firstExerciseId,
            currentExerciseName: summary.firstExerciseName,
            currentExerciseIndex: 0,
            totalExercises: summary.exerciseCount,
            elapsedTime: 0,
            workoutActivityType: summary.activityType,
            workoutLocationType: summary.locationType
        )
        watchConnectivity.currentWorkoutState = state

        try await startWorkout(
            configuration: configuration,
            workoutName: summary.name,
            notifyPhone: true
        )
    }

    func startWorkout(type: HKWorkoutActivityType, workoutName: String, notifyPhone: Bool) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown

        watchConnectivity.currentWorkoutState = WorkoutState(
            workoutId: UUID().uuidString,
            workoutName: workoutName,
            isActive: false,
            isPaused: false,
            startTime: Date(),
            workoutActivityType: type.rawValue,
            workoutLocationType: configuration.locationType.rawValue
        )

        try await startWorkout(
            configuration: configuration,
            workoutName: workoutName,
            notifyPhone: notifyPhone
        )
    }

    func startWorkout(configuration: HKWorkoutConfiguration, workoutName: String, notifyPhone: Bool) async throws {
        // Don't try to start twice.
        guard !isActive, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let configuration = Self.prepared(configuration)

        // Make sure HealthKit authorization is granted before we touch
        // HKWorkoutSession — otherwise the initializer throws
        // "not authorized", which is exactly the race we hit when iOS
        // auto-launches this app and triggers a mirrored start before the
        // scene's `.task` finishes its first auth request.
        try await requestHealthKitAuthorization()

        // If workout-type share is denied, the prompt above is a no-op (iOS
        // never re-prompts once the user has decided). Detect that case here
        // and surface a useful message instead of letting HKWorkoutSession
        // throw a generic "Not authorized". The user has to flip the toggle
        // in the iPhone's Watch app (My Watch → Health → Health Data) or in
        // watchOS Settings → Health → TrainingLab.
        if healthStore.authorizationStatus(for: .workoutType()) == .sharingDenied {
            let message = NSLocalizedString(
                "HealthKit access is off. On iPhone, open the Watch app → TrainingLab → Privacy and enable Health.",
                comment: "Watch error: HealthKit workout share denied"
            )
            lastError = message
            throw NSError(domain: "TrainingLab", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            // HKWorkoutSession can still throw "not authorized" if the user
            // never saw the prompt (status stayed `.notDetermined`). Telling
            // them to look in Settings won't help — the app won't be listed
            // there yet. Ask them to open TrainingLab on the watch directly
            // so the prompt is presented.
            lastError = NSLocalizedString(
                "Open TrainingLab on your Apple Watch and tap Allow when HealthKit asks for permission.",
                comment: "Watch error: HKWorkoutSession init failed"
            )
            throw error
        }
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        let startDate = Date()
        session.startActivity(with: startDate)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.beginCollection(withStart: startDate) { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // The session is already running but was never stored, so nothing
            // could end it later — the system workout indicator would stay on.
            session.end()
            builder.discardWorkout()
            lastError = error.localizedDescription
            throw error
        }

        workoutSession = session
        workoutBuilder = builder
        workoutStartTime = startDate
        pauseAccumulated = 0
        pauseStart = nil
        lastHealthMetricsBroadcastAt = nil
        localWorkoutName = workoutName
        sessionIsPhoneDriven = !notifyPhone
        if !watchConnectivity.currentWorkoutState.workoutId.isEmpty {
            localWorkoutId = watchConnectivity.currentWorkoutState.workoutId
            hasPhoneWorkoutId = !notifyPhone
        } else {
            localWorkoutId = UUID().uuidString
            hasPhoneWorkoutId = false
        }
        // Track which workoutId we just spun up so the next phone state
        // push isn't mistaken for a brand-new mirrored workout.
        lastSyncedWorkoutId = localWorkoutId
        currentWorkout = WatchWorkoutInfo()
        currentMetrics = WatchMetrics()
        isActive = true
        publishCurrentWorkoutState(isPaused: false)

        // When the user starts a workout directly on the watch, iOS has
        // no idea anything is happening — `publishCurrentWorkoutState`
        // only mutates the watch's local copy of the state. Send an
        // actual `.workoutStart` so iOS receives it through the guaranteed
        // delivery path (transferUserInfo) and its observer can flip
        // `isWorkoutActive`, route the data, surface it in the UI, etc.
        if notifyPhone {
            watchConnectivity.broadcastWorkoutStart(state: watchConnectivity.currentWorkoutState)
        }

        startTimer()

        if Self.waterSports.contains(configuration.activityType) {
            WKInterfaceDevice.current().enableWaterLock()
        }
    }

    func pauseWorkout() {
        pauseLocalOnly()
        publishCurrentWorkoutState(isPaused: true)
        watchConnectivity.pauseWorkout()
    }

    func resumeWorkout() {
        resumeLocalOnly()
        publishCurrentWorkoutState(isPaused: false)
        watchConnectivity.resumeWorkout()
    }

    /// Pause the local HK session only — used when the phone is the source of truth.
    private func pauseLocalOnly() {
        workoutSession?.pause()
        pauseStart = Date()
        currentWorkout?.isPaused = true
    }

    /// Resume the local HK session only — used when the phone is the source of truth.
    private func resumeLocalOnly() {
        workoutSession?.resume()
        if let start = pauseStart {
            pauseAccumulated += Date().timeIntervalSince(start)
            pauseStart = nil
        }
        currentWorkout?.isPaused = false
    }

    func endWorkout() async throws {
        try await endWorkout(notifyPhone: true)
    }

    /// `discard: true` ends the session without saving it to Health.
    func endWorkout(notifyPhone: Bool, discard: Bool = false) async throws {
        guard !isEnding else { return }
        isEnding = true
        stopTimer()

        // Capture the phone-side state and elapsed time BEFORE anything is
        // torn down. The notification to iOS is moved into the defer block
        // below so it ALWAYS fires — even if HK throws halfway through
        // `builder.endCollection` / `finishWorkout`. That was the cause of
        // the "ending from watch doesn't reach iOS" bug on devices where
        // workout-type share was denied (HK init failed earlier, session/
        // builder were nil, but iOS never heard about it).
        // The session's own id/name, not `currentWorkoutState`: a state the
        // iPhone pushed while browsing another workout may have replaced it.
        let phoneWorkoutId = isActive ? localWorkoutId : watchConnectivity.currentWorkoutState.workoutId
        let phoneWorkoutName = isActive ? localWorkoutName : watchConnectivity.currentWorkoutState.workoutName
        let phoneStartTime = workoutStartTime ?? watchConnectivity.currentWorkoutState.startTime
        let cachedCalories = currentMetrics.activeEnergyBurned
        let sport = sessionSport
        let endDate = Date()
        let cachedElapsed = workoutStartTime.map { endDate.timeIntervalSince($0) - pauseAccumulated } ?? 0

        defer {
            isActive = false
            currentWorkout = nil
            workoutSession = nil
            workoutBuilder = nil
            workoutStartTime = nil
            lastSyncedWorkoutId = nil
            // Clear last-known metrics so the next workout's MetricsView
            // doesn't briefly show stale HR/calories from the previous
            // session before live data starts flowing.
            currentMetrics = WatchMetrics()
            lastHealthMetricsBroadcastAt = nil
            localWorkoutId = UUID().uuidString
            localWorkoutName = "Workout"
            sessionIsPhoneDriven = false
            hasPhoneWorkoutId = false
            isEnding = false

            if notifyPhone {
                watchConnectivity.endWorkoutSession(
                    workoutId: phoneWorkoutId,
                    workoutName: phoneWorkoutName,
                    startTime: phoneStartTime,
                    duration: cachedElapsed,
                    calories: cachedCalories,
                    activityType: sport?.activityType,
                    locationType: sport?.locationType,
                    discarded: discard
                )
            } else if watchConnectivity.currentWorkoutState.isActive,
                      watchConnectivity.currentWorkoutState.workoutId == phoneWorkoutId {
                // Still showing this session as running, the workout list
                // would open the workout screen again, which starts a new one.
                watchConnectivity.currentWorkoutState = WorkoutState()
            }
        }

        guard let session = workoutSession, let builder = workoutBuilder else {
            return
        }

        session.end()

        if discard {
            builder.discardWorkout()
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: endDate) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        _ = try await builder.finishWorkout()
    }

    private func publishCurrentWorkoutState(isPaused: Bool) {
        let existing = watchConnectivity.currentWorkoutState
        let state = WorkoutState(
            // While a session runs, report its own id/name (see endWorkout).
            workoutId: isActive || existing.workoutId.isEmpty ? localWorkoutId : existing.workoutId,
            workoutName: isActive || existing.workoutName.isEmpty ? localWorkoutName : existing.workoutName,
            // Use the real session state instead of hardcoding `true`. The
            // previous bug let the watch echo back `isActive = true` even
            // after the local session had ended, which left iOS thinking
            // the workout was still running.
            isActive: isActive,
            isPaused: isPaused,
            startTime: existing.startTime ?? workoutStartTime ?? Date(),
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: currentWorkout?.elapsedTime ?? existing.elapsedTime,
            estimatedCalories: currentMetrics.activeEnergyBurned ?? existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: existing.exerciseElapsedTime,
            // The session's own while one runs, so the watch's echo back to
            // iOS doesn't silently revert them.
            workoutActivityType: sessionSport?.activityType ?? existing.workoutActivityType,
            workoutLocationType: sessionSport?.locationType ?? existing.workoutLocationType,
            isResting: existing.isResting ?? false,
            restSecondsRemaining: existing.restSecondsRemaining ?? 0
        )
        watchConnectivity.currentWorkoutState = state
    }

    /// Ack a phone-initiated mirror operation by broadcasting the watch's
    /// actual current state back to iOS. Without this, when iOS pauses the
    /// workout we mirror locally but iOS gets no confirmation that the
    /// session actually paused — and if our session was already gone, iOS
    /// would have no signal of the divergence.
    private func acknowledgeMirrorToPhone() {
        watchConnectivity.broadcastCurrentState()
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        // Stops itself once its manager is gone (only possible for a
        // non-singleton instance, e.g. in previews) — instead of a `deinit`,
        // which couldn't touch the main-actor `timer`.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        // A tick queued before `endWorkout` stopped the timer would report
        // the ending session as running again, to the iPhone too.
        guard let start = workoutStartTime, !isEnding else { return }

        var currentPause = pauseAccumulated
        if let ps = pauseStart {
            currentPause += Date().timeIntervalSince(ps)
        }
        let elapsed = Date().timeIntervalSince(start) - currentPause
        currentWorkout?.elapsedTime = elapsed

        updateMetrics()

        // Broadcast the watch's live elapsed time back to iOS every few
        // seconds so the iPhone has a visible signal that the session is
        // running — without this, rep-based workouts look frozen on iOS
        // because the iOS-local timer intentionally doesn't tick during
        // user-driven reps.
        broadcastElapsedTimeIfDue(elapsed: elapsed)
    }

    /// Throttle the elapsed-time broadcast to once every ~3 seconds so we
    /// don't flood WCSession with state pushes — iOS only needs a
    /// "yes, still running" tick, not per-second resolution.
    private var lastElapsedBroadcastAt: Date?
    private let elapsedBroadcastInterval: TimeInterval = 3

    private func broadcastElapsedTimeIfDue(elapsed: TimeInterval) {
        let now = Date()
        if let last = lastElapsedBroadcastAt, now.timeIntervalSince(last) < elapsedBroadcastInterval {
            return
        }
        lastElapsedBroadcastAt = now

        // Build a state with the live elapsed time, then push as
        // `.workoutState` (non-guaranteed) so it doesn't fill the
        // transferUserInfo queue with per-tick payloads.
        let existing = watchConnectivity.currentWorkoutState
        let state = WorkoutState(
            // While a session runs, report its own id/name (see endWorkout).
            workoutId: isActive || existing.workoutId.isEmpty ? localWorkoutId : existing.workoutId,
            workoutName: isActive || existing.workoutName.isEmpty ? localWorkoutName : existing.workoutName,
            isActive: isActive,
            isPaused: currentWorkout?.isPaused ?? false,
            startTime: existing.startTime ?? workoutStartTime ?? Date(),
            currentExerciseId: existing.currentExerciseId,
            currentExerciseName: existing.currentExerciseName,
            currentExerciseIndex: existing.currentExerciseIndex,
            totalExercises: existing.totalExercises,
            elapsedTime: elapsed,
            estimatedCalories: currentMetrics.activeEnergyBurned ?? existing.estimatedCalories,
            exerciseStartTime: existing.exerciseStartTime,
            exerciseElapsedTime: existing.exerciseElapsedTime,
            workoutActivityType: sessionSport?.activityType ?? existing.workoutActivityType,
            workoutLocationType: sessionSport?.locationType ?? existing.workoutLocationType,
            // Dropping these reset the rest countdown on the wrist ~3 s in.
            isResting: existing.isResting ?? false,
            restSecondsRemaining: existing.restSecondsRemaining ?? 0
        )
        watchConnectivity.currentWorkoutState = state
        watchConnectivity.broadcastCurrentState()
    }

    // MARK: - Metrics

    /// Throttle for the cross-device HR / calories broadcast. The
    /// on-wrist UI still refreshes at 1 Hz from the local
    /// `currentMetrics` read — only the WCSession push is rate-limited.
    /// Per-tick sends were saturating WCSession's reply queue
    /// (symptom: WCErrorCodeTransferTimedOut), starving the same
    /// channel iOS uses for everything else.
    private var lastHealthMetricsBroadcastAt: Date?
    private let healthMetricsBroadcastInterval: TimeInterval = 2

    private func updateMetrics() {
        guard let builder = workoutBuilder else { return }
        let stats = builder.allStatistics

        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        if let hrStat = stats[HKQuantityType.quantityType(forIdentifier: .heartRate)!] {
            currentMetrics.heartRate = hrStat.mostRecentQuantity()?.doubleValue(for: hrUnit)
            // Roll the running average forward so the summary at end-of-
            // workout has a value to show even if the user ends mid-tick.
            currentMetrics.averageHeartRate = hrStat.averageQuantity()?.doubleValue(for: hrUnit)
        }
        if let energyStat = stats[HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!] {
            currentMetrics.activeEnergyBurned = energyStat.sumQuantity()?.doubleValue(
                for: .kilocalorie()
            )
        }
        // Pick whichever distance series the active session is actually
        // populating — only one will be non-nil per workout type.
        let walkRun = stats[HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!]?.sumQuantity()
        let cycling = stats[HKQuantityType.quantityType(forIdentifier: .distanceCycling)!]?.sumQuantity()
        if let dist = walkRun ?? cycling {
            currentMetrics.distance = dist.doubleValue(for: .meter())
        }

        let now = Date()
        if let last = lastHealthMetricsBroadcastAt,
           now.timeIntervalSince(last) < healthMetricsBroadcastInterval {
            return
        }
        lastHealthMetricsBroadcastAt = now

        // Forward to iPhone so ActiveWorkoutView can display heart rate.
        let payload = HealthMetrics(
            heartRate: currentMetrics.heartRate,
            activeCalories: currentMetrics.activeEnergyBurned,
            totalCalories: currentMetrics.activeEnergyBurned,
            distance: currentMetrics.distance,
            steps: nil,
            timestamp: now
        )
        watchConnectivity.updateHealthMetrics(payload)
    }
}

// MARK: - Session delegate & crash recovery

extension WatchWorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in
            self.finishSessionEndedBySystem(workoutSession)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            appLog("Watch workout session failed: \(error)")
            self.finishSessionEndedBySystem(workoutSession)
        }
    }

    /// The system ended the session (another workout app took over, or it
    /// failed). Without this the watch kept showing — and telling the iPhone —
    /// that the workout was running, and a later end couldn't save it.
    private func finishSessionEndedBySystem(_ session: HKWorkoutSession) {
        guard session === workoutSession, isActive, !isEnding else { return }
        appLog("Workout session ended by the system; saving what was recorded")
        Task { @MainActor in
            do {
                try await self.endWorkout(notifyPhone: true)
            } catch {
                appLog("Saving the system-ended workout failed: \(error)")
            }
        }
    }

    /// Re-attaches to the session that was running when the app crashed or
    /// was killed (called from `WKApplicationDelegate.handleActiveWorkoutRecovery`).
    func recoverActiveWorkout() async {
        guard !isActive, !isStarting else { return }
        let session: HKWorkoutSession?
        do {
            session = try await withCheckedThrowingContinuation { continuation in
                healthStore.recoverActiveWorkoutSession { session, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: session)
                    }
                }
            }
        } catch {
            appLog("Workout recovery failed: \(error)")
            return
        }
        guard let session, !isActive else { return }

        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: session.workoutConfiguration
        )

        let now = Date()
        let start = session.startDate ?? builder.startDate ?? now
        workoutSession = session
        workoutBuilder = builder
        workoutStartTime = start
        // The builder's elapsed time excludes pauses; the gap to wall-clock
        // time is what was paused before the crash.
        pauseAccumulated = max(now.timeIntervalSince(start) - builder.elapsedTime, 0)
        let isPaused = session.state == .paused
        pauseStart = isPaused ? now : nil
        lastHealthMetricsBroadcastAt = nil

        let phoneState = watchConnectivity.currentWorkoutState
        sessionIsPhoneDriven = phoneState.isActive && !phoneState.workoutId.isEmpty
        hasPhoneWorkoutId = sessionIsPhoneDriven
        localWorkoutId = phoneState.workoutId.isEmpty ? UUID().uuidString : phoneState.workoutId
        localWorkoutName = phoneState.workoutName.isEmpty ? "Workout" : phoneState.workoutName
        lastSyncedWorkoutId = localWorkoutId

        var info = WatchWorkoutInfo()
        info.isPaused = isPaused
        currentWorkout = info
        currentMetrics = WatchMetrics()
        isActive = true
        publishCurrentWorkoutState(isPaused: isPaused)
        startTimer()
        appLog("Recovered active workout session")
    }
}
