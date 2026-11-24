//
//  WorkoutProgressView.swift
//  TrainingLab (iOS)
//
//  Progress-over-time charts built from logged weight/reps history: total
//  training volume per session, and per-exercise progression as best weight
//  or estimated 1RM.
//  All series come from the pure `WorkoutStats` helpers; values are shown in the
//  user's preferred unit.
//

import SwiftUI
import SwiftData
import Charts

struct WorkoutProgressView: View {

    @Query(sort: [SortDescriptor(\FinishedWorkout.endDate)])
    private var finishedWorkouts: [FinishedWorkout]

    @State private var selectedExerciseID: String?
    /// Best weight moves only with heavier sets; the estimated 1RM also
    /// rises when more reps are done at the same weight.
    @State private var showsEstimatedMax = false

    private var unit: WeightUnit { SettingsManager.shared.weightUnit }

    private struct DatedValue: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var snapshots: [WorkoutStats.Snapshot] {
        WorkoutStats.snapshots(from: finishedWorkouts)
    }

    private var volumePoints: [DatedValue] {
        WorkoutStats.volumeSeries(from: snapshots)
            .map { DatedValue(date: $0.date, value: unit.fromKilograms($0.volumeKg)) }
    }

    /// Exercises that have at least one logged weight, with display names.
    private var exerciseOptions: [(id: String, name: String)] {
        var names: [String: String] = [:]
        var logged: Set<String> = []
        for workout in finishedWorkouts {
            for (id, weights) in workout.setWeights where weights.contains(where: { $0 > 0 }) {
                logged.insert(id)
            }
            for exercise in workout.exercises ?? [] {
                names[exercise.id] = exercise.displayName
            }
        }
        return logged
            .map { (id: $0, name: names[$0] ?? NSLocalizedString("Exercise", comment: "Progress: unknown exercise")) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var weightPoints: [DatedValue] {
        guard let id = selectedExerciseID else { return [] }
        let series = showsEstimatedMax
            ? WorkoutStats.e1RMSeries(forExerciseID: id, from: snapshots)
            : WorkoutStats.bestWeightSeries(forExerciseID: id, from: snapshots)
        return series.map { DatedValue(date: $0.date, value: unit.fromKilograms($0.weightKg)) }
    }

    var body: some View {
        Group {
            if volumePoints.isEmpty {
                EmptyStateView(title: NSLocalizedString("No data yet", comment: "Progress empty state title"),
                               systemImage: "chart.xyaxis.line",
                               message: NSLocalizedString("Complete a workout with logged weights to see your progress here.",
                                                          comment: "Progress empty state description"))
                    .frame(maxHeight: .infinity)
                    .pageTint()
            } else {
                StyledList {
                    Section(NSLocalizedString("Total volume", comment: "Progress: volume section")) {
                        // A session's volume depends on what it was, so no
                        // change against the first one here.
                        headline(for: volumePoints, showsChange: false)
                        chart(for: volumePoints, valueLabel: NSLocalizedString("Volume", comment: "Progress: volume axis"))
                    }

                    if !exerciseOptions.isEmpty {
                        Section(NSLocalizedString("Exercise progression", comment: "Progress: per-exercise section")) {
                            Picker(NSLocalizedString("Exercise", comment: "Progress: exercise picker"),
                                   selection: $selectedExerciseID) {
                                ForEach(exerciseOptions, id: \.id) { option in
                                    Text(option.name).tag(Optional(option.id))
                                }
                            }
                            Picker(NSLocalizedString("Show", comment: "Progress: which value the exercise chart shows"),
                                   selection: $showsEstimatedMax) {
                                Text(NSLocalizedString("Best weight", comment: "Progress: chart of the heaviest set")).tag(false)
                                Text(NSLocalizedString("Est. 1RM", comment: "Progress: chart of the estimated one-rep max")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            if weightPoints.count >= 1 {
                                headline(for: weightPoints, showsChange: true)
                                chart(for: weightPoints, valueLabel: NSLocalizedString("Weight", comment: "Progress: weight axis"))
                            } else {
                                Text(NSLocalizedString("No sets logged for this exercise yet.", comment: "Progress: exercise no data"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Progress", comment: "Progress screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedExerciseID == nil { selectedExerciseID = exerciseOptions.first?.id }
        }
    }

    /// The latest value, large, and — for an exercise — how far it moved
    /// since the first session.
    private func headline(for points: [DatedValue], showsChange: Bool) -> some View {
        let latest = points.last?.value ?? 0
        let first = points.first?.value ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(latest.formatted(.number.precision(.fractionLength(0...1))))
                    .displayNumberFont(size: 30)
                    .contentTransition(.numericText(value: latest))
                Text(unit.abbreviation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if showsChange, points.count >= 2, let start = points.first?.date, first > 0 {
                let change = (latest - first) / first
                Label(String(format: NSLocalizedString("%@ since %@", comment: "Progress: change since the first session, e.g. '+12 % since Nov 3'"),
                             change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))),
                             start.formatted(.dateTime.month(.abbreviated).day())),
                      systemImage: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change > 0 ? Theme.success : Color.secondary)
            } else {
                Text(NSLocalizedString("Last session", comment: "Progress: the headline value is the latest session's"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: latest)
        .accessibilityElement(children: .combine)
    }

    private func chart(for points: [DatedValue], valueLabel: String) -> some View {
        let last = points.last?.id
        return Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value(valueLabel, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)],
                                            startPoint: .top, endPoint: .bottom))
            LineMark(
                x: .value("Date", point.date),
                y: .value(valueLabel, point.value)
            )
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Theme.accent)
            PointMark(
                x: .value("Date", point.date),
                y: .value(valueLabel, point.value)
            )
            .symbolSize(point.id == last ? 90 : 30)
            .foregroundStyle(Theme.accent)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
            }
        }
        .frame(height: 200)
        .padding(.vertical, 4)
    }
}
