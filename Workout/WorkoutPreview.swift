//
//  WorkoutPreview.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 24.03.23.
//

import SwiftUI
import HealthKit
import SwiftData
import WorkoutKit


struct WorkoutPreviewiOS: View {
    
    @Bindable var workout: Workout
    
    @Query var exercises: [Exercise]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var iOSWorkoutObserver: iOSWorkoutObserver
    
    var exercisesInWorkout: [Exercise] {
        exercises
            .filter { workout.exercisesSequenceID.contains($0.id) }
            .sorted {
                guard let i1 = workout.exercisesSequenceID.firstIndex(of: $0.id),
                      let i2 = workout.exercisesSequenceID.firstIndex(of: $1.id) else { return false }
                return i1 < i2
            }
    }
    //private var workoutAsPlan: WorkoutPlan
    
    init(workout: Workout, canStartWorkout: Bool = true) {
        self.workout = workout
        self.canStartWorkout = canStartWorkout
    }

    /// Build a WorkoutKit `WorkoutPlan` that mirrors this workout's exercises
    /// and timing. Time-based exercises (`repCount == 0`, e.g. plank, rowing)
    /// become time goals scaled by `setLength`; rep-based exercises become
    /// `.open` steps that the user advances manually on the watch — there's
    /// no rep goal in WorkoutKit, and `.open` is the only honest mapping.
    /// Recovery between steps stays time-based.
    private var workoutPlan: WorkoutPlan {
        // Per-set seconds, scaled from the workout's set-length slider (1...5).
        // Falls back to 30s when set-length is unset.
        let workSeconds: Double = workout.setLength > 0 ? workout.setLength * 30 : 30
        let restSeconds: Double = 15

        // One block per exercise, repeated for its own number of sets.
        let blocks: [IntervalBlock] = exercisesInWorkout.map { exercise in
            let plan = workout.plan(for: exercise)
            let workGoal: WorkoutGoal = plan.reps > 0
                ? .open
                : .time(workSeconds, .seconds)
            let work = IntervalStep(.work, goal: workGoal)
            let recovery = IntervalStep(.recovery, goal: .time(restSeconds, .seconds))
            return IntervalBlock(steps: [work, recovery], iterations: max(plan.sets, 1))
        }

        let activity = HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) ?? .functionalStrengthTraining
        let location = HKWorkoutSessionLocationType(rawValue: workout.workoutSessionLocation) ?? .unknown

        let custom = CustomWorkout(
            activity: activity,
            location: location,
            displayName: workout.displayName,
            warmup: nil,
            blocks: blocks,
            cooldown: nil
        )
        return WorkoutPlan(.custom(custom))
    }
    
    @State private var showActiveWorkoutView = false
    @State private var showPreview: Bool = false
    @State private var showEditViewFromMuscles = false
    @State private var isSummaryPresendet = false
    @State private var showReorderSheet = false
    
    var canStartWorkout: Bool = true
    
    private var equipmentInWorkout: [Equipment] {
        var equipmentArray: [Equipment] = []
        workout.exercises?.forEach { exercise in
            exercise.equipment.forEach { equipment in
                if let equipmentEnum = Equipment(rawValue: equipment), !equipmentArray.contains(equipmentEnum) {
                    equipmentArray.append(equipmentEnum)
                }
            }
        }
        return equipmentArray
    }
    
    /// Needle position for the difficulty dial. Three levels map to 33/67/100,
    /// not 0/50/100: an empty gauge reads as "none" or "no data" rather than
    /// "easy", which is a real rating and should show a real needle.
    private var difficultySymbol: String {
        switch workout.difficultyInt {
        case 1:
            return "gauge.with.dots.needle.33percent"
        case 3:
            return "gauge.with.dots.needle.100percent"
        default:
            return "gauge.with.dots.needle.67percent"
        }
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 16) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    if workout.isNew {
                                        Chip(title: NSLocalizedString("New", comment: "HorizontalView Title"), isSelected: true)
                                    }
                                    Chip(title: workout.displayDifficulty, systemImage: difficultySymbol)
                                        .accessibilityLabel(Text(String(
                                            format: NSLocalizedString("Difficulty: %@", comment: "Workout detail: difficulty a11y"),
                                            workout.displayDifficulty)))
                                    Chip(title: WorkoutCategory.getCategoryName(from: workout.muscleGroup),
                                         systemImage: WorkoutCategory.getSymbolName(from: workout.muscleGroup))
                                    Chip(title: String(format: NSLocalizedString("%d min", comment: "Workout card: duration in minutes"), workout.duration),
                                         systemImage: "clock")
                                    // Read-only: sets are edited in "Edit Workout"
                                    // below, per exercise. One explicit format key
                                    // rather than `Text("\(count) \(unit)")`, whose
                                    // shared "%lld %@" German value lost its space.
                                    Chip(title: String(format: NSLocalizedString("%d sets", comment: "Workout detail: set count"),
                                                       exercisesInWorkout.reduce(0) { $0 + workout.plan(for: $1).sets }),
                                         systemImage: "square.stack.3d.up")
                                }
                                .padding(.horizontal)
                            }

                            // Rest between rounds — only meaningful for circuit
                            // (cardio/HIIT) workouts; strength runs straight sets
                            // with no rest, so the control is hidden for them.
                            if isCardioOrHIIT {
                                HStack(spacing: 10) {
                                    Label("Rest", systemImage: "pause.circle")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Button { adjustRest(by: -5) } label: {
                                        Image(systemName: "minus")
                                            .frame(width: 32, height: 32)
                                            .background(Theme.inset, in: Circle())
                                            .accessibilityLabel(Text(NSLocalizedString("Shorter rest", comment: "Accessibility: rest stepper")))
                                    }
                                    .buttonStyle(.plain)
                                    Text("\(workout.restSeconds)s")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .frame(minWidth: 40)
                                    Button { adjustRest(by: 5) } label: {
                                        Image(systemName: "plus")
                                            .frame(width: 32, height: 32)
                                            .background(Theme.inset, in: Circle())
                                            .accessibilityLabel(Text(NSLocalizedString("Longer rest", comment: "Accessibility: rest stepper")))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .card(padding: 10)
                                .padding(.horizontal)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text(String(format: NSLocalizedString("Rest %d seconds", comment: "Workout detail: rest a11y"), workout.restSeconds)))
                            }

                            // Only when there's a description — an empty one left a blank card.
                            if !workout.displayInfoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(workout.displayInfoText)
                                    .foregroundStyle(Color.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                        
                        if !equipmentInWorkout.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Equipment")
                                    .sectionTitleStyle()
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(equipmentInWorkout, id: \.self) { equipment in
                                            VStack(spacing: 6) {
                                                Image(equipment.symbolName)
                                                    .resizable()
                                                    .aspectRatio(contentMode: ContentMode.fit)
                                                    .frame(width: 36, height: 36)
                                                    .frame(width: 60, height: 60)
                                                    .background(Theme.surface, in: Circle())
                                                
                                                Text(equipment.displayName.replacingOccurrences(of: "-", with: " "))
                                                    .font(.caption)
                                                    .foregroundStyle(Color.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Exercises")
                                    .displayFont(.title3)
                                Text("\(exercisesInWorkout.count)")
                                    .displayFont(.title3)
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                                if exercisesInWorkout.count > 1 {
                                    Button {
                                        showReorderSheet = true
                                    } label: {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(width: 36, height: 36)
                                            .background(Theme.surface, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("Reorder exercises"))
                                }
                            }
                            .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(Array(exercisesInWorkout.enumerated()), id: \.element) { index, exercise in
                                    NavigationLink {
                                        ChangeExerciseView(exercise: exercise)
                                    } label: {
                                        ExerciseRowCard(
                                            exercise: exercise,
                                            position: index + 1,
                                            difficultyLabel: exercise.displayDifficulty,
                                            plan: workout.plan(for: exercise),
                                            holdsTimedExercises: WorkoutCategory.holdsTimedExercises(workout.muscleGroup)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Button {
                            showEditViewFromMuscles.toggle()
                        } label: {
                            Label("Edit Workout", systemImage: "pencil")
                        }
                        .buttonStyle(.secondaryAction)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
                // A bar, so the list scrolls under it with the system's edge blur.
                .safeAreaBar(edge: .bottom) {
                    if canStartWorkout {
                        Button {
                            startWorkout()
                        } label: {
                            Label(NSLocalizedString("Start workout", comment: "Start plan workout action"), systemImage: "play.fill")
                        }
                        .buttonStyle(.primaryAction)
                        .accessibilityIdentifier("preview.start")
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .pageTint()
            }
        }
        .navigationTitle(workout.displayName)
        .onAppear {
            if SettingsManager.shared.appleWatchUsage {
                iOSWorkoutObserver.requestSync()
                iOSWorkoutObserver.previewWorkoutOnWatch(
                    workoutName: workout.displayName,
                    exerciseName: workout.exercises?.first?.displayName ?? "",
                    exerciseDuration: Double(workout.duration),
                    muscleGroup: workout.muscleGroup
                )
            }
        }
        .onDisappear {
            // Only when it changes: assigning the same value still marks the
            // record changed and exports it to iCloud again on every visit.
            if workout.isNew {
                withAnimation {
                    workout.isNew = false
                }
            }
        }
        .sheet(isPresented: $showEditViewFromMuscles) {
            NavigationStack {
                ChangeWorkoutView(workout: workout, onDelete: {
                    dismiss()
                })
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            ReorderExercisesSheet(workout: workout)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .toolbar {
            // A For You session's own copy is cleaned up later; not one to keep.
            if !workout.isHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { workout.toggleBookmark() }
                        Haptics.bookmark(saved: workout.isSaved)
                    } label: {
                        Image(systemName: workout.isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(workout.isSaved ? Theme.accent : Color.primary)
                    }
                    .accessibilityLabel(Text(workout.isSaved
                                             ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                             : NSLocalizedString("Bookmark", comment: "Workout card: save")))
                    .accessibilityIdentifier("preview.bookmark")
                }
            }
#if os(iOS)
            if SettingsManager.shared.appleWatchUsage {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showPreview = true
                    } label: {
                        Image(systemName: "applewatch.and.arrow.forward")
                            .accessibilityLabel(Text(NSLocalizedString("Send to Apple Watch", comment: "Accessibility: show the workout on Apple Watch")))
                    }
                }
            }
            
#endif
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showActiveWorkoutView, onDismiss: presentSummary, content: {
            ActiveWorkoutView(workout: workout)
        })
        .sheet(isPresented: $isSummaryPresendet, content: {
            withAnimation {
                FinishedWorkoutView(specificWorkout: nil)
            }
        })
        .workoutPreview(workoutPlan, isPresented: $showPreview)
        // A watch-driven end is handled inside ActiveWorkoutView: it saves the
        // workout and dismisses itself. Closing the cover from here as well
        // could tear the view down before that save ran.
        // Watch problems — a watch that can't be woken because it isn't worn,
        // or denied Health access — show in the workout screen
        // (`WatchIssueNotice`), not as an alert from here: presenting one
        // under the workout dismissed the workout to show it, leaving only
        // the resume bar.
#endif
    }
    
    private func presentSummary() {
        guard ActiveWorkoutView.lastEndSaved else { return }
        isSummaryPresendet.toggle()
    }

    /// Circuit workouts (cardio/HIIT) rest between rounds; everything else runs
    /// straight sets with no rest, so the rest control is hidden for them.
    private var isCardioOrHIIT: Bool {
        workout.muscleGroup == WorkoutCategory.cardio.rawValue ||
        workout.muscleGroup == WorkoutCategory.hiit.rawValue
    }

    /// Adjust the rest-between-rounds seconds (0...180) and persist it.
    private func startWorkout() {
        Haptics.start()
        showActiveWorkoutView.toggle()
        iOSWorkoutObserver.currentWorkout?.workoutName = workout.displayName
        // Always attempt the watch wake when the user opted in. We can't rely
        // on `isWatchAppInstalled` here because WCSession activation may not
        // have completed yet on first launch — the wake call itself handles
        // the "no watch / not paired / not installed" cases by throwing,
        // which we log and ignore.
        if SettingsManager.shared.appleWatchUsage {
            startWatchWorkout()
        }
    }

    private func adjustRest(by delta: Int) {
        let new = min(180, max(0, workout.restSeconds + delta))
        guard new != workout.restSeconds else { return }
        workout.restSeconds = new
        try? modelContext.save()
        Haptics.tap()
    }

    private func startWatchWorkout() {
        Task {
            do {
                try await iOSWorkoutObserver.startWorkout(workout: workout)
            } catch {
                appLog("Error: \(error)")
            }
        }
    }
}

struct ExerciseRowCard: View {
    let exercise: Exercise
    let position: Int
    let difficultyLabel: String
    /// This workout's sets × reps for the exercise.
    var plan: ExercisePlan?
    /// See `PlannedExercisesSection.holdsTimedExercises`.
    var holdsTimedExercises = true

    /// "Chest · Intermediate · 4 × 8 · 60 kg"
    private var detail: String {
        var parts = [WorkoutCategory.getCategoryName(from: exercise.muscleGroup), difficultyLabel]
        if let plan {
            let seconds = holdsTimedExercises ? plan.seconds ?? ExercisePlan.defaultHoldSeconds(for: exercise) : nil
            parts.append(PlannedExercisesSection.summary(sets: plan.sets, reps: plan.reps, seconds: seconds))
        }
        if let kg = plan?.targetWeightKg ?? exercise.targetWeightKg {
            parts.append(SettingsManager.shared.weightUnit.format(kilograms: kg))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .displayFont(.subheadline, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accentTint, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exercise.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    if plan?.supersetGroup != nil {
                        Image(systemName: "link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text(NSLocalizedString("Superset", comment: "Workout editor: exercise is part of a superset")))
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }
}

#Preview {
    WorkoutPreviewiOS(workout: .init(id: "id", infoText: "infoText", isUserGenerated: false, muscleGroup: 2, setLength: 2, straightSets: false, difficultyInt: 2, name: "Ausdauer-Workout", duration: 5, exercisesSequenceID: [], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5))
}
