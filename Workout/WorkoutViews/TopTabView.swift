//
//  TopTabView.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 02.04.23.
//

import SwiftUI
import SwiftData

struct TopTabView: View {
    
    var workouts: [Workout]
    
    @State private var tabViewSelection = 0
    @Namespace private var zoom
    /// A paged TabView needs a fixed height: a two-line title and the line
    /// above it, growing with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var height: CGFloat = 156
    @Environment(\.appTheme) private var theme

    /// Below the card for its shadow in a frosted style, which the pages
    /// would cut off.
    private var shadowRoom: CGFloat { theme.geometry.frostedCards ? 14 : 0 }
    
    var body: some View {
        TabView(selection: $tabViewSelection) {
            ForEach(workouts.indices, id: \.self) { index in
                NavigationLink {
                    WorkoutPreviewiOS(workout: workouts[index])
                        .navigationTransition(.zoom(sourceID: workouts[index].id, in: zoom))
                } label: {
                    FeaturedWorkoutCard(workout: workouts[index])
                        .zoomSource(id: workouts[index].id, in: zoom)
                }
                .buttonStyle(.pressable)
                .padding(.bottom, shadowRoom)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: height + shadowRoom, alignment: .center)
        // Rebuilt for a new style: a card here once kept the old colors for a
        // few seconds. The selection lives outside, so the page stays.
        .id(theme)
    }
}

struct TopTabView_Previews: PreviewProvider {
    static var previews: some View {
        TopTabView(workouts: [.init(id: "id", infoText: "infoText", isUserGenerated: false, muscleGroup: 2, setLength: 2, straightSets: false, difficultyInt: 2, name: "name", duration: 5, exercisesSequenceID: [], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5)])
    }
}
