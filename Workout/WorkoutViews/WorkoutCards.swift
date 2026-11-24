//
//  WorkoutCards.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 06.04.23.
//
import Foundation
import SwiftUI

// MARK: - Card detail

extension Workout {
    /// "Advanced · 45 min" — the line under a workout's name on every card
    /// and row, built from its data so each workout has one (the stored
    /// `shortInfo` is free text, and empty for the user's own).
    var levelAndDuration: String {
        displayDifficulty + " · "
            + String(format: NSLocalizedString("%d min", comment: "Workout card: duration in minutes"), duration)
    }
}

// MARK: - Featured workout card

/// The large card of the carousel at the top of Browse.
struct FeaturedWorkoutCard: View {

    @Bindable var workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(WorkoutCategory.getCategoryName(from: workout.muscleGroup),
                  systemImage: WorkoutCategory.getSymbolName(from: workout.muscleGroup))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.secondary)

            Spacer(minLength: 12)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.displayName)
                        .displayFont(.title2)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(workout.levelAndDuration)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48)
                    .controlBackground(.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(20)
        // Fills the carousel, whose height fits two lines of title.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
        .padding(.horizontal)
    }
}

// MARK: - Workout card

/// The card of every horizontal workout row: what it trains, its name, its
/// level and length, with a bookmark to save it.
struct WorkoutCard: View {

    @Bindable var workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IconBadge(systemName: WorkoutCategory.getSymbolName(from: workout.muscleGroup), size: 34,
                          tone: WorkoutCategory.tone(from: workout.muscleGroup))
                Spacer()
                Image(systemName: workout.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.subheadline)
                    .foregroundStyle(workout.isSaved ? Theme.accent : Color.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            workout.toggleBookmark()
                            Haptics.bookmark(saved: workout.isSaved)
                        }
                    }
                    .accessibilityLabel(Text(workout.isSaved
                                             ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                             : NSLocalizedString("Bookmark", comment: "Workout card: save")))
                    .accessibilityAddTraits(.isButton)
            }

            Spacer(minLength: 8)

            Text(workout.displayName)
                .displayFont(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(workout.levelAndDuration)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .padding(16)
        // As tall as the row's tallest card (see `HorizontalScrollView`).
        .frame(width: 200, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
        // The bookmark is inside the card's link; VoiceOver offers it as an action.
        .accessibilityAction(named: Text(workout.isSaved
                                         ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                         : NSLocalizedString("Bookmark", comment: "Workout card: save"))) {
            workout.toggleBookmark()
            Haptics.bookmark(saved: workout.isSaved)
        }
    }
}

#Preview {
    WorkoutCard(workout: .init(id: "id", infoText: "infoText", isUserGenerated: false, muscleGroup: 1, setLength: 2, straightSets: false, difficultyInt: 2, name: "Upper Body — Beginner", duration: 40, exercisesSequenceID: [], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5))
}
