//
//  HistoryView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 28.12.21.
//

import SwiftUI
import SwiftData
import HealthKit

struct ProtocolView: View {
    
    @Query var finishedWorkouts: [FinishedWorkout]
    
    @EnvironmentObject var iOSWorkoutObserver: iOSWorkoutObserver
    @Environment(\.modelContext) private var modelContext
    
    @State private var searchText = ""
    @State private var sortType: SortType = .dateNewest
    /// Workouts other apps saved to Apple Health, minus the sessions TrainingLab
    /// recorded itself. Weekly goals count them, so History shows them too.
    @State private var externalWorkouts: [ExternalWorkout] = []
    @AppStorage("historyShowsOtherApps") private var showsOtherApps = true
    
    /// Everything History lists; the stats count the same.
    private var items: [HistoryItem] {
        let own = finishedWorkouts.filter { !$0.name.isEmpty }.map(HistoryItem.own)
        return showsOtherApps ? own + externalWorkouts.map(HistoryItem.external) : own
    }
    
    private var searchResults: [HistoryItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.searchText.lowercased().contains(searchText.lowercased()) }
    }
    
    private var sortedItems: [HistoryItem] {
        switch sortType {
        case .dateNewest:
            return searchResults.sorted { $0.startDate > $1.startDate }
        case .dateOldest:
            return searchResults.sorted { $0.startDate < $1.startDate }
        case .activityType:
            // Grouped by activity below, so each activity's entries must be
            // contiguous; newest first within an activity.
            return searchResults.sorted {
                if $0.activityName != $1.activityName {
                    return $0.activityName.localizedStandardCompare($1.activityName) == .orderedAscending
                }
                return $0.startDate > $1.startDate
            }
        case .nameAscending:
            return searchResults.sorted { $0.name > $1.name }
        case .nameDescending:
            return searchResults.sorted { $0.name < $1.name }
        }
    }

    /// Groups sorted items for section headers: by activity when sorting by
    /// activity type, otherwise by month/year. Keys must be unique (ForEach id).
    private var groupedItems: [(key: String, items: [HistoryItem])] {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        
        var groups: [(key: String, items: [HistoryItem])] = []
        var currentKey = ""
        var currentGroup: [HistoryItem] = []
        
        for item in sortedItems {
            let key = sortType == .activityType
                ? item.activityName
                : formatter.string(from: item.startDate)
            if key != currentKey {
                if !currentGroup.isEmpty {
                    groups.append((key: currentKey, items: currentGroup))
                }
                currentKey = key
                currentGroup = [item]
            } else {
                currentGroup.append(item)
            }
        }
        if !currentGroup.isEmpty {
            groups.append((key: currentKey, items: currentGroup))
        }
        
        return groups
    }
    
    // MARK: - Stats
    
    private var totalWorkouts: Int {
        items.count
    }
    
    private var totalDuration: TimeInterval {
        items.reduce(0) { $0 + $1.duration }
    }
    
    private var thisWeekCount: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return items.filter { $0.startDate >= startOfWeek }.count
    }
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
    
    var body: some View {
        ScrollView(.vertical) {
            if sortedItems.isEmpty {
                // MARK: - Empty State
                // Full width (`EmptyStateView`), or the scroll view hugs the
                // text and the page tint behind it stops short of the edges.
                EmptyStateView(title: NSLocalizedString("No Workouts Yet", comment: "History: empty state title"),
                               systemImage: "figure.run",
                               message: NSLocalizedString("Complete a workout and it will show up here.", comment: "History: empty state message"))
                    .padding(.top, 40)
            } else {
                // MARK: - Stats Summary
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    HistoryStatCard(value: "\(totalWorkouts)", label: "Total", systemImage: "figure.strengthtraining.traditional")
                    HistoryStatCard(value: durationFormatter.string(from: totalDuration) ?? "0m", label: "Duration", systemImage: "timer", tone: 1)
                    HistoryStatCard(value: "\(thisWeekCount)", label: "This Week", systemImage: "calendar", tone: 2)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // MARK: - Grouped Workout List
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedItems, id: \.key) { group in
                        Section {
                            ForEach(group.items) { item in
                                switch item {
                                case .own(let workout):
                                    NavigationLink {
                                        FinishedWorkoutView(specificWorkout: workout)
                                    } label: {
                                        ProtocolCellView(workout: workout)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("history.row")
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            modelContext.delete(workout)
                                            try? modelContext.save()
                                            Task { await GoalReminderScheduler.shared.refresh(context: modelContext) }
                                        } label: {
                                            Label(NSLocalizedString("Delete workout", comment: "History: delete workout"), systemImage: "trash")
                                        }
                                    }
                                case .external(let workout):
                                    ExternalWorkoutCellView(workout: workout)
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.key)
                                    .displayFont(.subheadline, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.items.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.bar)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .refreshable { await loadExternalWorkouts() }
        // Again when the own history changes: a workout just finished here
        // may be the same session another app recorded.
        .task(id: finishedWorkouts.count) { await loadExternalWorkouts() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    WorkoutProgressView()
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                }
                .accessibilityLabel(Text(NSLocalizedString("Progress", comment: "Progress screen title")))
                .accessibilityIdentifier("history.progress")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sortType) {
                        Text("Date (Newest first)").tag(SortType.dateNewest)
                        Text("Date (Oldest first)").tag(SortType.dateOldest)
                        Text("Activity Type").tag(SortType.activityType)
                    }
                    Toggle(NSLocalizedString("Workouts from other apps", comment: "History: show workouts other apps saved to Apple Health"),
                           isOn: $showsOtherApps)
                } label: {
                    Image(systemName: "arrow.up.and.down.text.horizontal")
                }
                .accessibilityLabel(Text(NSLocalizedString("Sort and filter", comment: "History: sort and filter menu")))
            }
        }
        .pageTint()
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search for workouts")
    }

    private func loadExternalWorkouts() async {
        let all = await RecoveryMetricsProvider().externalWorkouts(from: .distantPast, to: .now)
        externalWorkouts = ExternalWorkout.distinct(all, from: finishedWorkouts)
    }
}

/// One History row: a TrainingLab workout, or one another app saved to
/// Apple Health.
private enum HistoryItem: Identifiable {
    case own(FinishedWorkout)
    case external(ExternalWorkout)

    var id: String {
        switch self {
        case .own(let workout):      return "own-\(workout.id)"
        case .external(let workout): return "health-\(workout.id.uuidString)"
        }
    }

    var startDate: Date {
        switch self {
        case .own(let workout):      return workout.startDate
        case .external(let workout): return workout.start
        }
    }

    var duration: TimeInterval {
        switch self {
        case .own(let workout):      return workout.duration
        case .external(let workout): return workout.duration
        }
    }

    var activityName: String {
        let type: Int
        switch self {
        case .own(let workout):      type = workout.workoutType
        case .external(let workout): type = workout.activityType
        }
        return HKWorkoutActivityType(rawValue: UInt(type))?.name
            ?? NSLocalizedString("Other", comment: "Fallback workout activity type")
    }

    /// Another app's workout has no name of its own; it's listed by activity.
    var name: String {
        switch self {
        case .own(let workout): return workout.name
        case .external:         return activityName
        }
    }

    var searchText: String {
        switch self {
        case .own(let workout):      return workout.name
        case .external(let workout): return "\(activityName) \(workout.sourceName)"
        }
    }
}

// MARK: - Stats Card

struct HistoryStatCard: View {
    let value: String
    let label: LocalizedStringKey
    let systemImage: String
    /// Its shade of the accent (`Theme.tone`).
    var tone = 0

    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.tone(tone))
            Text(value)
                .displayNumberFont(size: valueSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Workout Cell

struct ProtocolCellView: View {
    
    var workout: FinishedWorkout
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }
    
    private var weekdayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Date column
            VStack(spacing: 2) {
                Text(dayFormatter.string(from: workout.startDate))
                    .displayFont(.title2)
                Text(weekdayFormatter.string(from: workout.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 44)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: WorkoutCategory.getSymbolName(from: workout.muscleGroup))
                        .font(.caption)
                        .foregroundStyle(Theme.tone(WorkoutCategory.tone(from: workout.muscleGroup)))
                    Text(workout.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                
                HStack(spacing: 12) {
                    Label(durationFormatter.string(from: workout.duration) ?? "00:00:00", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(timeFormatter.string(from: workout.startDate), systemImage: "sun.horizon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if workout.exercisesSequenceID.count > 0 {
                        Label("\(workout.exercisesSequenceID.count)", systemImage: "figure.strengthtraining.traditional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if workout.additionalData.hasContent {
                        Text(workout.additionalData.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

/// A workout another app recorded, laid out like `ProtocolCellView` but
/// neutral and without a detail screen — its details live in the Health app.
struct ExternalWorkoutCellView: View {

    var workout: ExternalWorkout

    private var activity: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: UInt(workout.activityType)) ?? .other
    }

    // The same formats as `ProtocolCellView`, so the two kinds of row line up.
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 14) {
            // Date column
            VStack(spacing: 2) {
                Text(workout.start, format: .dateTime.day())
                    .displayFont(.title2)
                Text(workout.start, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: activity.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(activity.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !workout.sourceName.isEmpty {
                        Text(String(format: NSLocalizedString("From %@", comment: "History: the app that recorded a workout, e.g. 'From Strava'"),
                                    workout.sourceName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 12) {
                    Label(Self.durationFormatter.string(from: workout.duration) ?? "00:00:00", systemImage: "clock")
                    Label(Self.timeFormatter.string(from: workout.start), systemImage: "sun.horizon")
                    if let meters = workout.distanceMeters {
                        Label(Measurement(value: meters, unit: UnitLength.meters)
                                .formatted(.measurement(width: .abbreviated, usage: .road)),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

enum SortType {
    case dateNewest
    case dateOldest
    case activityType
    case nameAscending
    case nameDescending
}

#Preview {
    NavigationStack {
        ProtocolView()
    }
}

#Preview {
    ProtocolCellView(workout: FinishedWorkout.samples[0])
}
