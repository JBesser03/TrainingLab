//
//  OnboardingView.swift
//  Workout App (iOS)
//
//  The first-run setup, three short pages: weekly goals, gym equipment, and
//  Apple Health with reminders — so For You can pick a fitting workout from
//  the first day instead of guessing. Shown once to new installs
//  (`firstLaunch` sets `SettingsManager.showsOnboarding`); every page can be
//  skipped, and all of it can be changed later in For You and Settings.
//

import SwiftUI
import SwiftData
import HealthKit

@MainActor
enum Onboarding {
    static var shouldShow: Bool {
        #if DEBUG
        // UI tests can't answer its Health request; they opt in to see it.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestSkipHealthKit") && !arguments.contains("-UITestShowOnboarding") { return false }
        if arguments.contains("-UITestShowOnboarding") { return true }
        #endif
        return SettingsManager.shared.showsOnboarding
    }
}

struct OnboardingView: View {

    let onFinish: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.modelContext) private var modelContext

    enum Page: Int, CaseIterable { case goals, equipment, connect }

    @State private var page: Page = .goals
    /// Times per week, by goal category id; 0 = no goal.
    @State private var targets: [String: Int] = [GoalCategory.gym.id: 2]
    @State private var equipment: EquipmentPreset = .fullGym
    @State private var showEquipmentPicker = false
    /// "Choose each item" wrote the exact list; finishing keeps it.
    @State private var choseEachItem = false
    @State private var healthConnected = false
    @State private var remindersOn = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                goalsPage.tag(Page.goals)
                equipmentPage.tag(Page.equipment)
                connectPage.tag(Page.connect)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if let next = Page(rawValue: page.rawValue + 1) {
                    withAnimation { page = next }
                } else {
                    finish()
                }
            } label: {
                Text(page == .connect
                     ? NSLocalizedString("Start training", comment: "Onboarding: last button")
                     : NSLocalizedString("Continue", comment: "Onboarding: next page"))
            }
            .buttonStyle(.primaryAction)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityIdentifier("onboarding.next")

            Button(NSLocalizedString("Skip setup", comment: "Onboarding: leave without finishing")) {
                onFinish()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .accessibilityIdentifier("onboarding.skip")
        }
        .pageTint()
        .sheet(isPresented: $showEquipmentPicker) {
            GymEquipmentPickerView()
        }
    }

    // MARK: Pages

    private var goalsPage: some View {
        pageLayout(title: NSLocalizedString("What do you train?", comment: "Onboarding: goals title"),
             subtitle: NSLocalizedString("Set how often per week. Workouts from other apps in Apple Health count too.", comment: "Onboarding: goals subtitle")) {
            VStack(spacing: 0) {
                ForEach(GoalCategory.featured) { category in
                    goalRow(category)
                    if category.id != GoalCategory.featured.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 4)
            .cardBackground()
        }
    }

    private func goalRow(_ category: GoalCategory) -> some View {
        let value = targets[category.id] ?? 0
        return Stepper(value: Binding(get: { value }, set: { targets[category.id] = $0 }), in: 0...7) {
            HStack(spacing: 12) {
                Image(systemName: category.symbolName)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.displayName)
                    Text(value == 0
                         ? NSLocalizedString("No goal", comment: "Onboarding: sport without a weekly goal")
                         : String(format: NSLocalizedString("%d×/week", comment: "Weekly goal target"), value))
                        .font(.caption)
                        .foregroundStyle(value == 0 ? Color.secondary : Theme.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("onboarding.goal.\(category.id)")
    }

    private var equipmentPage: some View {
        pageLayout(title: NSLocalizedString("Where do you train?", comment: "Onboarding: equipment title"),
             subtitle: NSLocalizedString("Generated workouts only use exercises your equipment allows.", comment: "Onboarding: equipment subtitle")) {
            VStack(spacing: 10) {
                ForEach(EquipmentPreset.allCases) { preset in
                    Button {
                        equipment = preset
                        choseEachItem = false
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: preset.symbol)
                                .font(.title3)
                                .frame(width: 32)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title).font(.headline)
                                Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: equipment == preset ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(equipment == preset ? Theme.accent : Color.secondary)
                        }
                        .card(padding: 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(equipment == preset ? .isSelected : [])
                }
                Button(NSLocalizedString("Choose each item", comment: "Onboarding: open the full equipment list")) {
                    settings.availableGymEquipment = equipment.equipment
                    choseEachItem = true
                    showEquipmentPicker = true
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
        }
    }

    private var connectPage: some View {
        pageLayout(title: NSLocalizedString("Connect", comment: "Onboarding: Health and notifications title"),
             subtitle: NSLocalizedString("All of it stays on your devices and in your iCloud.", comment: "Onboarding: privacy note")) {
            VStack(spacing: 10) {
                connectRow(symbol: "heart.fill",
                           title: NSLocalizedString("Apple Health", comment: "Settings: section"),
                           detail: NSLocalizedString("Recovery from your sleep and heart rate, workouts from other apps, and your body weight.", comment: "Onboarding: why connect Health"),
                           below: true) {
                    if healthConnected {
                        Label(NSLocalizedString("Connected", comment: "Onboarding: Health access was asked for"), systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Button(NSLocalizedString("Connect", comment: "Onboarding: ask for Health access")) {
                            Task { await connectHealth() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.health")
                    }
                }
                connectRow(symbol: "bell.badge.fill",
                           title: NSLocalizedString("Goal reminders", comment: "Onboarding: notifications row"),
                           detail: NSLocalizedString("A nudge when a weekly goal is still open — at the time you usually train.", comment: "Onboarding: why notifications")) {
                    Toggle("", isOn: $remindersOn)
                        .labelsHidden()
                        .accessibilityLabel(Text(NSLocalizedString("Goal reminders", comment: "Onboarding: notifications row")))
                }
                connectRow(symbol: "applewatch",
                           title: NSLocalizedString("Apple Watch", comment: "Settings: section"),
                           detail: watchConnectivity.isWatchAppInstalled
                                ? NSLocalizedString("Found. Workouts started here run on your watch too.", comment: "Onboarding: watch with the app")
                                : NSLocalizedString("Install TrainingLab on your watch from the Watch app; it's used as soon as it's there.", comment: "Onboarding: no watch app yet")) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: Building blocks

    private func pageLayout<Content: View>(title: String, subtitle: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .displayFont(.largeTitle)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 48)
        }
    }

    /// - Parameter below: the control goes under the text rather than beside
    ///   it — a button there would squeeze the text into a narrow column.
    private func connectRow<Trailing: View>(symbol: String, title: String, detail: String, below: Bool = false,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if below {
                    trailing()
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 8)
            if !below {
                trailing()
            }
        }
        .card(padding: 14)
    }

    // MARK: Actions

    private func connectHealth() async {
        settings.tryEnableHealthKit = true
        #if DEBUG
        // UI tests can't answer the system sheet.
        if ProcessInfo.processInfo.arguments.contains("-UITestSkipHealthKit") {
            healthConnected = true
            return
        }
        #endif
        do {
            try await healthKitManager.requestAuthorization()
            settings.accessHealthKitSucceeded = true
            HealthGoalObserver.start(container: Workout_App.sharedContainer)
        } catch {
            appLog("Onboarding: HealthKit authorization failed: \(error)")
        }
        // HealthKit doesn't say what was allowed; asking was the step.
        healthConnected = true
    }

    private func finish() {
        let goals = GoalCategory.featured.compactMap { category -> WeeklyGoal? in
            guard let target = targets[category.id], target > 0 else { return nil }
            return WeeklyGoal(category: category, targetPerWeek: target)
        }
        if !goals.isEmpty { settings.weeklyGoals = goals }
        if !choseEachItem { settings.availableGymEquipment = equipment.equipment }
        if remindersOn {
            settings.notifications = true
            Task {
                _ = await GoalReminderScheduler.shared.requestAuthorization()
                await GoalReminderScheduler.shared.refresh(context: modelContext)
            }
        }
        onFinish()
    }
}

/// Quick picks for the equipment page.
enum EquipmentPreset: CaseIterable, Identifiable {
    case fullGym, home, none

    var id: Self { self }

    var title: String {
        switch self {
        case .fullGym: NSLocalizedString("Gym", comment: "Onboarding: equipment preset")
        case .home:    NSLocalizedString("Home with dumbbells", comment: "Onboarding: equipment preset")
        case .none:    NSLocalizedString("No equipment", comment: "Onboarding: equipment preset")
        }
    }

    var detail: String {
        switch self {
        case .fullGym: NSLocalizedString("Barbells, machines, cables and more", comment: "Onboarding: equipment preset detail")
        case .home:    NSLocalizedString("Dumbbells, a bench, bands and a mat", comment: "Onboarding: equipment preset detail")
        case .none:    NSLocalizedString("Just your body and a mat", comment: "Onboarding: equipment preset detail")
        }
    }

    var symbol: String {
        switch self {
        case .fullGym: "dumbbell.fill"
        case .home:    "house.fill"
        case .none:    "figure.core.training"
        }
    }

    var equipment: Set<Int> {
        let items: [Equipment]
        switch self {
        case .fullGym: items = Equipment.allCases.filter { $0 != .other }
        case .home:    items = [.exerciseMat, .dumbbells, .weightBench, .resistanceBands, .pullUpBar, .jumpRope, .stabilityBall, .foamRoller]
        case .none:    items = [.exerciseMat]
        }
        return Set(items.map(\.rawValue))
    }
}
