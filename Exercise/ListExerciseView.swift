//
//  ListUebungView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 24.09.21.
//

import SwiftUI
import SwiftData

struct ListExerciseView: View {

    @State private var showAddItemView = false

    var body: some View {
        ExercisesList(showAddItemView: $showAddItemView)
    }
}

struct ExercisesList: View {

    @Query var exercises: [Exercise]

    @Environment(\.modelContext) var modelContext

    @Binding var showAddItemView: Bool

    @State private var searchText = ""
    @State private var sortType: SortType = .nameAscending
    @State private var selectedCategory: WorkoutCategory? = nil
    @State private var exerciseToDelete: Exercise?

    var exercisesForSearchBar: [Exercise] {
        exercises.filter { exercise in
            exercise.isActive == false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ExerciseCategoryButtonRow(selected: $selectedCategory)

                if !sortedExercises.isEmpty {
                    HStack {
                        Text("\(sortedExercises.count) exercises")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }

                List {
                    if !sortedExercises.isEmpty {
                        ForEach(sortedExercises, id: \.self) { exercise in
                            NavigationLink {
                                ChangeExerciseView(exercise: exercise)
                            } label: {
                                ExerciseListRow(exercise: exercise)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete { (indexSet) in
                            // Confirm first: deleting removes the exercise from
                            // every workout that uses it and from past workouts.
                            if let index = indexSet.first {
                                exerciseToDelete = sortedExercises[index]
                            }
                        }
                    } else {
                        EmptyExercisesView()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search for exercises")
            }
        }
        .pageTint()
        .navigationTitle("Exercises")
        .alert(
            NSLocalizedString("Delete exercise?", comment: "Exercise list: delete confirmation title"),
            isPresented: Binding(
                get: { exerciseToDelete != nil },
                set: { if !$0 { exerciseToDelete = nil } }
            ),
            presenting: exerciseToDelete
        ) { exercise in
            Button(NSLocalizedString("Delete", comment: "Exercise list: confirm delete"), role: .destructive) {
                ExerciseItemManager.shared.configure(with: modelContext)
                ExerciseItemManager.shared.delete(exercise: exercise)
                exerciseToDelete = nil
            }
            Button(NSLocalizedString("Cancel", comment: "Exercise list: cancel delete"), role: .cancel) {
                exerciseToDelete = nil
            }
        } message: { exercise in
            Text(deleteMessage(for: exercise))
        }
        .sheet(isPresented: $showAddItemView, content: {
            AddExerciseView(showAddExerciseView: $showAddItemView)
        })
    #if os(iOS) || os(watchOS) || os(tvOS)
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
                    .disabled(exercises.isEmpty)
            }
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $sortType) {
                        Text("Name (ascending)").tag(SortType.nameAscending)
                        Text("Name (descending)").tag(SortType.nameDescending)
                    }
                } label: {
                    Image(systemName: "arrow.up.and.down.text.horizontal")
                        .accessibilityLabel(Text(NSLocalizedString("Sort by", comment: "")))
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddItemView = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text(NSLocalizedString("Add exercise", comment: "")))
                }
            }
        })
#else

#endif
    }
    var searchResults: [Exercise] {
        let base: [Exercise]
        if searchText.isEmpty {
            base = exercisesForSearchBar
        } else {
            base = exercisesForSearchBar.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let category = selectedCategory {
            return base.filter { $0.muscleGroup == category.rawValue }
        }
        return base
    }

    var sortedExercises: [Exercise] {
        switch sortType {
        case .nameAscending:
            return searchResults.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .nameDescending:
            return searchResults.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .dateNewest:
            return []
        case .dateOldest:
            return []
        case .activityType:
            return []
        }
    }

    private func deleteMessage(for exercise: Exercise) -> String {
        let workoutCount = (exercise.workouts ?? []).filter { !$0.isHidden }.count
        let inHistory = !(exercise.finishedWorkouts?.isEmpty ?? true)
        var parts: [String] = []
        if workoutCount > 0 {
            parts.append(String(format: NSLocalizedString("Workouts using it: %d. It will be removed from them.", comment: "Exercise delete confirmation: number of workouts that use it"), workoutCount))
        }
        if inHistory {
            parts.append(NSLocalizedString("It will also disappear from past workouts in your history.", comment: "Exercise delete confirmation: history warning"))
        }
        if parts.isEmpty {
            parts.append(NSLocalizedString("This can't be undone.", comment: "Exercise delete confirmation: generic warning"))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Category Filter Row

struct ExerciseCategoryButtonRow: View {

    @Binding var selected: WorkoutCategory?

    /// Categories shown in the filter row. `undefined` is hidden.
    private var categories: [WorkoutCategory] {
        WorkoutCategory.allCases.filter { $0 != .undefined }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(NSLocalizedString("All", comment: "Exercise filter, all categories"),
                     symbol: "square.grid.2x2.fill", isSelected: selected == nil) {
                    selected = nil
                }
                ForEach(categories, id: \.self) { category in
                    chip(category.displayName, symbol: category.symbolName, isSelected: selected == category) {
                        selected = (selected == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func chip(_ title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy, action)
        } label: {
            Chip(title: title, systemImage: symbol, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Exercise List Row

struct ExerciseListRow: View {
    let exercise: Exercise

    private var symbol: ExerciseSymbol? { ExerciseSymbol(name: exercise.symbol) }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let asset = symbol?.assetName {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: symbol?.systemName ?? WorkoutCategory.getSymbolName(from: exercise.muscleGroup))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 44, height: 44)
            .background(Theme.accentTint, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text("\(WorkoutCategory.getCategoryName(from: exercise.muscleGroup)) · \(exercise.displayDifficulty)")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .card(padding: 10)
    }
}

// MARK: - Empty State

struct EmptyExercisesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No exercises yet")
                .font(.headline)
            Text("Tap the + button to add your first exercise.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
