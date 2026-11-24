//
//  WeeklyGoalsWidget.swift
//  TrainingLabWidget-iOS
//
//  Home Screen and Lock Screen widget for this week's training goals
//  ("Gym 1/2 · Swimming 0/1"). Renders the `WeeklyGoalsSnapshot` the app keeps
//  in the shared App Group (see WeeklyGoalsWidgetSync), names and symbols
//  included; the only thing it works out itself is the reset when a new week
//  starts.
//

import Foundation
import SwiftUI
import WidgetKit

struct WeeklyGoalsEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written its first snapshot; empty when the user
    /// has no goals.
    let goals: [WeeklyGoalsSnapshot.Goal]?
}

struct WeeklyGoalsProvider: TimelineProvider {

    func placeholder(in context: Context) -> WeeklyGoalsEntry {
        WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(0, of: 1)])
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalsEntry) -> Void) {
        // The widget gallery shows sample goals until the app has real ones.
        if context.isPreview, WeeklyGoalsSnapshot.load() == nil {
            completion(placeholder(in: context))
        } else {
            completion(entry(at: .now, snapshot: WeeklyGoalsSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalsEntry>) -> Void) {
        let now = Date.now
        let snapshot = WeeklyGoalsSnapshot.load()
        let weekEnd = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        // An entry each midnight counts the medium widget's "days left" down,
        // and the one at the week's end drops the counts to 0/target — both
        // without waiting for the app to be opened. Every other change
        // arrives as an app-triggered reload; this one asks for the next
        // week's timeline once the last entry is reached.
        let dates = [now] + WeeklyGoalsSnapshot.dayStarts(from: now, to: weekEnd) + [weekEnd]
        completion(Timeline(entries: dates.map { entry(at: $0, snapshot: snapshot) }, policy: .atEnd))
    }

    private func entry(at date: Date, snapshot: WeeklyGoalsSnapshot?) -> WeeklyGoalsEntry {
        WeeklyGoalsEntry(date: date, goals: snapshot?.goals(at: date))
    }
}

struct WeeklyGoalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeeklyGoalsSnapshot.widgetKind, provider: WeeklyGoalsProvider()) { entry in
            WeeklyGoalsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(Text(NSLocalizedString("Weekly goals", comment: "Weekly goals editor title")))
        .description(Text(NSLocalizedString("Your training goals for this week.", comment: "Weekly goals widget: gallery description")))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Views

struct WeeklyGoalsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeeklyGoalsEntry

    /// Rows that fit the small widget and the Lock Screen; the editor's order
    /// decides which goals they are.
    static let maxRows = 3

    var body: some View {
        if let goals = entry.goals, !goals.isEmpty {
            switch family {
            case .accessoryInline:
                Text(verbatim: goals.map { "\($0.title) \($0.completed)/\($0.target)" }
                    .joined(separator: " · "))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(goals.prefix(Self.maxRows)) { goal in
                        AccessoryGoalRow(goal: goal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                MediumGoalsView(goals: goals, date: entry.date)
            default:
                GoalsList(goals: goals)
            }
        } else {
            NoGoalsView(family: family)
        }
    }
}

/// "This week" plus one progress row per goal — the For You card in miniature.
private struct GoalsList: View {
    let goals: [WeeklyGoalsSnapshot.Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("This week", comment: "Weekly goals card title"))
                .font(typography.title(.headline))
            ForEach(goals.prefix(WeeklyGoalsWidgetView.maxRows)) { goal in
                GoalRow(goal: goal)
            }
            if goals.count > WeeklyGoalsWidgetView.maxRows {
                Text(String(format: NSLocalizedString("+%d more", comment: "Weekly goals widget: goals that don't fit"),
                            goals.count - WeeklyGoalsWidgetView.maxRows))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalRow: View {
    let goal: WeeklyGoalsSnapshot.Goal

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: goal.symbolName)
                .font(.subheadline)
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(goal.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if goal.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(themed(.success))
                    } else {
                        Text(verbatim: "\(goal.completed)/\(goal.target)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressBar(fraction: Double(goal.completed) / Double(max(goal.target, 1)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(themed(.inset))
                Capsule().fill(accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

/// Every goal — up to the editor's six, in two columns filled row by row once
/// there are more than three — under a header with what's left of the week:
/// the one thing the rows themselves don't say.
private struct MediumGoalsView: View {
    let goals: [WeeklyGoalsSnapshot.Goal]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("This week", comment: "Weekly goals card title"))
                    .font(typography.title(.headline))
                Spacer(minLength: 8)
                WeekStatus(allDone: goals.allSatisfy(\.isDone), date: date)
            }
            // Up to three fit one full-width column; two columns only once
            // there are more, so a short list doesn't leave half the widget empty.
            if goals.count <= WeeklyGoalsWidgetView.maxRows {
                column(Array(goals.indices))
            } else {
                HStack(alignment: .top, spacing: 16) {
                    column(goals.indices.filter { $0.isMultiple(of: 2) })
                    column(goals.indices.filter { !$0.isMultiple(of: 2) })
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(indices, id: \.self) { GoalRow(goal: goals[$0]) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "3 days left" / "Last day", or a seal once every goal is met.
private struct WeekStatus: View {
    let allDone: Bool
    let date: Date

    var body: some View {
        if allDone {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(themed(.success))
                Text(NSLocalizedString("All goals done", comment: "Weekly goals widget: every goal met this week"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
        } else {
            let days = WeeklyGoalsSnapshot.daysLeftInWeek(at: date)
            Text(days <= 1
                 ? NSLocalizedString("Last day", comment: "Weekly goals widget: the week ends today")
                 : String(format: NSLocalizedString("%d days left", comment: "Weekly goals widget: days left in the week, today included"), days))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Lock Screen row: rendered in the system's tinted/vibrant style, so it
/// relies on hierarchy and `widgetAccentable` rather than color.
private struct AccessoryGoalRow: View {
    let goal: WeeklyGoalsSnapshot.Goal

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: goal.isDone ? "checkmark.circle.fill" : goal.symbolName)
                .widgetAccentable()
                .frame(width: 18)
            Text(goal.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(goal.completed)/\(goal.target)")
                .font(.headline.monospacedDigit())
        }
    }
}

private struct NoGoalsView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(NSLocalizedString("Set a goal", comment: "Set-goal prompt title"))
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(NSLocalizedString("Weekly goals", comment: "Weekly goals editor title"))
                    .font(.headline)
                Text(NSLocalizedString("Set a goal", comment: "Set-goal prompt title"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Text(NSLocalizedString("Weekly goals", comment: "Weekly goals editor title"))
                    .font(typography.title(.headline))
                Text(NSLocalizedString("Set a goal", comment: "Set-goal prompt title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    WeeklyGoalsWidget()
} timeline: {
    WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(1, of: 1)])
    WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(1, of: 1), .swimming(0, of: 1), .cycling(2, of: 3)])
    WeeklyGoalsEntry(date: .now, goals: [])
}

#Preview("Medium", as: .systemMedium) {
    WeeklyGoalsWidget()
} timeline: {
    WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(0, of: 1)])
    WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(0, of: 1), .swimming(0, of: 1), .cycling(2, of: 3)])
    WeeklyGoalsEntry(date: .now, goals: [.gym(2, of: 2), .running(1, of: 1)])
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    WeeklyGoalsWidget()
} timeline: {
    WeeklyGoalsEntry(date: .now, goals: [.gym(1, of: 2), .running(0, of: 1), .swimming(0, of: 1), .cycling(2, of: 3)])
}

// MARK: - Samples

/// The widget gallery's placeholder and the previews.
private extension WeeklyGoalsSnapshot.Goal {
    static func gym(_ completed: Int, of target: Int) -> Self {
        .init(id: "gym", title: NSLocalizedString("Gym", comment: "Weekly goal category"),
              symbolName: "dumbbell.fill", completed: completed, target: target)
    }

    static func running(_ completed: Int, of target: Int) -> Self {
        .init(id: "running", title: NSLocalizedString("Running", comment: "Weekly goal category"),
              symbolName: "figure.run", completed: completed, target: target)
    }

    static func swimming(_ completed: Int, of target: Int) -> Self {
        .init(id: "type.46", title: NSLocalizedString("Swimming", comment: "Sport category, swimming"),
              symbolName: "figure.pool.swim", completed: completed, target: target)
    }

    static func cycling(_ completed: Int, of target: Int) -> Self {
        .init(id: "type.13", title: NSLocalizedString("Cycling", comment: "Sport category, cycling"),
              symbolName: "figure.outdoor.cycle", completed: completed, target: target)
    }
}
