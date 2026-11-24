//
//  ExercisePickerView.swift
//  Workout App (iOS)
//
//  The exercise library as a searchable list with muscle-group filters — for
//  adding exercises to a workout (several at once) and for adding or swapping
//  one during a session. Replaces scrolling through every exercise inline in
//  the workout form.
//

import SwiftUI
import SwiftData

struct ExercisePickerView: View {

    enum Mode {
        /// Pick several, confirmed with Add.
        case multiple
        /// Pick one; tapping it closes the picker.
        case single
    }

    let mode: Mode
    let title: String
    /// Ids already in the workout: marked as added and not selectable again.
    var included: Set<String> = []
    /// Offered first, above the library — e.g. swap candidates.
    var suggestions: [Exercise] = []
    let onPick: ([Exercise]) -> Void

    @Query private var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscleGroup: Int?
    /// Multiple mode: the picks in tap order, which becomes the workout order.
    @State private var selection: [Exercise] = []

    private var library: [Exercise] {
        exercises
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { muscleGroup == nil || $0.muscleGroup == muscleGroup }
            .filter { search.isEmpty || $0.displayName.localizedStandardContains(search) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var showsSuggestions: Bool {
        !suggestions.isEmpty && search.isEmpty && muscleGroup == nil
    }

    var body: some View {
        NavigationStack {
            StyledList {
                if showsSuggestions {
                    Section(NSLocalizedString("Suggested", comment: "Exercise picker: suggested exercises")) {
                        rows(suggestions)
                    }
                }
                Section {
                    rows(library)
                } header: {
                    filterChips
                        .textCase(nil)
                }
            }
            // At the top, leaving the bottom edge to the Add button.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(NSLocalizedString("Search exercises", comment: "Exercise picker: search prompt")))
            // Pinned to the bottom rather than in the toolbar: while searching,
            // iOS hides the navigation bar and a toolbar button with it.
            .safeAreaInset(edge: .bottom) {
                if mode == .multiple && !selection.isEmpty {
                    Button {
                        onPick(selection)
                        dismiss()
                    } label: {
                        Text(String(format: NSLocalizedString("Add (%d)", comment: "Exercise picker: add the selected exercises, with their count"), selection.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(NSLocalizedString("All", comment: "Exercise picker: no muscle-group filter"), value: nil)
                ForEach(WorkoutCategory.allCases.filter { $0 != .undefined }, id: \.self) { category in
                    chip(category.displayName, value: category.rawValue)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, value: Int?) -> some View {
        let isOn = muscleGroup == value
        return Button {
            muscleGroup = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .controlBackground(isOn ? .accent : .surface)
                .foregroundStyle(isOn ? Theme.onAccent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func rows(_ list: [Exercise]) -> some View {
        ForEach(list, id: \.persistentModelID) { exercise in
            let isIncluded = included.contains(exercise.id)
            let isSelected = selection.contains { $0.persistentModelID == exercise.persistentModelID }
            Button {
                pick(exercise)
            } label: {
                HStack(spacing: 12) {
                    ExerciseSymbolImage(name: exercise.symbol)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.primary)
                        Text("\(WorkoutCategory.getCategoryName(from: exercise.muscleGroup)) · \(exercise.displayDifficulty)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    if isIncluded {
                        Text(NSLocalizedString("Added", comment: "Exercise picker: already in the workout"))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else if mode == .multiple {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    }
                }
            }
            .disabled(isIncluded)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("exercisePicker.row.\(exercise.id)")
        }
    }

    private func pick(_ exercise: Exercise) {
        switch mode {
        case .single:
            onPick([exercise])
            dismiss()
        case .multiple:
            if let index = selection.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) {
                selection.remove(at: index)
            } else {
                selection.append(exercise)
            }
        }
    }
}
