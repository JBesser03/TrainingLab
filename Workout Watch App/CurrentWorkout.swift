//
//  CurrentWorkout.swift
//  Workout Watch App
//
//  Created by Justus Besser on 26.08.23.
//

import SwiftUI
import WatchKit
import HealthKit
import SwiftData
import Combine

// NOTE: The active-workout screen used at runtime is
// `CurrentWorkoutView` in ContentView.swift. A second `CurrentWorkout`
// View struct used to live here as legacy/dead code — removed to avoid
// confusion when grepping for the current workout UI.

struct ControlsView: View {
    @EnvironmentObject var watchWorkoutManager: WatchWorkoutManager
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @Query private var exercises: [Exercise]
    @Environment(\.dismiss) var dismiss

    /// Error from the most recent end-workout attempt. Surfaced in an alert
    /// so a failure isn't just silently `print`-ed.
    @State private var endErrorMessage: String?
    @State private var showingEndError = false
    @State private var showingEndConfirmation = false

    /// Restart, skip and pause drive the iPhone's session, so they work while
    /// the phone's workout runs even if the watch's Health session never
    /// started (e.g. Health access denied).
    private var controlsEnabled: Bool {
        watchWorkoutManager.isActive || connectivity.currentWorkoutState.isActive
    }

    /// The local session's pause state, or the phone's when there's no local
    /// session — the same fallback the controls use.
    private var isPaused: Bool {
        watchWorkoutManager.currentWorkout?.isPaused ?? connectivity.currentWorkoutState.isPaused
    }

    /// Local countdown interpolation. iOS only pushes a fresh
    /// `exerciseElapsedTime` (semantically: seconds-remaining) every few
    /// seconds — sending per-tick across WCSession would saturate the
    /// channel on real devices. The TimelineView below re-renders every
    /// second and computes "remaining" relative to the last anchor, so
    /// the wrist shows a fluid 1 Hz countdown.
    @State private var lastSyncTime: Date = .now
    @State private var lastSyncedRemaining: TimeInterval = 0

    /// Same local-interpolation trick for the inter-exercise REST countdown
    /// mirrored from iOS. Rest length is fixed, so iOS pushes it once at
    /// rest-start and the wrist ticks it down from here.
    @State private var lastRestSyncTime: Date = .now
    @State private var lastSyncedRest: TimeInterval = 0
    /// Reps the iPhone planned per exercise in this workout. Only the
    /// exercise-change update carries them, so they're kept here for the later
    /// state pushes (pause, metrics) that don't.
    @State private var plannedReps: [String: Int] = [:]

    /// Timer font sizes scale with the user's Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var countUpSize: CGFloat = 30

    /// Prefer the name embedded in the workout state (sent by iOS). Falls
    /// back to a SwiftData lookup for compatibility with older state payloads
    /// where `currentExerciseName` wasn't populated.
    private func currentExerciseName(from state: WorkoutState) -> String? {
        if let name = state.currentExerciseName, !name.isEmpty { return name }
        guard let id = state.currentExerciseId, !id.isEmpty else { return nil }
        return exercises.first(where: { $0.id == id })?.name
    }

    private func rememberPlannedReps(_ state: WorkoutState) {
        if let reps = state.currentExerciseReps, let id = state.currentExerciseId {
            plannedReps[id] = reps
        }
    }

    /// Target reps when the current exercise is done by reps. The iPhone
    /// shows these instead of a countdown, so the wrist does too.
    private func repTarget(from state: WorkoutState) -> Int? {
        guard let id = state.currentExerciseId, !id.isEmpty else { return nil }
        let reps = state.currentExerciseReps ?? plannedReps[id] ?? exercises.first(where: { $0.id == id })?.repCount
        guard let reps, reps > 0 else { return nil }
        return reps
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header: exercise title (prominent) + index, with an explicit
            // "PAUSED" pill underneath when paused so the state is
            // unmistakable from any glance distance.
            let phoneState = connectivity.currentWorkoutState
            let isResting = phoneState.isResting ?? false

            VStack(spacing: 4) {
                // Workout name as a small persistent header. Without
                // this, the previous layout only showed the name when
                // `totalExercises == 0`, so iOS-initiated workouts
                // (which always send a non-zero count) had no visible
                // title on the wrist — only the "Exercise X of N" caption.
                if !phoneState.workoutName.isEmpty {
                    Text(phoneState.workoutName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if phoneState.totalExercises > 0 {
                    Text("Exercise \(phoneState.currentExerciseIndex + 1) of \(phoneState.totalExercises)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let name = currentExerciseName(from: phoneState) {
                        Text(name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }

                if isResting {
                    Text("RESTING")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.tint.opacity(0.25)))
                        .foregroundStyle(.tint)
                } else if isPaused {
                    Text("PAUSED")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundColor(.orange)
                }
            }

            // Primary display: the per-exercise countdown the iPhone pushes
            // (`exerciseElapsedTime`), which matches what the user sees on
            // iOS and ticks DOWN. The iPhone sends none for an exercise done
            // by reps: then the target reps, like on the iPhone. Without
            // either (a run, or a watch-started workout), the session time
            // ticking UP.
            if let workout = watchWorkoutManager.currentWorkout {
                let hasCountdown = lastSyncedRemaining > 0
                let reps = hasCountdown ? nil : repTarget(from: phoneState)

                VStack(spacing: 2) {
                    if isResting {
                        // Rest period mirrored from iOS. Blue, ticking down
                        // locally from the rest length sent at rest-start.
                        TimelineView(.periodic(from: lastRestSyncTime, by: 1)) { ctx in
                            let restLeft = max(0, Int((lastSyncedRest - ctx.date.timeIntervalSince(lastRestSyncTime)).rounded()))
                            Text("\(restLeft)")
                                .font(.system(size: countdownSize, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(.tint)
                                .contentTransition(.numericText())
                        }
                    } else if hasCountdown {
                        // TimelineView ticks the closure every second on
                        // watchOS without depending on Combine timers, so
                        // the countdown is reliable even when SwiftUI
                        // re-creates the parent view struct.
                        TimelineView(.periodic(from: lastSyncTime, by: 1)) { ctx in
                            let remaining: Int = {
                                if workout.isPaused {
                                    return Int(lastSyncedRemaining.rounded())
                                }
                                let elapsed = ctx.date.timeIntervalSince(lastSyncTime)
                                return max(0, Int((lastSyncedRemaining - elapsed).rounded()))
                            }()
                            Text("\(remaining)")
                                .font(.system(size: countdownSize, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(workout.isPaused ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                                .contentTransition(.numericText())
                        }
                    } else if let reps {
                        Text("\(reps)")
                            .font(.system(size: countdownSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(workout.isPaused ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                    } else {
                        Text(formatTime(workout.elapsedTime))
                            .font(.system(size: countUpSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(workout.isPaused ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                    }

                    Text(isResting
                         ? "seconds of rest left"
                         : (workout.isPaused
                            ? "paused"
                            : (hasCountdown ? "seconds left" : (reps != nil ? "reps" : "elapsed time"))))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isResting ? AnyShapeStyle(.tint) : AnyShapeStyle(workout.isPaused ? Color.orange : Color.secondary))
                }
            }

            // Control buttons
            HStack(spacing: 18) {
                // Restart current exercise — resets the iPhone's countdown
                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.sendExerciseControl(.restart)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundColor(.yellow)
                        .opacity(controlsEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
                .accessibilityLabel(Text("Restart exercise"))

                // Play/Pause Button
                Button {
                    togglePauseResume()
                } label: {
                    let systemImage = isPaused ? "play.fill" : "pause.fill"
                    Image(systemName: systemImage)
                        .font(.title)
                        .foregroundColor(.white)
                        .opacity(controlsEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
                .accessibilityLabel(Text(isPaused ? "Resume" : "Pause"))

                // Skip to next exercise
                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.sendExerciseControl(.skip)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .opacity(controlsEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
                .accessibilityLabel(Text("Skip exercise"))

                // Stop Button
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundColor(.red)
                        .opacity(controlsEnabled ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
                .accessibilityLabel(Text("End workout"))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .confirmationDialog("End workout?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End and save") { endActiveWorkout() }
            Button("Discard", role: .destructive) { endActiveWorkout(discard: true) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't end workout", isPresented: $showingEndError) {
            Button("OK", role: .cancel) {
                endErrorMessage = nil
            }
        } message: {
            Text(endErrorMessage ?? "")
        }
        .onAppear {
            // Seed from whatever state already landed before this view came up.
            resync(to: connectivity.currentWorkoutState)
        }
        .onChange(of: connectivity.currentWorkoutState.exerciseElapsedTime) { _, new in
            // iOS pushed a fresh "seconds remaining" — snap the local
            // countdown to it. Sub-second drift between pushes is what
            // the timer below interpolates.
            resync(to: connectivity.currentWorkoutState)
        }
        .onChange(of: connectivity.currentWorkoutState.currentExerciseReps) { _, _ in
            rememberPlannedReps(connectivity.currentWorkoutState)
        }
        .onChange(of: connectivity.currentWorkoutState.currentExerciseId) { _, _ in
            rememberPlannedReps(connectivity.currentWorkoutState)
            // Exercise transition: iOS sends the new exerciseElapsedTime
            // alongside, but explicitly re-syncing on id change avoids a
            // race where two pushes carry the same numeric remaining.
            resync(to: connectivity.currentWorkoutState)
        }
        .onChange(of: connectivity.currentWorkoutState.isResting) { wasResting, isResting in
            // Entering/leaving the inter-exercise rest — re-anchor the local
            // rest countdown to the value iOS just pushed.
            resync(to: connectivity.currentWorkoutState)
            // Rest over: a tap on the wrist says the next set is up.
            if wasResting == true, isResting != true {
                WKInterfaceDevice.current().play(.start)
            }
        }
        .onChange(of: connectivity.currentWorkoutState.isPaused) { _, paused in
            if !paused {
                // On resume, the "remaining" iOS just sent is anchored to
                // the resume instant. Restart the local interpolation
                // clock from now.
                lastSyncTime = .now
            }
        }
    }

    private func resync(to state: WorkoutState) {
        lastSyncTime = .now
        lastSyncedRemaining = state.exerciseElapsedTime
        lastRestSyncTime = .now
        lastSyncedRest = state.restSecondsRemaining ?? 0
    }

    private func togglePauseResume() {
        // Light haptic on intent — matches watchOS HIG for control taps.
        WKInterfaceDevice.current().play(.click)
        if let workout = watchWorkoutManager.currentWorkout {
            if workout.isPaused {
                watchWorkoutManager.resumeWorkout()
            } else {
                watchWorkoutManager.pauseWorkout()
            }
        } else if connectivity.currentWorkoutState.isActive {
            // No Health session here (e.g. access denied): pause the phone's
            // session directly. Not via `watchWorkoutManager`, which would
            // publish the state as inactive — the phone reads that as an end.
            if connectivity.currentWorkoutState.isPaused {
                connectivity.resumeWorkout()
            } else {
                connectivity.pauseWorkout()
            }
        }
    }

    private func endActiveWorkout(discard: Bool = false) {
        WKInterfaceDevice.current().play(.stop)
        Task { @MainActor in
            do {
                try await watchWorkoutManager.endWorkout(notifyPhone: true, discard: discard)
                dismiss()
            } catch {
                // Surface to the user — silently printing was leaving the
                // wrist looking unresponsive on an HK failure.
                endErrorMessage = error.localizedDescription
                showingEndError = true
            }
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct WatchMetricsView: View {
    @EnvironmentObject var watchWorkoutManager: WatchWorkoutManager
    @State private var displayTime: String = "00:00"
    @State private var heartRate: Double = 0.0
    @State private var calories: Double = 0.0
    @State private var distance: Double = 0.0
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Timer Display
                VStack(spacing: 4) {
                    Text(displayTime)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(watchWorkoutManager.currentWorkout?.isPaused == true ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                    
                    if let workout = watchWorkoutManager.currentWorkout {
                        Text(workout.isPaused ? "Paused" : "Active")
                            .font(.caption)
                            .foregroundStyle(workout.isPaused ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                    }
                }
                
                // Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    // Heart Rate
                    MetricCard(
                        value: heartRate > 0 ? "\(Int(heartRate))" : "—",
                        unit: "BPM",
                        icon: "heart.fill",
                        color: .red
                    )
                    
                    // Calories
                    MetricCard(
                        value: calories > 0 ? "\(Int(calories))" : "—",
                        unit: "CAL",
                        icon: "flame.fill",
                        color: .orange
                    )
                    
                    // Distance (if available)
                    if distance > 0 {
                        MetricCard(
                            value: String(format: "%.1f", distance / 1000),
                            unit: "KM",
                            icon: "figure.walk",
                            color: .blue
                        )
                        
                        // Pace (calculated)
                        if let workout = watchWorkoutManager.currentWorkout, workout.elapsedTime > 0 {
                            let pace = (workout.elapsedTime / 60) / (distance / 1000)
                            MetricCard(
                                value: String(format: "%.1f", pace),
                                unit: "MIN/KM",
                                icon: "speedometer",
                                color: .purple
                            )
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .onAppear {
            updateMetrics()
            updateDisplayTime()
        }
        .onReceive(timer) { _ in
            if watchWorkoutManager.isActive {
                updateDisplayTime()
                updateMetrics()
            }
        }
    }
    
    private func updateDisplayTime() {
        if let workout = watchWorkoutManager.currentWorkout {
            displayTime = formatTime(workout.elapsedTime)
        } else {
            displayTime = "00:00"
        }
    }
    
    private func updateMetrics() {
        let metrics = watchWorkoutManager.currentMetrics
        heartRate = metrics.heartRate ?? 0.0
        calories = metrics.activeEnergyBurned ?? 0.0
        distance = metrics.distance ?? 0.0
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct MetricCard: View {
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .minimumScaleFactor(0.8)
            
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

