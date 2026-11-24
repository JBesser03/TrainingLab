//
//  WorkoutStats.swift
//  TrainingLab (iOS)
//
//  Pure, deterministic aggregations over logged workout data — training volume
//  and personal-record detection. Kept free of SwiftData/SwiftUI so the numbers
//  behind the summary can be unit-tested directly.
//
//  Warm-up sets never count; drop sets count toward volume but not toward
//  PRs, the estimated 1RM or the weight the next session starts from. Sets
//  without a `SetDetail` (everything logged before set kinds existed) are
//  working sets.
//

import Foundation

enum WorkoutStats {

    /// Total training volume in kilograms: Σ (weight × reps) across every logged
    /// set except warm-ups — a bodyweight exercise's weight includes the body
    /// when the session recorded it. `setReps` is index-aligned with
    /// `setWeights`; a missing/short reps entry counts as 0 reps (so
    /// weight-only legacy records contribute nothing).
    static func volumeKilograms(setWeights: [String: [Double]],
                                setReps: [String: [Int]],
                                log: SessionLog = SessionLog()) -> Double {
        var total = 0.0
        for (id, weights) in setWeights {
            let reps = setReps[id] ?? []
            for i in weights.indices where log.detail(id, i).kind != .warmup {
                let r = i < reps.count ? reps[i] : 0
                total += log.load(id, addedKg: weights[i]) * Double(r)
            }
        }
        return total
    }

    /// A minimal, value-typed view of a finished workout for PR/trend analysis —
    /// avoids needing SwiftData objects in tests.
    struct Snapshot {
        let id: String
        let endDate: Date
        let setWeights: [String: [Double]]
        let setReps: [String: [Int]]
        let log: SessionLog

        init(id: String, endDate: Date,
             setWeights: [String: [Double]], setReps: [String: [Int]] = [:],
             log: SessionLog = SessionLog()) {
            self.id = id
            self.endDate = endDate
            self.setWeights = setWeights
            self.setReps = setReps
            self.log = log
        }

        /// Every logged set of `exerciseID`, in order, with its detail.
        func sets(_ exerciseID: String) -> [LoggedSet] {
            let weights = setWeights[exerciseID] ?? []
            let reps = setReps[exerciseID] ?? []
            return (0..<max(weights.count, reps.count)).map { i in
                LoggedSet(kg: i < weights.count ? weights[i] : 0,
                          reps: i < reps.count ? reps[i] : 0,
                          detail: log.detail(exerciseID, i))
            }
        }

        /// The working sets of `exerciseID` — no warm-ups, no drop sets.
        func workingSets(_ exerciseID: String) -> [LoggedSet] {
            sets(exerciseID).filter { $0.detail.kind == .working }
        }
    }

    struct LoggedSet: Hashable {
        let kg: Double
        let reps: Int
        let detail: SetDetail
    }

    /// Total volume (kg) for a single session snapshot.
    static func volumeKilograms(_ snapshot: Snapshot) -> Double {
        volumeKilograms(setWeights: snapshot.setWeights, setReps: snapshot.setReps, log: snapshot.log)
    }

    /// The most recent working weight (kg) logged for an exercise across
    /// `history` — the last working set of the newest session that recorded
    /// one. Basis for progressive overload / "last time" prefills.
    static func lastLoggedWeightKg(forExerciseID id: String, in history: [Snapshot]) -> Double? {
        history
            .filter { $0.workingSets(id).contains { $0.kg > 0 } }
            .max { $0.endDate < $1.endDate }?
            .workingSets(id)
            .last { $0.kg > 0 }?
            .kg
    }

    /// A progression signal in roughly [-1, 1]: how the user's mean session
    /// volume over the last `windowDays` compares to the preceding equal window.
    /// `> 0` = training volume is rising (adapting), `< 0` = falling. Returns `0`
    /// when there isn't enough history in both windows to compare.
    static func progressionScore(history: [Snapshot],
                                 now: Date = Date(),
                                 windowDays: Double = 14) -> Double {
        let window = windowDays * 86_400
        let recentStart = now.addingTimeInterval(-window)
        let olderStart = now.addingTimeInterval(-2 * window)

        let recent = history.filter { $0.endDate >= recentStart && $0.endDate <= now }
        let older = history.filter { $0.endDate >= olderStart && $0.endDate < recentStart }
        guard !recent.isEmpty, !older.isEmpty else { return 0 }

        let avg: ([Snapshot]) -> Double = { snaps in
            snaps.reduce(0) { $0 + volumeKilograms($1) } / Double(snaps.count)
        }
        let recentAvg = avg(recent)
        let olderAvg = avg(older)
        guard olderAvg > 0 else { return 0 }
        return min(max(recentAvg / olderAvg - 1.0, -1.0), 1.0)
    }

    /// Exercise ids in `current` that set a new max-weight personal record versus
    /// the best in any *earlier* workout in `history`. Requires prior history for
    /// that exercise (so a first-ever log isn't falsely flagged), and only counts
    /// workouts strictly before `current.endDate` (excluding `current` itself).
    static func personalRecordExerciseIDs(current: Snapshot,
                                          history: [Snapshot]) -> Set<String> {
        var prs: Set<String> = []
        for id in current.setWeights.keys {
            guard let currentMax = current.workingSets(id).map(\.kg).max(), currentMax > 0 else { continue }
            var previousBest = 0.0
            var hadHistory = false
            for other in history where other.id != current.id && other.endDate < current.endDate {
                if let best = other.workingSets(id).map(\.kg).max() {
                    hadHistory = true
                    previousBest = max(previousBest, best)
                }
            }
            if hadHistory && currentMax > previousBest {
                prs.insert(id)
            }
        }
        return prs
    }

    /// Adapts SwiftData records into value-typed snapshots for the pure helpers.
    static func snapshots(from workouts: [FinishedWorkout]) -> [Snapshot] {
        workouts.map {
            Snapshot(id: $0.id, endDate: $0.endDate, setWeights: $0.setWeights, setReps: $0.setReps,
                     log: $0.loggingDetails)
        }
    }

    // MARK: Time series (for charts)

    /// One data point per logged session: total training volume (kg) over time,
    /// oldest → newest. Sessions with no weighted volume are omitted.
    static func volumeSeries(from history: [Snapshot]) -> [(date: Date, volumeKg: Double)] {
        history
            .map { (date: $0.endDate, volumeKg: volumeKilograms($0)) }
            .filter { $0.volumeKg > 0 }
            .sorted { $0.date < $1.date }
    }

    /// Best (max) weight logged for one exercise per session, oldest → newest.
    /// The basis for a per-exercise strength-progression chart.
    static func bestWeightSeries(forExerciseID id: String,
                                 from history: [Snapshot]) -> [(date: Date, weightKg: Double)] {
        history
            .compactMap { snap -> (date: Date, weightKg: Double)? in
                guard let best = snap.workingSets(id).map(\.kg).max(), best > 0 else { return nil }
                return (date: snap.endDate, weightKg: best)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: Estimated 1RM

    /// The weight that set would allow for one rep (Epley). Nil without a
    /// weight, or above 12 reps, where the estimate stops being meaningful.
    static func estimatedOneRepMaxKg(kg: Double, reps: Int) -> Double? {
        guard kg > 0, (1...12).contains(reps) else { return nil }
        return reps == 1 ? kg : kg * (1 + Double(reps) / 30)
    }

    /// The best estimated 1RM among a session's working sets of `id`.
    static func bestE1RM(forExerciseID id: String, in snapshot: Snapshot) -> Double? {
        snapshot.workingSets(id).compactMap { estimatedOneRepMaxKg(kg: $0.kg, reps: $0.reps) }.max()
    }

    /// Best estimated 1RM per session, oldest → newest — the chart alternative
    /// to best weight, which a lighter set for more reps doesn't move.
    static func e1RMSeries(forExerciseID id: String,
                           from history: [Snapshot]) -> [(date: Date, weightKg: Double)] {
        history
            .compactMap { snap in bestE1RM(forExerciseID: id, in: snap).map { (date: snap.endDate, weightKg: $0) } }
            .sorted { $0.date < $1.date }
    }

    // MARK: Recent sessions

    /// One earlier session of an exercise, for the "last sessions" peek.
    struct ExerciseSession: Identifiable {
        let id: String
        let date: Date
        let sets: [LoggedSet]
        let bestE1RM: Double?
        let note: String?
    }

    /// The newest `limit` sessions that logged `id`, newest first.
    static func recentSessions(forExerciseID id: String, in history: [Snapshot], limit: Int = 3) -> [ExerciseSession] {
        history
            .filter { !$0.sets(id).isEmpty }
            .sorted { $0.endDate > $1.endDate }
            .prefix(limit)
            .map { snap in
                let note = snap.log.exerciseNotes[id].flatMap { $0.isEmpty ? nil : $0 }
                return ExerciseSession(id: snap.id, date: snap.endDate, sets: snap.sets(id),
                                       bestE1RM: bestE1RM(forExerciseID: id, in: snap), note: note)
            }
    }
}
