//
//  SavedWorkoutsView.swift
//  Workout App (iOS)
//
//  Every bookmarked workout in one list, opened from the Browse toolbar. The
//  "Saved Workouts" shelf in Browse shows them too, but only a few at a time.
//

import SwiftUI
import SwiftData

extension Workout {
    /// Bookmarks the workout or removes its bookmark, saved at once — left
    /// to autosave, a tap just before the app is closed can be lost.
    func toggleBookmark() {
        isSaved.toggle()
        try? modelContext?.save()
    }
}

struct SavedWorkoutsView: View {

    @Query(filter: #Predicate<Workout> { $0.isSaved && !$0.isHidden }) private var saved: [Workout]

    /// What the list shows: the saved workouts as of opening it. Removing a
    /// bookmark here keeps the row (with an empty bookmark to undo it) until
    /// the screen is left, so a mistap doesn't make it vanish.
    @State private var listed: [Workout] = []

    var body: some View {
        ScrollView {
            if listed.isEmpty {
                EmptyStateView(title: NSLocalizedString("No saved workouts", comment: "Saved workouts: empty state title"),
                               systemImage: "bookmark",
                               message: NSLocalizedString("Tap the bookmark on a workout to find it here.",
                                                          comment: "Saved workouts: empty state description"))
                    .padding(.top, 40)
            } else {
                HStack {
                    Text("\(listed.count) workouts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

                LazyVStack(spacing: 10) {
                    ForEach(listed) { workout in
                        NavigationLink {
                            WorkoutPreviewiOS(workout: workout)
                        } label: {
                            SavedWorkoutRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("savedWorkouts.row")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .pageTint()
        .navigationTitle(NSLocalizedString("Saved Workouts", comment: "HorizontalView Title"))
        // Also on coming back from a workout, whose bookmark may have changed.
        .onAppear {
            listed = saved.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }
}

/// A saved workout: what it trains, its name, level and length, and its
/// bookmark — tap it to remove the workout from the list (or to undo that).
private struct SavedWorkoutRow: View {

    @Bindable var workout: Workout

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: WorkoutCategory.getSymbolName(from: workout.muscleGroup), tone: WorkoutCategory.tone(from: workout.muscleGroup))

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(workout.levelAndDuration)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: workout.isSaved ? "bookmark.fill" : "bookmark")
                .font(.body)
                .foregroundStyle(workout.isSaved ? Theme.accent : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { workout.toggleBookmark() }
                    Haptics.bookmark(saved: workout.isSaved)
                }
        }
        .card(padding: 12)
        // The bookmark is inside the row's link; VoiceOver offers it as an action.
        .accessibilityAction(named: Text(workout.isSaved
                                         ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                         : NSLocalizedString("Bookmark", comment: "Workout card: save"))) {
            workout.toggleBookmark()
            Haptics.bookmark(saved: workout.isSaved)
        }
    }
}
