//
//  HorizontalScrollView.swift
//  Workout App
//
//  Created by Justus Besser on 17.11.23.
//

import SwiftUI

struct HorizontalScrollView: View {
    
    enum Content {
        case hiitAndCardio, customWorkouts, legTraining, featured, new, saved, recovery, running, forYou
    }
    
    var workouts: [Workout]
    var content: Content
    @Namespace private var zoom
    
    /// `title` is already localized. Each key is spelled out: passing a
    /// variable to `NSLocalizedString` keeps it out of the string catalog,
    /// and "Own Workouts" stayed English in German that way.
    var contentDetails: (title: String, badgeInput: String, isText: Bool) {
            switch content {
            case .featured:
                return (NSLocalizedString("Featured", comment: "HorizontalView Title"), "Featured", true)
            case .hiitAndCardio:
                return (NSLocalizedString("HIIT & Cardio", comment: "HorizontalView Title"), "bolt.fill", false)
            case .customWorkouts:
                return (NSLocalizedString("Own Workouts", comment: "HorizontalView Title"), "person.crop.circle.badge.plus", false)
            case .legTraining:
                return (NSLocalizedString("Leg day!", comment: "HorizontalView Title"), "figure.strengthtraining.functional", false)
            case .new:
                return (NSLocalizedString("New", comment: "HorizontalView Title"), "New", true)
            case .saved:
                return (NSLocalizedString("Saved Workouts", comment: "HorizontalView Title"), "Saved", true)
            case .recovery:
                return (NSLocalizedString("Recovery", comment: "HorizontalView Title"), "figure.mind.and.body", false)
            case .running:
                return (NSLocalizedString("Running", comment: "HorizontalView Title"), "figure.run", false)
            case .forYou:
                return (NSLocalizedString("Picked for you", comment: "HorizontalView Title"), "sparkles", false)
            }
        }
    
    var body: some View {
        
        VStack(spacing: 0) {
            Text(contentDetails.title)
                .sectionTitleStyle()
                .padding(.horizontal)
                .padding(.top, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(workouts, id: \.self) { workout in
                        NavigationLink {
                            WorkoutPreviewiOS(workout: workout)
                                .navigationTransition(.zoom(sourceID: workout.id, in: zoom))
                        } label: {
                            WorkoutCard(workout: workout)
                                .zoomSource(id: workout.id, in: zoom)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                // The row is as tall as its tallest card, and every card
                // stretches to it — no fixed height to leave empty when the
                // style's font is smaller.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            // The cards' shadows in a frosted style reach past the row.
            .scrollClipDisabled()
        }
    }
}

#Preview {
    HorizontalScrollView(workouts: [.init(id: "id", infoText: "infoText", isUserGenerated: false, muscleGroup: 2, setLength: 2, straightSets: false, difficultyInt: 2, name: "name", duration: 5, exercisesSequenceID: [], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5)], content: .hiitAndCardio)
}
