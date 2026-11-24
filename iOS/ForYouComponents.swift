//
//  ForYouComponents.swift
//  Workout App (iOS)
//
//  Reusable cards for the "For You" landing tab. Extracted from
//  WorkoutIntelligenceView so the same recovery/generated-workout presentation
//  isn't duplicated between screens.
//

import SwiftUI
import HealthKit

// MARK: - Recovery card

struct RecoveryScoreCard: View {

    let recovery: RecoveryEstimate
    /// Offered while the score rests on training history alone.
    var onConnectHealth: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 30
    /// Counts up from 0 when the card appears.
    @State private var shownScore = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.l) {
            HStack(spacing: 18) {
                ring
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(recovery.band.title)
                        .displayFont(.headline)
                    if recovery.isLowConfidence {
                        Text(NSLocalizedString("Limited data", comment: "Recovery card: score is a rough estimate"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, 2)
                            .controlBackground(.inset)
                            .foregroundStyle(Color.secondary)
                    }
                    Text(sourceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if !recovery.hasHealthData, let onConnectHealth {
                Button(action: onConnectHealth) {
                    Label(NSLocalizedString("Connect Apple Health", comment: "Settings: HealthKit toggle"), systemImage: "heart.text.square")
                }
                .buttonStyle(.secondaryAction)
                .accessibilityIdentifier("forYou.connectHealth")
            }

            if !recovery.factors.isEmpty {
                VStack(spacing: Spacing.s) {
                    ForEach(recovery.factors) { factor in
                        HStack(spacing: 10) {
                            Image(systemName: factor.systemImage)
                                .frame(width: 22)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(factor.label).font(.subheadline)
                                Text(factor.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Points of the score, which a rough estimate doesn't show.
                            if !recovery.isLowConfidence {
                                Text(factor.impact >= 0 ? "+\(Int(factor.impact.rounded()))" : "\(Int(factor.impact.rounded()))")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(factor.impact >= 0 ? Theme.accent : Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        .card(padding: 18)
        .onAppear(perform: reveal)
        .onChange(of: recovery.score) { reveal() }
    }

    /// The score as a ring that fills as it counts up. A rough estimate gets
    /// a dotted ring and no number: "75" from training history alone would
    /// look more exact than it is.
    @ViewBuilder
    private var ring: some View {
        if recovery.isLowConfidence {
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [0.5, 11]))
                Image(systemName: recovery.band.systemImage)
                    .font(.system(size: scoreSize, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
        } else {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(shownScore) / 100)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(shownScore)")
                        .displayNumberFont(size: scoreSize)
                        .contentTransition(.numericText(value: Double(shownScore)))
                    Text(NSLocalizedString("recovery", comment: "Recovery unit label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(recovery.score) \(NSLocalizedString("recovery", comment: "Recovery unit label"))"))
        }
    }

    private func reveal() {
        guard !recovery.isLowConfidence else { return }
        guard !reduceMotion else {
            shownScore = recovery.score
            return
        }
        withAnimation(.spring(duration: 1.1)) { shownScore = recovery.score }
    }

    /// Names the inputs the score actually used, instead of always claiming
    /// all four.
    private var sourceNote: String {
        if !recovery.hasHealthData {
            return NSLocalizedString("Based on your training history. Connect Apple Health for HRV, resting heart rate and sleep.", comment: "No health data note")
        }
        if recovery.signals.count == RecoverySignal.allCases.count {
            return NSLocalizedString("From your HRV, resting heart rate, sleep and training load.", comment: "Health data note")
        }
        let names = RecoverySignal.allCases.filter(recovery.signals.contains).map(\.listName)
        return String(format: NSLocalizedString("Based on %@.", comment: "Recovery card: list of signals used, e.g. 'sleep and training load'"),
                      ListFormatter.localizedString(byJoining: names))
    }
}

// MARK: - Generated workout card

struct GeneratedWorkoutCard: View {

    let plan: PersonalizedWorkoutPlan
    let narrative: CoachNarrative?
    let didSave: Bool
    /// Shows the type picker when set; called with the type the user tapped.
    var onSelectSplit: ((GymSplit) -> Void)? = nil
    let onStart: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if let onSelectSplit, plan.availableSplits.count > 1 {
                splitPicker(onSelect: onSelectSplit)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("Today's workout", comment: "For You: the recommended workout card's eyebrow"), systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent)
                Text(narrative?.title ?? plan.split.displayName)
                    .displayFont(.title)
                    .contentTransition(.opacity)
                Text(narrative?.summary ?? plan.rationale)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            stats

            Button(action: onStart) {
                Label(NSLocalizedString("Start workout", comment: "Start plan workout action"), systemImage: "play.fill")
            }
            .buttonStyle(.primaryAction)
            .accessibilityIdentifier("forYou.startWorkout")

            VStack(spacing: 0) {
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, ex in
                    HStack {
                        Text(NSLocalizedString(ex.name, comment: "Gym exercise name"))
                            .font(.subheadline)
                        Spacer()
                        Text(ex.repCount > 0
                             ? String(format: NSLocalizedString("%d reps", comment: "reps"), ex.repCount)
                             : NSLocalizedString("timed", comment: "timed exercise"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.s)
                    if index < plan.exercises.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardBackground(.inset)

            Button(action: onSave) {
                Label(didSave
                      ? NSLocalizedString("Saved", comment: "")
                      : NSLocalizedString("Save to my workouts", comment: ""),
                      systemImage: didSave ? "checkmark" : "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(didSave ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(didSave)
        }
        .card(padding: 18)
    }

    /// How long, how many exercises and how hard, at a glance — shortened as
    /// a whole where the full row doesn't fit, never cut off.
    private var stats: some View {
        let minutes = statChip(String(format: NSLocalizedString("%d min", comment: "Workout card: duration in minutes"), plan.durationMinutes),
                               systemImage: "clock")
        let exercises = statChip(String(format: NSLocalizedString("%d exercises", comment: "Workout meta: number of exercises"), plan.exercises.count),
                                 systemImage: "list.bullet")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) { minutes; exercises; effortChip(showsLabel: true) }
            HStack(spacing: Spacing.s) { minutes; exercises; effortChip(showsLabel: false) }
            HStack(spacing: Spacing.s) { minutes; effortChip(showsLabel: false) }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func effortChip(showsLabel: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: plan.prediction.systemImage)
                .foregroundStyle(Theme.accent)
            if showsLabel {
                Text(plan.prediction.label)
            }
            difficultyPips(plan.prediction.rating)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .controlBackground(.inset)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Expected effort: %@", comment: "Generated workout: how hard the session will feel, e.g. Challenging"), plan.prediction.label)))
    }

    private func statChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .controlBackground(.inset)
            .fixedSize()
    }

    /// One chip per type the equipment can build; the recommended one carries
    /// the For You sparkles after its name. While another type is chosen, a
    /// line names the recommended one so it's easy to go back to.
    private func splitPicker(onSelect: @escaping (GymSplit) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            splitChips(onSelect: onSelect)
            if plan.isUserChosenSplit, let recommended = plan.recommendedSplit {
                Text(String(format: NSLocalizedString("Recommended: %@", comment: "For You: names the recommended workout type while the user has chosen another one"), recommended.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func splitChips(onSelect: @escaping (GymSplit) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plan.availableSplits) { split in
                    let isSelected = split == plan.split
                    let isRecommended = split == plan.recommendedSplit
                    Button {
                        onSelect(split)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: split.symbolName)
                            Text(split.shortName)
                            if isRecommended {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
                        .controlBackground(isSelected ? .accent : .inset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRecommended
                                        ? Text(String(format: NSLocalizedString("%@, recommended", comment: "Accessibility: workout type chip for the recommended type"), split.displayName))
                                        : Text(split.displayName))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        // Scroll across the card's full width so chips clip at its edge
        // instead of at the padding or spilling past the card.
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .padding(.horizontal, -18)
    }

    private func difficultyPips(_ rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Double(i) < rating ? Theme.accent : Theme.hairline)
                    .frame(width: 4, height: 12)
            }
        }
    }
}

// MARK: - Equipment prompts

/// Blocking-style card shown when the generator couldn't build a session at
/// all — the user's declared equipment doesn't cover any split.
struct NotEnoughEquipmentCard: View {

    let onSetUpEquipment: () -> Void

    var body: some View {
        Button(action: onSetUpEquipment) {
            VStack(spacing: 10) {
                Image(systemName: "dumbbell")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Add the equipment your gym has so we can build a session for you.", comment: "No equipment"))
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Set up equipment", comment: "Equipment nudge action"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 24)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Weekly goals

/// Progress toward each configured weekly frequency goal (e.g. "Gym 1/2 this
/// week"). Purely a progress readout — starting the next session for an open
/// goal happens via its own card (`RunningSessionCard`, `GoalSessionCard`, or
/// the existing `GeneratedWorkoutCard` for gym) so goals can be completed in
/// any order.
struct WeeklyGoalsCard: View {

    struct Row: Identifiable {
        let category: GoalCategory
        let target: Int
        let completed: Int
        /// Of `completed`, the sessions only another app recorded — said on
        /// the row, since they aren't TrainingLab workouts.
        var fromOtherApps = 0
        var id: String { category.id }
        var isDone: Bool { completed >= target }
    }

    let rows: [Row]
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(NSLocalizedString("This week", comment: "Weekly goals card title"))
                    .displayFont(.title3)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("Edit goals", comment: "Accessibility label")))
            }

            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.category.symbolName)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(row.category.displayName)
                                .font(.subheadline.weight(.semibold))
                            if row.fromOtherApps > 0 {
                                Text(String(format: NSLocalizedString("%d from other apps", comment: "Weekly goals card: sessions recorded by other apps in Apple Health"),
                                            row.fromOtherApps))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.hairline).frame(height: 6)
                            GeometryReader { geo in
                                Capsule().fill(Theme.accent)
                                    .frame(width: geo.size.width * min(Double(row.completed) / Double(max(row.target, 1)), 1), height: 6)
                            }
                            .frame(height: 6)
                        }
                    }
                    Spacer(minLength: 8)
                    if row.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("\(row.completed)/\(row.target)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

/// "Start now" card for an open goal without a generator of its own (swimming,
/// cycling, a group…). A group offers its sports to pick from; the session is
/// a plain timer for that activity (`GoalSessionBuilder`).
struct GoalSessionCard: View {

    let goal: GoalCategory
    /// What can be started for the goal — one sport, or a group's sports.
    let sports: [HKWorkoutActivityType]
    let onStart: (HKWorkoutActivityType) -> Void

    @State private var selected: HKWorkoutActivityType?

    private var sport: HKWorkoutActivityType { selected ?? sports.first ?? .other }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBadge(systemName: goal.symbolName)
                Text(goal.displayName)
                    .displayFont(.title2)
                Spacer(minLength: 8)
                if sports.count > 1 {
                    Picker(NSLocalizedString("Sport", comment: "Goal session card: which sport of a group to start"),
                           selection: Binding(get: { sport }, set: { selected = $0 })) {
                        ForEach(sports, id: \.self) { type in
                            Label(type.name, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                }
            }

            Button {
                onStart(sport)
            } label: {
                Label(String(format: NSLocalizedString("Start %@", comment: "Goal session card: start action, e.g. 'Start Swimming'"),
                             sport.name),
                      systemImage: "play.fill")
            }
            .buttonStyle(.primaryAction)
        }
        .card(padding: 18)
    }
}

/// "Start now" card for an open running goal — mirrors `GeneratedWorkoutCard`'s
/// styling but simpler, since a running session has no exercise list.
struct RunningSessionCard: View {

    let workout: Workout
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Running", comment: "Weekly goal category"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(workout.displayName)
                    .displayFont(.title2)
                Text(workout.displayInfoText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Label(String(format: NSLocalizedString("about %d min", comment: "Running session duration"), workout.duration),
                  systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onStart) {
                Label(NSLocalizedString("Start run", comment: "Start running session action"), systemImage: "play.fill")
            }
            .buttonStyle(.primaryAction)
        }
        .card(padding: 18)
    }
}

/// Compact prompt shown when the user hasn't set any weekly goals yet.
struct SetGoalPromptCard: View {

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "flag.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accentFillGradient, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Set a goal", comment: "Set-goal prompt title"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(NSLocalizedString("Set weekly targets like running or gym twice a week.", comment: "Set-goal prompt subtitle"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

/// Lightweight, non-blocking nudge shown alongside a generated workout when the
/// user still has every piece of equipment enabled (the untouched default) —
/// a hint that customizing it would sharpen future recommendations.
struct EquipmentNudgeBanner: View {

    let onSetUpEquipment: () -> Void

    var body: some View {
        Button(action: onSetUpEquipment) {
            HStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Theme.accent)
                Text(NSLocalizedString("Set up your equipment for better recommendations.", comment: "Equipment nudge banner"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}
