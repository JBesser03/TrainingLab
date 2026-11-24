//
//  TabBarView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 26.12.21.
//

import SwiftUI
import SwiftData
import HealthKit

struct TabBarView: View {
    @State private var selectedTab: String = "forYou"
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var workoutObserver: iOSWorkoutObserver
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.modelContext) private var modelContext
    /// Watched only for its count: a workout arriving from anywhere — finished
    /// here, on the watch, or synced from another device via iCloud — has to
    /// reach the goals widget and reminders, not just the views that query it.
    @Query private var finishedWorkouts: [FinishedWorkout]
    /// The workout to re-present when the user taps the Resume banner.
    @State private var resumeWorkout: Workout?
    @State private var isResumeSummaryPresented = false
    @State private var showWhatsNew = WhatsNew.shouldShow
    @State private var showOnboarding = Onboarding.shouldShow
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ForYouView()
            }
            .tag("forYou")
            .tabItem {
                Label("For You", systemImage: "sparkles")
            }
            .toolbarBackground(.visible, for: .tabBar)

            NavigationStack {
                WorkoutsView()
            }
            .tag("workouts")
            .tabItem {
                Label("Browse", systemImage: "square.grid.2x2")
            }
            
            NavigationStack {
                WorkoutPlansView()
            }
            .tag("plans")
            .tabItem {
                Label("Plans", systemImage: "list.clipboard.fill")
            }
            
            NavigationStack {
                ProtocolView()
            }
            .tag("history")
            .tabItem {
                Label("History", systemImage: "chart.bar.fill")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tag("settings")
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(Theme.accent)
        .safeAreaInset(edge: .top) {
            // A watch problem outside a workout — the workout screen shows its
            // own (`WatchIssueNotice`).
            if let issue = workoutObserver.lastError {
                WatchIssueNotice(message: issue) {
                    withAnimation { workoutObserver.lastError = nil }
                }
                .accessibilityIdentifier("watchIssue")
                .padding(.horizontal)
            }
            if let snapshot = settings.resumeSnapshot {
                // An interrupted workout survived a background/kill — offer to
                // resume it (or discard). Takes precedence over the watch
                // banner: after the iPhone app was killed the watch session
                // usually still runs, and this is the only way back in.
                ResumeWorkoutBanner(
                    snapshot: snapshot,
                    onResume: {
                        if let match = workout(id: snapshot.workoutID) {
                            resumeWorkout = match
                        } else {
                            // Source workout is gone — drop the stale snapshot.
                            settings.resumeSnapshot = nil
                        }
                    },
                    onDiscard: {
                        // The watch may still be running this workout.
                        if workoutObserver.isWorkoutActive,
                           workoutObserver.currentWorkoutStateID == snapshot.workoutID {
                            workoutObserver.endWorkout(discard: true)
                        }
                        settings.resumeSnapshot = nil
                        WorkoutLiveActivityController.shared.endAll()
                    }
                )
            } else if workoutObserver.isWorkoutActive,
                      workoutObserver.currentWorkout?.isActive == true {
                WatchMirroredWorkoutBanner(
                    canOpen: workoutObserver.watchStartedWorkoutID != nil,
                    onOpen: openWatchWorkout
                )
                .environmentObject(workoutObserver)
            }
        }
        .fullScreenCover(item: $resumeWorkout, onDismiss: {
            if ActiveWorkoutView.lastEndSaved { isResumeSummaryPresented = true }
        }) { workout in
            ActiveWorkoutView(workout: workout, resumeSnapshot: settings.resumeSnapshot)
        }
        .sheet(isPresented: $isResumeSummaryPresented) {
            FinishedWorkoutView(specificWorkout: nil)
        }
        // Marked seen however it's closed (button or swipe), so it shows once.
        .sheet(isPresented: $showWhatsNew, onDismiss: WhatsNew.markSeen) {
            WhatsNewView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                settings.showsOnboarding = false
                showOnboarding = false
            }
        }
        .onChange(of: settings.appTheme) { applyTheme() }
        .onChange(of: settings.colorIntensity) { applyTheme() }
        .onChange(of: selectedTab) { oldValue, newValue in
            Haptics.select()
        }
        .onAppear {
            applyTheme()
            // A Lock Screen card outlives a killed process. With no interrupted
            // workout to resume, nothing can end it any more — clear it now.
            if settings.resumeSnapshot == nil {
                WorkoutLiveActivityController.shared.endAll()
            }
        }
        // Debounced: an iCloud import can deliver many workouts in a row, and
        // a changed count cancels the pending refresh.
        .task(id: finishedWorkouts.count) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await GoalReminderScheduler.shared.refresh(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            // The week-rollover engine. iOS gives this app no background
            // execution, so the pending goal reminders are only ever as fresh
            // as the last foreground — and progress can change without any
            // local event at all, since `FinishedWorkout` syncs via CloudKit
            // while the goals themselves are device-local UserDefaults.
            //
            // This lives on TabBarView rather than ForYouView because it is
            // always mounted, whichever tab the user left the app on.
            guard phase == .active else { return }
            Task {
                await GoalReminderScheduler.shared.refresh(context: modelContext)
                // Picks up plans added, edited or deleted on another device.
                await NotificationManager.shared.refreshPlanReminders(context: modelContext)
                // Keeps the watch's workout list current (see `WatchLibrary`).
                WatchConnectivityManager.shared.sendWorkoutLibrary(context: modelContext)
            }
        }
        // Outermost, so sheets and covers presented from here carry it too.
        .environment(\.appTheme, settings.appTheme)
        .environment(\.colorIntensity, settings.colorIntensity)
    }

    /// The chosen style as a trait of every window: `Theme`'s colors resolve
    /// against it, so they change in place, sheets and alerts included. The
    /// navigation bar titles are UIKit's and get the style's font here.
    private func applyTheme() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.traitOverrides.appTheme = settings.appTheme
                window.traitOverrides.colorIntensity = settings.colorIntensity
                // Alerts and confirmation dialogs take the window's tint.
                window.tintColor = AppTheme.themed(.accent)
            }
        }
        Theme.applyNavigationBarFonts(settings.appTheme)
    }

    /// Opens the workout screen for a workout started on the watch, which then
    /// drives the watch's session (see `iOSWorkoutObserver.joinWatchWorkout`).
    /// Its snapshot makes it resumable like one started here.
    private func openWatchWorkout() {
        guard let id = workoutObserver.watchStartedWorkoutID, let match = workout(id: id) else { return }
        settings.resumeSnapshot = workoutObserver.joinWatchWorkout(match)
        resumeWorkout = match
    }

    /// Looked up when the banner is tapped. A `@Query` of every workout here
    /// kept the whole table observed at the root of the app, re-running this
    /// body whenever any workout changed — which happens during every workout.
    private func workout(id: String) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

private struct ResumeWorkoutBanner: View {
    let snapshot: ResumeSnapshot
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workoutName.isEmpty
                     ? NSLocalizedString("Workout in progress", comment: "Resume banner: fallback title")
                     : snapshot.workoutName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("Tap to resume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDiscard) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Discard workout"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture(perform: onResume)
    }
}

private struct WatchMirroredWorkoutBanner: View {
    /// False when the iPhone has no workout screen for it (a watch quick start).
    let canOpen: Bool
    let onOpen: () -> Void
    @EnvironmentObject private var workoutObserver: iOSWorkoutObserver
    @State private var confirmEnd = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(workoutObserver.currentWorkout?.workoutName.isEmpty == false
                     ? workoutObserver.currentWorkout?.workoutName ?? NSLocalizedString("Apple Watch workout", comment: "Watch banner: fallback name")
                     : NSLocalizedString("Apple Watch workout", comment: "Watch banner: fallback name"))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatDuration(workoutObserver.watchElapsedTime))
                    if workoutObserver.currentHeartRate > 0 {
                        Label("\(Int(workoutObserver.currentHeartRate))", systemImage: "heart.fill")
                    }
                    if canOpen {
                        Text("Tap to open")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Live")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.accent)

            // Without an action this banner was a dead end whenever the
            // iPhone lost track of a workout still running on the watch.
            Button(NSLocalizedString("End", comment: "Watch banner: end the watch workout")) {
                confirmEnd = true
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture {
            if canOpen { onOpen() }
        }
        .confirmationDialog(NSLocalizedString("End workout?", comment: "Watch banner: end confirmation"),
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(NSLocalizedString("End workout", comment: "Watch banner: confirm end"), role: .destructive) {
                workoutObserver.endMirroredWorkoutFromPhone()
            }
            Button(NSLocalizedString("Cancel", comment: "Watch banner: cancel end"), role: .cancel) {}
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


struct TabBarView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarView()
    }
}

