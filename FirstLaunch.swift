//
//  FirstLaunch.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 05.04.23.
//

import Foundation
import HealthKit
import SwiftUI
import SwiftData

enum PlanGoal: Int, CaseIterable {
    
    case muscleBuilding = 1
    case strengthTraining = 2
    case weightLoss = 3
    case enduranceAndStamina = 4
    case flexibilityAndMobility = 5
    case functionalFitness = 6
    case sportSpecificTraining = 7
    case rehabilitationAndInjuryPrevention = 8
    case mindBodyConnection = 9
    case overallHealthAndWellness = 10
    case other = 100
    
    var displayName: String {
        let name: String
        
        switch self {
        case .muscleBuilding:                       name = "Muscle Building"
        case .strengthTraining:                     name = "Strength Training"
        case .weightLoss:                           name = "Weight Loss"
        case .enduranceAndStamina:                  name = "Endurance and Stamina"
        case .flexibilityAndMobility:               name = "Flexibility and Mobility"
        case .functionalFitness:                    name = "Functional Fitness"
        case .sportSpecificTraining:                name = "Sport-Specific Training"
        case .rehabilitationAndInjuryPrevention:    name = "Rehabilitation and Injury Prevention"
        case .mindBodyConnection:                   name = "Mind-Body Connection"
        case .overallHealthAndWellness:             name = "Overall Health and Wellness"
        case .other:                                name = "Other"
        }
        
        return NSLocalizedString(name, comment: "\(self), goal")
    }
    
    static func getGoalName(from rawValue: Int) -> String {
        return PlanGoal(rawValue: rawValue)?.displayName ?? PlanGoal.other.displayName
    }
}

enum WorkoutCategory: Int, CaseIterable {
    case fullbody = 1
    case upperbody = 2
    case arms = 3
    case back = 4
    case legs = 5
    case core = 6
    case chest = 7
    case shoulders = 8
    case cardio = 9
    case hiit = 10
    case yoga = 11
    case mobilityFlexibility = 12
    case undefined = 100

    /// Cardio/HIIT intervals, yoga poses and mobility work: no weights, and
    /// their timed exercises run for the workout's own pose or interval length.
    static let nonWeighted: Set<Int> = [
        cardio.rawValue, hiit.rawValue, yoga.rawValue, mobilityFlexibility.rawValue
    ]

    /// Whether a workout of `muscleGroup` holds its timed exercises — a plank,
    /// a hang — for a length set per exercise (`ExercisePlan.seconds`).
    static func holdsTimedExercises(_ muscleGroup: Int) -> Bool {
        !nonWeighted.contains(muscleGroup)
    }
    
    var displayName: String {
        let name: String
        
        switch self {
        case .fullbody:             name = "Full body"
        case .upperbody:            name = "Upper body"
        case .cardio:               name = "Cardio"
        case .arms:                 name = "Arms"
        case .back:                 name = "Back"
        case .legs:                 name = "Legs"
        case .core:                 name = "Core"
        case .chest:                name = "Chest"
        case .shoulders:            name = "Shoulders"
        case .mobilityFlexibility:  name = "Mobility/Flexibility"
        case .undefined:            name = "Undefined"
        case .hiit:                 name = "HIIT"
        case .yoga:                 name = "Yoga"
        }
        
        return NSLocalizedString(name, comment: "\(self), muscleGroup")
    }
    
    var symbolName: String {
        switch self {
        case .fullbody:             return "figure.strengthtraining.functional"
        case .upperbody:            return "figure.arms.open"
        case .arms:                 return "dumbbell.fill"
        case .back:                 return "figure.rower"
        case .legs:                 return "figure.step.training"
        case .core:                 return "figure.core.training"
        case .chest:                return "figure.strengthtraining.traditional"
        case .shoulders:            return "figure.cooldown"
        case .cardio:               return "figure.mixed.cardio"
        case .hiit:                 return "figure.highintensity.intervaltraining"
        case .yoga:                 return "figure.yoga"
        case .mobilityFlexibility:  return "figure.flexibility"
        case .undefined:            return "questionmark"
        }
    }

    /// The category's shade of the accent (`Theme.tone`), the same wherever
    /// it shows, so lists of workouts aren't one color repeated.
    var tone: Int {
        switch self {
        case .fullbody, .undefined:         return 0
        case .upperbody, .core, .mobilityFlexibility: return 1
        case .arms, .chest, .hiit:          return 2
        case .back, .shoulders, .yoga:      return 3
        case .legs, .cardio:                return 4
        }
    }

    static func tone(from rawValue: Int) -> Int {
        WorkoutCategory(rawValue: rawValue)?.tone ?? 0
    }
    
    static func getCategoryName(from rawValue: Int) -> String {
        return WorkoutCategory(rawValue: rawValue)?.displayName ?? WorkoutCategory.undefined.displayName
    }
    
    static func getSymbolName(from rawValue: Int) -> String {
        return WorkoutCategory(rawValue: rawValue)?.symbolName ?? WorkoutCategory.undefined.symbolName
    }
}

enum Equipment: Int, CaseIterable {
    case exerciseMat = 1
    case dumbbells = 2
    case kettlebells = 3
    case resistanceBands = 4
    case battleRopes = 5
    case barbells = 6
    case weightBench = 7
    case jumpRope = 8
    case pullUpBar = 9
    case medicineBall = 10
    case yogaBlocks = 11
    case yogaStrap = 12
    case stabilityBall = 13
    case foamRoller = 14
    case boxStepPlatform = 15
    case glovesWristWraps = 16
    case boxingGlovesPunchingBag = 17
    case ezBar = 18
    case cableMaschine = 19
    case legPressMaschine = 20
    case rowingMaschine = 21
    case stationaryBike = 22
    case treadmill = 23
    case stairClimber = 24
    case elliptical = 25
    case sled = 26
    case smithMaschine = 27
    case skiErg = 28
    case other = 100
    
    var displayName: String {
        let name: String
        
        switch self {
        case .exerciseMat:               name = "Exercise Mat"
        case .dumbbells:                 name = "Dumbbells"
        case .kettlebells:               name = "Kettlebells"
        case .resistanceBands:           name = "Resistance Bands"
        case .battleRopes:               name = "Battle Ropes"
        case .barbells:                  name = "Barbells"
        case .weightBench:               name = "Weight Bench"
        case .jumpRope:                  name = "Jump Rope"
        case .pullUpBar:                 name = "Pull-up Bar"
        case .medicineBall:              name = "Medicine Ball"
        case .yogaBlocks:                name = "Yoga Blocks"
        case .yogaStrap:                 name = "Yoga Strap"
        case .stabilityBall:             name = "Stability Ball"
        case .foamRoller:                name = "Foam Roller"
        case .boxStepPlatform:           name = "Box/Step Platform"
        case .glovesWristWraps:          name = "Gloves/Wrist Wraps"
        case .boxingGlovesPunchingBag:   name = "Boxing Gloves/Punching Bag"
        case .ezBar:                     name = "Ez Bar"
        case .cableMaschine:             name = "Cable Maschine"
        case .legPressMaschine:          name = "Leg Press Maschine"
        case .rowingMaschine:            name = "Rowing Maschine"
        case .stationaryBike:            name = "Stationary Bike"
        case .treadmill:                 name = "Treadmill"
        case .stairClimber:              name = "Stair Climber"
        case .elliptical:                name = "Elliptical"
        case .sled:                      name = "Sled"
        case .smithMaschine:             name = "Smith Maschine"
        case .skiErg:                    name = "Ski Erg"
        case .other:                     name = "Other"
        }
        
        return NSLocalizedString(name, comment: "\(self), equipment")
    }
    
    var symbolName: String {
        switch self {
        case .dumbbells:
            return "dumbbells"
        case .kettlebells:
            return "kettlebells"
        case .resistanceBands:
            return "resistanceBands"
        case .battleRopes:
            return "battleRopes"
        case .exerciseMat:
            return "exerciseMat"
        case .barbells:
            return "barbells"
        case .weightBench:
            return "weightBench"
        case .jumpRope:
            return "jumpRope"
        case .pullUpBar:
            return "pullUpBar"
        case .medicineBall:
            return "medicineBall"
        case .yogaBlocks:
            return "yogaBlocks"
        case .yogaStrap:
            return "yogaStrap"
        case .stabilityBall:
            return "stabilityBall"
        case .foamRoller:
            return "foamRoller"
        case .boxStepPlatform:
            return "yogaBlocks"
        case .glovesWristWraps:
            return "glovesAndWristWraps"
        case .boxingGlovesPunchingBag:
            return "boxingGlovesAndPunchingBag"
        case .ezBar:
            return "ezBar"
        case .cableMaschine:
            return "cableMaschine"
        case .legPressMaschine:
            return "legPressMaschine"
        case .rowingMaschine:
            return "rowingMaschine"
        case .stationaryBike:
            return "stationaryBike"
        case .treadmill:
            return "stationaryBike"
        case .stairClimber:
            return "stationaryBike"
        case .elliptical:
            return "stationaryBike"
        case .sled:
            return "battleRopes"
        case .smithMaschine:
            return "barbells"
        case .skiErg:
            return "rowingMaschine"
        case .other:
            return "questionmark"
        }
    }
    
    static func getEquipment(from rawValue: Int) -> Equipment? {
        return Equipment(rawValue: rawValue)
    }

    static func getEquipmentName(from rawValue: Int) -> String {
        return Equipment(rawValue: rawValue)?.displayName ?? Equipment.other.displayName
    }
    
    static func getEquipmentNames(from rawValues: [Int]) -> [String] {
        return rawValues.map { Equipment(rawValue: $0)?.displayName ?? Equipment.other.displayName }
    }
    
    static var allDisplayNames: [String] {
        return Equipment.allCases.map { $0.displayName }
    }
}

/// One-shot guard so `.onAppear` re-firing on every tab switch doesn't
/// re-run the seeding/dedup pipeline.
@MainActor private var firstLaunchDidRun = false

@MainActor
func firstLaunch(modelContext: ModelContext) {
    guard !firstLaunchDidRun else { return }
    firstLaunchDidRun = true

    let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "firstLaunch")

    // Trust the UserDefaults flag as the source of truth for "this device
    // has been seeded." The previous `hasData` check would race a fresh
    // install: CloudKit Import takes 30+ seconds to pull existing iCloud
    // data, the local store is empty during that window, and the else
    // branch would fire a heavy seed-insert + save. That export collided
    // with the in-flight import, kept the CoreData CloudKit background
    // task alive far longer than needed, and saturated IDS bandwidth —
    // which is what was breaking WCSession on real devices (timeouts
    // never reproduced in simulator because the sim has no iCloud data
    // to import).
    if hasLaunchedBefore {
        // Rewrite any seed names/descriptions that were frozen in a specific
        // language (older builds stored the resolved NSLocalizedString value)
        // back to their localization key, so they follow the device language.
        migrateSeedTextToKeys(modelContext: modelContext)
        // One-time backfill of rep counts onto already-seeded strength exercises.
        migrateSeedExerciseRepCounts(modelContext: modelContext)
        // Idempotent and cheap when there are no duplicates.
        deduplicateExercises(modelContext: modelContext)
        deduplicateWorkouts(modelContext: modelContext)
        deduplicatePlans(modelContext: modelContext)
    } else {
        // Clean up any existing non-user-generated data to prevent duplicates
        // (e.g., from CloudKit syncing old records back after a reset),
        // then seed the preloaded library.
        removePreloadedContent(modelContext: modelContext)
        seedDefaultContent(modelContext: modelContext)

        // MARK: Setting up SettingsManager
        UserDefaults.init().setValue(Int(5), forKey: "pauseTime")
        UserDefaults.init().setValue(false, forKey: "notifications")
        UserDefaults.init().setValue(false, forKey: "accessHealthKitSucceeded")

        appLog("this is a first launch")

        UserDefaults.standard.set(true, forKey: "firstLaunch")
        // Nothing is "new" to someone who just installed the app; the
        // first-run setup is for them instead.
        WhatsNew.markSeen()
        SettingsManager.shared.showsOnboarding = true
    }

    // Insert new catalog exercises into the browsable library and correct any
    // mis-filed muscle groups — for both fresh and existing installs
    // (version-gated, idempotent).
    syncSeedExerciseCatalog(modelContext: modelContext)

    // Sled and Smith-machine exercises used to count as bodyweight, so saved
    // sessions added the body mass to their volume. Needs the catalog's
    // equipment in place, hence after the sync above.
    repairSmithSledBodyweightLogs(modelContext: modelContext)

    // Retrofit existing installs' preset Workout/Plan catalog to the reworked
    // content (renames, retags, hides, plan-membership fixes) — for both fresh
    // and existing installs (version-gated, idempotent). Must run after the
    // migrations above so it sees normalized, deduplicated seed names.
    syncPresetCatalogV1(modelContext: modelContext)

    // Retire the legacy hand-authored catalog entirely in favor of the
    // template-generated one (version-gated, idempotent). Must run after
    // syncPresetCatalogV1 so any last-minute renames it applied are already
    // reflected before the wholesale hide.
    syncPresetCatalogV2(modelContext: modelContext)

    // Rebuild that catalog from the hand-authored session blueprints — the
    // algorithmically-picked sessions v2 shipped weren't worth training
    // (version-gated, idempotent). Runs last so it reconciles the final state.
    syncPresetCatalogV3(modelContext: modelContext)

    deleteFinishedSessionWorkouts(modelContext: modelContext)
}

/// For You and goal sessions run on a hidden workout made for them
/// (`ForYouView.startGymWorkout`, `startSession`). Once the session is over,
/// nothing needs it — the history keeps its own record — but every session
/// left another one in iCloud. Deletes them after half a day, so a session
/// still running on another device keeps its workout; not the one being
/// resumed, nor one a plan uses. One the summary made the user's own isn't
/// hidden any more.
@MainActor
private func deleteFinishedSessionWorkouts(modelContext: ModelContext) {
    let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.isHidden && $0.isUserGenerated })
    let sessionWorkouts = (try? modelContext.fetch(descriptor)) ?? []
    guard !sessionWorkouts.isEmpty else { return }
    let cutoff = Date.now.addingTimeInterval(-12 * 3600)
    let planned = Set(((try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []).flatMap(\.workoutsSequenceIDs))
    let resuming = SettingsManager.shared.resumeSnapshot?.workoutID
    var deleted = 0
    for workout in sessionWorkouts
    where !planned.contains(workout.id) && workout.id != resuming && (workout.createdAt ?? .distantPast) < cutoff {
        modelContext.delete(workout)
        deleted += 1
    }
    guard deleted > 0 else { return }
    try? modelContext.save()
    appLog("Deleted \(deleted) finished session workouts")
}

/// Deletes all preloaded (non-user-generated) workouts and plans, plus seed
/// exercises that aren't attached to any user-generated workout. Used on first
/// launch (to clear CloudKit re-imports) and by Settings → restore.
@MainActor
func removePreloadedContent(modelContext: ModelContext) {
    let existingWorkouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
    for workout in existingWorkouts where !workout.isUserGenerated {
        modelContext.delete(workout)
    }
    let existingPlans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
    for plan in existingPlans where !plan.isUserGenerated {
        NotificationManager.shared.cancelReminders(for: plan)
        modelContext.delete(plan)
    }
    let existingExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    for exercise in existingExercises {
        // Only delete exercises not attached to any user-generated workout AND
        // not referenced by a user's completed-workout history — that relationship
        // is live (not a snapshot), so deleting one still in FinishedWorkout.exercises
        // would blank part of the user's history display.
        let isOnlyInSeedWorkouts = exercise.workouts?.allSatisfy { !$0.isUserGenerated } ?? true
        let isUnusedInHistory = exercise.finishedWorkouts?.isEmpty ?? true
        if isOnlyInSeedWorkouts && isUnusedInHistory {
            modelContext.delete(exercise)
        }
    }
    try? modelContext.save()
}

/// Deletes all user-created workouts and plans, plus custom exercises that are
/// no longer referenced by any workout or workout history. Preloaded content
/// and the workout protocol (FinishedWorkout) are untouched.
@MainActor
func deleteCustomContent(modelContext: ModelContext) {
    let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
    for workout in workouts where workout.isUserGenerated {
        modelContext.delete(workout)
    }
    let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
    for plan in plans where plan.isUserGenerated {
        NotificationManager.shared.cancelReminders(for: plan)
        modelContext.delete(plan)
    }
    try? modelContext.save()

    // Custom exercises (no seed id) that just lost their last workout and
    // never appear in a finished workout are orphans — remove them too.
    let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    for exercise in exercises where !exercise.id.hasPrefix("seed-exercise-") {
        let isUnused = (exercise.workouts?.isEmpty ?? true) && (exercise.finishedWorkouts?.isEmpty ?? true)
        if isUnused {
            modelContext.delete(exercise)
        }
    }
    try? modelContext.save()
}

/// Inserts the full preloaded exercise / workout / plan library. Runs on
/// first launch and from Settings → restore.
func seedDefaultContent(modelContext: ModelContext) {
    seedTemplateCatalog(modelContext: modelContext, existingExercises: [])

    do {
        try modelContext.save()
    } catch {
        appLog("Error in saving preloaded data: \(error)")
    }
}

// MARK: - Template Catalog

/// Builds the full preset catalog (30 workouts, 12 plans — see
/// `Workout/ExerciseCatalog.swift` for the hand-authored session blueprints
/// behind each one) as a single source of truth, called from both the
/// fresh-install path (`seedDefaultContent`) and the existing-install
/// migrations (`syncPresetCatalogV2` / `syncPresetCatalogV3`).
///
/// Inserts a `Workout`/`Plan` whose stable id doesn't exist yet, and
/// *reconciles* one that does back to the current blueprint — insert-only
/// seeding meant an existing install kept whatever content it was first
/// seeded with forever, so a fixed workout only ever reached new users.
/// Reconciliation is field-by-field and skips anything already correct, so
/// repeat calls are cheap and produce no spurious CloudKit writes.
@discardableResult
func seedTemplateCatalog(modelContext: ModelContext, existingExercises: [Exercise]) -> (workouts: [Workout], plans: [Plan]) {
    let existingWorkouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
    let existingPlans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
    var workoutByID = Dictionary(existingWorkouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var planByID = Dictionary(existingPlans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // The exercise pool to reuse when materializing a blueprint. Callers on the
    // fresh-install path pass an empty array; reconciling an existing install
    // needs the real library or every workout would insert duplicate rows.
    var exercisePool = existingExercises
    if exercisePool.isEmpty {
        exercisePool = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    }
    var didChange = false

    func workoutID(_ template: CatalogTemplate, _ tier: CatalogTier) -> String {
        "seed-workout-\(template.rawValue)-\(tier.nameKeyComponent.lowercased())"
    }
    func workoutID(_ tier: YogaMobilityTier) -> String {
        "seed-workout-yogaMobility-\(tier.nameKeyComponent.lowercased())"
    }
    func difficultyLabel(for difficultyInt: Int) -> String {
        switch difficultyInt {
        case 1: return NSLocalizedString("easy", comment: "easy Difficulty (Plan)")
        case 3: return NSLocalizedString("hard", comment: "hard Difficulty (Plan)")
        default: return NSLocalizedString("medium", comment: "medium Difficulty (Plan)")
        }
    }

    /// Brings an already-seeded workout back in line with its blueprint. Only
    /// touches preset rows — a user who saved or re-planned one keeps that,
    /// since `isSaved`/`plan` membership aren't part of the blueprint.
    func reconcile(_ workout: Workout, to blueprint: CatalogWorkoutPlan) {
        guard !workout.isUserGenerated else { return }
        let entities = blueprint.exercises.map { $0.materialize(in: modelContext, existing: exercisePool) }
        for entity in entities where !exercisePool.contains(where: { $0.id == entity.id }) {
            exercisePool.append(entity)
        }
        let desiredIDs = entities.map(\.id)

        if workout.name != blueprint.nameKey { workout.name = blueprint.nameKey; didChange = true }
        if workout.infoText != blueprint.infoTextKey { workout.infoText = blueprint.infoTextKey; didChange = true }
        if workout.shortInfo != blueprint.shortInfo { workout.shortInfo = blueprint.shortInfo; didChange = true }
        if workout.muscleGroup != blueprint.muscleGroup { workout.muscleGroup = blueprint.muscleGroup; didChange = true }
        if workout.setLength != blueprint.setLength { workout.setLength = blueprint.setLength; didChange = true }
        if workout.straightSets != blueprint.straightSets { workout.straightSets = blueprint.straightSets; didChange = true }
        if workout.duration != blueprint.durationMinutes { workout.duration = blueprint.durationMinutes; didChange = true }
        if workout.difficultyInt != blueprint.difficultyInt { workout.difficultyInt = blueprint.difficultyInt; didChange = true }
        if workout.difficulty != difficultyLabel(for: blueprint.difficultyInt) {
            workout.difficulty = difficultyLabel(for: blueprint.difficultyInt); didChange = true
        }
        if workout.workoutActivityType != Int(blueprint.workoutActivityType.rawValue) {
            workout.workoutActivityType = Int(blueprint.workoutActivityType.rawValue); didChange = true
        }
        if workout.exercisesSequenceID != desiredIDs {
            workout.exercisesSequenceID = desiredIDs
            workout.exercises = entities
            didChange = true
        } else if (workout.exercises?.map(\.id) ?? []) != desiredIDs {
            workout.exercises = entities
            didChange = true
        }
        // A retired preset that's back in the catalog must become visible again.
        if workout.isHidden { workout.isHidden = false; didChange = true }
    }

    func makeOrUpdateWorkout(id: String, blueprint: CatalogWorkoutPlan?) {
        guard let blueprint else { return }
        if let existing = workoutByID[id] {
            reconcile(existing, to: blueprint)
        } else {
            let workout = blueprint.makeWorkout(id: id, in: modelContext, existingExercises: exercisePool)
            for entity in workout.exercises ?? [] where !exercisePool.contains(where: { $0.id == entity.id }) {
                exercisePool.append(entity)
            }
            modelContext.insert(workout)
            workoutByID[id] = workout
            didChange = true
        }
    }

    for template in CatalogTemplate.allCases {
        for tier in CatalogTier.allCases {
            makeOrUpdateWorkout(id: workoutID(template, tier),
                                blueprint: CatalogWorkoutBuilder.strengthPlan(template: template, tier: tier))
        }
    }
    for tier in YogaMobilityTier.allCases {
        makeOrUpdateWorkout(id: workoutID(tier), blueprint: CatalogWorkoutBuilder.yogaPlan(tier: tier))
    }

    func makePlan(id: String, name: String, infoText: String, goal: PlanGoal, muscleGroup: Int,
                  difficultyInt: Int, workoutIDs: [String]) {
        let workouts = workoutIDs.compactMap { workoutByID[$0] }
        // A plan whose workouts didn't all resolve would silently ship short.
        guard workouts.count == workoutIDs.count else { return }

        if let plan = planByID[id] {
            guard !plan.isUserGenerated else { return }
            if plan.name != name { plan.name = name; didChange = true }
            if plan.infoText != infoText { plan.infoText = infoText; didChange = true }
            if plan.goal != goal.rawValue { plan.goal = goal.rawValue; didChange = true }
            if plan.muscleGroup != muscleGroup { plan.muscleGroup = muscleGroup; didChange = true }
            if plan.difficultyInt != difficultyInt {
                plan.difficultyInt = difficultyInt
                plan.difficulty = difficultyLabel(for: difficultyInt)
                didChange = true
            }
            if plan.workoutsSequenceIDs != workoutIDs { plan.workoutsSequenceIDs = workoutIDs; didChange = true }
            // Mirror membership onto the `Workout.plan` side, which SwiftData
            // reflects back into `Plan.workouts`.
            let desired = Set(workoutIDs)
            for workout in plan.workouts ?? [] where !desired.contains(workout.id) {
                workout.plan?.removeAll { $0.id == plan.id }
                didChange = true
            }
            for workout in workouts where !(workout.plan?.contains { $0.id == plan.id } ?? false) {
                workout.plan?.append(plan)
                didChange = true
            }
            if plan.isHidden { plan.isHidden = false; didChange = true }
            return
        }

        let plan = Plan(id: id, goal: goal.rawValue, infoText: infoText, muscleGroup: muscleGroup,
                        name: name, difficultyInt: difficultyInt, interval: [:], intervalType: "",
                        isUserGenerated: false, workoutsSequenceIDs: workouts.map(\.id),
                        finishedWorkoutsSequence: [], workoutsInPlan: workouts)
        plan.difficulty = difficultyLabel(for: difficultyInt)
        for workout in workouts { workout.plan?.append(plan) }
        modelContext.insert(plan)
        planByID[id] = plan
        didChange = true
    }

    // MARK: Plans
    //
    // Ordered roughly the way somebody progresses through them. Each one is a
    // full training cycle you repeat, not a ladder you climb once: a two-workout
    // plan means "alternate these two sessions", which is how full-body and
    // upper/lower training actually run.

    // Full body beats a split for a true beginner: every muscle group gets
    // trained two or three times a week, and missing a session doesn't cost you
    // a whole body part. A/B alternate so the movements vary.
    makePlan(id: "seed-plan-full-body-starter", name: "Full Body Starter",
             infoText: "The best place to start. Two alternating full-body sessions built on the basic movement patterns — squat, hinge, press, pull. Run them two or three times a week with a rest day in between.",
             goal: .muscleBuilding, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 1,
             workoutIDs: [workoutID(.fullBodyA, .beginner), workoutID(.fullBodyB, .beginner)])

    makePlan(id: "seed-plan-full-body-strength", name: "Full Body Strength",
             infoText: "Two alternating full-body sessions centred on the barbell lifts. Three sessions a week, adding a little weight whenever you finish all your sets.",
             goal: .strengthTraining, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.fullBodyA, .intermediate), workoutID(.fullBodyB, .intermediate)])

    // Upper/lower reuses the Legs day rather than shipping a near-identical
    // "Lower Body" workout beside it.
    makePlan(id: "seed-plan-upper-lower", name: "Upper / Lower Split",
             infoText: "The classic four-day split: one upper-body session, one lower-body session, each run twice a week. More volume per muscle group than full body, without the schedule a six-day split demands.",
             goal: .muscleBuilding, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.upper, .intermediate), workoutID(.leg, .intermediate)])

    makePlan(id: "seed-plan-upper-lower-advanced", name: "Upper / Lower Strength",
             infoText: "A heavier upper/lower split for experienced lifters, anchored by the squat, bench, deadlift and overhead press. Four sessions a week.",
             goal: .strengthTraining, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 3,
             workoutIDs: [workoutID(.upper, .advanced), workoutID(.leg, .advanced)])

    makePlan(id: "seed-plan-ppl-beginner", name: "Push Pull Legs — Beginner",
             infoText: "Push, pull and legs across three sessions, using machines and dumbbells to keep the technique simple. Run the cycle once or twice a week.",
             goal: .muscleBuilding, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 1,
             workoutIDs: [workoutID(.push, .beginner), workoutID(.pull, .beginner), workoutID(.leg, .beginner)])

    makePlan(id: "seed-plan-ppl-intermediate", name: "Push Pull Legs — Intermediate",
             infoText: "The standard push/pull/legs cycle on barbells and dumbbells. Run it twice a week — six sessions — once you can recover from that.",
             goal: .muscleBuilding, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.push, .intermediate), workoutID(.pull, .intermediate), workoutID(.leg, .intermediate)])

    makePlan(id: "seed-plan-ppl-advanced", name: "Push Pull Legs — Advanced",
             infoText: "High-volume push/pull/legs for experienced lifters, with the deadlift, squat, bench and overhead press anchoring the week.",
             goal: .muscleBuilding, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 3,
             workoutIDs: [workoutID(.push, .advanced), workoutID(.pull, .advanced), workoutID(.leg, .advanced)])

    makePlan(id: "seed-plan-bodyweight-progression", name: "Bodyweight Progression",
             infoText: "Three no-equipment full-body circuits. Start at the level you can finish with good form and move up when it stops being hard.",
             goal: .functionalFitness, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.bodyweightCircuit, .beginner), workoutID(.bodyweightCircuit, .intermediate), workoutID(.bodyweightCircuit, .advanced)])

    makePlan(id: "seed-plan-cardio-progression", name: "Cardio Progression",
             infoText: "Three no-equipment cardio and HIIT sessions, from steady intervals to all-out work. Move up a level when the last one stops leaving you out of breath.",
             goal: .enduranceAndStamina, muscleGroup: WorkoutCategory.cardio.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.cardioHIIT, .beginner), workoutID(.cardioHIIT, .intermediate), workoutID(.cardioHIIT, .advanced)])

    makePlan(id: "seed-plan-core-progression", name: "Core Progression",
             infoText: "Three no-equipment core sessions, from bracing drills to loaded rollouts. Add one to the end of any workout, or run it on its own.",
             goal: .functionalFitness, muscleGroup: WorkoutCategory.core.rawValue, difficultyInt: 2,
             workoutIDs: [workoutID(.core, .beginner), workoutID(.core, .intermediate), workoutID(.core, .advanced)])

    makePlan(id: "seed-plan-no-equipment-starter", name: "No-Equipment Starter",
             infoText: "A complete week with nothing but a floor: a full-body circuit, a core session, a cardio session and a yoga flow to finish.",
             goal: .overallHealthAndWellness, muscleGroup: WorkoutCategory.fullbody.rawValue, difficultyInt: 1,
             workoutIDs: [workoutID(.bodyweightCircuit, .beginner), workoutID(.core, .beginner),
                          workoutID(.cardioHIIT, .beginner), workoutID(.short)])

    makePlan(id: "seed-plan-recovery-flexibility", name: "Recovery & Flexibility",
             infoText: "Two yoga flows and a mobility routine for rest days — for hips, hamstrings and the upper back, the places sitting and lifting both tighten up.",
             goal: .flexibilityAndMobility, muscleGroup: WorkoutCategory.mobilityFlexibility.rawValue, difficultyInt: 1,
             workoutIDs: [workoutID(.short), workoutID(.full), workoutID(.mobility)])

    if didChange {
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving template catalog: \(error)")
        }
    }

    return (Array(workoutByID.values), Array(planByID.values))
}

// MARK: - Seed Localization Migration

/// Default target reps for seeded strength exercises, keyed by stable id.
/// Exercises not listed are time-based (repCount stays 0 — the workout timer
/// drives them): cardio (jumping jacks, sprint, rowing…), isometric holds
/// (plank, wall sit, side plank) and yoga poses.
let seedExerciseRepCounts: [String: Int] = [
    "seed-exercise-pushups": 12,
    "seed-exercise-situps": 15,
    "seed-exercise-squats": 15,
    "seed-exercise-tricep-dips": 12,
    "seed-exercise-lunges": 12,
    "seed-exercise-burpees-with-pushups": 10,
    "seed-exercise-bicycle-crunches": 20,
    "seed-exercise-burpees": 10,
    "seed-exercise-superman": 12,
    "seed-exercise-russian-twists": 20,
    "seed-exercise-bench-press": 8,
    "seed-exercise-deadlifts": 8,
    "seed-exercise-overhead-press": 10,
    "seed-exercise-pull-ups": 8,
    "seed-exercise-kettlebell-swing": 15,
    "seed-exercise-lat-pulldown": 12,
    "seed-exercise-cable-crossover": 12,
    "seed-exercise-leg-press": 12,
    "seed-exercise-hammer-curls": 12,
    "seed-exercise-shoulder-press": 10,
    "seed-exercise-lateral-raise": 12,
    "seed-exercise-skullcrushers": 10,
    "seed-exercise-calf-raise": 15,
    "seed-exercise-romanian-deadlift": 10,
    "seed-exercise-pike-push-up": 8,
    "seed-exercise-dips": 10,
]

/// Localization keys used for seeded workout / exercise / plan names.
private let seedNameKeys: [String] = [
    "Arm Blaster",
    "Athlete Performance Plan",
    "Athletic Conditioning",
    "Back Builder",
    "Balanced Fitness Plan",
    "Battle Ropes",
    "Beginner Strength Plan",
    "Beginner-Leg-Workout",
    "Bench Press",
    "BodyweightStrengthCircuit",
    "Bicycle Crunches",
    "Boxing",
    "Burpees",
    "Burpees with Push-ups",
    "Cable Crossover",
    "Calf Raise",
    "Cardio Plan",
    "Cardio Workout",
    "Cobra Pose",
    "Core Focus Plan",
    "Core Stability",
    "Cycling",
    "Deadlifts",
    "Dips",
    "Downward Facing Dog",
    "Flexibility Plan",
    "Full Body Blast",
    "HIIT-Workout",
    "Hammer Curls",
    "High Knees",
    "IntermediateWorkout",
    "Jump Rope",
    "Jumping Jacks",
    "Kettlebell Circuit",
    "Kettlebell Swing",
    "Lat Pulldown",
    "Lateral Raise",
    "Leg Day",
    "Leg Press",
    "Lunges",
    "MaschineWorkout",
    "Mountain Climbers",
    "Overhead Press",
    "Pike Push-Up",
    "Plank",
    "Pull-ups",
    "Pushups",
    "Relaxing Plan",
    "Romanian Deadlift",
    "Rope Climb",
    "Rowing",
    "Russian Twists",
    "Seated Forward Bend",
    "Shoulder Blast",
    "Shoulder Press",
    "Side Plank",
    "Situps",
    "Skullcrushers",
    "Sprint",
    "Sprint Workout",
    "Squats",
    "Starter Plan",
    "StarterWorkout",
    "Strength Building Plan",
    "Strength Training",
    "Stretching",
    "Sun Salutation",
    "Superman",
    "Tree Pose",
    "Trizep-Dips",
    "Wall Sits",
    "Yoga",
]

/// Localization keys used for seeded workout / plan descriptions (`infoText`).
private let seedInfoTextKeys: [String] = [
    "A strong core is essential for all movement and physical activity. This plan focuses on developing core strength, stability, and endurance through a variety of targeted workouts.",
    "Description of Leg-Training for beginners. This Workout is perfect if you are someone honest, who does not skip the leg day.",
    "Designed for athletes looking to improve their sports performance, this plan combines strength, power, agility, and conditioning to enhance overall athletic capabilities.",
    "Focus on building a strong and stable core with this targeted workout. Core strength is essential for overall fitness and injury prevention.",
    "Focus on your arms with this comprehensive workout targeting biceps, triceps and forearms. Great for developing arm strength and definition.",
    "Getting out of breath too fast? Let's get your lungs burning to get a great stamina that can help you every day.",
    "Never skip leg day! This comprehensive lower body workout targets all major muscle groups in the legs for strength, power and endurance.",
    "Simple sprint Workout for fast paced sprints",
    "Start your strength training journey with this beginner-friendly plan. It focuses on fundamental movements and proper form to build a solid foundation for strength development.",
    "Strength training is a type of exercise that uses resistance to build strength, endurance, and size of muscles. It involves exercises like weight lifting, resistance band training, and bodyweight exercises.",
    "Target your shoulders with this comprehensive workout that focuses on all three deltoid heads. Perfect for building strong, defined shoulders.",
    "The Full Body Blast workout is a total body workout that targets all your major muscle groups. It's perfect for those who want to get a quick and effective workout in.",
    "The Highintesive Intervaltriainig is a Workout-type that doesn't need that much time but everyone gets out of breath. If you do not have much time but want to do something, this is the perfect Workout for you.",
    "The Starter Workout is designed specifically for beginners. With a short duration and simple exercises, it's manageable for almost anyone. If it feels too easy, you can immediately move on to a harder workout or repeat it.",
    "The perfect routine after you burned your muscles to recover properly",
    "This Plan is designed to help you relax and rejuvenate. It is a great way to reduce stress and tension.",
    "This Plan is perfect if you want to get into regular working out. With plans, you have a plan designed for your needs and a goal to archieve.",
    "This athletic conditioning workout focuses on power, agility, and explosive strength. Great for athletes looking to improve sports performance.",
    "This back-focused workout targets all the major muscles in your back for improved posture, strength and definition. A strong back is essential for overall upper body strength.",
    "This balanced fitness plan provides a well-rounded approach to overall health and fitness. It includes a mix of strength, cardio, flexibility, and core work for comprehensive fitness development.",
    "This bodyweight strength circuit challenges every major muscle group using nothing but your own body weight. It's intense — if you're just getting started, try an easier workout first.",
    "This cardio workout is designed to improve your cardiovascular health and burn calories. It consists of a variety of high-intensity exercises that will get your heart rate up and challenge your endurance.",
    "This comprehensive strength plan focuses on building functional strength across all major muscle groups. Follow this plan to increase your overall strength and muscle development.",
    "This kettlebell circuit workout combines strength and cardio for an efficient total body workout. The kettlebell is a versatile tool that provides both resistance and momentum challenges.",
    "This maschine-workout is for those who want to challenge themselves. It is for maschines! Many exercises that challange everyone. If you are not yet fit, you should probably try a simpler workout.",
    "With this intermediate workout, you will see progress easily. The exercises are not too difficult, but challenging enough to motivate you.",
    "Yoga is a physical, mental, and spiritual practice that originated in ancient India. It involves a series of postures, breathing exercises, and meditation techniques designed to promote relaxation, flexibility, strength, and balance.",
    "You feel rusty and have problems moving through your full range of motion? This plan focuses on improving flexibility and mobility through a variety of dynamic and static stretches.",
]

/// Stored values from older builds that no longer match the current catalog
/// rendering (e.g. German text that has since been reworded) mapped to their
/// current localization key.
private let legacySeedTextOverrides: [String: String] = [
    "Das Starter-Workout ist ein Workout, dass speziell für Einsteiger konzipiert wurde. Mit einer kurzen Dauer und einfachen Übungen ist das Workout für fast jeden zu meistern. Für wen das Workout zu leicht ist, kann sofort ein schwierigeres Workout anhängen oder es wiederholen.":
        "The Starter Workout is designed specifically for beginners. With a short duration and simple exercises, it's manageable for almost anyone. If it feels too easy, you can immediately move on to a harder workout or repeat it.",
]

/// Builds a `localizedValue -> localizationKey` lookup by rendering every seed
/// key in each compiled language bundle. This lets us recognise a frozen name
/// stored in any shipped language and rewrite it to the key.
private func buildSeedTextReverseMap() -> [String: String] {
    let bundles: [Bundle] = ["de", "en", "Base"].compactMap {
        Bundle.main.path(forResource: $0, ofType: "lproj").flatMap(Bundle.init(path:))
    }
    var map: [String: String] = legacySeedTextOverrides
    for key in seedNameKeys + seedInfoTextKeys {
        var variants: Set<String> = [key]
        for bundle in bundles {
            variants.insert(bundle.localizedString(forKey: key, value: key, table: nil))
        }
        for variant in variants where !variant.isEmpty {
            // First writer wins; never let a shared variant overwrite an
            // already-mapped key.
            if map[variant] == nil { map[variant] = key }
        }
    }
    return map
}

/// Rewrites seed names/descriptions that were stored as a resolved localized
/// string (older builds) back to their localization key, so `displayName` /
/// `displayInfoText` follow the current device language. User-generated content
/// is left untouched.
private func migrateSeedTextToKeys(modelContext: ModelContext) {
    let reverse = buildSeedTextReverseMap()
    let nameKeySet = Set(seedNameKeys)
    let infoKeySet = Set(seedInfoTextKeys)
    var didChange = false

    func remap(_ current: String, keySet: Set<String>) -> String? {
        guard !keySet.contains(current) else { return nil } // already a key
        guard let key = reverse[current], keySet.contains(key), key != current else { return nil }
        return key
    }

    if let workouts = try? modelContext.fetch(FetchDescriptor<Workout>()) {
        for workout in workouts where !workout.isUserGenerated {
            if let key = remap(workout.name, keySet: nameKeySet) { workout.name = key; didChange = true }
            if let key = remap(workout.infoText, keySet: infoKeySet) { workout.infoText = key; didChange = true }
        }
    }
    if let plans = try? modelContext.fetch(FetchDescriptor<Plan>()) {
        for plan in plans where !plan.isUserGenerated {
            if let key = remap(plan.name, keySet: nameKeySet) { plan.name = key; didChange = true }
            if let key = remap(plan.infoText, keySet: infoKeySet) { plan.infoText = key; didChange = true }
        }
    }
    if let exercises = try? modelContext.fetch(FetchDescriptor<Exercise>()) {
        for exercise in exercises where exercise.id.hasPrefix("seed-exercise-") {
            if let key = remap(exercise.name, keySet: nameKeySet) { exercise.name = key; didChange = true }
        }
    }

    if didChange {
        try? modelContext.save()
        appLog("Migrated seed names/descriptions to localization keys")
    }
}

/// Backfills default rep counts onto existing seeded strength exercises (matched
/// by stable id). Runs once, guarded by a UserDefaults flag, and only writes when
/// the exercise is still time-based (repCount 0) so it never clobbers a user edit.
private func migrateSeedExerciseRepCounts(modelContext: ModelContext) {
    let flag = "didBackfillSeedExerciseRepCounts"
    guard !UserDefaults.standard.bool(forKey: flag) else { return }

    if let exercises = try? modelContext.fetch(FetchDescriptor<Exercise>()) {
        var didChange = false
        for exercise in exercises {
            if let reps = seedExerciseRepCounts[exercise.id], exercise.repCount == 0 {
                exercise.repCount = reps
                didChange = true
            }
        }
        if didChange {
            try? modelContext.save()
            appLog("Backfilled rep counts on seeded strength exercises")
        }
    }
    UserDefaults.standard.set(true, forKey: flag)
}

/// Keeps the browsable exercise library aligned with `GymExerciseCatalog`:
/// inserts any catalog exercise missing from the store (so newly-added movements
/// appear for existing installs, not only fresh ones) and reconciles every
/// already-seeded row back to its catalog definition — muscle group, equipment,
/// rep count, difficulty, name and symbol — except the fields the user changed
/// (`Exercise.customizedFields`) — plus the calorie rate (kcal/s), which isn't
/// user-editable. Version-gated so it re-runs when the catalog
/// changes; a no-op (aside from the fetch) once everything is in sync.
private func syncSeedExerciseCatalog(modelContext: ModelContext) {
    let versionKey = "seedCatalogVersion"
    let currentVersion = 8
    guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

    let existing = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var didChange = false

    for def in GymExerciseCatalog.all {
        if let exercise = byID[def.id] {
            let customized = exercise.customizedFields
            // Correct the muscle group so it shows under the expected filter.
            if !customized.contains("muscleGroup"), exercise.muscleGroup != def.muscleGroup {
                exercise.muscleGroup = def.muscleGroup
                didChange = true
            }
            // Correct equipment — previously never reconciled here, so ids like
            // bench-press/mountain-climbers could silently drift out of sync
            // with the catalog forever (only muscleGroup/repCount were fixed).
            if !customized.contains("equipment"), exercise.equipment != def.equipment {
                exercise.equipment = def.equipment
                didChange = true
            }
            // Backfill rep count if this was a time-based placeholder.
            if !customized.contains("repCount"), exercise.repCount == 0, def.repCount > 0 {
                exercise.repCount = def.repCount
                didChange = true
            }
            // Correct difficulty — several movements were mis-rated (push-ups
            // as "hard", an all-out sprint as "easy"), which fed straight into
            // which exercises a generated session was allowed to use.
            if !customized.contains("difficulty"), exercise.difficultyInt != def.difficultyInt {
                exercise.difficultyInt = def.difficultyInt
                exercise.difficulty = def.difficultyLabel
                didChange = true
            }
            // Adopt renames ("Trizep-Dips" → "Bench Dips", "Hyperextension" →
            // "Back Extension"). `name` holds the localization key, so this
            // also rewrites rows frozen in the install language — the same job
            // `migrateSeedTextToKeys` does for the older hand-written seeds.
            if !customized.contains("name"), exercise.name != def.name {
                exercise.name = def.name
                didChange = true
            }
            if !customized.contains("symbol"), exercise.symbol != def.symbol {
                exercise.symbol = def.symbol
                didChange = true
            }
            // Fresh installs never got a rate (0), and older ones stored the
            // per-minute figure in this per-second field.
            if exercise.caloriesPerSecond != def.caloriesPerSecond {
                exercise.caloriesPerSecond = def.caloriesPerSecond
                didChange = true
            }
        } else {
            // New movement not yet in the library — insert it so it's browsable.
            let inserted = def.materialize(in: modelContext, existing: [])
            byID[def.id] = inserted
            didChange = true
        }
    }

    if didChange {
        try? modelContext.save()
        appLog("Synced seed exercise catalog (inserts, field fixes, calorie rates)")
    }
    UserDefaults.standard.set(currentVersion, forKey: versionKey)
}

/// Sessions saved while sled (26) and Smith-machine (27) exercises counted as
/// bodyweight list them in `SessionLog.bodyweightExerciseIDs`, so their volume
/// includes the body mass. Drops those ids — only for exercises that still have
/// that equipment, since one the user re-equipped since may really have been
/// bodyweight back then. Runs once; idempotent, so every synced device can.
private func repairSmithSledBodyweightLogs(modelContext: ModelContext) {
    let flag = "didRepairSmithSledBodyweightLogs"
    guard !UserDefaults.standard.bool(forKey: flag) else { return }
    if removeSmithSledFromBodyweightLogs(modelContext: modelContext) {
        try? modelContext.save()
        appLog("Removed sled/Smith-machine exercises from saved bodyweight logs")
    }
    UserDefaults.standard.set(true, forKey: flag)
}

/// The repair itself, without the run-once flag or the save. True when a
/// saved session changed.
func removeSmithSledFromBodyweightLogs(modelContext: ModelContext) -> Bool {
    let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    let affectedIDs = Set(exercises.filter { !Set($0.equipment).isDisjoint(with: [26, 27]) }.map(\.id))

    var didChange = false
    if !affectedIDs.isEmpty {
        for finished in (try? modelContext.fetch(FetchDescriptor<FinishedWorkout>())) ?? [] {
            var log = finished.loggingDetails
            guard !log.bodyweightExerciseIDs.isDisjoint(with: affectedIDs) else { continue }
            log.bodyweightExerciseIDs.subtract(affectedIDs)
            // Same as a new session: the body weight only comes along for a
            // bodyweight exercise.
            if log.bodyweightExerciseIDs.isEmpty { log.bodyWeightKg = nil }
            finished.loggingDetails = log
            didChange = true
        }
    }
    return didChange
}

// MARK: - Preset Catalog Migration

/// Retrofits existing installs' preset `Workout`/`Plan` catalog to match the
/// reworked content in `seedDefaultContent` (renames, retags, hides, and
/// plan-membership fixes) — `seedDefaultContent` only shapes *fresh* installs
/// correctly; this is the update path for everyone else.
///
/// Preset `Workout`/`Plan` ids are historically random UUIDs (unlike `Exercise`,
/// which already used stable `"seed-exercise-*"` ids), so there is no reliable
/// way to identify "the same preset across app versions" except by matching on
/// normalized name — the same technique `deduplicateWorkouts`/`deduplicatePlans`
/// already use. `seedDefaultContent` now assigns stable `"seed-workout-*"` /
/// `"seed-plan-*"` ids going forward, but that only helps installs seeded fresh
/// after this ships — existing installs stay matched by name permanently.
///
/// Never deletes a `Workout`/`Plan` — only mutates fields and relationship
/// membership — so a user's custom `Plan` referencing a retouched preset, or an
/// `isSaved` bookmark on one, keeps resolving. Version-gated and idempotent.
private func syncPresetCatalogV1(modelContext: ModelContext) {
    let versionKey = "presetCatalogVersion"
    let currentVersion = 1
    guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

    let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
    let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []

    func normalized(_ name: String) -> String { name.lowercased().trimmingCharacters(in: .whitespaces) }

    var workoutByName = Dictionary(
        workouts.filter { !$0.isUserGenerated }.map { (normalized($0.name), $0) },
        uniquingKeysWith: { first, _ in first })
    let planByName = Dictionary(
        plans.filter { !$0.isUserGenerated }.map { (normalized($0.name), $0) },
        uniquingKeysWith: { first, _ in first })

    var didChange = false

    // Rewrites a plan's workout membership to exactly the given set (matched by
    // current name). Only mutates the `Workout.plan` side — SwiftData mirrors
    // that into the declared inverse (`Plan.workouts`) automatically, the same
    // way seedDefaultContent already populates it (it passes `workouts: []` to
    // the initializer and relies entirely on `workout.plan?.append(plan)`).
    // Also keeps the redundant `workoutsSequenceIDs` id array in sync — several
    // views (PlanPreview, PlansView, PlansCards, PlanViewModel, AddPlans) read
    // it directly for progress/ordering, so leaving it stale would silently
    // break them.
    func setMembership(of plan: Plan, toWorkoutsNamed names: [String]) {
        let desired = names.compactMap { workoutByName[$0] }
        let desiredIDs = Set(desired.map(\.id))

        for workout in plan.workouts ?? [] where !desiredIDs.contains(workout.id) {
            workout.plan?.removeAll { $0.id == plan.id }
            didChange = true
        }
        for workout in desired where !(workout.plan?.contains { $0.id == plan.id } ?? false) {
            workout.plan?.append(plan)
            didChange = true
        }
        let newSequenceIDs = desired.map(\.id)
        if plan.workoutsSequenceIDs != newSequenceIDs {
            plan.workoutsSequenceIDs = newSequenceIDs
            didChange = true
        }
    }

    // MaschineWorkout → BodyweightStrengthCircuit: it never used a single
    // machine (boxing/pull-ups/situps/squats/dips are all bodyweight), and its
    // "for maniacs only" framing was needlessly intimidating.
    if let bodyweightCircuit = workoutByName["maschineworkout"] {
        bodyweightCircuit.name = "BodyweightStrengthCircuit"
        bodyweightCircuit.infoText = "This bodyweight strength circuit challenges every major muscle group using nothing but your own body weight. It's intense — if you're just getting started, try an easier workout first."
        bodyweightCircuit.shortInfo = "An intense full-body bodyweight circuit."
        didChange = true
        // Re-key so the plan-membership fixes below (which no longer include
        // this workout for Starter/Relaxing) still resolve it under its new name.
        workoutByName["bodyweightstrengthcircuit"] = bodyweightCircuit
    }

    // Thin single-exercise workout, redundant with the Running plan generator,
    // and not referenced by any preset plan — hidden rather than deleted.
    if let sprintWorkout = workoutByName["sprint workout"], !sprintWorkout.isHidden {
        sprintWorkout.isHidden = true
        didChange = true
    }

    // Typo fix ("challanging" → "challenging"); shortInfo is a localization key, so
    // this is safe to always re-apply on preset rows.
    if let hiitWorkout = workoutByName["hiit-workout"], hiitWorkout.shortInfo != "This HIIT-Workout is challenging to anybody!" {
        hiitWorkout.shortInfo = "This HIIT-Workout is challenging to anybody!"
        didChange = true
    }

    // Plan-membership fixes — see seedDefaultContent's inline comments for the
    // rationale behind each of these (mistagged difficulty/theme, or the
    // strengthPlan copy-paste bug that misdirected its inverse relationship).
    if let starterPlan = planByName["starter plan"] {
        setMembership(of: starterPlan, toWorkoutsNamed: ["beginner-leg-workout", "starterworkout", "yoga"])
    }
    if let cardioPlan = planByName["cardio plan"] {
        setMembership(of: cardioPlan, toWorkoutsNamed: ["cardio workout", "hiit-workout", "athletic conditioning"])
    }
    if let relaxingPlan = planByName["relaxing plan"] {
        setMembership(of: relaxingPlan, toWorkoutsNamed: ["yoga", "stretching"])
    }
    if let strengthPlan = planByName["strength building plan"] {
        setMembership(of: strengthPlan, toWorkoutsNamed: ["strength training", "back builder", "shoulder blast", "arm blaster", "leg day", "yoga"])
    }
    if let coreFocusPlan = planByName["core focus plan"] {
        setMembership(of: coreFocusPlan, toWorkoutsNamed: ["core stability", "yoga", "full body blast"])
    }

    if didChange {
        try? modelContext.save()
        appLog("Synced preset catalog to v\(currentVersion)")
    }
    UserDefaults.standard.set(currentVersion, forKey: versionKey)
}

/// Retires every legacy hand-authored preset `Workout`/`Plan` (today's 18
/// workouts + 9 plans, or whatever `syncPresetCatalogV1` already retitled) in
/// favor of the template-generated catalog (`seedTemplateCatalog`, 20
/// workouts + 8 plans). Unlike `syncPresetCatalogV1`'s targeted renames,
/// there's no honest 1:1 mapping from the old hand-picked content to the new
/// template-generated set — every workout's exercises/duration/name changed
/// shape, not just its wording — so this hides everything non-user-generated
/// that doesn't carry one of the new stable id prefixes, wholesale. Never
/// deletes: an existing custom `Plan` referencing a legacy preset, or an
/// `isSaved` bookmark on one, keeps resolving — just invisible in Browse going
/// forward. Version-gated and idempotent.
private func syncPresetCatalogV2(modelContext: ModelContext) {
    let versionKey = "presetCatalogVersion"
    let currentVersion = 2
    guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

    let newIDPrefixes = [
        "seed-workout-push-", "seed-workout-pull-", "seed-workout-leg-",
        "seed-workout-fullBodyA-", "seed-workout-fullBodyB-", "seed-workout-upper-",
        "seed-workout-bodyweightCircuit-", "seed-workout-core-",
        "seed-workout-cardioHIIT-", "seed-workout-yogaMobility-",
        "seed-plan-ppl-", "seed-plan-full-body-", "seed-plan-upper-lower",
        "seed-plan-bodyweight-progression",
        "seed-plan-cardio-progression", "seed-plan-core-progression",
        "seed-plan-no-equipment-starter", "seed-plan-recovery-flexibility"
    ]

    var didChange = false

    let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
    for workout in workouts where !workout.isUserGenerated && !workout.isHidden {
        if !newIDPrefixes.contains(where: { workout.id.hasPrefix($0) }) {
            workout.isHidden = true
            didChange = true
        }
    }
    let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
    for plan in plans where !plan.isUserGenerated && !plan.isHidden {
        if !newIDPrefixes.contains(where: { plan.id.hasPrefix($0) }) {
            plan.isHidden = true
            didChange = true
        }
    }

    // Insert the new template-generated catalog (idempotent on its own).
    let existingExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    seedTemplateCatalog(modelContext: modelContext, existingExercises: existingExercises)

    if didChange {
        try? modelContext.save()
        appLog("Synced preset catalog to v\(currentVersion) (legacy content hidden)")
    }
    UserDefaults.standard.set(currentVersion, forKey: versionKey)
}

/// Rebuilds the preset `Workout`/`Plan` catalog from the reworked, hand-authored
/// session blueprints (`CatalogSessionBlueprints`).
///
/// `syncPresetCatalogV2` shipped a catalog whose sessions were picked by an
/// algorithm that optimised for muscle-group *coverage* and nothing else. The
/// result was content that filled the slots but wasn't worth training: a "Push —
/// Advanced" of cable crossovers, shrugs and four curl variations with no press
/// in it, a "Pull — Beginner" with no pulling movement, and a "Legs — Advanced"
/// carrying two different calf raises but no squat. `seedTemplateCatalog` now
/// reconciles as well as inserts, so this migration just needs to run it once
/// more to pull every existing install onto the reworked content — including
/// the new full-body and upper/lower templates and their plans.
///
/// Never deletes: a custom `Plan` referencing a preset, or an `isSaved` bookmark
/// on one, keeps resolving. Version-gated and idempotent.
private func syncPresetCatalogV3(modelContext: ModelContext) {
    let versionKey = "presetCatalogVersion"
    let currentVersion = 3
    guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }

    // Reconcile against the real exercise library, not an empty array — passing
    // no pool would re-insert every movement as a duplicate row.
    let existingExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
    seedTemplateCatalog(modelContext: modelContext, existingExercises: existingExercises)

    appLog("Synced preset catalog to v\(currentVersion) (rebuilt from session blueprints)")
    UserDefaults.standard.set(currentVersion, forKey: versionKey)
}

// MARK: - Deduplication
//
// Seed content is created on every device with fresh UUIDs, so once CloudKit
// merges two devices' libraries the same preset exists twice. The records
// reference each other mostly through ID lists (`exercisesSequenceID`,
// `workoutsSequenceIDs`, …), not only relationships, so a duplicate can only
// be deleted after every ID list pointing at it has been rewritten to the
// survivor — otherwise workouts lose exercises and plans lose workouts.
//
// The survivor has to be the same on every device: two devices deduping while
// sync is still in flight would otherwise each keep a different copy, delete
// the other one's, and CloudKit would propagate both deletions. So it's picked
// from synced data only: catalog records with fixed IDs ("seed-workout-…")
// win over UUID ones, then the smallest ID.
//
// Hidden presets are left out: they're retired and invisible, and some share
// a name with their visible replacement — merging would delete the new one.
//
// Runs only from `firstLaunch`, before any view has fetched: deleting a model
// a view is still showing crashes SwiftData on the next property read.

private func sortedForDedup<T>(_ items: [T], id: (T) -> String) -> (keeper: T, duplicates: ArraySlice<T>) {
    let sorted = items.sorted {
        let (a, b) = (id($0), id($1))
        let (aIsUUID, bIsUUID) = (UUID(uuidString: a) != nil, UUID(uuidString: b) != nil)
        return aIsUUID != bIsUUID ? bIsUUID : a < b
    }
    return (sorted[0], sorted.dropFirst())
}

private func remapped(_ ids: [String], _ map: [String: String]) -> [String] {
    ids.map { map[$0] ?? $0 }
}

private func remapped<V>(_ dict: [String: V], _ map: [String: String]) -> [String: V] {
    var result: [String: V] = [:]
    // Survivor entries win over a duplicate's when both were logged.
    for (key, value) in dict where map[key] == nil { result[key] = value }
    for (key, value) in dict {
        guard let target = map[key], result[target] == nil else { continue }
        result[target] = value
    }
    return result
}

/// Whether two same-named exercises are interchangeable: everything the user
/// can set when creating or editing one matches. The target weight isn't
/// compared — merging carries it over.
private func hasSameSettings(_ a: Exercise, _ b: Exercise) -> Bool {
    a.repCount == b.repCount
        && (a.duration ?? 0) == (b.duration ?? 0)
        && a.equipment == b.equipment
        && a.muscleGroup == b.muscleGroup
        && a.difficultyInt == b.difficultyInt
}

/// Removes duplicate exercises that share the same name and repoints every
/// workout and history entry at the survivor.
func deduplicateExercises(modelContext: ModelContext) {
    guard let allExercises = try? modelContext.fetch(FetchDescriptor<Exercise>()) else { return }

    var exercisesByName: [String: [Exercise]] = [:]
    for exercise in allExercises {
        let key = exercise.name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        exercisesByName[key, default: []].append(exercise)
    }

    var idMap: [String: String] = [:]
    for (_, exercises) in exercisesByName where exercises.count > 1 {
        let (first, rest) = sortedForDedup(exercises, id: \.id)
        // Only true copies are merged — the same record twice (same id) or a
        // second seeding of it (same settings). Exercises don't record whether
        // the user made them, so a user's own "Squats" with other reps or
        // equipment used to be deleted here for sharing the catalog's name.
        // Each copy merges into the first survivor it copies, in the preferred
        // order, so copies that differ from an edited catalog entry still
        // merge with each other.
        var survivors = [first]
        for duplicate in rest {
            guard let keeper = survivors.first(where: { $0.id == duplicate.id || hasSameSettings(duplicate, $0) }) else {
                survivors.append(duplicate)
                continue
            }
            idMap[duplicate.id] = keeper.id
            // The catalog copy usually survives; don't drop a target weight
            // the user set on the other one.
            if keeper.targetWeightKg == nil { keeper.targetWeightKg = duplicate.targetWeightKg }
            // Assign rather than `keeper.workouts?.append`, which is a no-op
            // while the survivor's relationship is still nil.
            for workout in duplicate.workouts ?? []
            where !(keeper.workouts ?? []).contains(where: { $0.id == workout.id }) {
                keeper.workouts = (keeper.workouts ?? []) + [workout]
            }
            for finished in duplicate.finishedWorkouts ?? []
            where !(keeper.finishedWorkouts ?? []).contains(where: { $0.id == finished.id }) {
                keeper.finishedWorkouts = (keeper.finishedWorkouts ?? []) + [finished]
            }
            modelContext.delete(duplicate)
        }
    }
    guard !idMap.isEmpty else { return }

    for workout in (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? [] {
        let sequence = remapped(workout.exercisesSequenceID, idMap)
        if sequence != workout.exercisesSequenceID { workout.exercisesSequenceID = sequence }
        let finished = remapped(workout.finishedExercisesSequence, idMap)
        if finished != workout.finishedExercisesSequence { workout.finishedExercisesSequence = finished }
    }
    for finished in (try? modelContext.fetch(FetchDescriptor<FinishedWorkout>())) ?? [] {
        let sequence = remapped(finished.exercisesSequenceID, idMap)
        if sequence != finished.exercisesSequenceID { finished.exercisesSequenceID = sequence }
        if finished.setWeights.keys.contains(where: { idMap[$0] != nil }) {
            finished.setWeights = remapped(finished.setWeights, idMap)
        }
        if finished.setReps.keys.contains(where: { idMap[$0] != nil }) {
            finished.setReps = remapped(finished.setReps, idMap)
        }
    }
    try? modelContext.save()
}

/// Removes duplicate seed (non-user-generated) workouts that share the same
/// name and repoints every plan at the survivor.
func deduplicateWorkouts(modelContext: ModelContext) {
    guard let allWorkouts = try? modelContext.fetch(FetchDescriptor<Workout>()) else { return }

    var workoutsByName: [String: [Workout]] = [:]
    for workout in allWorkouts where !workout.isUserGenerated && !workout.isHidden {
        let key = workout.name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        workoutsByName[key, default: []].append(workout)
    }

    var idMap: [String: String] = [:]
    for (_, workouts) in workoutsByName where workouts.count > 1 {
        let (keeper, duplicates) = sortedForDedup(workouts, id: \.id)
        for duplicate in duplicates {
            idMap[duplicate.id] = keeper.id
            for plan in duplicate.plan ?? []
            where !(keeper.plan ?? []).contains(where: { $0.id == plan.id }) {
                keeper.plan = (keeper.plan ?? []) + [plan]
            }
            // A bookmark set on either copy survives.
            if duplicate.isSaved { keeper.isSaved = true }
            modelContext.delete(duplicate)
        }
    }
    guard !idMap.isEmpty else { return }

    for plan in (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? [] {
        let sequence = remapped(plan.workoutsSequenceIDs, idMap)
        if sequence != plan.workoutsSequenceIDs { plan.workoutsSequenceIDs = sequence }
        let finished = remapped(plan.finishedWorkoutsSequence, idMap)
        if finished != plan.finishedWorkoutsSequence { plan.finishedWorkoutsSequence = finished }
    }
    try? modelContext.save()
}

// MARK: - Plan Deduplication
/// Removes duplicate seed (non-user-generated) plans that share the same name,
/// carrying the user's bookmark, progress and reminder setup over to the survivor.
@MainActor
func deduplicatePlans(modelContext: ModelContext) {
    guard let allPlans = try? modelContext.fetch(FetchDescriptor<Plan>()) else { return }

    var plansByName: [String: [Plan]] = [:]
    for plan in allPlans where !plan.isUserGenerated && !plan.isHidden {
        let key = plan.name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        plansByName[key, default: []].append(plan)
    }

    var didChange = false
    for (_, plans) in plansByName where plans.count > 1 {
        let (keeper, duplicates) = sortedForDedup(plans, id: \.id)
        for duplicate in duplicates {
            if duplicate.isSaved { keeper.isSaved = true }
            if duplicate.finishedWorkoutsSequence.count > keeper.finishedWorkoutsSequence.count {
                keeper.finishedWorkoutsSequence = duplicate.finishedWorkoutsSequence
            }
            if keeper.intervalType.isEmpty && !duplicate.intervalType.isEmpty {
                keeper.intervalType = duplicate.intervalType
                keeper.interval = duplicate.interval
            }
            NotificationManager.shared.cancelReminders(for: duplicate)
            modelContext.delete(duplicate)
            didChange = true
        }
    }

    if didChange {
        try? modelContext.save()
    }
}
