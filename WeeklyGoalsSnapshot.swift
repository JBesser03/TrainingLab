//
//  WeeklyGoalsSnapshot.swift
//  TrainingLab
//
//  This week's goal progress as the app last computed it — the bridge to the
//  Weekly Goals widget. The widget can read neither the app's UserDefaults nor
//  its SwiftData store, so the app writes this small snapshot into the shared
//  App Group container (`WeeklyGoalsWidgetSync`) and the widget only renders
//  it. Compiled into both the app and the widget extension.
//
//  Each goal carries its display name and SF Symbol, resolved by the app when
//  it publishes, so the widget needs neither the sport catalog nor HealthKit.
//

import Foundation

// MARK: - Snapshot

struct WeeklyGoalsSnapshot: Codable, Equatable {

    struct Goal: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var symbolName: String
        var completed: Int
        var target: Int

        var isDone: Bool { completed >= target }
        var remaining: Int { max(target - completed, 0) }

        init(id: String, title: String, symbolName: String, completed: Int, target: Int) {
            self.id = id
            self.title = title
            self.symbolName = symbolName
            self.completed = completed
            self.target = target
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, symbolName, completed, target
            case category  // snapshots written before goals could be any sport
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            completed = try container.decode(Int.self, forKey: .completed)
            target = try container.decode(Int.self, forKey: .target)
            if let id = try container.decodeIfPresent(String.self, forKey: .id) {
                self.id = id
                title = try container.decode(String.self, forKey: .title)
                symbolName = try container.decode(String.self, forKey: .symbolName)
            } else {
                // Gym or running, the only two categories there were. Keeps the
                // widget showing progress after an update until the app next
                // runs and writes a current snapshot.
                let category = try container.decode(String.self, forKey: .category)
                id = category
                if category == "running" {
                    title = NSLocalizedString("Running", comment: "Weekly goal category")
                    symbolName = "figure.run"
                } else {
                    title = NSLocalizedString("Gym", comment: "Weekly goal category")
                    symbolName = "dumbbell.fill"
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(symbolName, forKey: .symbolName)
            try container.encode(completed, forKey: .completed)
            try container.encode(target, forKey: .target)
        }
    }

    var goals: [Goal]
    /// End of the calendar week the counts belong to.
    var weekEnd: Date

    static let appGroup = "group.Besser.Workout-Justus"
    static let widgetKind = "WeeklyGoalsWidget"
    private static let storageKey = "weeklyGoalsSnapshot"

    /// The goals as of `now`. Once the week the snapshot was taken in has
    /// ended, nothing is completed yet in the new one — so the widget resets
    /// on Monday even if the app isn't opened.
    func goals(at now: Date) -> [Goal] {
        guard now >= weekEnd else { return goals }
        return goals.map { Goal(id: $0.id, title: $0.title, symbolName: $0.symbolName, completed: 0, target: $0.target) }
    }

    /// Days still left in the calendar week containing `date`, today
    /// included — so 1 on its last day.
    static func daysLeftInWeek(at date: Date, calendar: Calendar = .current) -> Int {
        guard let weekEnd = calendar.dateInterval(of: .weekOfYear, for: date)?.end else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: weekEnd).day ?? 0
    }

    /// The midnights after `start` and before `end` — when a "days left"
    /// readout has to change.
    static func dayStarts(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start))
        while let day = next, day < end {
            days.append(day)
            next = calendar.date(byAdding: .day, value: 1, to: day)
        }
        return days
    }

    /// Where the snapshot lives: a file in the App Group container. A file
    /// rather than shared UserDefaults, because a widget process that is still
    /// running can go on reading its cached copy of a defaults value after the
    /// app has changed it.
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("WeeklyGoalsSnapshot.json")
    }

    /// - Parameter legacyDefaults: read when there's no file yet — where
    ///   snapshots were stored before.
    static func load(from url: URL? = fileURL,
                     legacyDefaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> WeeklyGoalsSnapshot? {
        if let url, let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(WeeklyGoalsSnapshot.self, from: data)
        }
        guard let data = legacyDefaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalsSnapshot.self, from: data)
    }

    func save(to url: URL? = WeeklyGoalsSnapshot.fileURL) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
