//
//  WorkoutLiveActivityWidget.swift
//  TrainingLabWidget-iOS
//
//  Lock Screen and Dynamic Island presentation of an in-progress workout.
//  Reads `WorkoutActivityAttributes` (shared with the app); the app owns all
//  the state, this file only renders it.
//
//  Two things to keep in mind when editing:
//  • Colors are defined inline (the accent in WidgetTheme.swift). The
//    widget has its own asset catalog and cannot see the app's colors, so
//    `Color("accentColor")` would silently render black here.
//  • Countdowns use `Text(timerInterval:)` against the anchored
//    `phaseEndDate`, so they keep running without the app pushing updates.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// Lock Screen card background — opaque and dark in *both* appearances.
///
/// Two reasons it doesn't follow the system appearance. A translucent tint
/// lets the wallpaper through, so whatever the user has behind it decides the
/// contrast, which we don't control. And the accent here is its light
/// dark-mode shade (`accentOnDark`), which on a light card falls far under
/// the 4.5:1 floor — it's made to sit on dark, as it does in the Dynamic
/// Island, which is always black.
///
/// Because this ignores the appearance, the foreground colors below have to
/// as well: `.primary`/`.secondary` would resolve to *black* here in light
/// mode. Everything drawn on this card uses `cardForeground`/`cardSecondary`.

/// On `activityBackground` — any style's card color in dark mode — at
/// least 4.5:1, the secondary too (`AppThemeTests.liveActivityStaysReadable`).
private let cardForeground = Color.white
private let cardSecondary = Color.white.opacity(0.62)

struct WorkoutLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(activityBackground)
                .activitySystemActionForegroundColor(accentOnDark)
        } dynamicIsland: { context in
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbolName)
                        .font(.title2)
                        .foregroundStyle(accentOnDark)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(setLabel(state))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.currentExerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        PhaseIndicator(state: state)
                        Spacer(minLength: 8)
                        if state.canCompleteSet {
                            Button(intent: CompleteSetIntent()) {
                                Label("Set done", systemImage: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .tint(accentOnDark)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(accentOnDark)
            } compactTrailing: {
                Text(setLabel(state))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: state.symbolName)
                    .foregroundStyle(accentOnDark)
            }
            .keylineTint(accentOnDark)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {

    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(attributes.workoutName)
                    .font(typography.title(.subheadline, weight: .semibold))
                    .foregroundStyle(cardForeground)
                    .lineLimit(1)
                Spacer()
                // Elapsed session time, counting up from the workout's start.
                // `pauseTime` freezes it while the session is paused — a
                // running clock under a "Paused" label contradicts itself.
                Text(timerInterval: attributes.startDate...elapsedHorizon,
                     pauseTime: state.pausedAt,
                     countsDown: false)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(cardSecondary)
                    .frame(maxWidth: 60, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabelledRow(caption: "NOW", value: state.currentExerciseName, prominent: true) {
                    Text(setLabel(state))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(cardSecondary)
                }
                if let next = state.nextExerciseName {
                    LabelledRow(caption: "NEXT", value: next, prominent: false) { EmptyView() }
                }
            }

            ProgressCapsule(fraction: exerciseProgress)

            HStack(spacing: 8) {
                PhaseIndicator(state: state)
                Spacer(minLength: 8)
                if state.canCompleteSet {
                    Button(intent: CompleteSetIntent()) {
                        Label("Set done", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            // Dark on the light dark-mode accent, which white can't be read on.
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(buttonShape)
                    .tint(accentOnDark)

                    Button(intent: SkipExerciseIntent()) {
                        Label("Skip", systemImage: "forward.end")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(buttonShape)
                    .tint(cardSecondary)
                }
            }
        }
        .padding(16)
    }

    /// `Text(timerInterval:)` needs a bounded range; no workout runs a day.
    private var elapsedHorizon: Date {
        attributes.startDate.addingTimeInterval(24 * 60 * 60)
    }

    /// Progress through the whole workout, counting sets so the bar still
    /// moves within a single exercise.
    private var exerciseProgress: Double {
        let totalSets = max(state.totalExercises * max(state.totalSets, 1), 1)
        let done = state.exerciseIndex * max(state.totalSets, 1) + state.setIndex
        return min(Double(done) / Double(totalSets), 1)
    }
}

// MARK: - Pieces

private struct LabelledRow<Trailing: View>: View {
    /// `LocalizedStringKey`, not `String`: `Text(someString)` picks the
    /// non-localizing initializer, so a `String` here rendered the literal
    /// "NOW"/"NEXT" even though both are translated in the catalog. Only
    /// string *literals* become `LocalizedStringKey` implicitly.
    let caption: LocalizedStringKey
    /// Stays a `String` on purpose — this is the exercise's `displayName`,
    /// already localized by the app. Treating it as a key would look the
    /// exercise name up in the catalog and miss.
    let value: String
    let prominent: Bool
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.caption2.weight(.bold))
                .foregroundStyle(cardSecondary)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(prominent ? typography.title(.headline) : .subheadline)
                .foregroundStyle(prominent ? cardForeground : cardSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

/// Whatever the session is doing right now: resting, paused, counting down a
/// timed exercise, or simply waiting on the user to finish their reps. Empty
/// for a session without exercises (a run), which only has the elapsed clock.
private struct PhaseIndicator: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            // The catalog stores this lowercase ("pausiert") because the app
            // uppercases it at the point of display; do the same here so the
            // widget matches, and sits alongside the NOW/NEXT caps.
            Label("Paused", systemImage: "pause.circle")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(cardSecondary)
        } else if let end = state.phaseEndDate {
            // The system can redraw stale content after the phase ended (the
            // app suspended mid-set); a range ending before now would trap.
            let now = Date()
            HStack(spacing: 4) {
                Image(systemName: state.isResting ? "hourglass" : "timer")
                Text(timerInterval: now...max(end, now), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.isResting ? AnyShapeStyle(cardSecondary) : AnyShapeStyle(accentOnDark))
        } else if state.canCompleteSet || state.loggedSetCount > 0 {
            Label("\(state.loggedSetCount) logged", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(cardSecondary)
        }
    }
}

private struct ProgressCapsule: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(accentOnDark)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

/// Buttons in the style's shape: capsules, or its square corners.
private var buttonShape: ButtonBorderShape {
    controlRadius >= 20 ? .capsule : .roundedRectangle(radius: controlRadius)
}

private func setLabel(_ state: WorkoutActivityAttributes.ContentState) -> String {
    "\(min(state.setIndex + 1, max(state.totalSets, 1)))/\(max(state.totalSets, 1))"
}
