//
//  Plan.swift
//  Workout App
//
//  Created by Justus Besser on 28.02.24.
//
//

import Foundation
import SwiftData
import CoreData

@Model public class Plan {
    public var id: String = UUID().uuidString
    var difficulty: String = ""
    var difficultyInt: Int = 2
    var goal: Int = 100
    var infoText: String = ""
    var isUserGenerated: Bool = false
    var muscleGroup: Int = 100
    var name: String = ""
    var isNew: Bool = true
    var isSaved: Bool = false
    /// Retires a preset plan from discovery surfaces without deleting it. See
    /// `Workout.isHidden` for the same rationale.
    var isHidden: Bool = false
    /// When the plan was created; nil for plans from before 1.2. Optional, so
    /// it's CloudKit-migration-safe (additive schema change) — but it has to
    /// be deployed to the Production schema before a release uses it.
    var createdAt: Date?

    /// Newest first; plans without a creation date keep a stable alphabetical
    /// order behind the dated ones. Same rule as `Workout.newestFirst`.
    static func newestFirst(_ lhs: Plan, _ rhs: Plan) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// User-facing, localized plan title. `name` stores a localization key for seeded
    /// plans or raw text for user-generated ones; `NSLocalizedString` returns the input
    /// unchanged when it isn't a catalog key. A built-in plan's level is
    /// shown on its own, not in its name (`CatalogName`).
    var displayName: String {
        let shown = isUserGenerated ? name : CatalogName.withoutLevel(name) ?? name
        return NSLocalizedString(shown, comment: "Plan name")
    }

    /// User-facing, localized plan description. See `displayName`.
    var displayInfoText: String { NSLocalizedString(infoText, comment: "Plan description") }

    /// User-facing, localized difficulty, derived from `difficultyInt`. The
    /// stored `difficulty` string was localized once when the plan was
    /// created, so it shows in whatever language the app had back then.
    var displayDifficulty: String { DifficultyLevel.name(for: difficultyInt) }

    @Attribute
    private var intervalData: Data = Data()
    
    var interval: [String: Date] {
        get {
            guard !intervalData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String: Date].self, from: intervalData)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                intervalData = encoded
            } else {
                intervalData = Data()
            }
        }
    }
    
    var intervalType: String = ""
    
    // Handle notificationIDs manually
    @Attribute
    private var notificationIDsData: Data = Data()
    
    var notificationIDs: [String] {
        get {
            guard !notificationIDsData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String].self, from: notificationIDsData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                notificationIDsData = encoded
            } else {
                notificationIDsData = Data()
            }
        }
    }
    
    // Handle finishedWorkoutsSequence manually
    @Attribute
    private var finishedWorkoutsSequenceData: Data = Data()
    
    var finishedWorkoutsSequence: [String] {
        get {
            guard !finishedWorkoutsSequenceData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String].self, from: finishedWorkoutsSequenceData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                finishedWorkoutsSequenceData = encoded
            } else {
                finishedWorkoutsSequenceData = Data()
            }
        }
    }
    
    // Handle workoutsSequenceIDs manually
    @Attribute
    private var workoutsSequenceIDsData: Data = Data()
    
    var workoutsSequenceIDs: [String] {
        get {
            guard !workoutsSequenceIDsData.isEmpty,
                  let decoded = try? JSONDecoder().decode([String].self, from: workoutsSequenceIDsData)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                workoutsSequenceIDsData = encoded
            } else {
                workoutsSequenceIDsData = Data()
            }
        }
    }
    
    @Relationship(deleteRule: .noAction, inverse: \Workout.plan)
    var workouts: [Workout]?
    
    public init(id: String = UUID().uuidString, goal: Int, infoText: String, muscleGroup: Int, name: String, isNew: Bool = true, isSaved: Bool = false, difficultyInt: Int = 2, workouts: [Workout] = [], interval: [String: Date], intervalType: String, notificationIDs: [String] = [], isUserGenerated: Bool = false, workoutsSequenceIDs: [String] = [], finishedWorkoutsSequence: [String] = [], workoutsInPlan: [Workout] = []) {
        self.id = id
        self.goal = goal
        self.infoText = infoText
        self.isUserGenerated = isUserGenerated
        self.muscleGroup = muscleGroup
        self.name = name
        self.isNew = isNew
        self.isSaved = isSaved
        self.workouts = workouts
        self.difficultyInt = difficultyInt
        self.interval = interval
        self.intervalType = intervalType
        self.notificationIDs = notificationIDs // This will trigger the setter
        self.workoutsSequenceIDs = workoutsSequenceIDs // This will trigger the setter
        self.finishedWorkoutsSequence = finishedWorkoutsSequence // This will trigger the setter
        self.createdAt = Date()
    }
}

extension Plan {
    /// Whether each slot of `workoutsSequenceIDs` is done. A workout can be in
    /// a plan more than once: each entry in `finishedWorkoutsSequence` marks
    /// one of its slots done, earliest first.
    var completedSlots: [Bool] {
        var finished = finishedWorkoutsSequence.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return workoutsSequenceIDs.map { id in
            guard let count = finished[id], count > 0 else { return false }
            finished[id] = count - 1
            return true
        }
    }

    /// Index in `workoutsSequenceIDs` of the first slot not done yet, or nil
    /// once every slot is done. Pass `existingIDs` to skip ids whose workout
    /// no longer exists (deleted before deletes cleaned up plans), so such a
    /// plan doesn't get stuck.
    func firstIncompleteSlot(existingIDs: Set<String>? = nil) -> Int? {
        let ids = workoutsSequenceIDs
        let done = completedSlots
        return ids.indices.first { !done[$0] && (existingIDs?.contains(ids[$0]) ?? true) }
    }

    /// The workout id of `firstIncompleteSlot`.
    func firstIncompleteWorkoutID(existingIDs: Set<String>? = nil) -> String? {
        firstIncompleteSlot(existingIDs: existingIDs).map { workoutsSequenceIDs[$0] }
    }

    /// Marks `workoutID` done in each of the user's plans (created or saved)
    /// whose next workout it is, wherever the workout was started (iPhone
    /// workout list, For You, or the watch's plan row). Never skips ahead and
    /// never touches preset plans the user hasn't saved. Returns the plans
    /// it credited, so the summary can say so and offer an undo.
    @discardableResult
    static func recordCompletion(ofWorkoutID workoutID: String, in plans: [Plan],
                                 existingIDs: Set<String>? = nil) -> [Plan] {
        var credited: [Plan] = []
        for plan in plans where (plan.isUserGenerated || plan.isSaved) && !plan.isHidden
            && plan.firstIncompleteWorkoutID(existingIDs: existingIDs) == workoutID {
            plan.finishedWorkoutsSequence.append(workoutID)
            credited.append(plan)
        }
        return credited
    }

    /// Reverts `recordCompletion` for one plan (the summary's Undo).
    func undoCompletion(ofWorkoutID workoutID: String) {
        guard let index = finishedWorkoutsSequence.lastIndex(of: workoutID) else { return }
        finishedWorkoutsSequence.remove(at: index)
    }

    /// Drops a deleted workout from this plan's sequence and progress.
    func removeWorkoutID(_ id: String) {
        if workoutsSequenceIDs.contains(id) {
            workoutsSequenceIDs.removeAll { $0 == id }
        }
        if finishedWorkoutsSequence.contains(id) {
            finishedWorkoutsSequence.removeAll { $0 == id }
        }
    }
}
