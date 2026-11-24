//
//  GymPlanGeneratorView.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 22.05.26.
//

import SwiftUI
import SwiftData
import HealthKit

// MARK: - Gym Split

enum GymSplit: String, CaseIterable, Identifiable {
    case push
    case pull
    case leg
    case pushFullbody
    case pullFullbody

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push:          return NSLocalizedString("Push", comment: "Gym split, push day")
        case .pull:          return NSLocalizedString("Pull", comment: "Gym split, pull day")
        case .leg:           return NSLocalizedString("Legs", comment: "Gym split, leg day")
        case .pushFullbody:  return NSLocalizedString("Push + Full Body", comment: "Gym split, push fullbody day")
        case .pullFullbody:  return NSLocalizedString("Pull + Full Body", comment: "Gym split, pull fullbody day")
        }
    }

    var shortName: String {
        switch self {
        case .push:          return NSLocalizedString("Push", comment: "Gym split short")
        case .pull:          return NSLocalizedString("Pull", comment: "Gym split short")
        case .leg:           return NSLocalizedString("Legs", comment: "Gym split short")
        case .pushFullbody:  return NSLocalizedString("Push/FB", comment: "Gym split short, push fullbody")
        case .pullFullbody:  return NSLocalizedString("Pull/FB", comment: "Gym split short, pull fullbody")
        }
    }

    var symbolName: String {
        switch self {
        case .push:          return "arrow.up.forward"
        case .pull:          return "arrow.down.backward"
        case .leg:           return "figure.strengthtraining.functional"
        case .pushFullbody:  return "arrow.up.forward.circle"
        case .pullFullbody:  return "arrow.down.backward.circle"
        }
    }

    /// Which training buckets belong on this day. `targetedMuscleGroups` is the
    /// browse taxonomy and can't express this on its own: both biceps and
    /// triceps work is filed under "Arms", but only one of them belongs on a
    /// push day. See `TrainingBucket` in ExerciseCatalog.swift.
    var trainingBuckets: [TrainingBucket] {
        switch self {
        case .push:          return [.push]
        case .pull:          return [.pull]
        case .leg:           return [.legs, .core]
        case .pushFullbody:  return [.push, .fullBody, .core]
        case .pullFullbody:  return [.pull, .fullBody, .core]
        }
    }

    /// Muscle groups (WorkoutCategory raw values) this split targets, in priority order.
    var targetedMuscleGroups: [Int] {
        switch self {
        case .push:
            return [
                WorkoutCategory.chest.rawValue,
                WorkoutCategory.shoulders.rawValue,
                WorkoutCategory.arms.rawValue
            ]
        case .pull:
            return [
                WorkoutCategory.back.rawValue,
                WorkoutCategory.arms.rawValue
            ]
        case .leg:
            return [
                WorkoutCategory.legs.rawValue,
                WorkoutCategory.core.rawValue
            ]
        case .pushFullbody:
            return [
                WorkoutCategory.chest.rawValue,
                WorkoutCategory.shoulders.rawValue,
                WorkoutCategory.arms.rawValue,
                WorkoutCategory.fullbody.rawValue,
                WorkoutCategory.core.rawValue
            ]
        case .pullFullbody:
            return [
                WorkoutCategory.back.rawValue,
                WorkoutCategory.arms.rawValue,
                WorkoutCategory.fullbody.rawValue,
                WorkoutCategory.core.rawValue
            ]
        }
    }

    /// Primary muscle group used to tag the generated workout.
    var primaryMuscleGroup: Int {
        switch self {
        case .push:          return WorkoutCategory.chest.rawValue
        case .pull:          return WorkoutCategory.back.rawValue
        case .leg:           return WorkoutCategory.legs.rawValue
        case .pushFullbody:  return WorkoutCategory.fullbody.rawValue
        case .pullFullbody:  return WorkoutCategory.fullbody.rawValue
        }
    }
}

// MARK: - Generator Mode

enum GymGeneratorMode: String, CaseIterable, Identifiable {
    case singleWorkout
    case plan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleWorkout: return NSLocalizedString("Single workout", comment: "Gym generator mode")
        case .plan:          return NSLocalizedString("Plan", comment: "Gym generator mode")
        }
    }
}

// MARK: - Generator View

struct GymPlanGeneratorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var existingPlans: [Plan]
    @Query private var existingWorkouts: [Workout]
    @Query private var existingExercises: [Exercise]

    @StateObject private var settings = SettingsManager.shared

    @State private var mode: GymGeneratorMode

    init(initialMode: GymGeneratorMode = .plan) {
        _mode = State(initialValue: initialMode)
    }

    // Single-workout mode
    @State private var selectedSplit: GymSplit = .push

    // Plan mode: how many times per week each split appears.
    @State private var splitFrequencies: [GymSplit: Int] = [
        .push: 1,
        .pull: 1,
        .leg: 1,
        .pushFullbody: 0,
        .pullFullbody: 0
    ]
    @State private var targetDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()

    @State private var showEquipmentPicker = false
    @State private var showNotEnoughEquipmentAlert = false

    // Review-before-keep state. Generated content is inserted first, then shown
    // for review; the review screens keep or discard it.
    @State private var reviewWorkout: Workout?
    @State private var showSingleReview = false
    @State private var reviewPlan: Plan?
    @State private var reviewPlanWorkouts: [Workout] = []
    @State private var showPlanReview = false


    private var weeksUntilTarget: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: targetDate)
        let weeks = calendar.dateComponents([.weekOfYear], from: startOfToday, to: startOfTarget).weekOfYear ?? 0
        return max(weeks, 1)
    }

    private var weeklySessionsTotal: Int {
        splitFrequencies.values.reduce(0, +)
    }

    private func availableExercises(for split: GymSplit) -> [GymExerciseDefinition] {
        GymExerciseCatalog.exercises(for: split, availableEquipment: settings.availableGymEquipment)
    }

    var body: some View {
        NavigationStack {
            StyledForm {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(GymGeneratorMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .singleWorkout
                         ? "Generate a single workout to do today."
                         : "Build a multi-week plan combining the splits you want.")
                }

                if mode == .singleWorkout {
                    singleWorkoutSection
                } else {
                    planSplitsSection
                    planScheduleSection
                }

                equipmentSection

                Section {
                    Button {
                        switch mode {
                        case .singleWorkout: generateSingleWorkout()
                        case .plan:          generatePlan()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "wand.and.stars")
                            Text(mode == .singleWorkout ? "Generate workout" : "Generate plan")
                                .bold()
                            Spacer()
                        }
                        .foregroundStyle(Theme.onAccent)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.accentFillGradient)
                    .disabled(mode == .plan && weeklySessionsTotal == 0)
                }
            }
            .navigationTitle(mode == .singleWorkout ? "Gym workout" : "Gym plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showEquipmentPicker) {
                GymEquipmentPickerView()
            }
            // Review the generated single workout before finishing. Dismissing
            // the review (Done keeps it, Delete discards it) closes the generator.
            .sheet(isPresented: $showSingleReview, onDismiss: { dismiss() }) {
                if let reviewWorkout {
                    NavigationStack {
                        ChangeWorkoutView(workout: reviewWorkout, onDelete: {})
                    }
                }
            }
            .sheet(isPresented: $showPlanReview, onDismiss: { dismiss() }) {
                if let reviewPlan {
                    GeneratedPlanReviewView(plan: reviewPlan, workouts: reviewPlanWorkouts)
                }
            }
            .alert("Not enough equipment", isPresented: $showNotEnoughEquipmentAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("There aren't enough exercises available for the selected splits with your equipment. Add more equipment to your gym profile.")
            }
        }
    }

    // MARK: - Sections

    private var singleWorkoutSection: some View {
        Section {
            Picker("Split", selection: $selectedSplit) {
                ForEach(GymSplit.allCases) { split in
                    Label(split.displayName, systemImage: split.symbolName)
                        .tag(split)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Workout type")
        } footer: {
            Text("\(availableExercises(for: selectedSplit).count) exercises available for this split.")
        }
    }

    private var planSplitsSection: some View {
        Section {
            ForEach(GymSplit.allCases) { split in
                Stepper(value: Binding(
                    get: { splitFrequencies[split] ?? 0 },
                    set: { splitFrequencies[split] = $0 }
                ), in: 0...6) {
                    HStack {
                        Image(systemName: split.symbolName)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(split.displayName)
                            Text("\(availableExercises(for: split).count) exercises available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(splitFrequencies[split] ?? 0)×")
                            .foregroundStyle(Theme.accent)
                            .font(.headline)
                    }
                }
            }
        } header: {
            HStack {
                Text("Splits per week")
                Spacer()
                Text("\(weeklySessionsTotal) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } footer: {
            Text("Pick how often each split appears in a single week. They'll cycle through that pattern every week.")
        }
    }

    private var planScheduleSection: some View {
        Section {
            DatePicker("Target date",
                       selection: $targetDate,
                       in: Date()...,
                       displayedComponents: .date)
            HStack {
                Text("Weeks to train")
                Spacer()
                Text("\(weeksUntilTarget)")
                    .foregroundStyle(Theme.accent)
                    .font(.headline)
            }
        } header: {
            Text("Schedule")
        }
    }

    private var equipmentSection: some View {
        Section {
            Button {
                showEquipmentPicker = true
            } label: {
                HStack {
                    Text("My gym equipment")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(settings.availableGymEquipment.count)")
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Equipment")
        } footer: {
            Text("Workouts will only include exercises that match the equipment your gym has.")
        }
    }

    // MARK: - Generation

    private func generateSingleWorkout() {
        let pool = availableExercises(for: selectedSplit)
        guard pool.count >= 3 else {
            showNotEnoughEquipmentAlert = true
            return
        }

        let workout = buildWorkout(for: selectedSplit, pool: pool, sessionIndex: 0, displayName: selectedSplit.displayName)
        let uniqueWorkoutName = uniqueWorkoutName(selectedSplit.displayName)
        workout.name = uniqueWorkoutName
        workout.isSaved = true

        modelContext.insert(workout)

        do {
            try modelContext.save()
        } catch {
            appLog("Error saving generated gym workout: \(error)")
        }

        // Show the draft for review/editing instead of finishing immediately.
        reviewWorkout = workout
        showSingleReview = true
    }

    private func generatePlan() {
        // Splits selected by the user — must have at least one with a positive frequency.
        let weeklyTemplate: [GymSplit] = GymSplit.allCases.flatMap { split in
            Array(repeating: split, count: max(splitFrequencies[split] ?? 0, 0))
        }

        guard !weeklyTemplate.isEmpty else {
            showNotEnoughEquipmentAlert = true
            return
        }

        // Validate that every selected split has enough exercises available.
        for split in Set(weeklyTemplate) {
            if availableExercises(for: split).count < 3 {
                showNotEnoughEquipmentAlert = true
                return
            }
        }

        let weeks = weeksUntilTarget
        var workouts: [Workout] = []
        var workoutIDs: [String] = []

        for week in 0..<weeks {
            for (slot, split) in weeklyTemplate.enumerated() {
                let pool = availableExercises(for: split)
                let sessionIndex = week * weeklyTemplate.count + slot
                let workout = buildWorkout(
                    for: split,
                    pool: pool,
                    sessionIndex: sessionIndex,
                    displayName: String(format: NSLocalizedString(
                        "Week %d · %@",
                        comment: "Plan workout name: week, split"
                    ), week + 1, split.shortName)
                )
                workouts.append(workout)
                workoutIDs.append(workout.id)
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: targetDate)

        let summarySplits = GymSplit.allCases
            .filter { (splitFrequencies[$0] ?? 0) > 0 }
            .map { "\(splitFrequencies[$0] ?? 0)× \($0.shortName)" }
            .joined(separator: " + ")

        let baseName = String(
            format: NSLocalizedString("Gym plan by %@", comment: "Generated gym plan name: date"),
            dateString
        )
        let planName = uniqueName(baseName)

        let infoFormat = NSLocalizedString(
            "Progressive %d-week gym plan (%@) using your available gym equipment.",
            comment: "Generated gym plan info"
        )
        let infoText = String(format: infoFormat, weeks, summarySplits)

        // Use the most-frequent split as the plan's primary muscle group tag.
        let dominantSplit = splitFrequencies.max(by: { $0.value < $1.value })?.key ?? .push

        let newPlan = Plan(
            goal: PlanGoal.muscleBuilding.rawValue,
            infoText: infoText,
            muscleGroup: dominantSplit.primaryMuscleGroup,
            name: planName,
            difficultyInt: 2,
            interval: [:],
            intervalType: "",
            notificationIDs: [],
            isUserGenerated: true,
            workoutsSequenceIDs: workoutIDs,
            finishedWorkoutsSequence: [],
            workoutsInPlan: workouts
        )
        newPlan.workouts = workouts
        newPlan.workoutsSequenceIDs = workoutIDs

        for workout in workouts {
            modelContext.insert(workout)
            workout.plan = [newPlan]
        }
        modelContext.insert(newPlan)

        do {
            try modelContext.save()
        } catch {
            appLog("Error saving generated gym plan: \(error)")
        }

        // Show the generated workouts for review/editing before keeping the plan.
        reviewPlan = newPlan
        reviewPlanWorkouts = workouts
        showPlanReview = true
    }

    /// Build a single Workout for the given split. `sessionIndex` is used to rotate
    /// exercise picks so successive sessions don't repeat the exact same set.
    private func buildWorkout(for split: GymSplit,
                              pool: [GymExerciseDefinition],
                              sessionIndex: Int,
                              displayName: String) -> Workout {
        let grouped = Dictionary(grouping: pool, by: { $0.muscleGroup })

        var picked: [GymExerciseDefinition] = []
        for muscleGroup in split.targetedMuscleGroups {
            guard let candidates = grouped[muscleGroup], !candidates.isEmpty else { continue }
            let offset = sessionIndex % candidates.count
            picked.append(candidates[offset])
            if candidates.count > 1 {
                let secondary = candidates[(offset + 1) % candidates.count]
                if !picked.contains(where: { $0.id == secondary.id }) {
                    picked.append(secondary)
                }
            }
        }

        if picked.count < 3 {
            for def in pool where !picked.contains(where: { $0.id == def.id }) {
                picked.append(def)
                if picked.count >= 4 { break }
            }
        }

        let exercises = picked.map { exerciseEntity(for: $0) }
        let estimatedDuration = max(exercises.count * 6, 20)

        return Workout(
            id: UUID().uuidString,
            infoText: NSLocalizedString(
                "Generated gym session targeting your selected split using only the equipment you marked as available.",
                comment: "Generated gym workout info"
            ),
            isUserGenerated: true,
            isNew: true,
            muscleGroup: split.primaryMuscleGroup,
            setLength: 4.0,
            straightSets: false,
            difficultyInt: 2,
            name: displayName,
            duration: estimatedDuration,
            exercisesSequenceID: exercises.map { $0.id },
            finishedExercisesSequence: [],
            exercises: exercises,
            plan: [],
            workoutActivityType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
            workoutSessionLocation: Int(HKWorkoutSessionLocationType.indoor.rawValue)
        )
    }

    /// Returns an existing Exercise with the given seed id if present, otherwise creates and inserts one.
    /// `repCount` is always written so previously seeded strength exercises get the
    /// rep-based behavior the gym generator expects.
    private func exerciseEntity(for def: GymExerciseDefinition) -> Exercise {
        def.materialize(in: modelContext, existing: existingExercises)
    }

    private func uniqueName(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while existingPlans.contains(where: { $0.name == candidate }) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }

    private func uniqueWorkoutName(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while existingWorkouts.contains(where: { $0.name == candidate }) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }
}

// MARK: - Equipment Picker

struct GymEquipmentPickerView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SettingsManager.shared


    private var equipmentOptions: [Equipment] {
        Equipment.allCases.filter { $0 != .other }
    }

    var body: some View {
        NavigationStack {
            StyledList {
                Section {
                    ForEach(equipmentOptions, id: \.self) { equipment in
                        Button {
                            toggle(equipment)
                        } label: {
                            HStack {
                                Image(systemName: settings.availableGymEquipment.contains(equipment.rawValue)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(settings.availableGymEquipment.contains(equipment.rawValue)
                                                     ? AnyShapeStyle(Theme.accent)
                                                     : AnyShapeStyle(Color.secondary))
                                Text(equipment.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Available equipment")
                } footer: {
                    Text("Tap to toggle each item your gym has. Generated workouts will only use exercises that match.")
                }

                Section {
                    Button("Select all") {
                        settings.availableGymEquipment = Set(equipmentOptions.map { $0.rawValue })
                    }
                    Button("Clear all", role: .destructive) {
                        settings.availableGymEquipment = []
                    }
                }
            }
            .navigationTitle("My gym")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func toggle(_ equipment: Equipment) {
        if settings.availableGymEquipment.contains(equipment.rawValue) {
            settings.availableGymEquipment.remove(equipment.rawValue)
        } else {
            settings.availableGymEquipment.insert(equipment.rawValue)
        }
    }
}

#Preview {
    let preview = PreviewPlan()
    return GymPlanGeneratorView()
        .modelContainer(preview.container)
}
