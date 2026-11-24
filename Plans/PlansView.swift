//
//  WorkoutPlansView.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 15.09.23.
//

import SwiftUI
import SwiftData

/// The catalog's plans grouped by what they train, so each one shows up
/// once — they used to repeat across five overlapping rows.
enum PlanGroup: CaseIterable, Identifiable {
    case strength, cardio, bodyweight, flexibility, wellness

    var id: Self { self }

    var title: String {
        switch self {
        case .strength:    NSLocalizedString("Strength & muscle", comment: "HorizontalViewPlan Title")
        case .cardio:      NSLocalizedString("Cardio & endurance", comment: "Plans: group title")
        case .bodyweight:  NSLocalizedString("Bodyweight & core", comment: "Plans: group title")
        case .flexibility: NSLocalizedString("Flexibility & mobility", comment: "HorizontalViewPlan Title")
        case .wellness:    NSLocalizedString("Health & wellness", comment: "Plans: group title")
        }
    }

    static func of(_ plan: Plan) -> PlanGroup {
        switch PlanGoal(rawValue: plan.goal) {
        case .muscleBuilding, .strengthTraining:
            return .strength
        case .enduranceAndStamina, .weightLoss:
            return .cardio
        case .functionalFitness, .sportSpecificTraining:
            return .bodyweight
        case .flexibilityAndMobility, .mindBodyConnection, .rehabilitationAndInjuryPrevention:
            return .flexibility
        case .overallHealthAndWellness:
            return .wellness
        case .other, nil:
            switch WorkoutCategory(rawValue: plan.muscleGroup) {
            case .cardio, .hiit:              return .cardio
            case .yoga, .mobilityFlexibility: return .flexibility
            case .undefined, nil:             return .wellness
            default:                          return .strength
            }
        }
    }
}

struct WorkoutPlansView: View {

    @Query(filter: #Predicate<Plan> { !$0.isHidden }) var plans: [Plan]
    
    @State private var showAddPlan = false
    @State private var selectedSport: SportCategory = .all
    /// `difficultyInt` to show, or nil for every level.
    @State private var level: Int?
    @State private var showRunningGenerator = false
    @State private var showGymGenerator = false
    
    private func isCompleted(_ plan: Plan) -> Bool {
        !plan.workoutsSequenceIDs.isEmpty
            && plan.finishedWorkoutsSequence.count >= plan.workoutsSequenceIDs.count
    }

    private func isInProgress(_ plan: Plan) -> Bool {
        !plan.finishedWorkoutsSequence.isEmpty && !isCompleted(plan)
    }

    /// Plans you made, bookmarked or started; the ones under way first.
    var yourPlans: [Plan] {
        let own = plans.filter { $0.isUserGenerated || $0.isSaved || !$0.finishedWorkoutsSequence.isEmpty }
        return own.sorted { lhs, rhs in
            if isInProgress(lhs) != isInProgress(rhs) { return isInProgress(lhs) }
            if lhs.isUserGenerated != rhs.isUserGenerated { return lhs.isUserGenerated }
            return Plan.newestFirst(lhs, rhs)
        }
    }

    private var catalogPlans: [Plan] {
        plans
            .filter { !$0.isUserGenerated && (level == nil || $0.difficultyInt == level) }
            .sorted { ($0.difficultyInt, $0.displayName) < ($1.difficultyInt, $1.displayName) }
    }

    /// "All", then only the sports that have a plan — the others led to an
    /// empty page.
    private var sports: [SportCategory] {
        SportCategory.allCases.filter { sport in
            sport == .all || plans.contains { sport.matches(plan: $0) }
        }
    }

    var filteredPlans: [Plan] {
        plans.filter { selectedSport.matches(plan: $0) }
    }
    
    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                if sports.count > 1 {
                    SportCategoryButtonRow(selected: $selectedSport, categories: sports)
                }

                if plans.isEmpty {
                    EmptyStateView(title: NSLocalizedString("No plans yet", comment: "Plans empty state title"),
                                   systemImage: "calendar",
                                   message: NSLocalizedString("Create a plan or generate one with the + button.", comment: "Plans empty state description"))
                        .padding(.top, 20)
                } else if selectedSport == .all {
                    if !yourPlans.isEmpty {
                        PlanHorizontalScrollView(title: NSLocalizedString("Your plans", comment: "Plans: plans you made, saved or started"),
                                                 plans: yourPlans)
                    }

                    Picker(NSLocalizedString("Level", comment: "Plans: difficulty filter"), selection: $level) {
                        Text(NSLocalizedString("All levels", comment: "Plans: no difficulty filter")).tag(Int?.none)
                        ForEach(DifficultyLevel.allCases) { level in
                            Text(level.name).tag(Int?.some(level.rawValue))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .accessibilityIdentifier("plans.level")

                    ForEach(PlanGroup.allCases) { group in
                        let groupPlans = catalogPlans.filter { PlanGroup.of($0) == group }
                        if !groupPlans.isEmpty {
                            PlanListSection(title: group.title, plans: groupPlans)
                        }
                    }

                    if catalogPlans.isEmpty {
                        Text(NSLocalizedString("No plans at this level yet.", comment: "Plans: level filter matches nothing"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 30)
                    }
                } else if filteredPlans.isEmpty {
                    EmptySportPlansView(sport: selectedSport)
                        .padding(.top, 30)
                } else {
                    PlanListSection(title: selectedSport.displayName, plans: filteredPlans)
                }
            }
            .onChange(of: sports) {
                // The last plan of a sport was deleted: back to All.
                if !sports.contains(selectedSport) { selectedSport = .all }
            }
        }
        .pageTint(onPlanPage: true)
        .navigationTitle("Plans")
        .toolbar(content: {
            // Every bookmarked plan, like Browse's saved workouts.
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    SavedPlansView()
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel(Text(NSLocalizedString("Saved plans", comment: "Saved plans: title")))
                .accessibilityIdentifier("plans.saved")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddPlan = true
                    } label: {
                        Label(NSLocalizedString("Build a plan", comment: "Plans + menu: from your own workouts"),
                              systemImage: "square.and.pencil")
                    }
                    Button {
                        showGymGenerator = true
                    } label: {
                        Label(NSLocalizedString("Generate a gym plan", comment: "Plans + menu"),
                              systemImage: "dumbbell.fill")
                    }
                    Button {
                        showRunningGenerator = true
                    } label: {
                        Label(NSLocalizedString("Running plan for a race", comment: "Plans + menu"),
                              systemImage: "figure.run")
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text(NSLocalizedString("Add plan", comment: "Accessibility: add a plan")))
                }
                .accessibilityIdentifier("plans.add")
            }
        })
        .sheet(isPresented: $showAddPlan, content: {
            AddPlans()
        })
        .sheet(isPresented: $showRunningGenerator) {
            RunningPlanGeneratorView()
        }
        .sheet(isPresented: $showGymGenerator) {
            GymPlanGeneratorView()
        }
    }
}

extension Plan {
    /// What kind of plan it is — a split, a focus, a sport — as a symbol, so a
    /// list of plans isn't one figure repeated. From the built-in plans' names
    /// (English keys); other plans get their group's.
    var symbolName: String {
        let key = name.lowercased()
        if key.contains("push pull legs") { return "arrow.triangle.2.circlepath" }
        if key.contains("upper / lower") { return "arrow.up.arrow.down" }
        if key.contains("full body") { return "figure.strengthtraining.functional" }
        if key.contains("no-equipment") { return "house.fill" }
        if key.contains("core") { return "figure.core.training" }
        if key.contains("recovery") { return "figure.flexibility" }
        if key.contains("run") || key.contains("marathon") || key.contains("5k") || key.contains("10k") { return "figure.run" }
        switch PlanGroup.of(self) {
        case .strength:    return "dumbbell.fill"
        case .cardio:      return "figure.mixed.cardio"
        case .bodyweight:  return "figure.cross.training"
        case .flexibility: return "figure.flexibility"
        case .wellness:    return "leaf.fill"
        }
    }

    /// The plan's level as a shade of the accent (`Theme.tone`): lighter for
    /// beginners, deeper for advanced.
    var tone: Int {
        switch difficultyInt {
        case ...1: 1
        case 2:    0
        default:   3
        }
    }
}

/// A titled list of plans, one row each.
struct PlanListSection: View {

    let title: String
    let plans: [Plan]
    @Namespace private var zoom

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .sectionTitleStyle()
                .padding(.horizontal)
                .padding(.top, 24)

            LazyVStack(spacing: 10) {
                ForEach(plans, id: \.self) { plan in
                    NavigationLink {
                        PlanPreview(plan: plan)
                            .navigationTransition(.zoom(sourceID: plan.id, in: zoom))
                    } label: {
                        PlanListRow(plan: plan)
                            .zoomSource(id: plan.id, in: zoom)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

struct PlanListRow: View {

    @Bindable var plan: Plan

    private var progress: Double {
        guard !plan.workoutsSequenceIDs.isEmpty else { return 0 }
        return Double(plan.finishedWorkoutsSequence.count) / Double(plan.workoutsSequenceIDs.count)
    }

    /// "3 workouts" — a bare "3" on the cards didn't say what it counted.
    static func workoutCount(_ plan: Plan) -> String {
        String(format: NSLocalizedString("%d workouts", comment: "Plan: number of workouts in it"),
               plan.workoutsSequenceIDs.count)
    }

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: plan.symbolName, size: 48, tone: plan.tone)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(plan.displayDifficulty) · \(PlanListRow.workoutCount(plan))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if !plan.finishedWorkoutsSequence.isEmpty {
                    ProgressView(value: progress)
                        .tint(Theme.accent)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .card(padding: 12)
    }
}

struct EmptySportPlansView: View {
    let sport: SportCategory

    var body: some View {
        EmptyStateView(title: String(format: NSLocalizedString("No %@ plans yet", comment: "Plans: empty sport filter, e.g. 'No Running plans yet'"), sport.displayName),
                       systemImage: sport.symbolName,
                       message: NSLocalizedString("Create one with the + button.", comment: "Plans: empty sport filter"))
    }
}

#Preview {
    let preview = PreviewPlan()
    preview.addExamples(Plan.samples)
    
    return WorkoutPlansView()
        .modelContainer(preview.container)
}
