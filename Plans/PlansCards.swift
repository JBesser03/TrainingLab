//
//  PlansCards.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 22.02.24.
//

import SwiftUI

/// The card of a horizontal plan row, like `WorkoutCard` for workouts.
struct PlanCard: View {

    @Bindable var plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IconBadge(systemName: plan.isUserGenerated ? "star.fill" : plan.symbolName, size: 34, tone: plan.tone)
                Spacer()
                Button {
                    plan.toggleBookmark()
                    Haptics.bookmark(saved: plan.isSaved)
                } label: {
                    Image(systemName: plan.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.subheadline)
                        .foregroundStyle(plan.isSaved ? Theme.accent : Color.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(plan.isSaved
                                         ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                         : NSLocalizedString("Bookmark", comment: "Workout card: save")))
            }

            Spacer(minLength: 8)

            Text(plan.displayName)
                .displayFont(.headline)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(plan.displayDifficulty) · \(PlanListRow.workoutCount(plan))")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .padding(16)
        // As tall as the row's tallest card (see `PlanHorizontalScrollView`).
        .frame(width: 200, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
        // The bookmark is inside the card's link; VoiceOver offers it as an action.
        .accessibilityAction(named: Text(plan.isSaved
                                         ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                         : NSLocalizedString("Bookmark", comment: "Workout card: save"))) {
            plan.toggleBookmark()
            Haptics.bookmark(saved: plan.isSaved)
        }
    }
}

#Preview {
    PlanCard(plan: Plan.samples[3])
}
