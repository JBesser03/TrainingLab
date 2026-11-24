//
//  TrainingAids.swift
//  Workout App (iOS)
//
//  The calculations behind the gym helpers: what to try next time
//  (`ProgressionAdvisor`), when a rest follows a set (`RestRule`), which
//  plates to load (`PlateCalculator`), what a session changed about its
//  workout (`RoutineChanges`) and the history export (`HistoryCSV`). Pure, so
//  they're tested without views or SwiftData.
//

import Foundation

// MARK: - Progression

/// What to try in the next session of an exercise, from the last one — the
/// usual double progression: once every set reaches its reps, add weight.
enum ProgressionAdvisor {

    enum Suggestion: Equatable {
        /// Every set reached its reps with some to spare.
        case addWeight(toKg: Double)
        /// The same for an exercise done without weight: one more rep.
        case addRep(to: Int)
    }

    /// - Parameters:
    ///   - lastSets: the working sets of the latest session with the exercise.
    ///   - targetReps: the plan's reps; 0 for a timed exercise.
    ///   - stepKg: the weight step (2.5 in the user's unit).
    /// - Returns: nil to repeat last time — a set fell short of its reps, or
    ///   one was rated as taken to failure (0 reps in reserve).
    static func suggestion(lastSets: [WorkoutStats.LoggedSet], targetReps: Int, stepKg: Double) -> Suggestion? {
        guard targetReps > 0, !lastSets.isEmpty,
              lastSets.allSatisfy({ $0.reps >= targetReps }),
              !lastSets.contains(where: { $0.detail.repsInReserve == 0 }) else { return nil }
        let heaviest = lastSets.map(\.kg).max() ?? 0
        if heaviest > 0 {
            // The next step above it — a typed 61 kg leads to 62.5, not 63.5.
            let steps = (heaviest / stepKg + 1e-6).rounded(.down)
            return .addWeight(toKg: (steps + 1) * stepKg)
        }
        let fewest = lastSets.map(\.reps).min() ?? targetReps
        return .addRep(to: fewest + 1)
    }
}

// MARK: - Rest timer

enum RestRule {

    /// Whether the rest timer runs after a set. Not after a drop set, which
    /// follows the set before it straight away, nor between the exercises of
    /// one superset round — only once the round is through (the sequencer
    /// wraps back to an earlier member) or the session moves on.
    static func restsAfter(kind: SetKind, current: Int, next: StraightSetSequencer.Step,
                           entries: [StraightSetSequencer.Entry]) -> Bool {
        guard kind != .drop, entries.indices.contains(current) else { return false }
        switch next {
        case .finish:
            return false
        case .stay:
            return true
        case .move(let target):
            guard let group = entries[current].supersetGroup,
                  entries.indices.contains(target),
                  entries[target].supersetGroup == group else { return true }
            return target < current
        }
    }
}

// MARK: - Plates

/// The plates for each side of a barbell, heaviest first.
enum PlateCalculator {

    static func availablePlates(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kilograms: return [25, 20, 15, 10, 5, 2.5, 1.25]
        case .pounds:    return [45, 35, 25, 10, 5, 2.5]
        }
    }

    /// Olympic, women's and technique bars in the unit's usual sizes, in
    /// kilograms. The saved bar stays selectable after switching units.
    static func barOptionsKg(for unit: WeightUnit, current: Double) -> [Double] {
        let bars = (unit == .kilograms ? [20.0, 15, 10] : [45.0, 35, 15]).map { unit.toKilograms($0) }
        return bars.contains(where: { abs($0 - current) < 0.01 }) ? bars : bars + [current]
    }

    /// - Parameters: weights in the unit the plates are in.
    /// - Returns: the plates per side, and what's left over that the plates
    ///   can't make (0 when the total loads exactly).
    static func perSide(total: Double, bar: Double, plates: [Double]) -> (plates: [Double], remainder: Double) {
        var left = max((total - bar) / 2, 0)
        var result: [Double] = []
        for plate in plates.sorted(by: >) {
            // A hair of tolerance: 62.5 kg in pounds and back isn't exact.
            while left + 0.001 >= plate {
                result.append(plate)
                left -= plate
            }
        }
        return (result, left < 0.01 ? 0 : left * 2)
    }
}

// MARK: - Workout changes

/// What a session changed about its workout — exercises swapped, added,
/// removed or reordered, or a different number of sets — so the summary can
/// offer to keep it for next time.
struct RoutineChanges: Equatable {
    let exerciseIDs: [String]
    let plans: [String: ExercisePlan]

    /// nil when the session ran the workout as saved. Skipping an exercise
    /// isn't a change: it stays in the workout.
    static func detect(savedIDs: [String], savedPlans: [String: ExercisePlan],
                       sessionIDs: [String], sessionPlans: [String: ExercisePlan]) -> RoutineChanges? {
        var plans: [String: ExercisePlan] = [:]
        for id in sessionIDs {
            if let plan = sessionPlans[id] ?? savedPlans[id] { plans[id] = plan }
        }
        let changedPlans = sessionIDs.contains { id in
            guard let session = sessionPlans[id] else { return false }
            return session != savedPlans[id]
        }
        guard sessionIDs != savedIDs || changedPlans, !sessionIDs.isEmpty else { return nil }
        return RoutineChanges(exerciseIDs: sessionIDs, plans: plans)
    }
}

/// The change the last finished session left for its summary to offer.
@MainActor
enum RoutineUpdateOffer {
    struct Pending {
        let workoutID: String
        let changes: RoutineChanges
    }

    private(set) static var pending: Pending?

    static func offer(_ changes: RoutineChanges, forWorkoutID id: String) {
        pending = Pending(workoutID: id, changes: changes)
    }

    /// Hands the offer to one summary; it's gone afterwards.
    static func take() -> Pending? {
        defer { pending = nil }
        return pending
    }

    static func clear() { pending = nil }
}

// MARK: - Export

/// The workout history as CSV, one row per logged set (with its hold time
/// for a timed set) — or one per session for a workout without sets, like a run. Readable by spreadsheets and the
/// importers of other training apps.
enum HistoryCSV {

    struct Session {
        let name: String
        let start: Date
        let end: Date
        let activity: String
        let calories: Double?
        let note: String
        /// In the session's exercise order.
        let exercises: [(id: String, name: String)]
        let setWeights: [String: [Double]]
        let setReps: [String: [Int]]
        let log: SessionLog
    }

    static let header = ["Date", "Workout", "Activity", "Duration (min)", "Calories", "Exercise",
                         "Set", "Set type", "Weight", "Unit", "Reps", "Seconds", "Reps in reserve", "Note"]

    static func make(_ sessions: [Session], unit: WeightUnit) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        var rows = [header]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let common = [dateFormatter.string(from: session.start),
                          session.name,
                          session.activity,
                          String(Int((session.end.timeIntervalSince(session.start) / 60).rounded())),
                          session.calories.map { String(Int($0.rounded())) } ?? ""]
            var wroteSet = false
            for exercise in session.exercises {
                let weights = session.setWeights[exercise.id] ?? []
                let reps = session.setReps[exercise.id] ?? []
                let note = session.log.exerciseNotes[exercise.id] ?? ""
                for i in 0..<max(weights.count, reps.count) {
                    let detail = session.log.detail(exercise.id, i)
                    let kg = i < weights.count ? weights[i] : 0
                    rows.append(common + [exercise.name,
                                          String(i + 1),
                                          detail.kind.rawValue,
                                          unit.displayNumber(kilograms: kg),
                                          unit == .kilograms ? "kg" : "lb",
                                          i < reps.count ? String(reps[i]) : "",
                                          detail.seconds.map(String.init) ?? "",
                                          detail.repsInReserve.map(String.init) ?? "",
                                          i == 0 ? note : ""])
                    wroteSet = true
                }
            }
            if !wroteSet {
                rows.append(common + ["", "", "", "", "", "", "", "", session.note])
            } else if !session.note.isEmpty {
                rows.append(common + ["", "", "", "", "", "", "", "", session.note])
            }
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Quotes a field holding a comma, quote or line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
