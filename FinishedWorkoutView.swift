//
//  FinishedWorkout.swift
//  Workout App
//
//  Created by Justus Besser on 18.11.23.
//

import SwiftUI
import HealthKitUI
import SwiftData
import UIKit

struct FinishedWorkoutView: View {
    
    var specificWorkout: FinishedWorkout?
    
    @Query(sort: [SortDescriptor(\FinishedWorkout.endDate, order: .reverse)]) var recentWorkouts: [FinishedWorkout]
    
    @EnvironmentObject var iOSWorkoutObserver: iOSWorkoutObserver
    @EnvironmentObject var activityManager: ActivityManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    var appleWatchUsage = SettingsManager.shared.appleWatchUsage
    var healthKitUsage = SettingsManager.shared.accessHealthKitSucceeded

    @State private var title = ""
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var didCelebratePR = false
    @Query private var plans: [Plan]
    @State private var planCreditUndone = false
    /// The session changed its workout; offered to keep for next time.
    @State private var routineOffer: RoutineUpdateOffer.Pending?
    @State private var routineSavedName: String?

    var dateFormatter = DateFormatter()
    var numberFormatter = NumberFormatter()

    var workout: FinishedWorkout {
        // `recentWorkouts` is already sorted by endDate descending in the DB,
        // so its first element is the most recent — no need to load and re-sort
        // a second, unsorted query on every access.
        specificWorkout ?? recentWorkouts.first ?? FinishedWorkout.notFoundFinishedWorkout
    }

    private var orderedExercises: [Exercise] {
        guard let exercises = workout.exercises else { return [] }
        let sequence = workout.exercisesSequenceID
        guard !sequence.isEmpty else { return exercises }
        return exercises.sorted {
            guard let i1 = sequence.firstIndex(of: $0.id),
                  let i2 = sequence.firstIndex(of: $1.id) else { return false }
            return i1 < i2
        }
    }

    private var caloriesText: String {
        guard let calories = workout.caloriesBurned else { return NSLocalizedString("N/A", comment: "Value not available") }
        return "\(Int(calories.rounded())) kcal"
    }

    /// Total training volume for the session: Σ weight × reps across every logged
    /// set except warm-ups (kilograms). Bodyweight sets (weight 0) contribute nothing.
    private var sessionVolumeKg: Double {
        WorkoutStats.volumeKilograms(setWeights: workout.setWeights, setReps: workout.setReps,
                                     log: workout.loggingDetails)
    }

    private var volumeText: String? {
        guard sessionVolumeKg > 0 else { return nil }
        return SettingsManager.shared.weightUnit.format(kilograms: sessionVolumeKg)
    }

    /// Exercise ids that set a new max-weight personal record this session,
    /// compared against the best in any earlier finished workout.
    private var prExerciseIDs: Set<String> {
        guard let current = WorkoutStats.snapshots(from: [workout]).first else { return [] }
        return WorkoutStats.personalRecordExerciseIDs(current: current, history: WorkoutStats.snapshots(from: recentWorkouts))
    }

    /// The result at a glance: what was done, a few large numbers, and a
    /// new record if there is one.
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if specificWorkout == nil {
                    Label(NSLocalizedString("Workout complete", comment: "Summary: eyebrow right after a session"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                }
                Text(workout.name)
                    .displayFont(.title)
                Text(workout.endDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !resultStats.isEmpty {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ForEach(resultStats) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .displayNumberFont(size: statSize)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Label(stat.title, systemImage: stat.symbol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !prExerciseIDs.isEmpty {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "trophy.fill")
                        .symbolEffect(.bounce, value: didCelebratePR)
                    Text(prExerciseIDs.count == 1
                         ? NSLocalizedString("New personal record!", comment: "Summary: one new PR")
                         : String(format: NSLocalizedString("%d new personal records!", comment: "Summary: multiple new PRs"), prExerciseIDs.count))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .controlBackground(.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
        .padding(.horizontal)
    }

    private struct ResultStat: Identifiable {
        let title: String
        let value: String
        let symbol: String
        var id: String { title }
    }

    @ScaledMetric(relativeTo: .title) private var statSize: CGFloat = 28

    /// Up to three numbers: how long, then the volume and sets of a strength
    /// session, or the calories where there are no sets.
    private var resultStats: [ResultStat] {
        var stats: [ResultStat] = []
        let seconds = max(workout.endDate.timeIntervalSince(workout.startDate), 0)
        stats.append(ResultStat(title: NSLocalizedString("Duration", comment: "Summary: how long the workout took"),
                                value: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds],
                                                                                  width: .narrow, maximumUnitCount: 2)),
                                symbol: "timer"))
        if let volumeText {
            stats.append(ResultStat(title: NSLocalizedString("Volume", comment: "Progress: volume axis"), value: volumeText, symbol: "scalemass"))
        }
        let sets = workout.setReps.values.reduce(0) { $0 + $1.count }
        if sets > 0 {
            stats.append(ResultStat(title: NSLocalizedString("Sets", comment: "Active workout: sets stepper label"), value: "\(sets)", symbol: "checkmark.circle"))
        }
        if let calories = workout.caloriesBurned, calories > 0 {
            stats.append(ResultStat(title: NSLocalizedString("Calories", comment: "Summary: active energy of the workout"),
                                    value: "\(Int(calories.rounded()))", symbol: "flame"))
        }
        return Array(stats.prefix(3))
    }

    /// When, what kind and where: the facts, in one quiet list at the end.
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(NSLocalizedString("Details", comment: "Summary: section with the workout's times, type and place"))
                .sectionTitleStyle()
            VStack(spacing: 0) {
                detailRow(NSLocalizedString("Start", comment: "Summary: start time"), symbol: "flag",
                          value: workout.startDate.formatted(date: .omitted, time: .shortened))
                Divider()
                detailRow(NSLocalizedString("End", comment: "Summary: end time"), symbol: "flag.pattern.checkered",
                          value: workout.endDate.formatted(date: .omitted, time: .shortened))
                Divider()
                detailRow(NSLocalizedString("Workout type", comment: "Finished workout: the sport, e.g. Swimming"),
                          symbol: (HKWorkoutActivityType(rawValue: UInt(workout.workoutType)) ?? .other).symbolName,
                          value: HKWorkoutActivityType(rawValue: UInt(workout.workoutType))?.name ?? HKWorkoutActivityType.other.name)
                Divider()
                detailRow(NSLocalizedString("Location", comment: "Summary: indoor or outdoor"), symbol: "location",
                          value: HKWorkoutSessionLocationType(rawValue: workout.workoutLocation)?.localizedName ?? HKWorkoutSessionLocationType.unknown.localizedName)
                Divider()
                detailRow(NSLocalizedString("Category", comment: "Summary: the workout's muscle group"),
                          symbol: WorkoutCategory.getSymbolName(from: workout.muscleGroup),
                          value: WorkoutCategory.getCategoryName(from: workout.muscleGroup))
                if workout.caloriesBurned != nil {
                    Divider()
                    detailRow(NSLocalizedString("Calories", comment: "Summary: active energy of the workout"), symbol: "flame", value: caloriesText)
                }
            }
            .padding(.horizontal, 14)
            .cardBackground()
        }
        .padding(.horizontal)
    }

    private func detailRow(_ title: String, symbol: String, value: String) -> some View {
        HStack(spacing: Spacing.m) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.s)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .combine)
    }

    /// Today's Move, Exercise and Stand rings from the Watch, in Apple's
    /// own colors.
    private var activityRingsCard: some View {
            ZStack {
                HStack {
                    ActivityRingView(activitySummary: activityManager.activitySummary)
                        .frame(width: 150, height: 150)
                        .padding()
                    Spacer()
                    VStack {
                        VStack {
                            let energyBurned = activityManager.activitySummary?.activeEnergyBurned.doubleValue(for: .kilocalorie()).rounded().formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            let energyBurnedGoal = activityManager.activitySummary?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()).formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            HStack {
                                Text("Move")
                                Spacer()
                            }
                            HStack {
                                Text("\(energyBurned)/\(energyBurnedGoal)\(HKUnit.kilocalorie().unitString.capitalized)")
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                        Divider()
                        
                        VStack {
                            let trainMinutes = activityManager.activitySummary?.appleExerciseTime.doubleValue(for: .minute()).formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            let trainMinutesGoal = activityManager.activitySummary?.exerciseTimeGoal?.doubleValue(for: .minute()).formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            HStack {
                                Text("Train")
                                Spacer()
                            }
                            
                            HStack {
                                Text("\(trainMinutes)/\(trainMinutesGoal)\(HKUnit.minute().unitString.capitalized)")
                                    .foregroundStyle(.green)
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                        Divider()
                        
                        VStack {
                            let standHours = activityManager.activitySummary?.appleStandHours.doubleValue(for: .count()).formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            let standHoursGoal = activityManager.activitySummary?.standHoursGoal?.doubleValue(for: .count()).formatted() ?? NSLocalizedString("N/A", comment: "Value not available")
                            
                            HStack {
                                Text("Stand")
                                Spacer()
                            }
                            
                            HStack {
                                Text("\(standHours)/\(standHoursGoal)\(HKUnit.hour().unitString.capitalized)")
                                    .foregroundStyle(.cyan)
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 150)
                    .padding()
                }
            }
            .cardBackground()
            .padding(.horizontal)
    }

    /// Plans the workout that just ended counted toward (see `PlanCredit`).
    private var creditedPlans: [Plan] {
        guard !planCreditUndone, let credit = PlanCredit.latest,
              credit.finishedWorkoutID == workout.id else { return [] }
        return plans.filter { credit.planIDs.contains($0.id) }
    }

    /// Says which plan this workout counted toward, with an undo — a
    /// matching workout counts automatically wherever it was started, so the
    /// user must be able to see it and take it back.
    @ViewBuilder
    private var planCreditBanner: some View {
        let plans = creditedPlans
        if let first = plans.first {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plans.count == 1
                         ? String(format: NSLocalizedString("Counted toward “%@”", comment: "Summary: workout counted toward a plan"), first.displayName)
                         : String(format: NSLocalizedString("Counted toward %d plans", comment: "Summary: workout counted toward several plans"), plans.count))
                        .font(.subheadline.weight(.semibold))
                    if plans.count == 1 {
                        Text(verbatim: "\(first.finishedWorkoutsSequence.count)/\(first.workoutsSequenceIDs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(NSLocalizedString("Undo", comment: "Summary: undo counting the workout toward a plan")) {
                    undoPlanCredit(plans)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .card()
            .padding(.horizontal)
        }
    }

    /// The workout today's session came from, if it's still there.
    private func sourceWorkout(_ offer: RoutineUpdateOffer.Pending) -> Workout? {
        let id = offer.workoutID
        return try? modelContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first
    }

    /// Exercises swapped, added or removed, or sets changed during the
    /// session: keep that for next time? Your own workout is updated; a
    /// preloaded one is copied, since catalog updates rewrite it; one For You
    /// made for this session (hidden) becomes your own.
    @ViewBuilder
    private var routineUpdateCard: some View {
        if let offer = routineOffer, let source = sourceWorkout(offer) {
            let updatesInPlace = source.isUserGenerated && !source.isHidden
            VStack(alignment: .leading, spacing: 10) {
                Label(NSLocalizedString("You changed this workout today", comment: "Summary: the session differed from its saved workout"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Text(updatesInPlace
                     ? NSLocalizedString("Keep today's exercises and sets for next time?", comment: "Summary: offer to update the workout")
                     : NSLocalizedString("Save today's exercises and sets as your own workout?", comment: "Summary: offer to copy a preloaded workout"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        routineSavedName = apply(offer.changes, to: source)
                        routineOffer = nil
                        Haptics.success()
                    } label: {
                        Text(updatesInPlace
                             ? NSLocalizedString("Update workout", comment: "Summary: save the session's changes to the workout")
                             : NSLocalizedString("Save as my workout", comment: "Summary: copy the workout with the session's changes"))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill)
                    .foregroundStyle(Theme.onAccent)
                    .accessibilityIdentifier("summary.updateWorkout")
                    Button(NSLocalizedString("Not now", comment: "Summary: keep the workout as it was")) {
                        routineOffer = nil
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.horizontal)
        } else if let routineSavedName {
            Label(String(format: NSLocalizedString("Saved to “%@”", comment: "Summary: the session's changes were saved to this workout"), routineSavedName),
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }

    /// Writes the session's exercises and plans into `source`, or into a
    /// copy of a preloaded workout. A For You session's workout is shown in
    /// Browse from then on. Returns the name it was saved under.
    private func apply(_ changes: RoutineChanges, to source: Workout) -> String {
        let all = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exercises = changes.exerciseIDs.compactMap { byID[$0] }
        let sets = Double(ExercisePlan.commonSetCount(Array(changes.plans.values), fallback: Int(source.setLength)))
        let target: Workout
        if source.isUserGenerated {
            target = source
            target.exercisesSequenceID = changes.exerciseIDs
            target.setLength = sets
            if target.isHidden {
                target.isHidden = false
                target.isSaved = true
                target.name = uniqueWorkoutName(target.displayName)
            }
        } else {
            target = Workout(infoText: source.displayInfoText, isUserGenerated: true, muscleGroup: source.muscleGroup,
                             setLength: sets, straightSets: source.straightSets, difficultyInt: source.difficultyInt,
                             name: String(format: NSLocalizedString("%@ (my version)", comment: "Summary: name of a copied preloaded workout"), source.displayName),
                             duration: source.duration, exercisesSequenceID: changes.exerciseIDs, finishedExercisesSequence: [],
                             workoutActivityType: source.workoutActivityType, workoutSessionLocation: source.workoutSessionLocation)
            target.restSeconds = source.restSeconds
            modelContext.insert(target)
        }
        target.exercises = exercises
        target.exercisePlans = changes.plans
        try? modelContext.save()
        WatchConnectivityManager.shared.sendWorkoutLibrary(context: modelContext)
        return target.displayName
    }

    /// `base`, or "base (2)" and so on if a workout already has that name.
    private func uniqueWorkoutName(_ base: String) -> String {
        let names = Set(((try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []).filter { !$0.isHidden }.map(\.name))
        var candidate = base
        var counter = 2
        while names.contains(candidate) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }

    private func undoPlanCredit(_ plans: [Plan]) {
        guard let credit = PlanCredit.latest else { return }
        for plan in plans { plan.undoCompletion(ofWorkoutID: credit.workoutID) }
        try? modelContext.save()
        WatchConnectivityManager.shared.sendWorkoutLibrary(context: modelContext)
        PlanCredit.latest = nil
        planCreditUndone = true
    }

    /// Asks how hard the session felt. The answer calibrates the For You
    /// difficulty predictions (`WorkoutDifficultyPredictor.calibrationOffset`).
    @ViewBuilder
    private var effortCard: some View {
        if workout !== FinishedWorkout.notFoundFinishedWorkout {
            EffortRatingCard(effort: workout.perceivedEffort) { effort in
                workout.perceivedEffort = effort
                try? modelContext.save()
            }
            .padding(.horizontal)

            SessionNoteCard(note: workout.loggingDetails.sessionNote) { note in
                var log = workout.loggingDetails
                guard log.sessionNote != note else { return }
                log.sessionNote = note
                workout.loggingDetails = log
                try? modelContext.save()
            }
            .padding(.horizontal)
        }
    }

    init(specificWorkout: FinishedWorkout?) {
        self.specificWorkout = specificWorkout
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(spacing: Spacing.l) {
                    resultCard

                    planCreditBanner

                    routineUpdateCard

                    effortCard

                    if appleWatchUsage {
                        activityRingsCard
                    }

                    if workout.additionalData.hasContent {
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundStyle(.secondary)
                            Text(workout.additionalData.description)
                                .font(.headline)
                            Spacer()
                        }
                        .card()
                        .padding(.horizontal)
                    }

                    ExerciseSummaryList(exercises: orderedExercises, setWeights: workout.setWeights, setReps: workout.setReps, log: workout.loggingDetails, prExerciseIDs: prExerciseIDs)

                    detailsCard
                }
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xl)
            }
            .pageTint()
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if specificWorkout == nil {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .bold()
                        }
                    } else {
                        Menu {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label(NSLocalizedString("Edit", comment: "Finished workout: edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label(NSLocalizedString("Delete workout", comment: "Finished workout: delete"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text(NSLocalizedString("More", comment: "Accessibility: menu with more actions")))
                        }
                    }
                }
            }
            .task {
                if let lastWorkout = recentWorkouts.first {
                    title = lastWorkout.name
                } else {
                    title = NSLocalizedString("No Recent Workouts", comment: "Summary: no workouts yet")
                }
            }
        }
        // Confetti for the summary right after the session.
        .overlay(alignment: .top) {
            if specificWorkout == nil {
                CelebrationBurst()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            activityManager.fetchActivityRings()
            // Only the summary right after the session, not one opened from History.
            if specificWorkout == nil, routineOffer == nil {
                routineOffer = RoutineUpdateOffer.take()
            }
            // A success haptic for a finished session or a new record (once).
            if (specificWorkout == nil || !prExerciseIDs.isEmpty) && !didCelebratePR {
                didCelebratePR = true
                Haptics.success()
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditFinishedWorkoutView(workout: workout)
        }
        .confirmationDialog(NSLocalizedString("Delete this workout?", comment: "Finished workout: delete confirmation title"),
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("Delete workout", comment: "Finished workout: delete"), role: .destructive) {
                deleteWorkout()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("This permanently removes the workout from your history.", comment: "Finished workout: delete message"))
        }
    }

    /// Deletes the currently shown finished workout and dismisses.
    private func deleteWorkout() {
        modelContext.delete(workout)
        try? modelContext.save()
        // Goal progress (reminders and widget) may have dropped below target.
        Task { await GoalReminderScheduler.shared.refresh(context: modelContext) }
        dismiss()
    }

}

#Preview {
    let healthStore = HKHealthStore.shared
    FinishedWorkoutView(specificWorkout: nil)
        //.environmentObject(iOSWorkoutObserver)
        .environmentObject(ActivityManager(healthStore: healthStore))
}

/// A note for the whole session, saved when the field loses focus.
struct SessionNoteCard: View {
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(note: String, onCommit: @escaping (String) -> Void) {
        self.onCommit = onCommit
        _draft = State(initialValue: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(NSLocalizedString("Notes", comment: "Summary: session note title"), systemImage: "note.text")
                .font(.subheadline.weight(.semibold))
            TextField(NSLocalizedString("How did it go?", comment: "Summary: session note placeholder"),
                      text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .focused($isFocused)
        }
        .card()
        .onChange(of: isFocused) { _, focused in
            if !focused { onCommit(draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        .onDisappear { onCommit(draft.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

/// A 1…10 "how hard was it?" scale on the workout summary.
struct EffortRatingCard: View {
    let effort: Int?
    let onRate: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("How hard was it?", comment: "Workout summary: effort rating title"))
                    .displayFont(.headline)
                Spacer()
                if let effort {
                    Text(Self.label(for: effort))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 2) {
                ForEach(1...10, id: \.self) { value in
                    Button {
                        rate(value)
                    } label: {
                        Text("\(value)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Circle().fill(value == effort ? AnyShapeStyle(Theme.accentFillGradient) : AnyShapeStyle(Theme.inset)))
                            .foregroundStyle(value == effort ? Theme.onAccent : Color.primary)
                            // The whole 44 pt-tall column is tappable, not just the circle.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // One adjustable control for VoiceOver (swipe up/down) instead of
            // ten separate buttons — the standard pattern for a rating scale.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NSLocalizedString("How hard was it?", comment: "Workout summary: effort rating title")))
            .accessibilityValue(Text(effort.map { "\($0), \(Self.label(for: $0))" }
                                     ?? NSLocalizedString("Not rated", comment: "Effort rating: no value yet")))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rate(min((effort ?? 5) + 1, 10))
                case .decrement: rate(max((effort ?? 6) - 1, 1))
                @unknown default: break
                }
            }
            Text(NSLocalizedString("Your rating tunes how hard future suggestions are predicted to feel.", comment: "Workout summary: effort rating explanation"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func rate(_ value: Int) {
        onRate(value)
        Haptics.select()
    }

    static func label(for effort: Int) -> String {
        switch effort {
        case ...2: return NSLocalizedString("Very easy", comment: "Effort rating label")
        case 3...4: return NSLocalizedString("Easy", comment: "Difficulty label")
        case 5...6: return NSLocalizedString("Moderate", comment: "Difficulty label")
        case 7...8: return NSLocalizedString("Challenging", comment: "Difficulty label")
        case 9: return NSLocalizedString("Very hard", comment: "Difficulty label")
        default: return NSLocalizedString("Max effort", comment: "Effort rating label")
        }
    }
}

struct ExerciseSummaryList: View {
    let exercises: [Exercise]
    /// Per-set weights logged for the session, keyed by exercise id (kilograms).
    var setWeights: [String: [Double]] = [:]
    /// Per-set reps logged for the session, index-aligned with `setWeights`.
    var setReps: [String: [Int]] = [:]
    /// Set kinds, reps in reserve and notes.
    var log = SessionLog()
    /// Exercise ids that set a new personal record this session.
    var prExerciseIDs: Set<String> = []

    private var weightUnit: WeightUnit { SettingsManager.shared.weightUnit }

    /// Combined per-set "weight × reps" text for an exercise, with warm-up and
    /// drop sets marked, or nil if nothing was logged for it.
    private func loggedSetsText(for exercise: Exercise) -> String? {
        let snapshot = WorkoutStats.Snapshot(id: "", endDate: .now, setWeights: setWeights, setReps: setReps, log: log)
        let text = weightUnit.formatSets(snapshot.sets(exercise.id), bodyweight: exercise.isBodyweight)
        return text.isEmpty ? nil : text
    }

    var body: some View {
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Exercises")
                        .displayFont(.title3)
                    Spacer()
                    Text("\(exercises.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .displayFont(.footnote, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                                .frame(width: 30, height: 30)
                                .background(Theme.accentTint, in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayName.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? NSLocalizedString("Unnamed exercise", comment: "Finished workout: exercise without a name")
                                     : exercise.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(WorkoutCategory.getCategoryName(from: exercise.muscleGroup))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let setsText = loggedSetsText(for: exercise) {
                                    Label(setsText, systemImage: "scalemass")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                if let note = log.exerciseNotes[exercise.id], !note.isEmpty {
                                    Label(note, systemImage: "note.text")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if prExerciseIDs.contains(exercise.id) {
                                Label("PR", systemImage: "trophy.fill")
                                    .font(.caption2.weight(.bold))
                                    .labelStyle(.titleAndIcon)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .controlBackground(.accent)
                                    .foregroundStyle(Theme.onAccent)
                                    .accessibilityLabel(Text("Personal record"))
                            }

                        }
                        .card(padding: 12)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }
}

// MARK: - HKWorkoutActivityType Name Extension

extension HKWorkoutActivityType {
    /// Human-readable, localized name for every workout activity type listed
    /// in `HKWorkoutActivityType.selectable`. Previously this fell through
    /// to "Other" for most sports, so the picker showed the same label for
    /// dozens of unrelated activities.
    var name: String {
        let key: String
        switch self {
        case .americanFootball: key = "American Football"
        case .archery: key = "Archery"
        case .australianFootball: key = "Australian Football"
        case .badminton: key = "Badminton"
        case .barre: key = "Barre"
        case .baseball: key = "Baseball"
        case .basketball: key = "Basketball"
        case .bowling: key = "Bowling"
        case .boxing: key = "Boxing"
        case .climbing: key = "Climbing"
        case .coreTraining: key = "Core Training"
        case .crossCountrySkiing: key = "Cross Country Skiing"
        case .crossTraining: key = "Cross Training"
        case .curling: key = "Curling"
        case .cycling: key = "Cycling"
        case .dance: key = "Dance"
        case .discSports: key = "Disc Sports"
        case .downhillSkiing: key = "Downhill Skiing"
        case .elliptical: key = "Elliptical"
        case .equestrianSports: key = "Equestrian Sports"
        case .fencing: key = "Fencing"
        case .fishing: key = "Fishing"
        case .fitnessGaming: key = "Fitness Gaming"
        case .flexibility: key = "Flexibility"
        case .functionalStrengthTraining: key = "Strength Training"
        case .golf: key = "Golf"
        case .gymnastics: key = "Gymnastics"
        case .handCycling: key = "Hand Cycling"
        case .handball: key = "Handball"
        case .highIntensityIntervalTraining: key = "HIIT"
        case .hiking: key = "Hiking"
        case .hockey: key = "Hockey"
        case .hunting: key = "Hunting"
        case .jumpRope: key = "Jump Rope"
        case .kickboxing: key = "Kickboxing"
        case .lacrosse: key = "Lacrosse"
        case .martialArts: key = "Martial Arts"
        case .mindAndBody: key = "Mind and Body"
        case .mixedCardio: key = "Mixed Cardio"
        case .paddleSports: key = "Paddle Sports"
        case .pilates: key = "Pilates"
        case .play: key = "Play"
        case .preparationAndRecovery: key = "Preparation and Recovery"
        case .racquetball: key = "Racquetball"
        case .rowing: key = "Rowing"
        case .rugby: key = "Rugby"
        case .running: key = "Running"
        case .sailing: key = "Sailing"
        case .skatingSports: key = "Skating"
        case .snowSports: key = "Snow Sports"
        case .snowboarding: key = "Snowboarding"
        case .soccer: key = "Soccer"
        case .softball: key = "Softball"
        case .squash: key = "Squash"
        case .stairClimbing: key = "Stair Climbing"
        case .stairs: key = "Stairs"
        case .stepTraining: key = "Step Training"
        case .surfingSports: key = "Surfing"
        case .swimming: key = "Swimming"
        case .tableTennis: key = "Table Tennis"
        case .taiChi: key = "Tai Chi"
        case .tennis: key = "Tennis"
        case .trackAndField: key = "Track and Field"
        case .traditionalStrengthTraining: key = "Strength Training"
        case .volleyball: key = "Volleyball"
        case .walking: key = "Walking"
        case .waterFitness: key = "Water Fitness"
        case .waterPolo: key = "Water Polo"
        case .waterSports: key = "Water Sports"
        case .wheelchairRunPace: key = "Wheelchair Run Pace"
        case .wheelchairWalkPace: key = "Wheelchair Walk Pace"
        case .wrestling: key = "Wrestling"
        case .yoga: key = "Yoga"
        default: key = "Other"
        }
        return NSLocalizedString(key, comment: "HKWorkoutActivityType display name")
    }
}

// MARK: - HKWorkoutSessionLocationType Name Extension

extension HKWorkoutSessionLocationType {
    var localizedName: String {
        switch self {
        case .indoor:
            return NSLocalizedString("Indoor", comment: "HKWorkoutSessionLocationType: indoor")
        case .outdoor:
            return NSLocalizedString("Outdoor", comment: "HKWorkoutSessionLocationType: outdoor")
        case .unknown:
            return NSLocalizedString("Unknown", comment: "HKWorkoutSessionLocationType: unknown")
        @unknown default:
            return NSLocalizedString("Unknown", comment: "HKWorkoutSessionLocationType: unknown")
        }
    }
}
