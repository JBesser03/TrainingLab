//
//  ForYouView.swift
//  Workout App (iOS)
//
//  The app's default landing tab: a personalized surface built on top of the
//  existing recovery/generator engine (WorkoutIntelligence.swift) instead of
//  the full, unfiltered workout catalog. Replaces the old "Smart workout"
//  beta sheet as the primary way to reach these features.
//
//  Weekly goals (`iOS/WeeklyGoals.swift`) let a user track multiple
//  activities at their own flexible cadence — e.g. "Running ×2/week" and
//  "Gym ×2/week" — rather than a fixed sequence: any open goal can be done in
//  any order, so both a gym card and a running card can be open at once.
//

import SwiftUI
import SwiftData
import HealthKit

struct ForYouView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var workoutObserver: iOSWorkoutObserver
    @EnvironmentObject private var healthManager: HealthKitManager

    @Query(sort: \FinishedWorkout.endDate, order: .reverse) private var finishedWorkouts: [FinishedWorkout]
    @Query private var existingExercises: [Exercise]
    @Query(filter: #Predicate<Workout> { !$0.isHidden }) private var allWorkouts: [Workout]

    @StateObject private var settings = SettingsManager.shared

    @State private var isLoading = true
    @State private var recovery: RecoveryEstimate?
    @State private var plan: PersonalizedWorkoutPlan?
    @State private var narrative: CoachNarrative?
    /// Narratives already written for a plan, keyed by `narrativeKey` — every
    /// sheet dismissal re-runs `load()`, and an unchanged plan shouldn't cost
    /// another model call (or change its wording under the user).
    @State private var narrativeCache: [String: CoachNarrative] = [:]
    @State private var narrativeTask: Task<Void, Never>?
    @State private var notEnoughEquipment = false
    @State private var didSave = false
    @State private var showEquipmentPicker = false
    @State private var showGoalsEditor = false
    @State private var startWorkout: Workout?
    @State private var isSummaryPresented = false
    /// This week's "next run", already readiness-adjusted by `load()` — nil
    /// when there's no open running goal (recomputing it would be wasted work).
    @State private var runningSessionPreview: Workout?
    /// Other apps' workouts this week (Apple Workout, Strava, …), which count
    /// toward goals too. Loaded in `load()`.
    @State private var externalThisWeek: [ExternalWorkout] = []
    /// Bumped by the toolbar's Regenerate so it yields a different exercise
    /// selection instead of rebuilding the day's identical plan.
    @State private var variation = 0
    /// A type the user picked instead of the recommended one; nil follows
    /// the recommendation. Holds until a workout is finished anywhere or the
    /// day changes (see `load()`).
    @State private var chosenSplit: GymSplit?
    @State private var chosenSplitAt: Date?
    #if DEBUG
    @State private var mockEnabled = DebugHealthData.isEnabled
    @AppStorage(AppleIntelligence.simulateUnavailableKey) private var simulateNoAppleIntelligence = false
    #endif

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                if isLoading {
                    // The shapes of what's coming, instead of a spinner.
                    VStack(spacing: 20) {
                        SkeletonCard(lines: 4)
                        SkeletonCard(lines: 2, showsButton: false)
                    }
                    .padding(.horizontal)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(NSLocalizedString("Analyzing your recovery…", comment: "Loading")))
                } else {
                    // Today's sessions first, with their Start buttons.
                    sessionCards

                    if let recovery {
                        RecoveryScoreCard(recovery: recovery, onConnectHealth: connectHealth)
                            .padding(.horizontal)
                    }

                    if hasGoals {
                        WeeklyGoalsCard(rows: goalRows) { showGoalsEditor = true }
                            .padding(.horizontal)
                    } else {
                        SetGoalPromptCard { showGoalsEditor = true }
                            .padding(.horizontal)
                    }

                    if !hasCustomizedEquipment {
                        EquipmentNudgeBanner { showEquipmentPicker = true }
                            .padding(.horizontal)
                    }

                    if !pickedForYou.isEmpty {
                        HorizontalScrollView(workouts: pickedForYou, content: .forYou)
                    }

                    disclaimer
                        .padding(.horizontal)
                }

                #if DEBUG
                if !DemoData.isActive {
                    debugControls
                        .padding(.horizontal)
                }
                #endif
            }
            .padding(.top, 8)
            .padding(.bottom, Spacing.l)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
        }
        .pageTint()
        .navigationTitle(NSLocalizedString("For You", comment: "Screen title"))
        .toolbar {
            if plan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await regenerate() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(Text(NSLocalizedString("Regenerate", comment: "")))
                }
            }
        }
        .sheet(isPresented: $showEquipmentPicker, onDismiss: { Task { await load() } }) {
            GymEquipmentPickerView()
        }
        .sheet(isPresented: $showGoalsEditor, onDismiss: { Task { await load() } }) {
            WeeklyGoalsEditorView(suggestedHour: settings.goalReminderHour
                                  ?? GoalReminderPlanner.inferredHour(history: finishedWorkouts))
        }
        .fullScreenCover(item: $startWorkout, onDismiss: presentSummary) { workout in
            ActiveWorkoutView(workout: workout, plan: nil)
        }
        .sheet(isPresented: $isSummaryPresented, onDismiss: { Task { await load() } }) {
            FinishedWorkoutView(specificWorkout: nil)
        }
        .task {
            WorkoutCoach.prewarm()
            await load()
        }
    }

    private var hasGoals: Bool { !settings.weeklyGoals.isEmpty }

    /// The sessions to start today: the gym workout (the general fallback
    /// without goals, or the Gym goal's next session while it's open), the
    /// next run, and a session for every other open goal.
    @ViewBuilder
    private var sessionCards: some View {
        if !hasGoals || isGoalOpen(.gym) {
            if notEnoughEquipment {
                NotEnoughEquipmentCard { showEquipmentPicker = true }
                    .padding(.horizontal)
            } else if let plan {
                GeneratedWorkoutCard(plan: plan, narrative: narrative, didSave: didSave,
                                     onSelectSplit: selectSplit) {
                    startGymWorkout(plan)
                } onSave: {
                    save(plan)
                }
                .padding(.horizontal)
            }
        }

        // Running only ever appears as an explicit goal — there's no
        // "general fallback" run the way there is for gym.
        if isGoalOpen(.running), let runningSessionPreview {
            RunningSessionCard(workout: runningSessionPreview) {
                startSession(runningSessionPreview)
            }
            .padding(.horizontal)
        }

        // Every other open goal — swimming, cycling, a group… — gets a plain
        // session for its sport.
        ForEach(otherOpenGoals, id: \.goal.id) { item in
            GoalSessionCard(goal: item.goal, sports: item.sports) { type in
                startSession(GoalSessionBuilder.makeWorkout(type: type, uniqueName: uniqueWorkoutName(type.name)))
            }
            .padding(.horizontal)
        }
    }

    /// Asks for Apple Health, as Settings' switch does, and rebuilds the
    /// recommendation from the new data.
    private func connectHealth() {
        settings.tryEnableHealthKit = true
        Task {
            do {
                try await healthManager.requestAuthorization()
                settings.accessHealthKitSucceeded = true
            } catch {
                appLog("error requesting healthkit authorization: \(error)")
            }
            await load()
        }
    }

    private var goalRows: [WeeklyGoalsCard.Row] {
        settings.weeklyGoals.map { goal in
            let progress = goalProgressThisWeek(goal.category, history: finishedWorkouts, external: externalThisWeek)
            return WeeklyGoalsCard.Row(category: goal.category, target: goal.targetPerWeek,
                                       completed: progress.own + progress.external,
                                       fromOtherApps: progress.external)
        }
    }

    /// Open goals besides Gym and Running, which have cards of their own, with
    /// the sports that can be started for each. A group's Gym is left out —
    /// the gym card covers it — and a group with nothing else gets no card.
    private var otherOpenGoals: [(goal: GoalCategory, sports: [HKWorkoutActivityType])] {
        settings.weeklyGoals.compactMap { goal in
            let category = goal.category
            guard category.id != GoalCategory.gym.id, category.id != GoalCategory.running.id,
                  isGoalOpen(category) else { return nil }
            let sports = category.isGroup
                ? category.groupSports.filter { $0.id != GoalCategory.gym.id }.flatMap(\.sportTypes)
                : category.sportTypes
            return sports.isEmpty ? nil : (category, sports)
        }
    }

    /// True when `category` has a configured goal that isn't yet met this week.
    private func isGoalOpen(_ category: GoalCategory) -> Bool {
        guard let goal = settings.weeklyGoals.first(where: { $0.category.id == category.id }) else { return false }
        return completedThisWeek(goal.category, history: finishedWorkouts, external: externalThisWeek) < goal.targetPerWeek
    }

    private var disclaimer: some View {
        Text(NSLocalizedString("Recommendations are on-device estimates from your health and training data — not medical advice.", comment: "AI feature disclaimer"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// True once the user has trimmed the equipment set from its "everything
    /// available" install default — used to decide whether the (non-blocking)
    /// equipment nudge is still worth showing.
    private var hasCustomizedEquipment: Bool {
        settings.availableGymEquipment != Set(Equipment.allCases.filter { $0 != .other }.map(\.rawValue))
    }

    /// A short, ranked shelf of existing catalog workouts that fit the user's
    /// declared equipment and recent difficulty tolerance — a handful of good
    /// next picks, not the full catalog.
    private var pickedForYou: [Workout] {
        let tolerance = WorkoutDifficultyPredictor.userTolerance(history: finishedWorkouts)
        let equipment = settings.availableGymEquipment

        let scored = allWorkouts
            // Catalog content only — `isUserGenerated` covers manually-added
            // workouts and anything from the Gym/Running/Natural-language
            // generators. Those aren't marked `isSaved` (only the ad-hoc
            // single-workout generator sets that), so relying on `isSaved`
            // alone let running-plan sessions (which have no exercises, so
            // they trivially pass the equipment check below) leak in here.
            .filter { !$0.isUserGenerated && !$0.isSaved && !(($0.exercises ?? []).isEmpty) }
            .map { workout -> (Workout, Double) in
                let required = Set((workout.exercises ?? []).flatMap(\.equipment))
                let equipmentPenalty = required.isSubset(of: equipment) ? 0.0 : 10.0
                let difficultyDelta = abs(Double(workout.difficultyInt) - tolerance)
                return (workout, difficultyDelta + equipmentPenalty)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.isNew && !rhs.0.isNew
            }

        return Array(scored.prefix(5).map(\.0))
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        didSave = false
        let history = finishedWorkouts
        externalThisWeek = await externalWorkoutsThisWeek()
        let inputs = await RecoveryMetricsProvider().loadInputs(history: history)
        let estimate = RecoveryEstimator.estimate(from: inputs)
        recovery = estimate

        // A hand-picked type only holds until the history moves on — a workout
        // finished here, in Browse, from a plan or on the watch — or the day
        // changes; then the card follows the recommendation again.
        if let chosenAt = chosenSplitAt,
           (history.first.map { $0.endDate > chosenAt } ?? false) || !Calendar.current.isDateInToday(chosenAt) {
            chosenSplit = nil
            chosenSplitAt = nil
        }

        // Gym: always computed — it's either the no-goals fallback or the
        // "Gym" goal's next session.
        buildGymPlan(recovery: estimate, history: history)

        // Running: only worth computing while that goal is open.
        if isGoalOpen(.running) {
            let completed = completedThisWeek(.running, history: history, external: externalThisWeek)
            let sessionPlan = RunningSessionBuilder.nextSession(completedThisWeek: completed, recovery: estimate)
            let name = uniqueWorkoutName(NSLocalizedString(sessionPlan.kind.nameKey, comment: "Running session kind"))
            runningSessionPreview = sessionPlan.makeWorkout(uniqueName: name)
        } else {
            runningSessionPreview = nil
        }

        isLoading = false

        // A second pass after TabBarView's foreground refresh, by which point
        // a CloudKit import triggered on activation has had a chance to land.
        // Cheap — the history is already in hand.
        await GoalReminderScheduler.shared.refresh(goals: settings.weeklyGoals, history: history,
                                                   external: externalThisWeek)
    }

    private func buildGymPlan(recovery: RecoveryEstimate, history: [FinishedWorkout]) {
        let generator = PersonalizedWorkoutGenerator(
            availableEquipment: settings.availableGymEquipment,
            history: history)
        let generated = generator.generate(recovery: recovery, variation: variation, split: chosenSplit)
        // The equipment may no longer build the chosen type; the generator then
        // fell back to the recommendation, so stop asking for it.
        if chosenSplit != nil, generated?.split != chosenSplit {
            chosenSplit = nil
            chosenSplitAt = nil
        }

        plan = generated
        notEnoughEquipment = generated == nil
        // Not awaited: the plan is ready now, and the card shows the
        // deterministic title/rationale until the model's wording arrives.
        requestNarrative(for: generated)
    }

    private func regenerate() async {
        Haptics.tap()
        variation += 1
        await load()
    }

    /// Swaps the gym card to another type. Only the plan is rebuilt — the
    /// recovery estimate is still current, so no reload or spinner.
    private func selectSplit(_ split: GymSplit) {
        guard let plan, split != plan.split else { return }
        Haptics.select()
        chosenSplit = split == plan.recommendedSplit ? nil : split
        chosenSplitAt = chosenSplit == nil ? nil : .now
        didSave = false
        withAnimation {
            buildGymPlan(recovery: plan.recovery, history: finishedWorkouts)
        }
    }

    /// Everything the narrative depends on. Same key → same facts → the
    /// cached narrative still fits.
    private func narrativeKey(_ plan: PersonalizedWorkoutPlan) -> String {
        let daysSinceTrained = plan.hoursSinceTrained.map { "\(Int($0 / 24))" } ?? "-"
        return ([plan.split.rawValue, "\(plan.isUserChosenSplit)", "\(plan.recovery.score)", plan.prediction.label, daysSinceTrained]
                + plan.exercises.map(\.id)).joined(separator: "|")
    }

    private func requestNarrative(for plan: PersonalizedWorkoutPlan?) {
        narrativeTask?.cancel()
        guard let plan else {
            narrative = nil
            return
        }
        let key = narrativeKey(plan)
        if let cached = narrativeCache[key] {
            narrative = cached
            return
        }
        narrative = nil
        narrativeTask = Task {
            let result = await WorkoutCoach.narrative(for: plan)
            // A newer plan may have replaced this one while the model ran.
            guard !Task.isCancelled else { return }
            narrativeCache[key] = result
            if let current = self.plan, narrativeKey(current) == key {
                withAnimation { narrative = result }
            }
        }
    }

    /// Saved names are deterministic: the model's title varies between
    /// generations and would otherwise end up in the history as the name.
    ///
    /// A started (not saved) session is hidden, so each "Start" doesn't add a
    /// "Push (2)", "Push (3)", … to the user's workouts. Its history entry keeps
    /// the name and exercises.
    private func startGymWorkout(_ plan: PersonalizedWorkoutPlan) {
        let workout = plan.makeWorkout(in: modelContext, existingExercises: existingExercises,
                                       name: plan.split.displayName)
        workout.isHidden = true
        modelContext.insert(workout)
        do {
            try modelContext.save()
            begin(workout)
        } catch {
            appLog("Failed to start generated workout: \(error)")
        }
    }

    /// A run or another goal's session: not in the catalog, so hidden.
    private func startSession(_ workout: Workout) {
        workout.isHidden = true
        modelContext.insert(workout)
        do {
            try modelContext.save()
            begin(workout)
        } catch {
            appLog("Failed to start session: \(error)")
        }
    }

    /// Presents the active workout and, like `WorkoutPreviewiOS`, wakes the
    /// watch when the user opted in.
    private func begin(_ workout: Workout) {
        Haptics.start()
        startWorkout = workout
        guard settings.appleWatchUsage else { return }
        Task {
            do {
                try await workoutObserver.startWorkout(workout: workout)
            } catch {
                appLog("Failed to start watch workout: \(error)")
            }
        }
    }

    /// Shows the summary (with the effort rating) after a saved workout, the
    /// same as starting from a workout's or plan's page.
    private func presentSummary() {
        guard ActiveWorkoutView.lastEndSaved else { return }
        isSummaryPresented = true
    }

    private func save(_ plan: PersonalizedWorkoutPlan) {
        let name = uniqueWorkoutName(plan.split.displayName)
        let workout = plan.makeWorkout(in: modelContext, existingExercises: existingExercises, name: name)
        workout.isSaved = true
        modelContext.insert(workout)
        do {
            try modelContext.save()
            didSave = true
            Haptics.bookmark(saved: true)
        } catch {
            appLog("Failed to save personalized workout: \(error)")
        }
    }

    private func uniqueWorkoutName(_ base: String) -> String {
        let existing = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
        var candidate = base
        var counter = 2
        while existing.contains(where: { $0.name == candidate }) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }

    #if DEBUG
    /// Simulator-only controls: inject mock HealthKit signals and seed sample
    /// workout history so the recovery / generator / difficulty features have
    /// data to work with. Compiled out of release builds.
    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Debug", systemImage: "ladybug.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)

            Toggle("Use mock health data", isOn: $mockEnabled)
                .font(.footnote)
                .onChange(of: mockEnabled) { _, newValue in
                    DebugHealthData.isEnabled = newValue
                    Task { await load() }
                }

            Toggle("Simulate no Apple Intelligence", isOn: $simulateNoAppleIntelligence)
                .font(.footnote)
                .onChange(of: simulateNoAppleIntelligence) { _, _ in
                    Task { await regenerate() }
                }

            Button {
                seedSampleHistory()
            } label: {
                Label("Seed sample workout history", systemImage: "calendar.badge.plus")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)

            NavigationLink {
                WorkoutParserEvaluationView()
            } label: {
                Label("Evaluate workout-request parsing", systemImage: "checklist")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.yellow.opacity(0.12)))
    }

    /// Inserts a few recent `FinishedWorkout` rows across different muscle
    /// groups so the generator's freshness logic and the difficulty
    /// predictor's tolerance estimate have something to chew on.
    private func seedSampleHistory() {
        let now = Date()
        let samples: [(daysAgo: Int, muscleGroup: Int, name: String)] = [
            (1, WorkoutCategory.chest.rawValue, "Sample Push"),
            (2, WorkoutCategory.back.rawValue, "Sample Pull"),
            (4, WorkoutCategory.legs.rawValue, "Sample Legs")
        ]
        for sample in samples {
            let end = Calendar.current.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
            let start = end.addingTimeInterval(-45 * 60)
            let finished = FinishedWorkout(
                endDate: end,
                name: sample.name,
                startDate: start,
                muscleGroup: sample.muscleGroup,
                exercisesSequenceID: [],
                exercises: [])
            modelContext.insert(finished)
        }
        try? modelContext.save()
        Task { await load() }
    }
    #endif
}

#Preview {
    NavigationStack {
        ForYouView()
    }
}
