//
//  EditFinishedWorkoutView.swift
//  TrainingLab (iOS)
//
//  Lets the user correct a logged workout after the fact: rename it, change
//  what sport it was (and so which weekly goal it counts toward), fix or
//  remove the per-set weight/reps, change a set's type (working, warm-up,
//  drop set) and add a set that wasn't logged. Edits a local copy and writes
//  back to `setWeights` / `setReps` / `loggingDetails` only on Save — the set
//  details stay index-aligned with the weights, so removing a set moves its
//  type and reps in reserve with it.
//

import SwiftUI
import SwiftData
import HealthKit

struct EditFinishedWorkoutView: View {
    @Bindable var workout: FinishedWorkout

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var activityType = HKWorkoutActivityType.other
    @State private var weights: [String: [Double]] = [:]
    @State private var reps: [String: [Int]] = [:]
    @State private var details: [String: [SetDetail]] = [:]
    /// Set by `load`: the form appears again on coming back from the type
    /// list, and loading then would undo every change made so far.
    @State private var loaded = false

    /// Exercises in the workout's canonical order.
    private var orderedExercises: [Exercise] {
        guard let exercises = workout.exercises else { return [] }
        let sequence = workout.exercisesSequenceID
        guard !sequence.isEmpty else { return exercises }
        return exercises.sorted { (sequence.firstIndex(of: $0.id) ?? Int.max) < (sequence.firstIndex(of: $1.id) ?? Int.max) }
    }

    var body: some View {
        NavigationStack {
            StyledForm {
                Section(NSLocalizedString("Name", comment: "")) {
                    TextField(NSLocalizedString("Name", comment: ""), text: $name)
                }

                Section {
                    NavigationLink {
                        ActivityTypePicker(selection: $activityType, current: workoutActivityType)
                    } label: {
                        HStack {
                            Text(NSLocalizedString("Workout type", comment: ""))
                            Spacer()
                            Label(activityType.name, systemImage: activityType.symbolName)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .accessibilityIdentifier("editWorkout.type")
                } footer: {
                    Text(NSLocalizedString("Decides which weekly goal the workout counts toward. Apple Health keeps the type it was recorded with.",
                                           comment: "Edit finished workout: what changing the workout type does"))
                }

                ForEach(orderedExercises, id: \.id) { exercise in
                    Section(exercise.displayName) {
                        let count = weights[exercise.id]?.count ?? 0
                        if count == 0 {
                            Text(NSLocalizedString("No sets logged", comment: "Edit finished workout: exercise without sets"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(0..<count, id: \.self) { index in
                                // Two lines: in one, the reps were squeezed
                                // until "reps" broke over two lines.
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 12) {
                                        kindMenu(exercise.id, index)
                                        Spacer(minLength: 0)
                                        WeightEntryField(weightKg: weightBinding(exercise.id, index))
                                    }
                                    Stepper(value: repsBinding(exercise.id, index), in: 0...100) {
                                        Text(String(format: NSLocalizedString("%d reps", comment: ""), reps[exercise.id]?[safe: index] ?? 0))
                                            .font(.subheadline)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .onDelete { deleteSets(exercise.id, $0) }
                        }
                        Button {
                            addSet(exercise.id)
                        } label: {
                            Label(NSLocalizedString("Add set", comment: "Edit finished workout: add a set that wasn't logged"),
                                  systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Edit workout", comment: "Edit finished workout: title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "")) { save() }
                        .bold()
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Data

    private var workoutActivityType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: UInt(workout.workoutType)) ?? .other
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = workout.name
        activityType = workoutActivityType
        // Normalise so weights and reps arrays are the same length per exercise
        // (older records may have logged weight-only), which keeps index-based
        // bindings safe.
        var w = workout.setWeights
        var r = workout.setReps
        for id in Set(w.keys).union(r.keys) {
            let n = max(w[id]?.count ?? 0, r[id]?.count ?? 0)
            var wa = w[id] ?? [], ra = r[id] ?? []
            while wa.count < n { wa.append(0) }
            while ra.count < n { ra.append(0) }
            w[id] = wa
            r[id] = ra
        }
        weights = w
        reps = r
        // The details too, so each one stays with its set.
        let log = workout.loggingDetails
        var d: [String: [SetDetail]] = [:]
        for (id, sets) in w {
            d[id] = sets.indices.map { log.detail(id, $0) }
        }
        details = d
    }

    /// "Set 2", or the set's type for a warm-up or drop set — tap to change it.
    private func kindMenu(_ id: String, _ index: Int) -> some View {
        let kind = details[id]?[safe: index]?.kind ?? .working
        return Menu {
            Picker(NSLocalizedString("Set type", comment: "Edit finished workout: working, warm-up or drop set"),
                   selection: kindBinding(id, index)) {
                Text(NSLocalizedString("Working set", comment: "Edit finished workout: a regular set")).tag(SetKind.working)
                Text(NSLocalizedString("Warm-up", comment: "Active workout: next set is a warm-up")).tag(SetKind.warmup)
                Text(NSLocalizedString("Drop set", comment: "Active workout: next set is a drop set")).tag(SetKind.drop)
            }
        } label: {
            Text(kind == .working
                 ? String(format: NSLocalizedString("Set %d", comment: "Edit finished workout: set number"), index + 1)
                 : kind == .warmup ? NSLocalizedString("Warm-up", comment: "Active workout: next set is a warm-up")
                 : NSLocalizedString("Drop set", comment: "Active workout: next set is a drop set"))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 64, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    private func kindBinding(_ id: String, _ index: Int) -> Binding<SetKind> {
        Binding(
            get: { details[id]?[safe: index]?.kind ?? .working },
            set: { newValue in
                guard var arr = details[id], arr.indices.contains(index) else { return }
                arr[index].kind = newValue
                details[id] = arr
            }
        )
    }

    /// A set that wasn't logged, starting from the last one's values.
    private func addSet(_ id: String) {
        weights[id, default: []].append(weights[id]?.last ?? 0)
        reps[id, default: []].append(reps[id]?.last ?? 0)
        // A timed set keeps its hold, which can't be typed here.
        details[id, default: []].append(SetDetail(seconds: details[id]?.last?.seconds))
    }

    private func weightBinding(_ id: String, _ index: Int) -> Binding<Double?> {
        Binding(
            get: {
                let value = weights[id]?[safe: index] ?? 0
                return value > 0 ? value : nil
            },
            set: { newValue in
                guard var arr = weights[id], arr.indices.contains(index) else { return }
                arr[index] = newValue ?? 0
                weights[id] = arr
            }
        )
    }

    private func repsBinding(_ id: String, _ index: Int) -> Binding<Int> {
        Binding(
            get: { reps[id]?[safe: index] ?? 0 },
            set: { newValue in
                guard var arr = reps[id], arr.indices.contains(index) else { return }
                arr[index] = max(0, newValue)
                reps[id] = arr
            }
        )
    }

    private func deleteSets(_ id: String, _ offsets: IndexSet) {
        if var w = weights[id] { w.remove(atOffsets: offsets); weights[id] = w }
        if var r = reps[id] { r.remove(atOffsets: offsets); reps[id] = r }
        if var d = details[id] { d.remove(atOffsets: offsets); details[id] = d }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { workout.name = trimmed }
        let typeChanged = activityType != workoutActivityType
        if typeChanged { workout.workoutType = Int(activityType.rawValue) }
        workout.setWeights = weights
        workout.setReps = reps
        var log = workout.loggingDetails
        log.setDetails = details
        workout.loggingDetails = log
        try? modelContext.save()
        // Another sport may now have met its weekly goal, or this one not.
        if typeChanged {
            Task { await GoalReminderScheduler.shared.refresh(context: modelContext) }
        }
        dismiss()
    }
}

/// Every sport, searchable, the common ones first — for a workout recorded
/// as the wrong one.
private struct ActivityTypePicker: View {
    @Binding var selection: HKWorkoutActivityType
    /// The workout's saved type, which decides the strength type offered.
    let current: HKWorkoutActivityType

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let sections = HKWorkoutActivityType.pickerSections(current: current)
        StyledList {
            if search.isEmpty {
                Section(NSLocalizedString("Popular", comment: "Goal picker: featured sports")) {
                    rows(sections.popular)
                }
                Section(NSLocalizedString("All sports", comment: "Goal picker: every sport")) {
                    rows(sections.others)
                }
            } else {
                rows((sections.popular + sections.others)
                    .filter { $0.name.localizedStandardContains(search) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(NSLocalizedString("Search sports", comment: "Goal picker: search prompt")))
        .navigationTitle(NSLocalizedString("Workout type", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(_ types: [HKWorkoutActivityType]) -> some View {
        ForEach(types, id: \.self) { type in
            Button {
                selection = type
                dismiss()
            } label: {
                HStack {
                    Label(type.name, systemImage: type.symbolName)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if type == selection {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .accessibilityAddTraits(type == selection ? .isSelected : [])
        }
    }
}
