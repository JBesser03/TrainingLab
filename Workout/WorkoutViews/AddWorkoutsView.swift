//
//  TestAddWorkoutsView.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 03.04.23.
//

import SwiftUI
import HealthKit
import SwiftData
import Combine

struct AddWorkoutDummy {
    var workoutName = ""
    var id = UUID().uuidString
    var workoutDifficulty = "medium"
    var workoutDifficultyInt = 2
    var workoutDuration = 10
    var infoText = ""
    var isUserGenerated = true
    var isNew = true
    var muscleGroup: Int = WorkoutCategory.fullbody.rawValue
    var setLength = 3.0
    var exercises: [Exercise]? = nil
    var workoutActivityType = HKWorkoutActivityType.traditionalStrengthTraining.rawValue
    var workoutSessionLocation: Int = HKWorkoutSessionLocationType.indoor.rawValue
    var exercisesSequenceID: [String] = []
    var exercisePlans: [String: ExercisePlan] = [:]
}

struct AddWorkoutsView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @State private var addWorkoutDummy = AddWorkoutDummy()
    @State private var items: [PlannedExercise] = []
    @State private var showExercisePicker = false
    /// Until the user sets a duration, it follows the planned sets.
    @State private var durationEdited = false
    
    @Binding var showAddWorkoutView: Bool
    
    private var duration: Int {
        durationEdited ? addWorkoutDummy.workoutDuration : WorkoutDefaults.estimatedMinutes(items)
    }
    
    var body: some View {
        NavigationStack {
            StyledForm {
                Section {
                    TextField("Name", text: $addWorkoutDummy.workoutName)
                    
                    Picker("Muscle group", selection: muscleGroupBinding) {
                        ForEach(WorkoutCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category.rawValue)
                        }
                    }
                }

                PlannedExercisesSection(items: $items,
                                        holdsTimedExercises: WorkoutCategory.holdsTimedExercises(addWorkoutDummy.muscleGroup)) {
                    showExercisePicker = true
                }

                Section {
                    DisclosureGroup(NSLocalizedString("More options", comment: "Workout editor: duration, difficulty, activity type, location, description")) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Stepper(value: Binding(get: { duration },
                                                   set: { addWorkoutDummy.workoutDuration = $0; durationEdited = true }),
                                    in: 5...120, step: 5) {
                                Text("\(duration) min")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize()
                        }

                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Picker("Difficulty", selection: $addWorkoutDummy.workoutDifficultyInt) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.name).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }

                        Picker("Activity-type", selection: $addWorkoutDummy.workoutActivityType) {
                            ForEach(HKWorkoutActivityType.selectable, id: \.self) { type in
                                Text(type.name).tag(type.rawValue)
                            }
                        }

                        Picker("Location", selection: $addWorkoutDummy.workoutSessionLocation) {
                            ForEach(1...3, id: \.self) { locationValue in
                                if let location = HKWorkoutSessionLocationType(rawValue: locationValue) {
                                    Text("\(location.localizedName)").tag(locationValue)
                                }
                            }
                        }

                        TextField("Description", text: $addWorkoutDummy.infoText, axis: .vertical)
                            .lineLimit(100)
                    }
                }
            }
            .navigationTitle("Add Workout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showAddWorkoutView = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView(mode: .multiple,
                                   title: NSLocalizedString("Add exercises", comment: "Workout editor: open the exercise picker"),
                                   included: Set(items.map(\.id))) { picked in
                    items += picked.map(PlannedExercise.init(exercise:))
                }
            }
        }
    }

    /// Changing the muscle group carries the activity type and location along
    /// while they're still the old group's defaults.
    private var muscleGroupBinding: Binding<Int> {
        Binding(get: { addWorkoutDummy.muscleGroup }, set: { new in
            let old = addWorkoutDummy.muscleGroup
            if addWorkoutDummy.workoutActivityType == WorkoutDefaults.activityType(forMuscleGroup: old).rawValue {
                addWorkoutDummy.workoutActivityType = WorkoutDefaults.activityType(forMuscleGroup: new).rawValue
            }
            if addWorkoutDummy.workoutSessionLocation == WorkoutDefaults.location(forMuscleGroup: old).rawValue {
                addWorkoutDummy.workoutSessionLocation = WorkoutDefaults.location(forMuscleGroup: new).rawValue
            }
            addWorkoutDummy.muscleGroup = new
        })
    }

    private func save() {
        addWorkoutDummy.exercises = items.map(\.exercise)
        addWorkoutDummy.exercisesSequenceID = items.map(\.id)
        let plans = PlannedExercise.plans(items)
        addWorkoutDummy.exercisePlans = plans
        addWorkoutDummy.setLength = Double(ExercisePlan.commonSetCount(Array(plans.values)))
        addWorkoutDummy.workoutDuration = duration
        WorkoutItemManager.shared.configure(with: modelContext)
        WorkoutItemManager.shared.addWorkout(fromDummy: addWorkoutDummy)
        showAddWorkoutView = false
    }
}

// MARK: - ChangeWorkoutView

struct ChangeWorkoutView: View {
    
    @Bindable var workout: Workout
    let onDelete: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @StateObject var changeWorkoutViewModel = ChangeWorkoutViewModel()

    /// Set when the workout is deleted/discarded so `onDisappear` doesn't try to
    /// save onto an already-removed model.
    @State private var didDelete = false
    /// View state, not on the view model: SwiftUI resets it while the dialog
    /// and this screen close, and that write to a `@Published` property
    /// published a change from within a view update.
    @State private var showDeleteConfirmation = false
    @State private var showExercisePicker = false

    var body: some View {
            StyledForm {
                Section {
                    TextField("Name", text: $changeWorkoutViewModel.selectionWorkoutName)

                    Picker("Muscle group", selection: muscleGroupBinding) {
                        ForEach(WorkoutCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category.rawValue)
                        }
                    }
                }

                // The order here becomes exercisesSequenceID on save.
                PlannedExercisesSection(items: $changeWorkoutViewModel.selectionItems,
                                        holdsTimedExercises: WorkoutCategory.holdsTimedExercises(changeWorkoutViewModel.selectionMuscleGroup)) {
                    showExercisePicker = true
                }

                Section {
                    DisclosureGroup(NSLocalizedString("More options", comment: "Workout editor: duration, difficulty, activity type, location, description")) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Stepper(value: $changeWorkoutViewModel.selectionDuration, in: 5...120, step: 5) {
                                Text("\(changeWorkoutViewModel.selectionDuration) min")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize()
                        }

                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Picker("Difficulty", selection: $changeWorkoutViewModel.selectionDifficultyInt) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.name).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }

                        Picker("Activity-type", selection: $changeWorkoutViewModel.selectionActivityType) {
                            ForEach(HKWorkoutActivityType.selectable, id: \.self) { type in
                                Text(type.name).tag(type.rawValue)
                            }
                        }

                        Picker("Location", selection: $changeWorkoutViewModel.selectionWorkoutLocation) {
                            ForEach(1...3, id: \.self) { locationValue in
                                if let location = HKWorkoutSessionLocationType(rawValue: locationValue) {
                                    Text("\(location.localizedName)").tag(locationValue)
                                }
                            }
                        }

                        TextField("Description", text: $changeWorkoutViewModel.selectionInfoText, axis: .vertical)
                            .lineLimit(100)
                    }
                }
            }
            .confirmationDialog("Delete Workout", isPresented: $showDeleteConfirmation, actions: {
                Button("Delete Workout") {
                    didDelete = true
                    WorkoutItemManager.shared.configure(with: modelContext)
                    WorkoutItemManager.shared.delete(workout: workout)
                    appLog("Workout has been deleted")

                    dismiss()
                    onDelete()
                }
            })
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView(mode: .multiple,
                                   title: NSLocalizedString("Add exercises", comment: "Workout editor: open the exercise picker"),
                                   included: Set(changeWorkoutViewModel.selectionItems.map(\.id))) { picked in
                    changeWorkoutViewModel.selectionItems += picked.map(PlannedExercise.init(exercise:))
                }
            }
            .onDisappear {
                // Don't save onto a workout that was just deleted/discarded.
                if !didDelete {
                    saveWorkout()
                }
            }
            .navigationTitle("Edit Workout")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .accessibilityLabel(Text(NSLocalizedString("Delete Workout", comment: "")))
                    }
                    Button("Done") {
                        // saveWorkout() writes the exercise membership, their
                        // order and their plans.
                        saveWorkout()
                        dismiss()
                    }
                }
            }
        .onAppear(perform: {
            changeWorkoutViewModel.initValues(workout)
        })
    }

    /// Changing the muscle group carries the activity type and location along
    /// while they're still the old group's defaults.
    private var muscleGroupBinding: Binding<Int> {
        Binding(get: { changeWorkoutViewModel.selectionMuscleGroup }, set: { new in
            let model = changeWorkoutViewModel
            let old = model.selectionMuscleGroup
            if model.selectionActivityType == WorkoutDefaults.activityType(forMuscleGroup: old).rawValue {
                model.selectionActivityType = WorkoutDefaults.activityType(forMuscleGroup: new).rawValue
            }
            if model.selectionWorkoutLocation == WorkoutDefaults.location(forMuscleGroup: old).rawValue {
                model.selectionWorkoutLocation = WorkoutDefaults.location(forMuscleGroup: new).rawValue
            }
            model.selectionMuscleGroup = new
        })
    }

    func saveWorkout() {
        workout.name = changeWorkoutViewModel.selectionWorkoutName
        workout.duration = changeWorkoutViewModel.selectionDuration
        workout.difficultyInt = changeWorkoutViewModel.selectionDifficultyInt
        workout.muscleGroup = changeWorkoutViewModel.selectionMuscleGroup
        workout.infoText = changeWorkoutViewModel.selectionInfoText
        workout.workoutActivityType = Int(changeWorkoutViewModel.selectionActivityType)
        workout.workoutSessionLocation = changeWorkoutViewModel.selectionWorkoutLocation

        // Persist the exercise membership, their order and their plans. The
        // order is the source of truth for ActiveWorkoutView/WorkoutPreview,
        // so write both sides.
        let items = changeWorkoutViewModel.selectionItems
        workout.exercises = items.map(\.exercise)
        workout.exercisesSequenceID = items.map(\.id)
        let plans = PlannedExercise.plans(items)
        if plans != workout.exercisePlans { workout.exercisePlans = plans }
        let sets = Double(ExercisePlan.commonSetCount(Array(plans.values), fallback: Int(workout.setLength)))
        if sets != workout.setLength { workout.setLength = sets }

        do {
            try modelContext.save()
        } catch {
            appLog("Error saving modelContext: \(error)")
        }
    }
}

//MARK: - ChangeWorkoutViewModel

class ChangeWorkoutViewModel: ObservableObject {
    
    @Published var selectionWorkoutName = ""
    @Published var selectionDuration: Int = 10
    @Published var selectionDifficultyInt: Int = 2
    @Published var selectionMuscleGroup = WorkoutCategory.fullbody.rawValue
    @Published var selectionActivityType = HKWorkoutActivityType.other.rawValue
    @Published var selectionWorkoutLocation = HKWorkoutSessionLocationType.unknown.rawValue
    @Published var selectionInfoText: String = "InfoText"
    @Published var selectionItems: [PlannedExercise] = []
    
    func initValues(_ workout: Workout) {
        selectionWorkoutName = workout.name
        selectionDuration = workout.duration
        selectionDifficultyInt = workout.difficultyInt
        selectionMuscleGroup = workout.muscleGroup
        selectionActivityType = UInt(workout.workoutActivityType)
        selectionWorkoutLocation = workout.workoutSessionLocation
        selectionInfoText = workout.infoText
        // Present exercises in the workout's canonical order so reordering starts
        // from what the user actually sees, not the unordered relationship array.
        let all = workout.exercises ?? []
        let sequence = workout.exercisesSequenceID
        let ordered = sequence.isEmpty
            ? all
            : all.sorted { (sequence.firstIndex(of: $0.id) ?? Int.max) < (sequence.firstIndex(of: $1.id) ?? Int.max) }
        selectionItems = PlannedExercise.items(for: workout, ordered: ordered)
    }
}
