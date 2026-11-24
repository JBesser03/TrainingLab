//
//  AddChangeUebungView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 24.09.21.
//

import SwiftUI
import SwiftData

struct AddExerciseDummy {
    var id = UUID().uuidString
    var name = ""
    var duration: Double? = nil
    var equipment: [Int] = []
    var caloriesPerSecond: Double? = nil
    var symbol = "not Found"
    var difficulty = "medium"
    var difficultyInt = 2
    var muscleGroup = WorkoutCategory.undefined.rawValue
    /// `0` = time-based (workout timer drives it); `> 0` = rep-based.
    var repCount: Int = 0
    /// Optional target weight in kilograms; `nil` = no target set.
    var targetWeightKg: Double? = nil
}

//MARK: - AddUebungView
struct AddExerciseView: View {
    
    @Environment(\.modelContext) var modelContext
    
    @State private var gearPreview: String = NSLocalizedString("None", comment: "None")
    @State private var addExerciseDummy = AddExerciseDummy()
    @State private var isSymbolSelectionPresented = false
    
    @Binding var showAddExerciseView: Bool

    /// Toggles the exercise between time-based (repCount 0) and rep-based.
    private var isRepBasedBinding: Binding<Bool> {
        Binding(
            get: { addExerciseDummy.repCount > 0 },
            set: { addExerciseDummy.repCount = $0 ? max(addExerciseDummy.repCount, 10) : 0 }
        )
    }

    /// Work duration in whole seconds for a time-based exercise (default 30s).
    private var workSecondsBinding: Binding<Int> {
        Binding(
            get: { Int(addExerciseDummy.duration ?? 30) },
            set: { addExerciseDummy.duration = Double($0) }
        )
    }

    var body: some View {
        NavigationStack {
            StyledForm {
// MARK: Name
                TextField("Name", text: $addExerciseDummy.name)
                
// MARK: Difficulty
                HStack {
                    Text("Difficulty")
                    Spacer()
                    Picker("Difficulty", selection: $addExerciseDummy.difficultyInt) {
                        ForEach(DifficultyLevel.allCases) { level in
                            Text(level.name).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

// MARK: Reps vs Time
                Toggle("Count reps instead of time", isOn: isRepBasedBinding)
                if addExerciseDummy.repCount > 0 {
                    Stepper(value: $addExerciseDummy.repCount, in: 1...100) {
                        Text("Target reps: \(addExerciseDummy.repCount)")
                    }
                } else {
                    // Time-based: the work duration (seconds) drives the timer.
                    Stepper(value: workSecondsBinding, in: 10...300, step: 5) {
                        Text("Work time: \(workSecondsBinding.wrappedValue)s")
                    }
                }

// MARK: Target weight
                HStack {
                    Text("Target weight")
                    Spacer()
                    WeightEntryField(weightKg: $addExerciseDummy.targetWeightKg)
                }

// MARK: Muscle Group
                Picker("Muscle Group", selection: $addExerciseDummy.muscleGroup) {
                    ForEach(WorkoutCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                
// MARK: Equipment
                Menu {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Button {
                            gearSelectionToggle(gear: equipment.rawValue)
                            gearPreview = Equipment.getEquipmentNames(from: addExerciseDummy.equipment).joined(separator: ", ")
                        } label: {
                            HStack {
                                Image(systemName: addExerciseDummy.equipment.contains(equipment.rawValue) ? "checkmark" : "xmark")
                                Text(equipment.displayName)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Equipment")
                            .foregroundColor(.primary)
                        Spacer()
                        HStack {
                            Text(gearPreview)
                            
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .onChange(of: addExerciseDummy.equipment) {
                    gearPreview = Equipment.getEquipmentNames(from: addExerciseDummy.equipment).joined(separator: ", ")
                }
                
// MARK: Symbol
                Button(action: {
                    isSymbolSelectionPresented.toggle()
                }, label: {
                    HStack {
                        Text("Symbol")
                            .foregroundColor(.primary)
                        Spacer()
                        
                        ExerciseSymbolImage(name: addExerciseDummy.symbol)
                            .frame(height: 25)
                            .opacity(0.6)
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                })
            }
            .onAppear {
                gearPreview = Equipment.getEquipmentNames(from: addExerciseDummy.equipment).joined(separator: ", ")
                if addExerciseDummy.equipment.isEmpty {
                    gearPreview = NSLocalizedString("None", comment: "None")
                }
            }
            .sheet(isPresented: $isSymbolSelectionPresented, content: {
                SymbolChangeView(selectedSymbol: $addExerciseDummy.symbol)
            })
            
            .navigationTitle("Add Exercise")
#if os(iOS) || os(watchOS) || os(tvOS)
            .navigationBarItems(
                leading: Button("Cancel") {
                    showAddExerciseView = false
                }, trailing: Button("Save") {
                    ExerciseItemManager.shared.configure(with: modelContext)
                    ExerciseItemManager.shared.addItem(fromDummy: addExerciseDummy)
                    showAddExerciseView = false
                })
#else
            
#endif
        }
    }
    
    private func gearSelectionToggle(gear: Int) {
        if let index = addExerciseDummy.equipment.firstIndex(of: gear) {
            addExerciseDummy.equipment.remove(at: index)
        } else {
            addExerciseDummy.equipment.append(gear)
        }
        if addExerciseDummy.equipment.isEmpty {
            addExerciseDummy.equipment.append(100)
        } else if addExerciseDummy.equipment.contains(100) && addExerciseDummy.equipment.count > 1 {
            addExerciseDummy.equipment.removeAll { $0 == 100 }
        }
    }
}

//MARK: - ChangeExerciseView
struct ChangeExerciseView: View {
    @Bindable var exercise: Exercise

    @Query var exercises: [Exercise]

    @Environment(\.modelContext) var modelContext

    @State private var equipmentPreview: String = "None"
    @State private var isSymbolSelectionPresented = false
    /// The editable fields as they were when the screen opened, to tell on
    /// the way out which ones the user changed (`recordCustomizations`).
    @State private var original: [String: AnyHashable] = [:]

    private var difficultySymbol: String {
        switch exercise.difficultyInt {
        case 1: return "gauge.with.dots.needle.0percent"
        case 2: return "gauge.with.dots.needle.50percent"
        case 3: return "gauge.with.dots.needle.100percent"
        default: return "gauge.with.dots.needle.50percent"
        }
    }

    private var symbol: ExerciseSymbol? { ExerciseSymbol(name: exercise.symbol) }

    /// Toggles the exercise between time-based (repCount 0) and rep-based.
    private var isRepBasedBinding: Binding<Bool> {
        Binding(
            get: { exercise.repCount > 0 },
            set: { exercise.repCount = $0 ? max(exercise.repCount, 10) : 0 }
        )
    }

    /// Work duration in whole seconds for a time-based exercise (default 30s).
    private var workSecondsBinding: Binding<Int> {
        Binding(
            get: { Int(exercise.duration ?? 30) },
            set: { exercise.duration = Double($0) }
        )
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    // MARK: Hero header
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Theme.inset)
                                .frame(width: 56, height: 56)

                            if let asset = symbol?.assetName {
                                Image(asset)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                            } else {
                                Image(systemName: symbol?.systemName ?? WorkoutCategory.getSymbolName(from: exercise.muscleGroup))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(exercise.displayName.isEmpty ? NSLocalizedString("Unnamed Exercise", comment: "Placeholder for empty exercise name") : exercise.displayName)
                                .displayFont(.headline)
                                .lineLimit(1)

                            Label("\(exercise.displayDifficulty) · \(WorkoutCategory.getCategoryName(from: exercise.muscleGroup))",
                                  systemImage: difficultySymbol)
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }

                        Spacer()
                    }
                    .card(padding: 12)
                    .padding(.horizontal)

                    // MARK: Editable fields
                    VStack(spacing: 12) {
                        EditFieldCard(label: "Name", icon: "pencil") {
                            TextField("Name", text: $exercise.name)
                                .textFieldStyle(.plain)
                                .font(.body.weight(.medium))
                        }

                        EditFieldCard(label: "Difficulty", icon: "gauge.with.dots.needle.50percent") {
                            Picker("Difficulty", selection: $exercise.difficultyInt) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.name).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }

                        EditFieldCard(label: "Type", icon: "repeat") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle("Count reps instead of time", isOn: isRepBasedBinding)
                                if exercise.repCount > 0 {
                                    Stepper(value: $exercise.repCount, in: 1...100) {
                                        Text("Target reps: \(exercise.repCount)")
                                    }
                                } else {
                                    // Time-based: the work duration (seconds) drives the timer.
                                    Stepper(value: workSecondsBinding, in: 10...300, step: 5) {
                                        Text("Work time: \(workSecondsBinding.wrappedValue)s")
                                    }
                                }
                            }
                        }

                        EditFieldCard(label: "Target weight", icon: "scalemass") {
                            HStack {
                                WeightEntryField(weightKg: $exercise.targetWeightKg)
                                Spacer()
                            }
                        }

                        EditFieldCard(label: "Muscle group", icon: "figure.strengthtraining.traditional") {
                            Picker("Muscle group", selection: $exercise.muscleGroup) {
                                ForEach(WorkoutCategory.allCases, id: \.self) { category in
                                    Text(category.displayName).tag(category.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        EditFieldCard(label: "Equipment", icon: "dumbbell.fill") {
                            Menu {
                                ForEach(Equipment.allCases, id: \.self) { equipment in
                                    Button {
                                        gearSelectionToggle(gear: equipment.rawValue)
                                        refreshEquipmentPreview()
                                    } label: {
                                        HStack {
                                            Image(systemName: exercise.equipment.contains(equipment.rawValue) ? "checkmark" : "xmark")
                                            Text(equipment.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(equipmentPreview)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }

                        EditFieldCard(label: "Symbol", icon: "photo.on.rectangle.angled") {
                            Button {
                                isSymbolSelectionPresented.toggle()
                            } label: {
                                HStack {
                                    if let asset = symbol?.assetName {
                                        Image(asset)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 28)
                                    } else if let system = symbol?.systemName {
                                        Image(systemName: system)
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(Color.primary)
                                    } else {
                                        Text(NSLocalizedString("None", comment: "None"))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $isSymbolSelectionPresented, content: {
            SymbolChangeView(selectedSymbol: $exercise.symbol)
        })
        .onAppear {
            refreshEquipmentPreview()
            if original.isEmpty { original = editableFields() }
        }
        .onDisappear(perform: recordCustomizations)
        .pageTint()
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func editableFields() -> [String: AnyHashable] {
        ["name": exercise.name, "symbol": exercise.symbol, "equipment": exercise.equipment,
         "repCount": exercise.repCount, "difficulty": exercise.difficultyInt, "muscleGroup": exercise.muscleGroup]
    }

    /// Marks the fields changed here as the user's, so the catalog sync and
    /// the workout generators don't undo the edit.
    private func recordCustomizations() {
        guard !original.isEmpty else { return }
        let current = editableFields()
        let changed = Set(current.keys.filter { current[$0] != original[$0] })
        guard !changed.isSubset(of: exercise.customizedFields) else { return }
        exercise.customizedFields.formUnion(changed)
        try? modelContext.save()
    }

    private func refreshEquipmentPreview() {
        if exercise.equipment.isEmpty {
            equipmentPreview = NSLocalizedString("None", comment: "None")
        } else {
            let names = Equipment.getEquipmentNames(from: exercise.equipment)
            equipmentPreview = names.isEmpty ? NSLocalizedString("None", comment: "None") : names.joined(separator: ", ")
        }
    }

    private func gearSelectionToggle(gear: Int) {
        if exercise.equipment.contains(gear) {
            exercise.equipment.removeAll { $0 == gear }
        } else {
            exercise.equipment.append(gear)
        }
    }
}

// MARK: - WeightEntryField

/// A weight entry bound to an optional kilogram value. The user can tap −/+ to
/// step by 2.5 (in their unit) or type an exact amount; the value is stored back
/// in kilograms. An empty field / zero means "no target" (`nil`).
struct WeightEntryField: View {
    @Binding var weightKg: Double?
    @ObservedObject private var settings = SettingsManager.shared
    @FocusState private var isFocused: Bool

    /// One tap = 2.5 in the user's display unit, expressed in kilograms.
    private var stepKg: Double { settings.weightUnit.toKilograms(2.5) }

    private var hasValue: Bool { (weightKg ?? 0) > 0 }

    var body: some View {
        let unit = settings.weightUnit
        HStack(spacing: 12) {
            Button {
                adjust(by: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .accessibilityLabel(Text(NSLocalizedString("Decrease weight", comment: "Accessibility: weight stepper")))
                    .font(.title3)
                    .foregroundStyle(hasValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .buttonStyle(.borderless)
            .disabled(!hasValue)

            HStack(spacing: 4) {
                TextField(NSLocalizedString("None", comment: "None"), text: text(for: unit))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .frame(minWidth: 44)
                    .focused($isFocused)
                    .toolbar {
                        // The decimal pad has no return key, so give the user an
                        // explicit way to dismiss the keyboard.
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(NSLocalizedString("Done", comment: "Dismiss keyboard")) {
                                isFocused = false
                            }
                        }
                    }
                Text(unit.abbreviation)
                    .foregroundStyle(.secondary)
            }

            Button {
                adjust(by: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .accessibilityLabel(Text(NSLocalizedString("Increase weight", comment: "Accessibility: weight stepper")))
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
        }
    }

    /// Steps the weight by `direction` increments, clamped at zero. Stepping down
    /// to zero clears the target (`nil`) so it reads "None" again.
    private func adjust(by direction: Double) {
        let base = weightKg ?? 0
        let updated = base + direction * stepKg
        weightKg = updated > 0.0001 ? updated : nil
    }

    private func text(for unit: WeightUnit) -> Binding<String> {
        Binding(
            get: {
                guard let kg = weightKg else { return "" }
                let value = unit.fromKilograms(kg)
                let rounded = (value * 10).rounded() / 10
                return rounded == rounded.rounded()
                    ? String(Int(rounded))
                    : String(format: "%.1f", rounded)
            },
            set: { newValue in
                let normalized = newValue
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                if normalized.isEmpty {
                    weightKg = nil
                } else if let display = Double(normalized), display >= 0 {
                    weightKg = unit.toKilograms(display)
                }
            }
        )
    }
}

// MARK: - EditFieldCard

private struct EditFieldCard<Content: View>: View {
    let label: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

// MARK: - SymbolChangeView
struct SymbolChangeView: View {
    
    let exerciseSymbolDictionary: [String: String] = [
        "Pushups": "pushupsSymbol",
        "Boxing": "boxingSymbol",
        "Jumping Jacks": "jumpingJacksSymbol",
        "Situps": "situpsSymbol",
        "Squats": "squatsSymbol",
        "Trizep-Dips": "tricepDipsSymbol",
        "Mountain Climbers": "mountainClimberSymbol",
        "Plank": "plankSymbol",
        "Lunges": "lungesSymbol",
        "Burpees with Push-ups": "burpeesSymbol",
        "Bicycle Crunches": "bicycleCrunchesSymbol",
        "Burpees": "burpeesSymbol",
        "Wall Sits": "wallSitSymbol",
        "Superman": "supermanSymbol",
        "Russian Twists": "russianTwistsSymbol",
        "Side Plank": "sidePlankSymbol",
        "Bench Press": "benchPressSymbol",
        "Deadlifts": "deadliftsSymbol",
        "Overhead Press": "overheadPressSymbol",
        "Pull-ups": "pullUpSymbol",
        "Sun Salutation": "sunSalutationSymbol",
        "Tree Pose": "treePoseSymbol",
        "Cobra Pose": "cobraPoseSymbol",
        "Downward Facing Dog": "downwardFacingDogSymbol",
        "Seated Forward Bend": "seatedForwardBendSymbol",
        "Jump Rope": "jumpRopeSymbol",
        "High Knees": "highKneesSymbol",
        "Sprint": "figure.run",
        "Kettlebell Swing": "kettlebells",
        "Rope Climb": "ropeClimb",
        "Battle Ropes": "battleRopes",
        "Lat Pulldown": "latPulldown",
        "Cable Crossover": "cableCrossover",
        "Leg Press": "legPressMaschine",
        "Hammer Curls": "curlSymbol",
        "Shoulder Press": "overheadPressSymbol",
        "Lateral Raise": "lateralRaise",
        "Skullcrushers": "skullcrusher",
        "Calf Raise": "calfRaise",
        "Romanian Deadlift": "deadliftsSymbol",
        "Pike Push-up": "downwardFacingDogSymbol",
        "Dips": "tricepDipsSymbol",
        "Rowing": "rowingMaschine",
        "Cycling": "stationaryBike",
        "Glute Bridge": "gluteBridgeSymbol",
        "Leg Extension": "legExtensionSymbol",
        "Leg Curl": "legCurlSymbol",
        "Hip Abduction": "hipAbductionSymbol",
        "Glute Kickback": "gluteKickbackSymbol",
        "Bird Dog": "birdDogSymbol",
        "Tricep Kickback": "tricepKickbackSymbol",
        "Nordic Curl": "nordicCurlSymbol",
        "Inverted Row": "invertedRowSymbol",
        "Sled Push": "sledPushSymbol",
        "Turkish Get-Up": "turkishGetUpSymbol",
        "90/90 Hip Switch": "hip9090Symbol",
        "Pec Deck": "pecDeckSymbol",
        "Tricep Pushdown": "tricepPushdownSymbol",
        "Face Pull": "facePullSymbol",
        "Cable Crunch": "cableCrunchSymbol",
        "Cable Woodchopper": "cableRotationSymbol",
        "Overhead Tricep Extension": "overheadTricepSymbol",
        "Dumbbell Pullover": "pulloverSymbol",
        "Hanging Leg Raise": "hangingLegRaiseSymbol",
        "Ab Wheel Rollout": "abWheelSymbol",
        "Bear Crawl": "bearCrawlSymbol",
        "Child's Pose": "childsPoseSymbol",
        "Pigeon Pose": "pigeonPoseSymbol",
        "Cat-Cow": "catCowSymbol",
        "Pistol Squat": "pistolSquatSymbol",
    ]
    
    @Binding var selectedSymbol: String
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack(root: {
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(exerciseSymbolDictionary.keys.sorted(), id: \.self) { symbol in
                        Button {
                            selectedSymbol = exerciseSymbolDictionary[symbol] ?? "Not found"
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedSymbol == exerciseSymbolDictionary[symbol] ? .blue : .gray.opacity(0.5))
                                    .frame(width: 70, height: 70)
                                    .opacity(0.6)
                                
                                ExerciseSymbolImage(name: exerciseSymbolDictionary[symbol] ?? "Not found")
                                    .frame(height: 50)
                            }
                        }
                        // The keys are exercise names; VoiceOver otherwise
                        // reads nothing for an image-only button.
                        .accessibilityLabel(Text(NSLocalizedString(symbol, comment: "Exercise name")))
                        .accessibilityAddTraits(selectedSymbol == exerciseSymbolDictionary[symbol] ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal)
            .pageTint()
            .navigationTitle("Change Symbol")
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        })
    }
}

#Preview {
    SymbolChangeView(selectedSymbol: .constant("plankSymbol"))
}
