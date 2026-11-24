//
//  ContentView.swift
//  Workout Watch App
//
//  Created by Justus Besser on 26.08.23.
//

import SwiftUI
import HealthKit
import SwiftData
import WatchKit

struct ContentView: View {
    @State private var errorMessage: String?
    @State private var showingError = false

    @EnvironmentObject var watchWorkoutManager: WatchWorkoutManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @State private var healthAccessMissing = false
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    @Environment(\.modelContext) var modelContext
    /// CloudKit-synced data. Only used until the iPhone has sent its list
    /// (`connectivity.workoutLibrary`): CloudKit often never reaches the watch.
    @Query var allWorkouts: [Workout]
    @Query var plans: [Plan]

    private var library: WatchLibrary {
        connectivity.workoutLibrary ?? WatchLibrary.make(workouts: allWorkouts, plans: plans)
    }

    private var hasActiveWorkout: Bool {
        watchWorkoutManager.isActive || connectivity.currentWorkoutState.isActive
    }
    
    var body: some View {
        Group {
            if hasActiveWorkout {
                CurrentWorkoutView()
                    .task {
                        await ensureLocalWorkoutSessionStarted()
                    }
            } else {
                workoutList
            }
        }
        // The accent chosen on the iPhone; the watch's own (the default style's) until it arrives.
        .tint(connectivity.accentColor)
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            requestStateRefresh()
        }
        .onChange(of: watchWorkoutManager.lastError) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            errorMessage = newValue
            watchWorkoutManager.lastError = nil
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = nil
                showingError = false
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: errorMessage) { _, newValue in
            showingError = newValue != nil
        }
    }

    private var workoutList: some View {
        NavigationView {
            List {
                let library = self.library

                // One row per plan in progress: tap starts its next workout.
                if !library.plans.isEmpty {
                    Section("Plans") {
                        ForEach(library.plans, id: \.planId) { entry in
                            Button {
                                startSyncedWorkout(entry.next)
                            } label: {
                                PlanNextWorkoutRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // The user's own workouts from the iPhone (outside plans).
                if !library.own.isEmpty {
                    Section("From iPhone") {
                        workoutRows(library.own)
                    }
                }

                // A few workouts from the iPhone's catalog.
                if !library.catalog.isEmpty {
                    Section("Catalog") {
                        workoutRows(library.catalog)
                    }
                }

                // Generic quick-start types — no library lookup required,
                // good fallback for ad-hoc workouts.
                Section("Quick start") {
                    // The name is also what the iPhone's history shows, so it
                    // is localized here rather than only in the row.
                    ForEach(quickStartTypes, id: \.type) { item in
                        WorkoutTypeRow(title: item.name, type: item.type) {
                            startWorkout(type: item.type, workoutName: item.name)
                        }
                    }
                }

                // Only shown while access is missing. Implicit auth flows can
                // be skipped when the iPhone launches this app in the
                // background, so the wrist needs its own way to ask.
                if healthAccessMissing {
                    Section {
                        HealthAccessRow { healthAccessMissing = false }
                    } header: {
                        Text("Health")
                    }
                }
            }
            .navigationTitle("Workouts")
            .onAppear {
                requestStateRefresh()
                healthAccessMissing = HKHealthStore.shared.authorizationStatus(for: .workoutType()) != .sharingAuthorized
            }
        }
    }
    
    private func workoutRows(_ workouts: [WatchWorkoutSummary]) -> some View {
        ForEach(workouts, id: \.id) { workout in
            Button {
                startSyncedWorkout(workout)
            } label: {
                WorkoutHistoryRow(workout: workout)
            }
            .buttonStyle(.plain)
        }
    }

    private func requestStateRefresh() {
        connectivity.requestSync()
    }

    private var quickStartTypes: [(type: HKWorkoutActivityType, name: String)] {
        [(.highIntensityIntervalTraining, NSLocalizedString("HIIT", comment: "Watch quick start")),
         (.running, NSLocalizedString("Running", comment: "Watch quick start")),
         (.cycling, NSLocalizedString("Cycling", comment: "Watch quick start")),
         (.functionalStrengthTraining, NSLocalizedString("Strength", comment: "Watch quick start")),
         (.swimming, NSLocalizedString("Swimming", comment: "Watch quick start")),
         (.walking, NSLocalizedString("Walking", comment: "Watch quick start")),
         (.yoga, NSLocalizedString("Yoga", comment: "Watch quick start"))]
    }

    private func startFailedMessage(_ error: Error) -> String {
        String(format: NSLocalizedString("Failed to start workout: %@", comment: "Watch: start error"),
               error.localizedDescription)
    }

    @MainActor
    private func ensureLocalWorkoutSessionStarted() async {
        guard !watchWorkoutManager.isActive,
              connectivity.currentWorkoutState.isActive else { return }

        let state = connectivity.currentWorkoutState
        let workoutName = state.workoutName.isEmpty
            ? NSLocalizedString("Workout", comment: "Watch: fallback workout name")
            : state.workoutName

        // Honor the activity / location type sent from iOS so HK records
        // the workout correctly (calorie & distance accuracy depend on it).
        // Fall back to functionalStrengthTraining only if the WCSession
        // state arrived without an activity-type hint.
        let activity = HKWorkoutActivityType(rawValue: state.workoutActivityType)
            ?? .functionalStrengthTraining
        let location = HKWorkoutSessionLocationType(rawValue: state.workoutLocationType)
            ?? .unknown
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = location

        do {
            try await watchWorkoutManager.startWorkout(
                configuration: configuration,
                workoutName: workoutName,
                notifyPhone: false
            )
        } catch {
            errorMessage = startFailedMessage(error)
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType, workoutName: String) {
        Task { @MainActor in
            do {
                try await watchWorkoutManager.startWorkout(type: type, workoutName: workoutName)
            } catch {
                errorMessage = startFailedMessage(error)
            }
        }
    }

    /// Start a workout selected from the synced (iPhone-authored) list,
    /// honoring its configured activity type so HealthKit records the right
    /// session category.
    private func startSyncedWorkout(_ workout: WatchWorkoutSummary) {
        Task { @MainActor in
            do {
                try await watchWorkoutManager.startWorkout(summary: workout)
            } catch {
                errorMessage = startFailedMessage(error)
            }
        }
    }
}

// MARK: - Helper Views

struct WorkoutTypeRow: View {
    let title: String
    let type: HKWorkoutActivityType
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: workoutIcon(for: type))
                .foregroundColor(workoutColor(for: type))
                .frame(width: 24)
            
            Text(title)
            
            Spacer()
            
            Button("Start") {
                action()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .contentShape(Rectangle())
    }
    
    private func workoutIcon(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .highIntensityIntervalTraining: return "flame.fill"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .functionalStrengthTraining: return "dumbbell.fill"
        case .swimming: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        default: return "figure.walk"
        }
    }
    
    private func workoutColor(for type: HKWorkoutActivityType) -> Color {
        switch type {
        case .highIntensityIntervalTraining: return .orange
        case .running: return .green
        case .cycling: return .blue
        case .functionalStrengthTraining: return .purple
        case .swimming: return .cyan
        case .walking: return .yellow
        case .yoga: return .mint
        default: return .gray
        }
    }
}

// MARK: - Current Workout View

struct CurrentWorkoutView: View {
    enum Tab: CaseIterable {
        case metrics, controls, music
        
        var title: String {
            switch self {
            case .metrics: return "Metrics"
            case .controls: return "Controls"
            case .music: return "Music"
            }
        }
    }
    
    @State private var selection: Tab = .controls
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var watchWorkoutManager: WatchWorkoutManager
    
    var body: some View {
        TabView(selection: $selection) {
            WatchMetricsView()
                .tag(Tab.metrics)
            
            ControlsView()
                .tag(Tab.controls)
            
            // The system's Now Playing controls: whatever plays on the watch
            // or the iPhone, from any app.
            WatchKit.NowPlayingView()
                .tag(Tab.music)
        }
        .tabViewStyle(.page)
        .onChange(of: watchWorkoutManager.isActive) { _, isActive in
            if !isActive {
                dismiss()
            }
        }
    }
}

/// Asks for HealthKit workout access from the wrist. Implicit auth flows
/// (the scene's `.task`, the app delegate) can be skipped when the iPhone
/// launches this app in the background, so the user needs a way to trigger
/// the prompt here. Once denied, iOS never shows the prompt again, so that
/// case explains where to turn access back on instead.
struct HealthAccessRow: View {
    var onGranted: () -> Void

    @State private var status: HKAuthorizationStatus = HKHealthStore.shared.authorizationStatus(for: .workoutType())
    @State private var inFlight = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status == .sharingDenied {
                Text("HealthKit access is off. On iPhone, open the Watch app → TrainingLab → Privacy and enable Health.")
                    .font(.caption2)
            } else {
                Text("Health access is needed to record workouts.")
                    .font(.caption2)
                Button {
                    Task { await requestPermission() }
                } label: {
                    if inFlight {
                        ProgressView()
                    } else {
                        Text("Allow access")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(inFlight)
            }

            if let failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @MainActor
    private func requestPermission() async {
        inFlight = true
        failure = nil
        defer { inFlight = false }
        do {
            try await WatchWorkoutManager.shared.requestHealthKitAuthorization()
            status = HKHealthStore.shared.authorizationStatus(for: .workoutType())
            if status == .sharingAuthorized { onGranted() }
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct PlanNextWorkoutRow: View {
    let entry: WatchPlanEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.planName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                // Composed in code: a key made only of format specifiers
                // can't be put in the string catalog (symbol generation).
                Text(verbatim: "\(entry.next.name) · \(entry.done)/\(entry.total)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }
}

struct WorkoutHistoryRow: View {
    let workout: WatchWorkoutSummary

    /// "Advanced · 7 exercises": the level of a built-in workout, which its
    /// name leaves out, and how many exercises.
    private var detail: String? {
        let exercises = workout.exerciseCount > 0
            // Int64 for %lld: `Int` is 32 bits on the Series 4 (arm64_32).
            // `localizedStringWithFormat` applies the plural forms.
            ? String.localizedStringWithFormat(NSLocalizedString("%lld exercises", comment: "Watch: number of exercises in a workout"),
                                               Int64(workout.exerciseCount))
            : nil
        let parts = [workout.level, exercises].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }
}
