//
//  SavedPlansView.swift
//  Workout App (iOS)
//
//  Every bookmarked plan in one list, opened from the Plans toolbar — the
//  plans counterpart of `SavedWorkoutsView`.
//

import SwiftUI
import SwiftData

extension Plan {
    /// See `Workout.toggleBookmark()`.
    func toggleBookmark() {
        isSaved.toggle()
        try? modelContext?.save()
    }
}

struct SavedPlansView: View {

    @Query(filter: #Predicate<Plan> { $0.isSaved && !$0.isHidden }) private var saved: [Plan]

    /// The saved plans as of opening the list; see `SavedWorkoutsView.listed`.
    @State private var listed: [Plan] = []

    var body: some View {
        ScrollView {
            if listed.isEmpty {
                EmptyStateView(title: NSLocalizedString("No saved plans", comment: "Saved plans: empty state title"),
                               systemImage: "bookmark",
                               message: NSLocalizedString("Tap the bookmark on a plan to find it here.",
                                                          comment: "Saved plans: empty state description"))
                    .padding(.top, 40)
            } else {
                HStack {
                    Text("\(listed.count) plans")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

                LazyVStack(spacing: 10) {
                    ForEach(listed) { plan in
                        NavigationLink {
                            PlanPreview(plan: plan)
                        } label: {
                            SavedPlanRow(plan: plan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("savedPlans.row")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .pageTint(onPlanPage: true)
        .navigationTitle(NSLocalizedString("Saved plans", comment: "Saved plans: title"))
        // Also on coming back from a plan, whose bookmark may have changed.
        .onAppear {
            listed = saved.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }
}

/// A saved plan as `PlanListRow` shows it, with its bookmark in place of the
/// chevron — tap it to remove the plan from the list (or to undo that).
private struct SavedPlanRow: View {

    @Bindable var plan: Plan

    private var progress: Double {
        guard !plan.workoutsSequenceIDs.isEmpty else { return 0 }
        return Double(plan.finishedWorkoutsSequence.count) / Double(plan.workoutsSequenceIDs.count)
    }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: plan.symbolName, size: 48, tone: plan.tone)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(plan.displayDifficulty) · \(PlanListRow.workoutCount(plan))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                if !plan.finishedWorkoutsSequence.isEmpty {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: plan.isSaved ? "bookmark.fill" : "bookmark")
                .font(.body)
                .foregroundStyle(plan.isSaved ? Theme.accent : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { plan.toggleBookmark() }
                    Haptics.bookmark(saved: plan.isSaved)
                }
        }
        .card(padding: 12)
        // The bookmark is inside the row's link; VoiceOver offers it as an action.
        .accessibilityAction(named: Text(plan.isSaved
                                         ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                         : NSLocalizedString("Bookmark", comment: "Workout card: save"))) {
            plan.toggleBookmark()
            Haptics.bookmark(saved: plan.isSaved)
        }
    }
}
