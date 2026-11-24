//
//  WeeklyGoalsEditorView.swift
//  Workout App (iOS)
//
//  Sheet for setting weekly training-frequency targets per activity (e.g.
//  "Running ×2/week"). Goals are added from the sport catalog or as a named
//  group of sports (`GoalSportPickerView`), removed by swiping, and reordered
//  by dragging — the order is the one the For You card and the widget use.
//
//  Also where reminders are opted into: this is the moment a nudge starts
//  meaning something, so it's where the system permission prompt is asked for
//  rather than at launch. See `iOS/GoalReminders.swift` for what actually
//  gets scheduled.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct WeeklyGoalsEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @StateObject private var settings = SettingsManager.shared
    @StateObject private var scheduler = GoalReminderScheduler.shared

    @State private var goals: [WeeklyGoal]
    @State private var showSportPicker = false
    @State private var editingGroup: GoalCategory?
    @State private var remindersEnabled: Bool
    @State private var usesCustomTime: Bool
    @State private var reminderTime: Date
    @State private var showPermissionExplainer = false

    /// The hour to pre-fill the picker with when the user hasn't chosen one —
    /// inferred by the caller from training history.
    private let suggestedHour: Int

    init(suggestedHour: Int = GoalReminderPlanner.defaultHour) {
        self.suggestedHour = suggestedHour

        let settings = SettingsManager.shared
        _goals = State(initialValue: settings.weeklyGoals.filter { $0.targetPerWeek > 0 })

        _remindersEnabled = State(initialValue: settings.notifications)
        _usesCustomTime = State(initialValue: settings.goalReminderHour != nil)

        var components = DateComponents()
        components.hour = settings.goalReminderHour ?? suggestedHour
        components.minute = settings.goalReminderMinute
        _reminderTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    /// Enough to fill the For You card without it turning into a list; the
    /// widget shows the first three.
    static let maxGoals = 6

    private var hasAnyGoal: Bool { !goals.isEmpty }

    var body: some View {
        NavigationStack {
            StyledForm {
                Section {
                    ForEach($goals) { $goal in
                        Stepper(value: $goal.targetPerWeek, in: 1...7) {
                            GoalRowLabel(goal: goal)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                goals.removeAll { $0.id == goal.id }
                            } label: {
                                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                            }
                            if goal.category.isGroup {
                                Button {
                                    editingGroup = goal.category
                                } label: {
                                    Label(NSLocalizedString("Edit", comment: "Weekly goals: edit a sport group"), systemImage: "pencil")
                                }
                            }
                        }
                    }
                    .onMove { goals.move(fromOffsets: $0, toOffset: $1) }

                    if goals.count < Self.maxGoals {
                        Button {
                            showSportPicker = true
                        } label: {
                            Label(NSLocalizedString("Add goal", comment: "Weekly goals: add a goal"), systemImage: "plus.circle.fill")
                        }
                    }
                } footer: {
                    Text(NSLocalizedString("Swipe left to edit or remove a goal, hold and drag to reorder. Workouts other apps save to Apple Health count too.",
                                           comment: "Weekly goals footer"))
                }

                if hasAnyGoal {
                    remindersSection
                }
            }
            .navigationTitle(NSLocalizedString("Weekly goals", comment: "Weekly goals editor title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Save", comment: "")) {
                        Task { await save() }
                    }
                    .bold()
                }
            }
            .task { await scheduler.refreshAuthorizationStatus() }
            .sheet(isPresented: $showSportPicker) {
                GoalSportPickerView(excluded: Set(goals.map(\.id))) { category in
                    goals.append(WeeklyGoal(category: category, targetPerWeek: 1))
                }
            }
            .sheet(item: $editingGroup) { group in
                NavigationStack {
                    GoalGroupEditorView(group: group) { updated in
                        if let index = goals.firstIndex(where: { $0.id == updated.id }) {
                            goals[index].category = updated
                        }
                    }
                }
            }
            .alert(NSLocalizedString("Get a nudge when you're falling behind",
                                     comment: "Notification permission explainer title"),
                   isPresented: $showPermissionExplainer) {
                Button(NSLocalizedString("Not now", comment: "Notification permission explainer: decline")) {
                    // Keep the goals that were just saved, just without
                    // reminders. Don't ask again this session.
                    settings.notifications = false
                    dismiss()
                }
                Button(NSLocalizedString("Continue", comment: "Notification permission explainer: accept")) {
                    Task {
                        await scheduler.requestAuthorization()
                        await scheduler.refresh(context: modelContext)
                        dismiss()
                    }
                }
            } message: {
                Text(NSLocalizedString("TrainingLab sends at most two reminders a week, and none at all once your goals are met.",
                                       comment: "Notification permission explainer body"))
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            if scheduler.authorizationStatus == .denied {
                // iOS never shows the permission prompt twice, so re-asking
                // here would do nothing — send the user to Settings instead.
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Notifications are off in iOS Settings.",
                                           comment: "Weekly goals: notifications denied"))
                        .font(.subheadline)
                    Button(NSLocalizedString("Open Settings", comment: "Weekly goals: open iOS settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } else {
                Toggle(NSLocalizedString("Remind me", comment: "Weekly goals: reminders toggle"),
                       isOn: $remindersEnabled)

                if remindersEnabled {
                    Picker(NSLocalizedString("Reminder time", comment: "Weekly goals: reminder time picker"),
                           selection: $usesCustomTime) {
                        Text(NSLocalizedString("Automatic", comment: "Weekly goals: automatic reminder time")).tag(false)
                        Text(NSLocalizedString("Custom", comment: "Weekly goals: custom reminder time")).tag(true)
                    }
                    .pickerStyle(.segmented)

                    if usesCustomTime {
                        DatePicker(NSLocalizedString("Time", comment: "Weekly goals: reminder time"),
                                   selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                    } else {
                        HStack {
                            Text(NSLocalizedString("Time", comment: "Weekly goals: reminder time"))
                            Spacer()
                            Text(automaticTimeDescription)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(NSLocalizedString("Reminders", comment: "Weekly goals: reminders section header"))
        } footer: {
            Text(NSLocalizedString("You'll only hear from us when a goal is still open — and never once you've hit it. Automatic picks a time from when you usually train.",
                                   comment: "Weekly goals: reminders footer"))
        }
    }

    /// The hour "Automatic" currently resolves to, so the choice isn't opaque.
    private var automaticTimeDescription: String {
        var components = DateComponents()
        components.hour = suggestedHour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Actions

    private func save() async {
        settings.weeklyGoals = goals

        if usesCustomTime {
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            settings.goalReminderHour = components.hour
            settings.goalReminderMinute = components.minute ?? 0
        } else {
            settings.goalReminderHour = nil
            settings.goalReminderMinute = 0
        }

        // Only touch the master switch when the reminders section was
        // actually on screen. Clearing every goal shouldn't silently revoke
        // the notification opt-in that plan reminders also rely on.
        let wantsReminders = remindersEnabled && hasAnyGoal
        if hasAnyGoal {
            settings.notifications = remindersEnabled
        }

        // First time asking: explain what they're signing up for before the
        // system prompt, so a reflexive "Don't Allow" doesn't kill the feature
        // permanently. Deliberately does *not* dismiss yet.
        if wantsReminders, scheduler.authorizationStatus == .notDetermined {
            showPermissionExplainer = true
            return
        }

        await scheduler.refresh(context: modelContext)
        dismiss()
    }
}

/// Symbol, name (with a group's sports underneath) and the weekly target.
private struct GoalRowLabel: View {
    let goal: WeeklyGoal

    var body: some View {
        HStack {
            Image(systemName: goal.category.symbolName)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.category.displayName)
                if goal.category.isGroup {
                    Text(goal.category.groupSports.map(\.displayName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(String(format: NSLocalizedString("%d×/week", comment: "Weekly goal stepper value"), goal.targetPerWeek))
                .foregroundStyle(Theme.accent)
                .font(.headline)
        }
    }
}
