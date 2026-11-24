//
//  WorkoutsView.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 02.04.23.
//

import SwiftUI
import SwiftData
import HealthKit

struct WorkoutsView: View {

    @Query(filter: #Predicate<Workout> { !$0.isHidden }) var workouts: [Workout]
    
    @Environment(\.modelContext) var modelContext
    
    @State private var searchText = ""
    @State private var showAddItemWorkoutView = false
    @State private var showGymGenerator = false
    @State private var showNLBuilder = false
    
    var userGeneratedWorkouts: [Workout] {
        workouts.filter { workout in
            workout.isUserGenerated == true && (workout.plan?.isEmpty ?? true)
        }
        .sorted(by: Workout.newestFirst)
    }
    
    var defaultWorkouts: [Workout] {
        workouts.filter { workout in
            workout.isUserGenerated == false
        }
    }
    
    var workoutsForSearchBar: [Workout] {
        return workouts
    }
    
    /// Catalog (non-user-generated) workouts only — every category shelf below
    /// is meant to be "browse the catalog", not the user's own custom or
    /// plan-generated content (that already has its own "Own Workouts" shelf
    /// and, for multi-session plans like Running/Gym generators, the Plans
    /// tab). Without this, e.g. a generated running plan's sessions — which
    /// default to `isNew: true`, `muscleGroup: .cardio`, and running activity
    /// type, but aren't attached to "Own Workouts" since they belong to a plan
    /// — leaked into New/Try also/HIIT & Cardio/Running with nowhere else to go.
    private var catalogWorkouts: [Workout] {
        workouts.filter { !$0.isUserGenerated }
    }

    var legWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.muscleGroup == WorkoutCategory.legs.rawValue
        }
    }

    var hiitAndCardioWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.muscleGroup == WorkoutCategory.cardio.rawValue
        }
    }

    var upperbodyWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.muscleGroup == WorkoutCategory.upperbody.rawValue
        }
    }

    var newWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.isNew
        }
    }

    var savedWorkouts: [Workout] {
        workouts.filter { workout in
            workout.isSaved
        }
    }

    var recoveryWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.muscleGroup == WorkoutCategory.yoga.rawValue || workout.muscleGroup == WorkoutCategory.mobilityFlexibility.rawValue
        }
    }

    /// Running sessions (generated runs and any custom workout with the
    /// running activity type) — matched by HK activity, not muscle group.
    var runningWorkouts: [Workout] {
        catalogWorkouts.filter { workout in
            workout.workoutActivityType == Int(HKWorkoutActivityType.running.rawValue)
        }
    }
    
    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                exerciseLibraryRow

                if !workouts.isEmpty {
                    if !upperbodyWorkouts.isEmpty {
                        TopTabView(workouts: upperbodyWorkouts)
                    }
                    
                    if !userGeneratedWorkouts.isEmpty {
                        HorizontalScrollView(workouts: userGeneratedWorkouts, content: .customWorkouts)
                    }
                    
                    if !newWorkouts.isEmpty {
                        HorizontalScrollView(workouts: newWorkouts, content: .new)
                    }
                    
                    if !hiitAndCardioWorkouts.isEmpty {
                        HorizontalScrollView(workouts: hiitAndCardioWorkouts, content: .hiitAndCardio)
                    }

                    if !runningWorkouts.isEmpty {
                        HorizontalScrollView(workouts: runningWorkouts, content: .running)
                    }
                    
                    if !savedWorkouts.isEmpty {
                        HorizontalScrollView(workouts: savedWorkouts, content: .saved)
                    }
                    
                    if !legWorkouts.isEmpty {
                        HorizontalScrollView(workouts: legWorkouts, content: .legTraining)
                    }
                    
                    MuscleGroupsView()

                    if !recoveryWorkouts.isEmpty {
                        HorizontalScrollView(workouts: recoveryWorkouts, content: .recovery)
                    }
                    
                } else {
                    EmptyStateView(title: NSLocalizedString("No workouts yet", comment: "Workouts empty state title"),
                                   systemImage: "figure.strengthtraining.traditional",
                                   message: NSLocalizedString("Build or generate your first workout with the + button.", comment: "Workouts empty state description"))
                        .padding(.top, 20)
                }
            }
            .searchable(text: $searchText, prompt: "Search for Workouts")
            .toolbar(content: {
                // Every bookmarked workout; leading, like History's Progress.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SavedWorkoutsView()
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel(Text(NSLocalizedString("Saved Workouts", comment: "HorizontalView Title")))
                    .accessibilityIdentifier("browse.saved")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showAddItemWorkoutView = true
                        } label: {
                            Label(NSLocalizedString("Build a workout", comment: "Browse + menu: pick exercises yourself"),
                                  systemImage: "square.and.pencil")
                        }
                        Button {
                            showGymGenerator = true
                        } label: {
                            Label(NSLocalizedString("Generate a gym workout", comment: "Browse + menu"),
                                  systemImage: "wand.and.stars")
                        }
                        Button {
                            showNLBuilder = true
                        } label: {
                            Label(NSLocalizedString("Describe a workout (Beta)", comment: "Browse + menu: type what you want"),
                                  systemImage: "text.bubble")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text(NSLocalizedString("Add workout", comment: "Accessibility: add a workout")))
                    }
                    .accessibilityIdentifier("browse.add")
                }
            })
            
            if !searchText.isEmpty {
                withAnimation {
                    ZStack {
                        Rectangle()
                            .fill(.clear)
                        
                        StyledList {
                            ForEach(searchResuslts, id: \.self) { workout in
                                NavigationLink {
                                    WorkoutPreviewiOS(workout: workout)
                                } label: {
                                    WorkoutSearchListView(workout: workout)
                                }
                                .accessibilityIdentifier("browse.searchResult")
                            }
                        }
                        .animation(.easeIn(duration: 0.3), value: searchResuslts)
                    }
                }
            }
        }
        .pageTint()
        .navigationTitle("Browse")
        .sheet(isPresented: $showAddItemWorkoutView, content: {
            AddWorkoutsView(showAddWorkoutView: $showAddItemWorkoutView)
        })
        .sheet(isPresented: $showGymGenerator) {
            GymPlanGeneratorView(initialMode: .singleWorkout)
        }
        .sheet(isPresented: $showNLBuilder) {
            NaturalLanguageWorkoutView()
        }
    }

    /// The exercise library, named — it used to be an unlabelled dumbbell
    /// in the toolbar.
    private var exerciseLibraryRow: some View {
        NavigationLink {
            ListExerciseView()
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: "dumbbell.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Exercise library", comment: "Browse: row opening all exercises"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("Search, edit or add your own", comment: "Browse: exercise library row subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browse.exerciseLibrary")
        .padding(.horizontal)
        .padding(.top, 8)
    }

    var searchResuslts: [Workout] {
        withAnimation {
            if searchText.isEmpty {
                return workoutsForSearchBar
            } else {
                return workoutsForSearchBar.filter { workout in
                    workout.displayName.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
}

struct WorkoutSearchListView: View {
    
    var workout: Workout
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.displayName)
                .font(.body.weight(.semibold))
            // Results mix categories, so this one names it too.
            Text(workout.levelAndDuration + " · " + WorkoutCategory.getCategoryName(from: workout.muscleGroup))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    WorkoutSearchListView(workout: Workout.samples[0])
}
