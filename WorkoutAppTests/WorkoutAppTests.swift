//
//  WorkoutAppTests.swift
//  WorkoutAppTests
//
//  Unit tests for the iOS app's shared logic — workout state wire format,
//  message classification, and the gym workout generator's pure helpers.
//  Uses Swift Testing per the project's testing convention.
//
//  These tests `@testable import` the iOS app module (`Workout_Multiplatform`),
//  which is why they have to live in a unit-test bundle rather than the
//  existing UI-testing bundle.
//

import Testing
import Foundation
import HealthKit
import SwiftData
import UIKit
@testable import Workout_Multiplatform

// MARK: - WatchMessage delivery

@Suite("WatchMessage delivery classification")
struct WatchMessageDeliveryTests {

    /// Discrete state events must round-trip even if the other device is
    /// asleep. They ride `transferUserInfo` in addition to the immediate
    /// sendMessage / applicationContext path.
    @Test func discreteEventsRequireGuaranteedDelivery() {
        let discrete: [WatchMessage] = [
            .workoutStart, .workoutPause, .workoutResume, .workoutEnd,
            .exerciseStart, .exerciseComplete, .workoutJoin
        ]
        for message in discrete {
            #expect(
                message.requiresGuaranteedDelivery,
                "\(message.rawValue) should be guaranteed-delivered"
            )
        }
    }

    /// Continuous / per-tick updates must NOT enqueue a persistent transfer
    /// each time — that would flood `transferUserInfo` and backlog the
    /// guaranteed-delivery queue. Earlier regression: the per-second
    /// `.workoutState` push was queued every tick.
    @Test func continuousEventsDoNotRequireGuaranteedDelivery() {
        let continuous: [WatchMessage] = [
            .workoutState, .timerSync, .healthKitUpdate,
            .heartRateUpdate, .caloriesUpdate, .requestSync,
            .authorizationStatus
        ]
        for message in continuous {
            #expect(
                !message.requiresGuaranteedDelivery,
                "\(message.rawValue) should NOT be guaranteed-delivered"
            )
        }
    }
}

// MARK: - WorkoutState Codable

@Suite("WorkoutState Codable round-trip")
struct WorkoutStateCodableTests {

    /// The whole sync subsystem depends on `WorkoutState` encoding and
    /// decoding cleanly across iOS ↔ watchOS. If anyone ever forgets to
    /// thread a new field through the initializer, this test catches it
    /// before it manifests as silently-dropped sync data on device.
    @Test func roundTripsAllFields() throws {
        let original = WorkoutState(
            workoutId: "workout-id-1",
            workoutName: "Upper Body",
            isActive: true,
            isPaused: false,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            currentExerciseId: "exercise-id-7",
            currentExerciseName: "Bench Press",
            currentExerciseIndex: 3,
            totalExercises: 6,
            elapsedTime: 432,
            estimatedCalories: 215.5,
            exerciseStartTime: Date(timeIntervalSince1970: 1_700_000_300),
            exerciseElapsedTime: 90
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: data)

        #expect(decoded.workoutId == original.workoutId)
        #expect(decoded.workoutName == original.workoutName)
        #expect(decoded.isActive == original.isActive)
        #expect(decoded.isPaused == original.isPaused)
        #expect(decoded.startTime == original.startTime)
        #expect(decoded.currentExerciseId == original.currentExerciseId)
        #expect(decoded.currentExerciseName == original.currentExerciseName)
        #expect(decoded.currentExerciseIndex == original.currentExerciseIndex)
        #expect(decoded.totalExercises == original.totalExercises)
        #expect(decoded.elapsedTime == original.elapsedTime)
        #expect(decoded.estimatedCalories == original.estimatedCalories)
        #expect(decoded.exerciseStartTime == original.exerciseStartTime)
        #expect(decoded.exerciseElapsedTime == original.exerciseElapsedTime)
    }

    /// Defaults must produce an "empty / inactive" state — the iOS observer
    /// uses this on workout end to signal teardown to the watch.
    @Test func defaultInitializerIsInactiveAndEmpty() {
        let state = WorkoutState()
        #expect(state.isActive == false)
        #expect(state.isPaused == false)
        #expect(state.workoutId.isEmpty)
        #expect(state.workoutName.isEmpty)
        #expect(state.currentExerciseId == nil)
        #expect(state.currentExerciseName == nil)
        #expect(state.currentExerciseIndex == 0)
        #expect(state.totalExercises == 0)
        #expect(state.elapsedTime == 0)
        #expect(state.estimatedCalories == nil)
    }
}

// MARK: - HealthMetrics Codable

@Suite("HealthMetrics Codable round-trip")
struct HealthMetricsCodableTests {

    @Test func roundTripsAllFields() throws {
        let original = HealthMetrics(
            heartRate: 142,
            activeCalories: 88,
            totalCalories: 120,
            distance: 1500,
            steps: 1800,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthMetrics.self, from: data)

        #expect(decoded.heartRate == original.heartRate)
        #expect(decoded.activeCalories == original.activeCalories)
        #expect(decoded.totalCalories == original.totalCalories)
        #expect(decoded.distance == original.distance)
        #expect(decoded.steps == original.steps)
        #expect(decoded.timestamp == original.timestamp)
    }
}

// MARK: - GymSplit metadata

@Suite("GymSplit display + muscle targeting")
struct GymSplitTests {

    /// Each split must have a non-empty display name; a UI regression that
    /// blanks one out would silently break the gym generator's pickers.
    @Test func everySplitHasDisplayAndShortName() {
        for split in GymSplit.allCases {
            #expect(!split.displayName.isEmpty)
            #expect(!split.shortName.isEmpty)
            #expect(!split.symbolName.isEmpty)
        }
    }

    /// Targeted muscle groups should never be empty — generation falls
    /// back to "no exercises available" if a split's target list is empty,
    /// which would silently produce no workout.
    @Test func everySplitTargetsAtLeastOneMuscleGroup() {
        for split in GymSplit.allCases {
            #expect(!split.targetedMuscleGroups.isEmpty,
                    "Split \(split.rawValue) has no targeted muscle groups")
        }
    }

    /// Push-day muscle priority should lead with chest. If anyone reorders
    /// the targetedMuscleGroups, the generator's bias changes — catch that.
    @Test func pushSplitLeadsWithChest() {
        #expect(GymSplit.push.targetedMuscleGroups.first == WorkoutCategory.chest.rawValue)
        #expect(GymSplit.pull.targetedMuscleGroups.first == WorkoutCategory.back.rawValue)
        #expect(GymSplit.leg.targetedMuscleGroups.first == WorkoutCategory.legs.rawValue)
    }
}

// MARK: - GymExerciseCatalog filtering

@Suite("GymExerciseCatalog equipment filter")
struct GymExerciseCatalogTests {

    /// A user with NO equipment should still get the body-weight exercises
    /// (e.g., dips, plank, calf raise) — they don't require equipment.
    @Test func bodyweightExercisesAlwaysAvailable() {
        let pool = GymExerciseCatalog.exercises(
            forMuscleGroups: [
                WorkoutCategory.arms.rawValue,
                WorkoutCategory.core.rawValue,
                WorkoutCategory.legs.rawValue
            ],
            availableEquipment: []
        )

        // Anything in the pool should require no equipment.
        for definition in pool {
            #expect(
                definition.equipment.isEmpty,
                "\(definition.name) requires equipment but slipped through"
            )
        }
        // At least one should be present (e.g., plank, calf raise, dips).
        #expect(!pool.isEmpty, "No bodyweight exercises returned for empty equipment set")
    }

    /// When the user has all equipment, every catalog exercise matching
    /// the requested muscle group(s) should be returned.
    @Test func allEquipmentReturnsEverything() {
        let allEquipment = Set(GymExerciseCatalog.all.flatMap { $0.equipment })
        let allMuscleGroups = Set(GymExerciseCatalog.all.map { $0.muscleGroup })

        let pool = GymExerciseCatalog.exercises(
            forMuscleGroups: Array(allMuscleGroups),
            availableEquipment: allEquipment
        )

        #expect(pool.count == GymExerciseCatalog.all.count)
    }

    /// Asking only for chest exercises should return only chest exercises.
    @Test func filterRespectsMuscleGroup() {
        let allEquipment = Set(GymExerciseCatalog.all.flatMap { $0.equipment })
        let pool = GymExerciseCatalog.exercises(
            forMuscleGroups: [WorkoutCategory.chest.rawValue],
            availableEquipment: allEquipment
        )

        for definition in pool {
            #expect(definition.muscleGroup == WorkoutCategory.chest.rawValue)
        }
        #expect(!pool.isEmpty, "Catalog has no chest exercises — likely a regression")
    }

    /// Missing equipment must exclude exercises that need it.
    @Test func missingEquipmentExcludesDependentExercises() {
        // Lat pulldown needs the cable machine. Without it, the result
        // must NOT include lat pulldown.
        let pool = GymExerciseCatalog.exercises(
            forMuscleGroups: [WorkoutCategory.back.rawValue],
            availableEquipment: [Equipment.barbells.rawValue]
        )
        let latPulldown = pool.first(where: { $0.id == "seed-exercise-lat-pulldown" })
        #expect(latPulldown == nil, "Lat pulldown surfaced without cable machine")
    }
}

// MARK: - Recovery estimation

@Suite("RecoveryEstimator scoring")
struct RecoveryEstimatorTests {

    private func inputs(hrv: Double? = nil, hrvBase: Double? = nil,
                        rhr: Double? = nil, rhrBase: Double? = nil,
                        sleep: Double? = nil,
                        acute: Double = 0, chronic: Double? = nil) -> RecoveryInputs {
        RecoveryInputs(hrvSDNN: hrv, hrvBaseline: hrvBase,
                       restingHR: rhr, restingHRBaseline: rhrBase,
                       sleepHoursLastNight: sleep,
                       acuteLoad: acute, chronicLoad: chronic)
    }

    /// With no HealthKit signals and no load history the score is the neutral
    /// baseline and the "no health data" flag is set so the UI can explain it.
    @Test func noDataYieldsNeutralBaseline() {
        let estimate = RecoveryEstimator.estimate(from: inputs())
        #expect(estimate.score == 75)
        #expect(estimate.band == .ready)
        #expect(estimate.hasHealthData == false)
        #expect(estimate.factors.isEmpty)
    }

    /// Strong signals (HRV above baseline, low resting HR, good sleep, managed
    /// load) push recovery high and into the "ready" band.
    @Test func strongSignalsProduceHighReadyScore() {
        let estimate = RecoveryEstimator.estimate(from: inputs(
            hrv: 80, hrvBase: 50, rhr: 50, rhrBase: 60, sleep: 8.5,
            acute: 20, chronic: 30))
        #expect(estimate.score >= 90)
        #expect(estimate.band == .ready)
        #expect(estimate.hasHealthData)
    }

    /// Poor signals (suppressed HRV, elevated resting HR, short sleep, a load
    /// spike) drive recovery down into the "rest" band without underflowing.
    @Test func poorSignalsProduceLowRestScore() {
        let estimate = RecoveryEstimator.estimate(from: inputs(
            hrv: 30, hrvBase: 60, rhr: 72, rhrBase: 60, sleep: 5,
            acute: 60, chronic: 20))
        #expect(estimate.score < 45)
        #expect(estimate.score >= 0)
        #expect(estimate.band == .rest)
    }

    /// The score is always clamped to 0…100 regardless of extreme inputs.
    @Test func scoreStaysWithinBounds() {
        let high = RecoveryEstimator.estimate(from: inputs(hrv: 999, hrvBase: 10, rhr: 30, rhrBase: 90, sleep: 12))
        let low = RecoveryEstimator.estimate(from: inputs(hrv: 1, hrvBase: 200, rhr: 200, rhrBase: 50, sleep: 0, acute: 999, chronic: 1))
        #expect(high.score <= 100)
        #expect(low.score >= 0)
    }
}

// MARK: - Difficulty prediction

@Suite("WorkoutDifficultyPredictor")
struct WorkoutDifficultyPredictorTests {

    /// The same workout must feel harder when the athlete is under-recovered.
    @Test func lowRecoveryRaisesPerceivedDifficulty() {
        let fresh = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2, 2], exerciseCount: 4, setLength: 3,
            durationMinutes: 30, recovery: 0.9, history: [])
        let tired = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2, 2], exerciseCount: 4, setLength: 3,
            durationMinutes: 30, recovery: 0.2, history: [])
        #expect(tired.rating > fresh.rating)
    }

    /// Harder exercises produce a higher rating than easy ones, all else equal.
    @Test func harderExercisesRaiseRating() {
        let easy = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [1, 1, 1], exerciseCount: 3, setLength: 3,
            durationMinutes: 25, recovery: 0.7, history: [])
        let hard = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [3, 3, 3], exerciseCount: 3, setLength: 3,
            durationMinutes: 25, recovery: 0.7, history: [])
        #expect(hard.rating > easy.rating)
    }

    /// The rating is always within the documented 1…5 range.
    @Test func ratingStaysWithinOneToFive() {
        let extreme = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [3, 3, 3, 3, 3, 3], exerciseCount: 6, setLength: 5,
            durationMinutes: 90, recovery: 0.0, history: [])
        #expect(extreme.rating >= 1 && extreme.rating <= 5)
        #expect(!extreme.label.isEmpty)
    }

    /// Rising logged-volume progression makes the same session feel easier than
    /// flat/declining progression.
    @Test func positiveProgressionLowersDifficulty() {
        let base = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2], exerciseCount: 3, setLength: 3,
            durationMinutes: 30, recovery: 0.7, history: [], progression: 0)
        let progressing = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2], exerciseCount: 3, setLength: 3,
            durationMinutes: 30, recovery: 0.7, history: [], progression: 1.0)
        #expect(progressing.rating < base.rating)
    }
}

// MARK: - Sleep interval merge (multi-source double-count fix)

@Suite("Sleep interval merge")
struct SleepMergeTests {

    private func at(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(hours * 3600)
    }

    /// Overlapping samples from different sources covering the same night must
    /// count the night's sleep once — not sum to an impossible total.
    @Test func overlappingSourcesCountOnce() {
        let intervals: [(start: Date, end: Date)] = [
            (at(0), at(8)),   // iPhone estimate: 8 h
            (at(0), at(2)),   // Watch core (overlaps)
            (at(2), at(3)),   // Watch REM (overlaps)
            (at(3), at(8))    // Watch core (overlaps)
        ]
        #expect(abs(RecoveryMetricsProvider.mergedAsleepHours(intervals) - 8.0) < 0.001)
    }

    /// Genuinely separate sleep blocks (e.g. a nap) still add up.
    @Test func disjointBlocksSum() {
        let intervals: [(start: Date, end: Date)] = [(at(0), at(6)), (at(8), at(9))]
        #expect(abs(RecoveryMetricsProvider.mergedAsleepHours(intervals) - 7.0) < 0.001)
    }

    @Test func emptyIsZero() {
        #expect(RecoveryMetricsProvider.mergedAsleepHours([]) == 0)
    }
}

// MARK: - Watch-only workout interval

@Suite("Watch workout interval")
@MainActor
struct WatchWorkoutIntervalTests {

    /// An end message received hours later must not stretch the workout.
    @Test func endComesFromStartPlusElapsed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(3 * 3600)
        let state = WorkoutState(startTime: start, elapsedTime: 1800)
        let interval = iOSWorkoutObserver.watchWorkoutInterval(for: state, now: now)
        #expect(interval.start == start)
        #expect(interval.end == start.addingTimeInterval(1800))
    }

    @Test func missingStartFallsBackToNow() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let state = WorkoutState(elapsedTime: 600)
        let interval = iOSWorkoutObserver.watchWorkoutInterval(for: state, now: now)
        #expect(interval.end == now)
        #expect(interval.start == now.addingTimeInterval(-600))
    }
}

// MARK: - Phone workout Health write

@Suite("Phone workout energy estimate")
struct PhoneWorkoutEnergyTests {

    @Test func averagesKnownRatesOverDuration() {
        // (0.1 + 0.2) / 2 = 0.15 kcal/s over 10 min; exercises without a rate are ignored.
        let kcal = PhoneWorkoutHealthWriter.estimatedEnergy(caloriesPerSecond: [0.1, 0.2, 0], duration: 600)
        #expect(abs((kcal ?? 0) - 90) < 0.0001)
    }

    @Test func noRatesMeansNoEstimate() {
        #expect(PhoneWorkoutHealthWriter.estimatedEnergy(caloriesPerSecond: [0, 0], duration: 600) == nil)
        #expect(PhoneWorkoutHealthWriter.estimatedEnergy(caloriesPerSecond: [], duration: 600) == nil)
    }

    /// 30 min with a 5 min and a 10 min pause: 15 min of workout.
    @Test func pausesDontCountAsWorkoutTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let pauses = [DateInterval(start: start.addingTimeInterval(300), duration: 300),
                      DateInterval(start: start.addingTimeInterval(900), duration: 600)]
        #expect(PhoneWorkoutHealthWriter.activeDuration(start: start, end: end, pauses: pauses) == 900)
        #expect(PhoneWorkoutHealthWriter.activeDuration(start: start, end: end, pauses: []) == 1800)
    }

    /// Pauses reaching outside the session are clipped to it, and overlapping
    /// ones count once, so the paused time is never subtracted twice.
    @Test func pausesAreClippedAndMerged() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1000)
        let pauses = [DateInterval(start: start.addingTimeInterval(900), duration: 500),   // runs past the end
                      DateInterval(start: start.addingTimeInterval(100), duration: 200),
                      DateInterval(start: start.addingTimeInterval(200), duration: 200),   // overlaps the one before
                      DateInterval(start: start.addingTimeInterval(-100), duration: 50)]   // before the start
        let normalized = PhoneWorkoutHealthWriter.normalizedPauses(pauses, start: start, end: end)
        #expect(normalized == [DateInterval(start: start.addingTimeInterval(100), duration: 300),
                               DateInterval(start: start.addingTimeInterval(900), duration: 100)])
        #expect(PhoneWorkoutHealthWriter.activeDuration(start: start, end: end, pauses: pauses) == 600)
    }

    /// A session paused for nearly all of it is not a workout worth logging:
    /// the minimum is measured on the active time.
    @Test func pausedTimeDoesntReachTheMinimum() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let pauses = [DateInterval(start: start.addingTimeInterval(30), end: end)]
        #expect(PhoneWorkoutHealthWriter.activeDuration(start: start, end: end, pauses: pauses)
                < PhoneWorkoutHealthWriter.minimumDuration)
    }
}

// MARK: - Watch status merge

@Suite("Watch status merge")
struct WatchStatusMergeTests {

    /// A periodic watch status sent before an iPhone pause / exercise change
    /// must not undo it; only the watch's session metrics are taken.
    @Test func keepsPhonePauseAndExerciseTakesWatchMetrics() {
        let local = WorkoutState(workoutId: "w", workoutName: "Push", isActive: true, isPaused: true,
                                 currentExerciseName: "Dips", currentExerciseIndex: 2, totalExercises: 4,
                                 elapsedTime: 100)
        let watch = WorkoutState(workoutId: "w", workoutName: "Push", isActive: true, isPaused: false,
                                 currentExerciseName: "Bench", currentExerciseIndex: 1, totalExercises: 4,
                                 elapsedTime: 130, estimatedCalories: 42)
        let merged = WatchConnectivityManager.merging(watchStatus: watch, into: local)
        #expect(merged.isPaused == true)
        #expect(merged.currentExerciseIndex == 2)
        #expect(merged.currentExerciseName == "Dips")
        #expect(merged.elapsedTime == 130)
        #expect(merged.estimatedCalories == 42)
        #expect(merged.isActive)
    }
}

// MARK: - Ended-session filter

@Suite("Ended-session filter")
struct EndedSessionFilterTests {

    private let end = Date(timeIntervalSince1970: 1_000_000)

    /// A status the watch sent just before the iPhone ended the workout
    /// arrived afterwards, and the workout restarted on both devices.
    @Test func runningStateOfTheEndedSessionIsDropped() {
        let state = WorkoutState(workoutId: "w", isActive: true, startTime: end.addingTimeInterval(-600))
        #expect(WatchConnectivityManager.belongsToEndedSession(state, endedAt: end))
    }

    /// Every session of a workout has the same id; one started later is new.
    @Test func laterSessionOfTheSameWorkoutIsKept() {
        let state = WorkoutState(workoutId: "w", isActive: true, startTime: end.addingTimeInterval(60))
        #expect(!WatchConnectivityManager.belongsToEndedSession(state, endedAt: end))
    }

    @Test func endStatesAndWorkoutsThatDidNotEndAreKept() {
        let ended = WorkoutState(workoutId: "w", isActive: false, startTime: end.addingTimeInterval(-600))
        #expect(!WatchConnectivityManager.belongsToEndedSession(ended, endedAt: end))
        let running = WorkoutState(workoutId: "w", isActive: true, startTime: end.addingTimeInterval(-600))
        #expect(!WatchConnectivityManager.belongsToEndedSession(running, endedAt: nil))
    }
}

// MARK: - WorkoutState rest fields (watch rest mirroring)

@Suite("WorkoutState rest fields")
struct WorkoutStateRestFieldTests {

    /// The rest fields added for watch rest-period mirroring must round-trip.
    @Test func restFieldsRoundTrip() throws {
        let resting = WorkoutState(isActive: true, isResting: true, restSecondsRemaining: 30)
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: JSONEncoder().encode(resting))
        #expect(decoded.isResting == true)
        #expect(decoded.restSecondsRemaining == 30)
    }

    /// A payload encoded before the rest fields existed (keys absent) must still
    /// decode — that's why the fields are optional. Missing → nil, not a failure.
    @Test func legacyPayloadWithoutRestFieldsDecodes() throws {
        let legacy = """
        {"workoutId":"x","workoutName":"y","isActive":false,"isPaused":false,\
        "currentExerciseIndex":0,"totalExercises":0,"elapsedTime":0,\
        "exerciseElapsedTime":0,"workoutActivityType":63,"workoutLocationType":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: legacy)
        #expect(decoded.isResting == nil)
        #expect(decoded.restSecondsRemaining == nil)
        #expect(decoded.discarded == nil)
    }

    /// "End without saving" must reach the other device, or it saves anyway.
    @Test func discardedRoundTrips() throws {
        let end = WorkoutState(workoutId: "x", isActive: false, discarded: true)
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: JSONEncoder().encode(end))
        #expect(decoded.discarded == true)
    }
}

// MARK: - WeightUnit conversion / formatting

@Suite("WeightUnit conversion and formatting")
struct WeightUnitTests {

    /// kg is the storage unit, so its conversions are identities.
    @Test func kilogramsAreIdentity() {
        #expect(WeightUnit.kilograms.toKilograms(60) == 60)
        #expect(WeightUnit.kilograms.fromKilograms(60) == 60)
    }

    /// Converting kg → lbs → kg (and back) must round-trip within FP tolerance.
    @Test func poundsRoundTrip() {
        let kg = 82.5
        let lbs = WeightUnit.pounds.fromKilograms(kg)
        #expect(abs(lbs - 181.881) < 0.01)
        let back = WeightUnit.pounds.toKilograms(lbs)
        #expect(abs(back - kg) < 0.0001)
    }

    /// Whole numbers drop the decimal; fractional values keep one place, and the
    /// unit abbreviation is appended.
    @Test func formattingIsClean() {
        #expect(WeightUnit.kilograms.format(kilograms: 60) == "60 kg")
        #expect(WeightUnit.kilograms.format(kilograms: 62.5) == "62.5 kg")
    }

    /// A per-set list joins values with a middle dot and a single trailing unit;
    /// an empty list produces no text.
    @Test func setListFormatting() {
        #expect(WeightUnit.kilograms.format(kilogramsList: [60, 65, 65]) == "60 · 65 · 65 kg")
        #expect(WeightUnit.kilograms.format(kilogramsList: []) == "")
    }

    /// A single set combines weight and reps, and degrades gracefully when one is
    /// missing (bodyweight sets show reps only; timed sets with neither are empty).
    @Test func singleSetFormatting() {
        // Reps-only uses the localized "%d reps" string, so compare against the
        // same expansion rather than a hardcoded English literal (tests may run
        // in a non-English locale).
        let eightReps = String(format: NSLocalizedString("%d reps", comment: ""), 8)
        #expect(WeightUnit.kilograms.formatSet(kilograms: 60, reps: 8) == "60 kg × 8")
        #expect(WeightUnit.kilograms.formatSet(kilograms: 60, reps: 0) == "60 kg")
        #expect(WeightUnit.kilograms.formatSet(kilograms: 0, reps: 8) == eightReps)
        #expect(WeightUnit.kilograms.formatSet(kilograms: 0, reps: 0) == "")
    }

    /// A full set list zips weight and reps; a shorter reps array (older records
    /// that logged weight only) still renders each set as weight-only.
    @Test func setListWithReps() {
        #expect(WeightUnit.kilograms.formatSets(kilograms: [60, 65], reps: [8, 6]) == "60 kg × 8 · 65 kg × 6")
        #expect(WeightUnit.kilograms.formatSets(kilograms: [60, 65], reps: []) == "60 kg · 65 kg")
        #expect(WeightUnit.kilograms.formatSets(kilograms: [], reps: []) == "")
    }
}

// MARK: - WorkoutStats (volume + personal records)

@Suite("WorkoutStats aggregations")
struct WorkoutStatsTests {

    /// Volume is Σ (weight × reps) over every set of every exercise.
    @Test func volumeSumsWeightTimesReps() {
        let weights = ["bench": [60.0, 60, 65], "squat": [100.0, 100]]
        let reps = ["bench": [8, 8, 6], "squat": [5, 5]]
        // 60*8 + 60*8 + 65*6 = 1350 ; 100*5 + 100*5 = 1000 ; total 2350
        #expect(WorkoutStats.volumeKilograms(setWeights: weights, setReps: reps) == 2350)
    }

    /// Missing reps (legacy weight-only records) and bodyweight (0 kg) sets add nothing.
    @Test func volumeHandlesMissingRepsAndBodyweight() {
        #expect(WorkoutStats.volumeKilograms(setWeights: ["a": [60, 65]], setReps: [:]) == 0)
        #expect(WorkoutStats.volumeKilograms(setWeights: ["a": [0, 0]], setReps: ["a": [10, 10]]) == 0)
        #expect(WorkoutStats.volumeKilograms(setWeights: [:], setReps: [:]) == 0)
    }

    private func snap(_ id: String, _ t: TimeInterval, _ w: [String: [Double]]) -> WorkoutStats.Snapshot {
        WorkoutStats.Snapshot(id: id, endDate: Date(timeIntervalSince1970: t), setWeights: w)
    }

    /// Beating the best of an earlier session flags a PR for that exercise.
    @Test func prDetectedWhenBeatingEarlierBest() {
        let older = snap("1", 100, ["bench": [60, 60]])
        let current = snap("2", 200, ["bench": [65]])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: current, history: [older, current]) == ["bench"])
    }

    /// A first-ever log (no prior history for the exercise) is not a PR.
    @Test func noPRWithoutPriorHistory() {
        let current = snap("1", 200, ["bench": [65]])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: current, history: [current]).isEmpty)
    }

    /// Equalling or falling short of the previous best is not a PR.
    @Test func noPRWhenNotExceeding() {
        let older = snap("1", 100, ["bench": [70]])
        let current = snap("2", 200, ["bench": [65]])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: current, history: [older, current]).isEmpty)
    }

    /// Only workouts strictly *before* the current one count as history.
    @Test func laterWorkoutsAreNotHistory() {
        let older = snap("1", 100, ["bench": [60]])
        let current = snap("2", 200, ["bench": [65]])
        let future = snap("3", 300, ["bench": [100]])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: current, history: [older, current, future]) == ["bench"])
    }

    /// Bodyweight (0 kg) exercises never register a weight PR.
    @Test func bodyweightIsNotAPR() {
        let older = snap("1", 100, ["pullup": [0]])
        let current = snap("2", 200, ["pullup": [0]])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: current, history: [older, current]).isEmpty)
    }

    /// Last logged weight is the newest session's last positive set for the exercise.
    @Test func lastLoggedWeightPicksNewestSession() {
        let history = [
            snap("1", 100, ["bench": [60, 62]]),
            snap("2", 300, ["bench": [65, 67]]),   // newest
            snap("3", 200, ["bench": [63]]),
        ]
        #expect(WorkoutStats.lastLoggedWeightKg(forExerciseID: "bench", in: history) == 67)
        #expect(WorkoutStats.lastLoggedWeightKg(forExerciseID: "squat", in: history) == nil)
    }

    private func snapVR(_ t: TimeInterval, _ w: [String: [Double]], _ r: [String: [Int]]) -> WorkoutStats.Snapshot {
        WorkoutStats.Snapshot(id: UUID().uuidString, endDate: Date(timeIntervalSince1970: t), setWeights: w, setReps: r)
    }

    /// Progression is positive when recent mean session volume exceeds the prior window.
    @Test func progressionRisesWithVolume() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let day = 86_400.0
        let history = [
            // older window (14–28 days ago): ~600 volume
            snapVR(100 * day - 20 * day, ["a": [50]], ["a": [12]]),   // 600
            // recent window (0–14 days ago): ~1000 volume
            snapVR(100 * day - 5 * day, ["a": [100]], ["a": [10]]),   // 1000
        ]
        #expect(WorkoutStats.progressionScore(history: history, now: now) > 0)
    }

    /// No progression signal without data in both windows.
    @Test func progressionZeroWithoutBothWindows() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let recentOnly = [snapVR(100 * 86_400 - 3 * 86_400, ["a": [100]], ["a": [10]])]
        #expect(WorkoutStats.progressionScore(history: recentOnly, now: now) == 0)
        #expect(WorkoutStats.progressionScore(history: [], now: now) == 0)
    }

    /// Volume series is oldest→newest and drops zero-volume sessions.
    @Test func volumeSeriesSortedAndFiltersEmpty() {
        let history = [
            snapVR(300, ["a": [100]], ["a": [10]]),  // 1000, newest
            snapVR(100, ["a": [50]], ["a": [10]]),   // 500, oldest
            snapVR(200, ["a": [0]], ["a": [10]]),    // 0 → filtered out
        ]
        #expect(WorkoutStats.volumeSeries(from: history).map(\.volumeKg) == [500, 1000])
    }

    /// Per-exercise series uses the max set per session, oldest→newest.
    @Test func bestWeightSeriesPicksMaxPerSession() {
        let history = [
            snapVR(100, ["bench": [60, 65]], [:]),
            snapVR(200, ["bench": [70, 68]], [:]),
            snapVR(150, ["squat": [100]], [:]),
        ]
        #expect(WorkoutStats.bestWeightSeries(forExerciseID: "bench", from: history).map(\.weightKg) == [65, 70])
        #expect(WorkoutStats.bestWeightSeries(forExerciseID: "deadlift", from: history).isEmpty)
    }
}

// MARK: - FinishedWorkout per-set persistence (SwiftData round-trip)

@Suite("FinishedWorkout per-set persistence")
@MainActor
struct FinishedWorkoutPersistenceTests {

    /// In-memory SwiftData context mirroring the app's schema.
    private func makeContext() throws -> ModelContext {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Weights and reps survive an encode → save → decode round-trip and stay
    /// index-aligned.
    @Test func setWeightsAndRepsRoundTrip() throws {
        let ctx = try makeContext()
        let fw = FinishedWorkout(endDate: .now, name: "T", startDate: .now,
                                 muscleGroup: 1, exercisesSequenceID: ["bench"])
        ctx.insert(fw)
        fw.setWeights = ["bench": [60, 65, 65]]
        fw.setReps = ["bench": [8, 6, 6]]
        try ctx.save()

        #expect(fw.setWeights["bench"] == [60, 65, 65])
        #expect(fw.setReps["bench"] == [8, 6, 6])
    }

    /// A fresh record (and legacy records with no reps blob) reads back empty
    /// rather than crashing — the reason `setReps` is a separate optional blob.
    @Test func freshRecordHasEmptyPerSetData() throws {
        let ctx = try makeContext()
        let fw = FinishedWorkout(endDate: .now, name: "T", startDate: .now,
                                 muscleGroup: 1, exercisesSequenceID: [])
        ctx.insert(fw)
        #expect(fw.setWeights.isEmpty)
        #expect(fw.setReps.isEmpty)
    }
}

// MARK: - iOSWorkoutObserver watch-end teardown guard

// Serialized: both tests mutate the shared `WatchConnectivityManager.shared`
// state the observer subscribes to. Without this, Swift Testing's default
// parallelism let the `realEnd` test's populated end-state leak into the
// `placeholder` test's observer and flip its `isWorkoutActive` off.
@Suite("iOSWorkoutObserver placeholder-state guard", .serialized)
@MainActor
struct iOSWorkoutObserverWatchEndTests {

    /// The observer mirrors the watch via `WatchConnectivityManager.shared`'s
    /// `receivedWorkoutState`, whose Combine sink hops through
    /// `DispatchQueue.main`. Give that hop a chance to deliver before asserting.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func makeWorkout(id: String) -> Workout {
        Workout(id: id, infoText: "", isUserGenerated: true, muscleGroup: 1, setLength: 3,
                straightSets: true, difficultyInt: 2, name: "Push", duration: 20,
                exercisesSequenceID: ["e1", "e2"], finishedExercisesSequence: [],
                workoutActivityType: 50, workoutSessionLocation: 2)
    }

    /// Regression: a freshly-woken watch replies to the sync handshake with a
    /// placeholder `WorkoutState()` (isActive=false, empty id/name) before its
    /// own HK session is up. That must NOT tear down an iOS-initiated active
    /// workout — doing so dismissed ActiveWorkoutView the instant the watch
    /// woke, while the system's live workout banner appeared with no way back.
    @Test func placeholderStateDoesNotEndActiveWorkout() async {
        let connectivity = WatchConnectivityManager.shared
        let observer = iOSWorkoutObserver()
        observer.isWorkoutActive = true                     // iOS owns a live workout
        await settle()

        // Placeholder state from the launching watch.
        connectivity.receivedWorkoutState.send(WorkoutState())
        await settle()

        #expect(observer.isWorkoutActive == true)
    }

    /// A genuine watch-driven end always carries the workout's id/name, so it
    /// must still tear the workout down on iOS.
    @Test func realEndStateEndsActiveWorkout() async {
        let connectivity = WatchConnectivityManager.shared
        let observer = iOSWorkoutObserver()
        observer.isWorkoutActive = true
        await settle()

        // Watch stop button: populated id/name, isActive=false.
        connectivity.receivedWorkoutState.send(WorkoutState(
            workoutId: "workout-123",
            workoutName: "Upper Body",
            isActive: false
        ))
        await settle()

        #expect(observer.isWorkoutActive == false)
    }

    /// Regression: the iPhone's own inactive state (e.g. an exercise update
    /// sent from the active workout screen just before the watch start set
    /// `isWorkoutActive`) was read as "the watch ended it", closing the
    /// just-started workout while the watch kept running.
    @Test func localInactiveStateDoesNotEndActiveWorkout() async {
        let connectivity = WatchConnectivityManager.shared
        let observer = iOSWorkoutObserver()
        observer.isWorkoutActive = true
        await settle()

        connectivity.currentWorkoutState = WorkoutState(
            workoutId: "workout-123",
            workoutName: "Upper Body",
            isActive: false
        )
        await settle()

        #expect(observer.isWorkoutActive == true)
        connectivity.currentWorkoutState = WorkoutState()
    }

    /// Before the watch session starts, an exercise update must not build or
    /// send an (inactive) state carrying the workout's id.
    @Test func exerciseUpdateBeforeStartSendsNothing() async {
        let connectivity = WatchConnectivityManager.shared
        connectivity.currentWorkoutState = WorkoutState()
        let observer = iOSWorkoutObserver()
        let workout = Workout(id: "w-1", infoText: "", isUserGenerated: true, muscleGroup: 1, setLength: 3,
                              straightSets: true, difficultyInt: 2, name: "Push", duration: 20,
                              exercisesSequenceID: ["e1"], finishedExercisesSequence: [],
                              workoutActivityType: 50, workoutSessionLocation: 2)

        observer.updateCurrentExercise(workout: workout, index: 0, remainingSeconds: 30)

        #expect(connectivity.currentWorkoutState.workoutId.isEmpty)
    }

    /// A workout started from the watch's list is one of the iPhone's, so the
    /// banner can open it; a watch quick start (random id) is not.
    @Test func watchStartedWorkoutIsFoundOnPhone() async throws {
        let connectivity = WatchConnectivityManager.shared
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(makeWorkout(id: "w-2"))
        try context.save()
        let observer = iOSWorkoutObserver()
        observer.configure(modelContext: context)

        connectivity.receivedWorkoutState.send(WorkoutState(workoutId: "w-2", workoutName: "Push",
                                                            isActive: true, startTime: .now))
        await settle()
        #expect(observer.watchStartedWorkoutID == "w-2")

        // Discarded, so nothing is saved to the history.
        connectivity.receivedWorkoutState.send(WorkoutState(workoutId: "w-2", workoutName: "Push",
                                                            isActive: false, discarded: true))
        await settle()
        #expect(observer.watchStartedWorkoutID == nil)

        connectivity.receivedWorkoutState.send(WorkoutState(workoutId: UUID().uuidString, workoutName: "HIIT",
                                                            isActive: true, startTime: .now))
        await settle()
        #expect(observer.isWorkoutActive)
        #expect(observer.watchStartedWorkoutID == nil)
    }

    /// Opening a watch-started workout on the iPhone resumes from the watch's
    /// start time and exercise, and the iPhone drives the session from then on.
    @Test func joiningContinuesTheWatchSession() {
        let connectivity = WatchConnectivityManager.shared
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        connectivity.currentWorkoutState = WorkoutState(workoutId: "w-3", workoutName: "Push", isActive: true,
                                                        startTime: start, currentExerciseIndex: 1,
                                                        totalExercises: 2)
        let observer = iOSWorkoutObserver()

        let snapshot = observer.joinWatchWorkout(makeWorkout(id: "w-3"))

        #expect(snapshot.workoutID == "w-3")
        #expect(snapshot.startDate == start)
        #expect(snapshot.exerciseIndex == 1)
        #expect(snapshot.setCount == 3)
        #expect(connectivity.phoneOwnsWorkout)
        connectivity.phoneOwnsWorkout = false
        connectivity.currentWorkoutState = WorkoutState()
    }
}

// MARK: - Own workouts and plans order

@Suite("Own workouts and plans order")
@MainActor
struct OwnWorkoutsOrderTests {

    private func workout(_ name: String, createdAt: Double?) -> Workout {
        let workout = Workout(infoText: "", isUserGenerated: true, muscleGroup: 1, setLength: 3,
                              straightSets: false, difficultyInt: 2, name: name, duration: 20,
                              exercisesSequenceID: [], finishedExercisesSequence: [],
                              workoutActivityType: 50, workoutSessionLocation: 2)
        workout.index = createdAt
        return workout
    }

    @Test func newWorkoutRecordsWhenItWasCreated() throws {
        let before = Date()
        let createdAt = try #require(Workout(infoText: "", isUserGenerated: true, muscleGroup: 1, setLength: 3,
                                             straightSets: false, difficultyInt: 2, name: "Push", duration: 20,
                                             exercisesSequenceID: [], finishedExercisesSequence: [],
                                             workoutActivityType: 50, workoutSessionLocation: 2).createdAt)
        #expect(createdAt >= before)
        #expect(createdAt <= Date())
    }

    /// Newest first; workouts from before 1.2 (index 0 or 1, or none) go
    /// last, alphabetically.
    @Test func newestFirstThenUndatedByName() {
        let workouts = [workout("Zulu", createdAt: 1), workout("Older", createdAt: 1_700_000_000),
                        workout("Alpha", createdAt: 0), workout("Newest", createdAt: 1_800_000_000),
                        workout("Beta", createdAt: nil)]
        #expect(workouts.sorted(by: Workout.newestFirst).map(\.name) == ["Newest", "Older", "Alpha", "Beta", "Zulu"])
    }

    /// Own plans follow the same rule; plans from before 1.2 have no date.
    @Test func plansNewestFirstThenUndatedByName() {
        func plan(_ name: String, createdAt: Date?) -> Plan {
            let plan = Plan(goal: 100, infoText: "", muscleGroup: 2, name: name, interval: [:], intervalType: "")
            plan.createdAt = createdAt
            return plan
        }
        let fresh = Plan(goal: 100, infoText: "", muscleGroup: 2, name: "Fresh", interval: [:], intervalType: "")
        #expect(fresh.createdAt != nil)

        let plans = [plan("Zulu", createdAt: nil), plan("Older", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
                     plan("Alpha", createdAt: nil), plan("Newest", createdAt: Date(timeIntervalSince1970: 1_800_000_000))]
        #expect(plans.sorted(by: Plan.newestFirst).map(\.name) == ["Newest", "Older", "Alpha", "Zulu"])
    }
}

// MARK: - ResumeSnapshot persistence

@Suite("ResumeSnapshot Codable")
struct ResumeSnapshotTests {

    /// The whole resume feature depends on this snapshot surviving encode/decode,
    /// since it's persisted to UserDefaults as JSON.
    @Test func roundTripsProgress() throws {
        let snapshot = ResumeSnapshot(
            workoutID: "w1",
            workoutName: "Push Day",
            exerciseIndex: 2,
            setIndex: 1,
            setCount: 4,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            loggedWeights: ["bench": [60, 62.5]],
            loggedReps: ["bench": [8, 8]]
        )
        let decoded = try JSONDecoder().decode(ResumeSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    /// Pauses survive a kill, so a resumed session still leaves them out of Health.
    @Test func roundTripsPauses() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = ResumeSnapshot(workoutID: "w1", workoutName: "Push Day", exerciseIndex: 0, setIndex: 0,
                                      setCount: 3, startDate: start, loggedWeights: [:], loggedReps: [:])
        snapshot.pauseIntervals = [DateInterval(start: start.addingTimeInterval(60), duration: 120)]
        snapshot.pausedAt = start.addingTimeInterval(600)
        let decoded = try JSONDecoder().decode(ResumeSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    /// A snapshot saved by a version without pause tracking still resumes.
    @Test func decodesSnapshotWithoutPauses() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let old = ResumeSnapshot(workoutID: "w1", workoutName: "Push Day", exerciseIndex: 0, setIndex: 0,
                                 setCount: 3, startDate: start, loggedWeights: [:], loggedReps: [:])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "pauseIntervals")
        json.removeValue(forKey: "pausedAt")
        let decoded = try JSONDecoder().decode(ResumeSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.pauseIntervals == nil && decoded.pausedAt == nil)
        #expect(decoded.workoutID == "w1")
    }
}

// MARK: - Gym catalog completeness

@Suite("GymExerciseCatalog completeness")
struct GymExerciseCatalogCompletenessTests {

    private func def(_ id: String) -> GymExerciseDefinition? {
        GymExerciseCatalog.all.first { $0.id == id }
    }

    /// Common movements users look for must exist under the muscle group they'd
    /// filter by — the regression that hid Bench Press under "Upper Body".
    @Test func hasCommonPressesUnderCorrectGroup() {
        #expect(def("seed-exercise-bench-press")?.muscleGroup == WorkoutCategory.chest.rawValue)
        #expect(def("seed-exercise-machine-chest-press")?.muscleGroup == WorkoutCategory.chest.rawValue)
        #expect(def("seed-exercise-shoulder-press")?.muscleGroup == WorkoutCategory.shoulders.rawValue)
        #expect(def("seed-exercise-incline-dumbbell-press") != nil)
    }

    /// Seed IDs must be unique — a duplicate would collapse two movements into
    /// one Exercise row when materialized (they're matched by id).
    @Test func seedIDsAreUnique() {
        let ids = GymExerciseCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Every definition needs a non-empty symbol so list rows don't render blank.
    @Test func everyDefinitionHasSymbol() {
        for def in GymExerciseCatalog.all {
            #expect(!def.symbol.isEmpty, "\(def.id) has no symbol")
        }
    }

    /// A symbol is either one of the app's assets or an SF Symbol — a typo in
    /// either would silently fall back to the generic muscle-group icon.
    @Test func everySymbolResolvesToAssetOrSFSymbol() {
        for def in GymExerciseCatalog.all {
            #expect(ExerciseSymbol(name: def.symbol) != nil, "\(def.id): '\(def.symbol)' is neither an asset nor an SF Symbol")
        }
    }

    /// The 50–200 px bitmaps look blurry at the active-workout ring's size, and
    /// the text-glyph SVGs render as a "?" box; neither may be offered again.
    @Test @MainActor func noLowResolutionOrBrokenSymbols() {
        let unusable: Set<String> = ["Pull-UpIcon", "Tricep DipsIcon", "Downward Facing DogIcon",
                                     "burpeesWithPushUpsSymbol", "deadlift", "sprintSymbol"]
        for def in GymExerciseCatalog.all {
            #expect(!unusable.contains(def.symbol), "\(def.id) uses '\(def.symbol)'")
        }
        for symbol in SymbolChangeView(selectedSymbol: .constant("")).exerciseSymbolDictionary.values {
            #expect(!unusable.contains(symbol), "symbol picker offers '\(symbol)'")
        }
    }

    /// Custom exercises may still store the broken asset names; they must show
    /// the SF Symbol the asset was meant to contain, not the "?" box.
    @Test func textGlyphAssetsResolveToTheirSFSymbol() {
        #expect(ExerciseSymbol(name: "deadlift") == .system("figure.strengthtraining.traditional"))
        #expect(ExerciseSymbol(name: "sprintSymbol") == .system("figure.run"))
        #expect(ExerciseSymbol(name: "plankSymbol") == .asset("plankSymbol"))
        #expect(ExerciseSymbol(name: "not Found") == nil)
    }

    /// A count drift here means an entry was accidentally dropped or
    /// duplicated. Seed ids are permanent, so this number only ever grows.
    @Test func catalogHasExpectedSize() {
        #expect(GymExerciseCatalog.all.count == 170)
    }

    /// The muscle-group filters shown in the UI must each have something behind
    /// them. Mobility/Flexibility used to be an empty category — the filter was
    /// there, no exercise was ever filed under it.
    @Test func everyBrowsableMuscleGroupHasExercises() {
        let browsable: [WorkoutCategory] = [.fullbody, .upperbody, .arms, .back, .legs, .core,
                                            .chest, .shoulders, .cardio, .hiit, .yoga,
                                            .mobilityFlexibility]
        for group in browsable {
            let matches = GymExerciseCatalog.all.filter { $0.muscleGroup == group.rawValue }
            #expect(!matches.isEmpty, "\(group.displayName) has no exercises")
        }
    }

    /// The staple barbell lifts every gym-goer searches for must exist, under a
    /// muscle group they'd actually look in.
    @Test func hasTheCoreBarbellLifts() {
        #expect(def("seed-exercise-bench-press")?.muscleGroup == WorkoutCategory.chest.rawValue)
        #expect(def("seed-exercise-back-squat")?.muscleGroup == WorkoutCategory.legs.rawValue)
        #expect(def("seed-exercise-overhead-press")?.muscleGroup == WorkoutCategory.shoulders.rawValue)
        #expect(def("seed-exercise-barbell-row")?.muscleGroup == WorkoutCategory.back.rawValue)
        // The deadlift used to be filed under "Full body", which meant it never
        // appeared on a back or leg day in any generated session.
        #expect(def("seed-exercise-deadlifts")?.muscleGroup == WorkoutCategory.back.rawValue)
    }

    /// Biceps are trained on pull days and triceps on push days, whatever
    /// filter they browse under. Getting this wrong is what put curls on push
    /// day and tricep pushdowns on back day.
    @Test func armWorkIsBucketedByFunctionNotByFilter() {
        for id in ["seed-exercise-bicep-curl", "seed-exercise-hammer-curls",
                   "seed-exercise-barbell-curl", "seed-exercise-preacher-curl"] {
            #expect(def(id)?.bucket == .pull, "\(id) should be pull-day work")
        }
        for id in ["seed-exercise-tricep-pushdown", "seed-exercise-skullcrushers",
                   "seed-exercise-overhead-tricep-extension", "seed-exercise-dips"] {
            #expect(def(id)?.bucket == .push, "\(id) should be push-day work")
        }
        // Rear delts and traps go with the pulling, not the pressing.
        #expect(def("seed-exercise-face-pull")?.bucket == .pull)
        #expect(def("seed-exercise-shrugs")?.bucket == .pull)
    }

    /// An exercise that needs a machine, a bar or a bench must say so, or it
    /// leaks into "no equipment" sessions.
    @Test func equipmentDependentExercisesDeclareTheirEquipment() {
        #expect(def("seed-exercise-hyperextension")?.equipment.isEmpty == false)
        #expect(def("seed-exercise-tricep-dips")?.equipment.contains(Equipment.weightBench.rawValue) == true)
        #expect(def("seed-exercise-lat-pulldown")?.equipment.contains(Equipment.cableMaschine.rawValue) == true)
        #expect(def("seed-exercise-pull-ups")?.equipment.contains(Equipment.pullUpBar.rawValue) == true)
    }

    /// Time-based movements must carry no rep target (the workout timer drives
    /// them) and rep-based ones must carry one.
    @Test func repCountsMatchHowTheMovementIsPerformed() {
        for id in ["seed-exercise-plank", "seed-exercise-side-plank", "seed-exercise-wall-sits",
                   "seed-exercise-rowing", "seed-exercise-jump-rope", "seed-exercise-sun-salutation"] {
            #expect(def(id)?.repCount == 0, "\(id) is held for time and should have no rep target")
        }
        for id in ["seed-exercise-bench-press", "seed-exercise-back-squat", "seed-exercise-squats",
                   "seed-exercise-bicep-curl", "seed-exercise-pushups"] {
            #expect((def(id)?.repCount ?? 0) > 0, "\(id) is a rep-based lift and needs a rep target")
        }
    }

    /// Difficulty drives which exercises a tier is allowed to use, so a
    /// mis-rating quietly changes what gets programmed.
    @Test func difficultyRatingsAreInRangeAndSane() {
        for def in GymExerciseCatalog.all {
            #expect((1...3).contains(def.difficultyInt), "\(def.id) has difficulty \(def.difficultyInt)")
        }
        // Push-ups were rated "hard" (3) — harder than the bench press, which
        // excluded them from every beginner session.
        #expect(def("seed-exercise-pushups")?.difficultyInt == 1)
        #expect(def("seed-exercise-goblet-squat")?.difficultyInt == 1)
        #expect(def("seed-exercise-deadlifts")?.difficultyInt == 3)
        #expect(def("seed-exercise-pistol-squat")?.difficultyInt == 3)
    }
}

// MARK: - Template catalog (preset-catalog generator)

@Suite("Template catalog generation")
struct TemplateCatalogGenerationTests {

    private func plan(_ template: CatalogTemplate, _ tier: CatalogTier) -> CatalogWorkoutPlan? {
        CatalogWorkoutBuilder.strengthPlan(template: template, tier: tier)
    }

    /// Every blueprint id must resolve against the catalog. A typo would
    /// otherwise ship a workout silently missing an exercise.
    @Test func everyBlueprintIDResolves() {
        for template in CatalogTemplate.allCases {
            for tier in CatalogTier.allCases {
                let ids = CatalogSessionBlueprints.exerciseIDs(for: template, tier: tier)
                for id in ids {
                    #expect(GymExerciseCatalog.byID[id] != nil,
                            "\(template) \(tier) references unknown exercise \(id)")
                }
                #expect(plan(template, tier) != nil, "\(template) \(tier) produced no plan")
            }
        }
        for tier in YogaMobilityTier.allCases {
            for id in CatalogSessionBlueprints.exerciseIDs(for: tier) {
                #expect(GymExerciseCatalog.byID[id] != nil, "\(tier) references unknown exercise \(id)")
            }
            #expect(CatalogWorkoutBuilder.yogaPlan(tier: tier) != nil, "\(tier) produced no plan")
        }
    }

    /// No session may repeat an exercise, and no session may spend more than
    /// two of its slots on one movement pattern — that's what produced a
    /// "Legs — Advanced" carrying two different calf raises and a "Push —
    /// Advanced" with three curl variations.
    ///
    /// Two is the ceiling rather than one because a compound plus its isolation
    /// is real programming: a flat press and an incline press, or dips followed
    /// by skullcrushers, are not the same exercise twice. Conditioning work is
    /// exempt — a HIIT circuit is four conditioning movements by design.
    @Test func noSessionRepeatsAnExerciseOrOverloadsAPattern() {
        for template in CatalogTemplate.allCases {
            for tier in CatalogTier.allCases {
                guard let exercises = plan(template, tier)?.exercises else { continue }
                let ids = exercises.map(\.id)
                #expect(Set(ids).count == ids.count, "\(template) \(tier) repeats an exercise")

                var tally: [String: Int] = [:]
                for exercise in exercises where exercise.role != .conditioning {
                    tally[String(describing: exercise.pattern), default: 0] += 1
                }
                for (pattern, count) in tally {
                    #expect(count <= 2,
                            "\(template) \(tier) spends \(count) slots on \(pattern)")
                }
            }
        }
    }

    /// A strength session has to start with a real compound. "Push — Advanced"
    /// used to open with a cable crossover and never press anything.
    @Test func everyStrengthSessionIsAnchoredByACompound() {
        let strengthTemplates: [CatalogTemplate] = [.push, .pull, .leg, .fullBodyA, .fullBodyB, .upper]
        for template in strengthTemplates {
            for tier in CatalogTier.allCases {
                guard let exercises = plan(template, tier)?.exercises else { continue }
                #expect(exercises.first?.role == .primary,
                        "\(template) \(tier) opens with \(exercises.first?.name ?? "nothing"), not a compound")
                let compounds = exercises.filter { $0.role <= .secondary }
                #expect(compounds.count >= 2,
                        "\(template) \(tier) has only \(compounds.count) compound movement(s)")
            }
        }
    }

    /// Compounds first, accessory and isolation work after — the order you'd
    /// actually train in, because the heavy lifts are the ones that need you
    /// fresh. The order *within* the compounds is a deliberate design choice
    /// per session (a full-body day alternates squat → press → pull), so this
    /// only asserts the split, not a total ordering.
    @Test func compoundsComeBeforeIsolationWork() {
        for template in CatalogTemplate.allCases {
            for tier in CatalogTier.allCases {
                guard let exercises = plan(template, tier)?.exercises else { continue }
                let lastCompound = exercises.lastIndex { $0.role <= .secondary }
                let firstAccessory = exercises.firstIndex { $0.role > .secondary && $0.role != .conditioning }
                if let lastCompound, let firstAccessory {
                    #expect(lastCompound < firstAccessory,
                            "\(template) \(tier) puts isolation work before a compound: \(exercises.map(\.name))")
                }
            }
        }
    }

    /// A push day must actually press and a pull day must actually pull — the
    /// bug that produced a "Pull — Beginner" of Superman and two curls.
    @Test func splitSessionsTrainTheirOwnBucket() {
        for tier in CatalogTier.allCases {
            let push = plan(.push, tier)?.exercises ?? []
            #expect(push.allSatisfy { $0.bucket == .push },
                    "Push \(tier) contains non-push work: \(push.filter { $0.bucket != .push }.map(\.name))")
            #expect(push.contains { $0.pattern == .horizontalPress || $0.pattern == .verticalPress },
                    "Push \(tier) has no pressing movement")

            let pull = plan(.pull, tier)?.exercises ?? []
            #expect(pull.allSatisfy { $0.bucket == .pull },
                    "Pull \(tier) contains non-pull work: \(pull.filter { $0.bucket != .pull }.map(\.name))")
            #expect(pull.contains { $0.pattern == .horizontalPull || $0.pattern == .verticalPull },
                    "Pull \(tier) has no pulling movement")

            let legs = plan(.leg, tier)?.exercises ?? []
            #expect(legs.allSatisfy { $0.bucket == .legs }, "Legs \(tier) contains non-leg work")
            #expect(legs.contains { $0.pattern == .squat }, "Legs \(tier) has no squatting movement")
        }
        // Legs — Intermediate and Advanced should hinge as well as squat.
        for tier in [CatalogTier.intermediate, .advanced] {
            #expect(plan(.leg, tier)?.exercises.contains { $0.pattern == .hinge } == true,
                    "Legs \(tier) has no hip hinge")
        }
    }

    /// A full-body session covers the body: a squat or hinge, a press and a pull.
    @Test func fullBodySessionsCoverTheMajorPatterns() {
        for template in [CatalogTemplate.fullBodyA, .fullBodyB] {
            for tier in CatalogTier.allCases {
                let exercises = plan(template, tier)?.exercises ?? []
                #expect(exercises.contains { $0.pattern == .squat || $0.pattern == .hinge },
                        "\(template) \(tier) has no squat or hinge")
                #expect(exercises.contains { $0.pattern == .horizontalPress || $0.pattern == .verticalPress },
                        "\(template) \(tier) has no press")
                #expect(exercises.contains { $0.pattern == .horizontalPull || $0.pattern == .verticalPull },
                        "\(template) \(tier) has no pull")
            }
        }
    }

    /// An upper-body session must cover chest, back and shoulders — not just
    /// whichever group happened to sort first.
    @Test func upperBodySessionsCoverChestBackAndShoulders() {
        for tier in CatalogTier.allCases {
            let groups = Set(plan(.upper, tier)?.exercises.map(\.muscleGroup) ?? [])
            #expect(groups.contains(WorkoutCategory.chest.rawValue), "Upper \(tier) skips chest")
            #expect(groups.contains(WorkoutCategory.back.rawValue), "Upper \(tier) skips back")
            #expect(groups.contains(WorkoutCategory.shoulders.rawValue), "Upper \(tier) skips shoulders")
        }
    }

    /// The bodyweight/core/cardio templates promise "no equipment". They must
    /// use nothing beyond a mat or a jump rope — a back extension needs a
    /// roman chair and has no business in a living-room circuit.
    @Test func bodyweightTemplatesUseNoRealEquipment() {
        for template in CatalogTemplate.allCases where template.requiresBodyweightOnly {
            for tier in CatalogTier.allCases {
                for exercise in plan(template, tier)?.exercises ?? [] {
                    let extra = Set(exercise.equipment)
                        .subtracting(CatalogTemplate.bodyweightFriendlyEquipment)
                    #expect(extra.isEmpty,
                            "\(template) \(tier) needs equipment for \(exercise.name)")
                }
            }
        }
    }

    /// A tier must not program movements above its technical level, and each
    /// tier should be harder than the one below it.
    @Test func tiersRespectTheirDifficultyCeiling() {
        for template in CatalogTemplate.allCases {
            var previousAverage = 0.0
            for tier in CatalogTier.allCases {
                let exercises = plan(template, tier)?.exercises ?? []
                for exercise in exercises {
                    #expect(exercise.difficultyInt <= tier.maxDifficulty,
                            "\(template) \(tier) programs \(exercise.name) (difficulty \(exercise.difficultyInt))")
                }
                let average = Double(exercises.map(\.difficultyInt).reduce(0, +)) / Double(max(exercises.count, 1))
                #expect(average >= previousAverage,
                        "\(template) \(tier) is easier than the tier below it")
                previousAverage = average
            }
        }
    }

    /// Exercise count and session length must both grow with the tier.
    @Test func higherTiersAreLongerSessions() {
        for template in CatalogTemplate.allCases {
            let beginner = plan(template, .beginner)
            let advanced = plan(template, .advanced)
            #expect((beginner?.exercises.count ?? 0) >= 4, "\(template) beginner is too thin")
            #expect((advanced?.exercises.count ?? 0) > (beginner?.exercises.count ?? 0),
                    "\(template) advanced isn't bigger than beginner")
            #expect((advanced?.durationMinutes ?? 0) > (beginner?.durationMinutes ?? 0),
                    "\(template) advanced isn't longer than beginner")
        }
    }

    /// Durations have to be believable: six barbell exercises for four sets is
    /// an hour, not the flat 36 minutes the old `count × 6` formula produced.
    @Test func durationsAreRealistic() {
        for template in CatalogTemplate.allCases {
            for tier in CatalogTier.allCases {
                guard let plan = plan(template, tier) else { continue }
                #expect((15...120).contains(plan.durationMinutes),
                        "\(template) \(tier) claims \(plan.durationMinutes) min")
            }
        }
        // A six-exercise, four-set barbell session is a real hour of training.
        #expect((plan(.leg, .advanced)?.durationMinutes ?? 0) >= 55)
    }

    /// Heavy strength work runs as straight sets; only conditioning circuits.
    @Test func onlyConditioningTemplatesAreCircuits() {
        #expect(CatalogWorkoutBuilder.strengthPlan(template: .leg, tier: .advanced)?.straightSets == true)
        #expect(CatalogWorkoutBuilder.strengthPlan(template: .cardioHIIT, tier: .beginner)?.straightSets == false)
        #expect(CatalogWorkoutBuilder.strengthPlan(template: .bodyweightCircuit, tier: .beginner)?.straightSets == false)
    }

    /// The yoga flows and the mobility routine must be distinct sessions, and
    /// the mobility one has to actually be mobility work.
    @Test func yogaAndMobilityTiersAreDistinct() {
        let short = Set(CatalogSessionBlueprints.exerciseIDs(for: .short))
        let full = Set(CatalogSessionBlueprints.exerciseIDs(for: .full))
        let mobility = Set(CatalogSessionBlueprints.exerciseIDs(for: .mobility))

        #expect(short.isSubset(of: full), "The short flow should be a subset of the full one")
        #expect(full.count > short.count)
        #expect(mobility.intersection(full).count <= 1, "Mobility duplicates the yoga flow")

        for id in mobility {
            #expect(GymExerciseCatalog.byID[id]?.role == .mobility, "\(id) isn't mobility work")
        }
        #expect(CatalogWorkoutBuilder.yogaPlan(tier: .mobility)?.muscleGroup
                == WorkoutCategory.mobilityFlexibility.rawValue)
    }

    /// Catalog generation must be reproducible across devices/relaunches — no
    /// `Date()` dependency, unlike the live "For You" generator.
    @Test func strengthPlanGenerationIsDeterministic() {
        for template in CatalogTemplate.allCases {
            for tier in CatalogTier.allCases {
                let first = plan(template, tier)
                let second = plan(template, tier)
                #expect(first?.exercises.map(\.id) == second?.exercises.map(\.id),
                        "\(template) \(tier) picked different exercises on repeat generation")
            }
        }
    }

    /// Workout ids are derived from `rawValue` + tier and are permanent —
    /// changing one orphans every install's seeded content.
    @Test func templateRawValuesAreStable() {
        #expect(Set(CatalogTemplate.allCases.map(\.rawValue)) ==
                ["push", "pull", "leg", "fullBodyA", "fullBodyB", "upper",
                 "bodyweightCircuit", "core", "cardioHIIT"])
        #expect(Set(YogaMobilityTier.allCases.map(\.nameKeyComponent)) == ["Short", "Full", "Mobility"])
    }
}

// MARK: - Template catalog seeding (SwiftData round-trip)

@Suite("Template catalog seeding")
@MainActor
struct TemplateCatalogSeedingTests {

    /// In-memory SwiftData context mirroring the app's schema.
    private func makeContext() throws -> ModelContext {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// 9 templates × 3 tiers + 3 yoga/mobility flows = 30 workouts, and 12
    /// plans. Re-seeding must be a no-op — `seedTemplateCatalog` reconciles as
    /// well as inserts, and it runs on every launch path, so a second call
    /// must not duplicate anything.
    @Test func seedsExpectedCountAndIsIdempotent() throws {
        let expectedWorkouts = CatalogTemplate.allCases.count * CatalogTier.allCases.count
            + YogaMobilityTier.allCases.count
        let ctx = try makeContext()
        let first = seedTemplateCatalog(modelContext: ctx, existingExercises: [])
        #expect(first.workouts.count == expectedWorkouts)
        #expect(first.plans.count == 12)

        let existingExercises = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        let second = seedTemplateCatalog(modelContext: ctx, existingExercises: existingExercises)
        #expect(second.workouts.count == expectedWorkouts)
        #expect(second.plans.count == 12)

        #expect(try ctx.fetch(FetchDescriptor<Workout>()).count == expectedWorkouts)
        #expect(try ctx.fetch(FetchDescriptor<Plan>()).count == 12)
        // Reconciling must reuse the exercise rows, not insert a second copy
        // of every movement it touches.
        let exerciseIDs = try ctx.fetch(FetchDescriptor<Exercise>()).map(\.id)
        #expect(Set(exerciseIDs).count == exerciseIDs.count, "re-seeding duplicated exercises")
    }

    /// Re-seeding over content that has drifted must pull it back to the
    /// blueprint — the whole reason `seedTemplateCatalog` reconciles instead of
    /// only inserting. Without this, a fixed workout would only ever reach
    /// users installing the app for the first time.
    @Test func reseedingRepairsDriftedPresetContent() throws {
        let ctx = try makeContext()
        let first = seedTemplateCatalog(modelContext: ctx, existingExercises: [])

        guard let workout = first.workouts.first(where: { $0.id == "seed-workout-push-advanced" }) else {
            Issue.record("Push — Advanced missing from the seeded catalog")
            return
        }
        let blueprintIDs = workout.exercisesSequenceID
        workout.name = "Something Else"
        workout.duration = 3
        workout.isHidden = true
        workout.exercisesSequenceID = ["seed-exercise-bicep-curl"]

        let existingExercises = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        seedTemplateCatalog(modelContext: ctx, existingExercises: existingExercises)

        #expect(workout.name == "Push — Advanced")
        #expect(workout.duration > 3)
        #expect(workout.isHidden == false)
        #expect(workout.exercisesSequenceID == blueprintIDs)
    }

    /// A built-in name's level isn't shown — it has its own place — while the
    /// stored name, the key the deduplication groups by, keeps it. Your own
    /// workout's name is shown as typed.
    @Test func catalogNamesShowWithoutTheirLevel() {
        #expect(CatalogName.withoutLevel("Push — Advanced") == "Push")
        #expect(CatalogName.withoutLevel("Push Pull Legs — Beginner") == "Push Pull Legs")
        #expect(CatalogName.withoutLevel("Yoga Flow — Short") == nil)
        let preset = Workout(id: "p", infoText: "", isUserGenerated: false, muscleGroup: 7, setLength: 4, straightSets: true,
                             difficultyInt: 3, name: "Push — Advanced", duration: 60, exercisesSequenceID: [],
                             finishedExercisesSequence: [], workoutActivityType: 50, workoutSessionLocation: 2)
        #expect(preset.displayName == "Push")
        #expect(preset.name == "Push — Advanced")
        // The watch's row shows the level next to the exercise count.
        #expect(WatchWorkoutSummary(workout: preset).name == "Push")
        #expect(WatchWorkoutSummary(workout: preset).level == DifficultyLevel.advanced.name)
        let mine = Workout(id: "m", infoText: "", isUserGenerated: true, muscleGroup: 7, setLength: 4, straightSets: true,
                           difficultyInt: 3, name: "Leg day — Advanced", duration: 60, exercisesSequenceID: [],
                           finishedExercisesSequence: [], workoutActivityType: 50, workoutSessionLocation: 2)
        #expect(mine.displayName == "Leg day — Advanced")
        #expect(WatchWorkoutSummary(workout: mine).level == nil)
    }

    /// A preset workout must never ship with an exercise list that disagrees
    /// with the order the session is meant to be trained in — several views
    /// read `exercisesSequenceID` rather than the relationship.
    @Test func seededWorkoutSequencesMatchTheirExercises() throws {
        let ctx = try makeContext()
        let result = seedTemplateCatalog(modelContext: ctx, existingExercises: [])
        for workout in result.workouts where !workout.isUserGenerated {
            let sequence = workout.exercisesSequenceID
            #expect(!sequence.isEmpty, "\(workout.name) has no exercises")
            #expect(Set(sequence) == Set(workout.exercises?.map(\.id) ?? []),
                    "\(workout.name)'s sequence disagrees with its exercise relationship")
        }
    }

    /// Every seeded plan's `workoutsSequenceIDs` must resolve to workouts that
    /// actually exist and belong to it — the id array is what plan-progress UI
    /// reads directly (`PlanPreview`, `PlansView`, `PlansCards`).
    @Test func everyPlansWorkoutSequenceResolves() throws {
        let ctx = try makeContext()
        let result = seedTemplateCatalog(modelContext: ctx, existingExercises: [])
        let workoutByID = Dictionary(uniqueKeysWithValues: result.workouts.map { ($0.id, $0) })

        for plan in result.plans {
            #expect(!plan.workoutsSequenceIDs.isEmpty, "\(plan.name) has no workouts")
            for id in plan.workoutsSequenceIDs {
                #expect(workoutByID[id] != nil, "\(plan.name) references missing workout \(id)")
            }
        }
    }
}

// MARK: - Plan progress

@Suite("Plan progress")
struct PlanProgressTests {

    @Test func firstIncompleteWorkoutIDSkipsCompletedSlots() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", workoutsSequenceIDs: ["a", "b", "c"],
                        finishedWorkoutsSequence: ["a"])
        #expect(plan.firstIncompleteWorkoutID() == "b")
    }

    @Test func firstIncompleteWorkoutIDIsNilWhenAllComplete() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", workoutsSequenceIDs: ["a", "b"],
                        finishedWorkoutsSequence: ["a", "b"])
        #expect(plan.firstIncompleteWorkoutID() == nil)
    }

    @Test func firstIncompleteWorkoutIDSkipsDeletedWorkouts() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", workoutsSequenceIDs: ["a", "b", "c"],
                        finishedWorkoutsSequence: ["a"])
        #expect(plan.firstIncompleteWorkoutID(existingIDs: ["a", "c"]) == "c")
    }

    @Test func watchCompletionAdvancesOnlyPlansWhereItIsNext() {
        let mine = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "Mine",
                        interval: [:], intervalType: "", isUserGenerated: true,
                        workoutsSequenceIDs: ["a", "b"], finishedWorkoutsSequence: [])
        let notNext = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "Other",
                           interval: [:], intervalType: "", isUserGenerated: true,
                           workoutsSequenceIDs: ["b", "a"], finishedWorkoutsSequence: [])
        let preset = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "Preset",
                          interval: [:], intervalType: "", workoutsSequenceIDs: ["a"], finishedWorkoutsSequence: [])

        let updated = Plan.recordCompletion(ofWorkoutID: "a", in: [mine, notNext, preset])

        #expect(updated.map(\.name) == ["Mine"])
        #expect(mine.finishedWorkoutsSequence == ["a"])
        #expect(mine.firstIncompleteWorkoutID() == "b")
        #expect(notNext.finishedWorkoutsSequence.isEmpty)   // "a" isn't its next workout
        #expect(preset.finishedWorkoutsSequence.isEmpty)    // not the user's plan
    }

    @Test func repeatedWorkoutIsDoneOncePerCompletion() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", isUserGenerated: true,
                        workoutsSequenceIDs: ["a", "b", "a"], finishedWorkoutsSequence: [])

        Plan.recordCompletion(ofWorkoutID: "a", in: [plan])
        #expect(plan.completedSlots == [true, false, false])   // only the first "a"
        #expect(plan.firstIncompleteWorkoutID() == "b")

        Plan.recordCompletion(ofWorkoutID: "b", in: [plan])
        #expect(plan.firstIncompleteSlot() == 2)
        #expect(plan.firstIncompleteWorkoutID() == "a")

        Plan.recordCompletion(ofWorkoutID: "a", in: [plan])
        #expect(plan.completedSlots == [true, true, true])
        #expect(plan.firstIncompleteWorkoutID() == nil)

        plan.undoCompletion(ofWorkoutID: "a")
        #expect(plan.completedSlots == [true, true, false])
    }

    @Test func undoCompletionRemovesOnlyTheLatestEntry() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", isUserGenerated: true,
                        workoutsSequenceIDs: ["a", "b", "a"], finishedWorkoutsSequence: ["a", "b"])
        plan.undoCompletion(ofWorkoutID: "b")
        #expect(plan.finishedWorkoutsSequence == ["a"])
        plan.undoCompletion(ofWorkoutID: "x")   // not recorded: no change
        #expect(plan.finishedWorkoutsSequence == ["a"])
    }

    @Test func removeWorkoutIDDropsSequenceAndProgress() {
        let plan = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "T",
                        interval: [:], intervalType: "", workoutsSequenceIDs: ["a", "b", "c"],
                        finishedWorkoutsSequence: ["a", "b"])
        plan.removeWorkoutID("b")
        #expect(plan.workoutsSequenceIDs == ["a", "c"])
        #expect(plan.finishedWorkoutsSequence == ["a"])
        #expect(plan.firstIncompleteWorkoutID() == "c")
    }
}

// MARK: - Watch workout library

@Suite("Watch workout library")
struct WatchLibraryTests {

    private func workout(_ id: String, mine: Bool = false, saved: Bool = false, hidden: Bool = false,
                         group: Int = 1, activity: HKWorkoutActivityType = .functionalStrengthTraining) -> Workout {
        let workout = Workout(id: id, infoText: "", isUserGenerated: mine, muscleGroup: group,
                              setLength: 3, straightSets: false, difficultyInt: 2, name: id, duration: 20,
                              exercisesSequenceID: ["e1", "e2"], finishedExercisesSequence: [],
                              workoutActivityType: Int(activity.rawValue),
                              workoutSessionLocation: HKWorkoutSessionLocationType.indoor.rawValue)
        workout.isSaved = saved   // `Workout.init` ignores its `isSaved` argument
        workout.isHidden = hidden
        return workout
    }

    private func plan(_ name: String, ids: [String], done: [String] = []) -> Plan {
        Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: name,
             interval: [:], intervalType: "", isUserGenerated: true,
             workoutsSequenceIDs: ids, finishedWorkoutsSequence: done)
    }

    @Test func planShowsItsNextWorkoutAndItsWorkoutsStayOutOfOwn() {
        let workouts = [workout("p1", mine: true), workout("p2", mine: true), workout("solo", mine: true)]
        let library = WatchLibrary.make(workouts: workouts, plans: [plan("Plan", ids: ["p1", "p2"], done: ["p1"])])

        #expect(library.plans.count == 1)
        #expect(library.plans.first?.next.id == "p2")
        #expect(library.plans.first?.done == 1)
        #expect(library.plans.first?.total == 2)
        #expect(library.own.map(\.id) == ["solo"])
    }

    @Test func finishedPlanIsNotListed() {
        let library = WatchLibrary.make(workouts: [workout("p1", mine: true)],
                                        plans: [plan("Plan", ids: ["p1"], done: ["p1"])])
        #expect(library.plans.isEmpty)
    }

    @Test func catalogTakesSavedFirstThenOnePerShelf() {
        let workouts = [
            workout("legs1", group: 5), workout("legs2", group: 5),
            workout("upper", group: 2),
            workout("hiit", group: 9),
            workout("run", group: 9, activity: .running),
            workout("yoga", group: 11),
            workout("savedCore", saved: true, group: 6),
            workout("hidden", hidden: true, group: 2),
            workout("mine", mine: true, group: 2),
        ]
        let library = WatchLibrary.make(workouts: workouts, plans: [])

        #expect(library.catalog.map(\.id) == ["savedCore", "upper", "legs1", "hiit", "run", "yoga"])
        #expect(library.catalog.count <= WatchLibrary.maxCatalog)
    }

    @Test func catalogSkipsAPlansNextWorkout() {
        let workouts = [workout("upperA", group: 2), workout("upperB", group: 2)]
        let saved = Plan(goal: PlanGoal.muscleBuilding.rawValue, infoText: "", muscleGroup: 1, name: "Preset",
                         interval: [:], intervalType: "", workoutsSequenceIDs: ["upperA"])
        saved.isSaved = true   // `Plan.init` ignores its `isSaved` argument
        let library = WatchLibrary.make(workouts: workouts, plans: [saved])

        #expect(library.plans.first?.next.id == "upperA")
        #expect(library.catalog.map(\.id) == ["upperB"])
    }

    @Test func libraryRoundTripsThroughJSON() throws {
        let library = WatchLibrary.make(workouts: [workout("p1", mine: true), workout("upper", group: 2)],
                                        plans: [plan("Plan", ids: ["p1"])],
                                        now: Date(timeIntervalSince1970: 1_000))
        let decoded = try JSONDecoder().decode(WatchLibrary.self, from: JSONEncoder().encode(library))
        #expect(decoded == library)
    }
}

// MARK: - Weekly goals

@Suite("Weekly goals")
struct WeeklyGoalsTests {

    private func finished(daysAgo: Int, workoutType: HKWorkoutActivityType, now: Date) -> FinishedWorkout {
        let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return FinishedWorkout(endDate: end, name: "T", startDate: end.addingTimeInterval(-1800),
                               muscleGroup: 1, workoutType: Int(workoutType.rawValue), exercisesSequenceID: [])
    }

    @Test func categoryMatchesExpectedActivityTypes() {
        let run = FinishedWorkout(endDate: .now, name: "R", startDate: .now, muscleGroup: 1,
                                  workoutType: Int(HKWorkoutActivityType.running.rawValue), exercisesSequenceID: [])
        let strength = FinishedWorkout(endDate: .now, name: "S", startDate: .now, muscleGroup: 1,
                                       workoutType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue), exercisesSequenceID: [])
        #expect(GoalCategory.running.matches(run))
        #expect(!GoalCategory.gym.matches(run))
        #expect(GoalCategory.gym.matches(strength))
        #expect(!GoalCategory.running.matches(strength))
    }

    /// A workout saved as the wrong sport (a swim the watch reported as
    /// strength training) can be changed to any sport, which then decides
    /// its goal; only one "Strength Training" is offered.
    @Test func workoutTypeChoices() {
        for current in [HKWorkoutActivityType.functionalStrengthTraining, .traditionalStrengthTraining, .swimming] {
            let (popular, others) = HKWorkoutActivityType.pickerSections(current: current)
            let all = popular + others
            #expect(all.contains(current), "\(current.rawValue) missing")
            #expect(Set(all).count == all.count, "a type is listed twice")
            #expect(all.filter { $0 == .functionalStrengthTraining || $0 == .traditionalStrengthTraining }.count == 1)
            #expect(all.contains(.swimming) && all.contains(.yoga))
        }
        #expect(HKWorkoutActivityType.pickerSections(current: .functionalStrengthTraining).popular.first == .functionalStrengthTraining)
        #expect(HKWorkoutActivityType.pickerSections(current: .swimming).popular.first == .traditionalStrengthTraining)
        // A type the app doesn't offer, recorded elsewhere, stays listed.
        #expect(HKWorkoutActivityType.pickerSections(current: .cardioDance).others.contains(.cardioDance))

        let swim = FinishedWorkout(endDate: .now, name: "Swim", startDate: .now, muscleGroup: 100,
                                   workoutType: Int(HKWorkoutActivityType.functionalStrengthTraining.rawValue), exercisesSequenceID: [])
        #expect(GoalCategory.gym.matches(swim))
        swim.workoutType = Int(HKWorkoutActivityType.swimming.rawValue)
        #expect(!GoalCategory.gym.matches(swim))
        #expect(GoalCategory.sport(.swimming).matches(swim))
    }

    /// A session from last week (or later) must not count toward this week's
    /// progress — otherwise a goal could look permanently met.
    @Test func completedThisWeekOnlyCountsCurrentWeek() {
        // Anchor "now" to a Wednesday so both a same-week and a >7-day-ago
        // session land unambiguously on opposite sides of the week boundary.
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.weekday = 4 // Wed
        let now = Calendar.current.date(from: components) ?? .now

        let thisWeek = finished(daysAgo: 1, workoutType: .running, now: now)
        let lastWeek = finished(daysAgo: 10, workoutType: .running, now: now)
        #expect(completedThisWeek(.running, history: [thisWeek, lastWeek], now: now) == 1)
    }

    /// Rotates through easy/tempo/intervals so consecutive suggestions vary,
    /// but low readiness always forces an easy run regardless of rotation.
    @Test func runningSessionRotatesByCompletedCount() {
        let ready = RecoveryEstimate(score: 85, band: .ready, factors: [], hasHealthData: true)
        #expect(RunningSessionBuilder.nextSession(completedThisWeek: 0, recovery: ready).kind == .easy)
        #expect(RunningSessionBuilder.nextSession(completedThisWeek: 1, recovery: ready).kind == .tempo)
        #expect(RunningSessionBuilder.nextSession(completedThisWeek: 2, recovery: ready).kind == .intervals)

        let rest = RecoveryEstimate(score: 30, band: .rest, factors: [], hasHealthData: true)
        #expect(RunningSessionBuilder.nextSession(completedThisWeek: 2, recovery: rest).kind == .easy)
    }

    @Test func runningSessionDurationScalesWithReadiness() {
        let ready = RecoveryEstimate(score: 85, band: .ready, factors: [], hasHealthData: true)
        let moderate = RecoveryEstimate(score: 60, band: .moderate, factors: [], hasHealthData: true)
        let rest = RecoveryEstimate(score: 30, band: .rest, factors: [], hasHealthData: true)

        let readyDuration = RunningSessionBuilder.nextSession(completedThisWeek: 0, recovery: ready).durationMinutes
        let moderateDuration = RunningSessionBuilder.nextSession(completedThisWeek: 0, recovery: moderate).durationMinutes
        let restDuration = RunningSessionBuilder.nextSession(completedThisWeek: 0, recovery: rest).durationMinutes

        #expect(readyDuration > moderateDuration)
        #expect(moderateDuration > restDuration)
    }
}

// MARK: - Weekly goal reminders

/// Covers `GoalReminderPlanner`. Every test injects an explicit `Calendar`
/// with a pinned `firstWeekday` and `timeZone` — without that these assertions
/// would pass or fail depending on the CI runner's locale, and the whole point
/// of threading `calendar` through `completedThisWeek` was to make the
/// scheduler and the UI agree on where the week starts.
@Suite("Weekly goal reminders")
struct WeeklyGoalReminderTests {

    /// Monday-start, UTC — so "day 0 of the week" is unambiguous.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 09:00 on Monday 2026-01-05 — a Monday well clear of any year boundary.
    private func monday(hour: Int = 9, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 5
        components.hour = hour; components.minute = 0
        return calendar.date(from: components)!
    }

    private func finished(_ type: HKWorkoutActivityType, at date: Date) -> FinishedWorkout {
        FinishedWorkout(endDate: date, name: "T", startDate: date.addingTimeInterval(-1800),
                        muscleGroup: 1, workoutType: Int(type.rawValue), exercisesSequenceID: [])
    }

    private func plan(goals: [WeeklyGoal], history: [FinishedWorkout] = [], now: Date, hour: Int = 18) -> [PlannedReminder] {
        GoalReminderPlanner.plan(goals: goals, history: history, now: now,
                                 hour: hour, minute: 0, calendar: calendar)
    }

    // MARK: Opting out

    @Test func noRemindersWithoutGoals() {
        let now = monday(calendar: calendar)
        #expect(plan(goals: [], now: now).isEmpty)
    }

    /// Stepping a goal back down to 0 deletes it; it must not be treated as a
    /// target of zero that is trivially "met".
    @Test func zeroTargetIsTreatedAsNoGoal() {
        let now = monday(calendar: calendar)
        #expect(plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 0)], now: now).isEmpty)
    }

    // MARK: Silence when met

    @Test func onlyWeekStartRemainsOnceGoalsAreMet() {
        let now = monday(calendar: calendar)
        let history = [finished(.running, at: now.addingTimeInterval(-3600)),
                       finished(.running, at: now.addingTimeInterval(-7200))]
        let reminders = plan(goals: [WeeklyGoal(category: .running, targetPerWeek: 2)],
                             history: history, now: now)

        #expect(reminders.map(\.kind) == [.weekStart])
    }

    /// The kickoff repeats forever, which is what guarantees the app gets
    /// opened — and therefore rescheduled — at least once a week.
    @Test func weekStartReminderRepeats() {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)], now: now)
        let weekStart = reminders.first { $0.kind == .weekStart }

        #expect(weekStart?.repeats == true)
        #expect(reminders.filter { $0.repeats }.count == 1)
    }

    // MARK: Pace

    /// Monday 09:00, 2 gym sessions open, 7 usable 18:00 slots left (Monday's
    /// is still ahead). Slack is 5, so the nudge belongs on the 6th slot —
    /// Saturday, the last day on which skipping still leaves room — and
    /// emphatically not today, when there is no risk yet.
    @Test func paceNudgeLandsWhenSlackRunsOut() throws {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)], now: now)
        let pace = try #require(reminders.first { $0.kind == .pace })

        let dayIndex = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: pace.fireDate)).day
        #expect(dayIndex == 5)
        #expect(calendar.component(.hour, from: pace.fireDate) == 18)
    }

    /// A user who is comfortably ahead of pace should not be interrupted at
    /// all — the pace nudge collapses into the final-day reminder.
    @Test func noSeparatePaceNudgeWhenOneSessionOpenAllWeek() {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 1)], now: now)

        #expect(!reminders.contains { $0.kind == .pace })
        #expect(reminders.contains { $0.kind == .lastChance })
    }

    /// With as many sessions left as days left, every remaining day counts —
    /// the nudge has to come at the next opportunity. Anchored to Tuesday so
    /// the slot doesn't collide with the Monday kickoff (see below).
    @Test func paceNudgeIsImmediateWhenNoSlackLeft() throws {
        let now = calendar.date(byAdding: .day, value: 1, to: monday(calendar: calendar))!
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 6)], now: now)
        let pace = try #require(reminders.first { $0.kind == .pace })

        let dayIndex = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: pace.fireDate)).day
        #expect(dayIndex == 0)
    }

    /// A pace nudge due on the first weekday at the reminder hour would fire
    /// alongside the repeating kickoff. One notification, not two.
    @Test func paceNudgeOnFirstWeekdayCollapsesIntoTheKickoff() {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 7)], now: now)

        #expect(!reminders.contains { $0.kind == .pace })
        #expect(reminders.contains { $0.kind == .weekStart })
    }

    // MARK: Last chance

    @Test func lastChanceLandsOnFinalDayOfWeek() throws {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)], now: now)
        let lastChance = try #require(reminders.first { $0.kind == .lastChance })

        // Monday-start week → Sunday is the final day.
        #expect(calendar.component(.weekday, from: lastChance.fireDate) == 1)
    }

    // MARK: Invariants

    @Test func oneShotRemindersAreAlwaysInTheFuture() {
        // Late on the final day, past the reminder hour: every remaining slot
        // for this week is gone.
        let now = calendar.date(byAdding: .day, value: 6, to: monday(hour: 20, calendar: calendar))!
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)], now: now)

        for reminder in reminders where !reminder.repeats {
            #expect(reminder.fireDate > now)
        }
        #expect(!reminders.contains { $0.kind == .lastChance })
    }

    @Test func identifiersAreNamespacedAwayFromPlanReminders() {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 3)], now: now)

        #expect(!reminders.isEmpty)
        #expect(reminders.allSatisfy { $0.id.hasPrefix("goalreminder.") })
        // Plan reminders use bare UUIDs, so the namespaces cannot overlap.
        #expect(UUID().uuidString.hasPrefix("goalreminder.") == false)
    }

    @Test func staysWellUnderThePendingRequestLimit() {
        let now = monday(calendar: calendar)
        let reminders = plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 4),
                                     WeeklyGoal(category: .running, targetPerWeek: 3)],
                             now: now)
        #expect(reminders.count <= 3)
    }

    /// Guards against computing day offsets with `+ 86400`: in a week holding
    /// a DST transition that drifts the fire time by an hour.
    @Test func reminderHourSurvivesADaylightSavingTransition() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.firstWeekday = 2
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!

        // Week containing the 2026-03-29 spring-forward transition.
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 23
        components.hour = 9; components.minute = 0
        let now = berlin.date(from: components)!

        let reminders = GoalReminderPlanner.plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)],
                                                 history: [], now: now,
                                                 hour: 18, minute: 0, calendar: berlin)

        for reminder in reminders where !reminder.repeats {
            #expect(berlin.component(.hour, from: reminder.fireDate) == 18)
        }
    }

    /// The scheduler and the goals card must agree on where the week starts,
    /// which is only true because `completedThisWeek` takes a calendar too.
    @Test func weekBoundaryFollowsCalendarFirstWeekday() throws {
        var sundayStart = calendar
        sundayStart.firstWeekday = 1

        let now = monday(calendar: calendar)
        let mondayWeek = try #require(plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)], now: now)
            .first { $0.kind == .lastChance })
        let sundayWeek = try #require(GoalReminderPlanner.plan(goals: [WeeklyGoal(category: .gym, targetPerWeek: 2)],
                                                               history: [], now: now, hour: 18, minute: 0,
                                                               calendar: sundayStart)
            .first { $0.kind == .lastChance })

        // Monday-start → final day Sunday; Sunday-start → final day Saturday.
        #expect(calendar.component(.weekday, from: mondayWeek.fireDate) == 1)
        #expect(sundayStart.component(.weekday, from: sundayWeek.fireDate) == 7)
    }

    // MARK: Preferred hour

    @Test func peakHourPrefersTheBusiestWindow() {
        #expect(GoalReminderPlanner.peakHour(hours: [7, 7, 8, 18, 19, 19, 20]) == 19)
    }

    /// A mean would put 23:00 and 01:00 at midday; the window has to wrap.
    @Test func peakHourWrapsAroundMidnight() {
        #expect(GoalReminderPlanner.peakHour(hours: [23, 23, 0, 0, 1]) == 0)
    }

    @Test func inferredHourFallsBackWithoutEnoughHistory() {
        let now = monday(calendar: calendar)
        let history = (0..<4).map { finished(.running, at: now.addingTimeInterval(TimeInterval(-86_400 * $0))) }
        #expect(GoalReminderPlanner.inferredHour(history: history, now: now, calendar: calendar)
                == GoalReminderPlanner.defaultHour)
    }

    /// A history of dawn sessions must not produce a 04:00 notification.
    @Test func inferredHourIsClampedToWakingHours() {
        let now = monday(calendar: calendar)
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 2
        components.hour = 5; components.minute = 0
        let base = calendar.date(from: components)!

        let history = (0..<8).map { offset -> FinishedWorkout in
            let date = calendar.date(byAdding: .day, value: -offset, to: base)!
            return FinishedWorkout(endDate: date.addingTimeInterval(1800), name: "T", startDate: date,
                                   muscleGroup: 1, workoutType: Int(HKWorkoutActivityType.running.rawValue),
                                   exercisesSequenceID: [])
        }

        let hour = GoalReminderPlanner.inferredHour(history: history, now: now, calendar: calendar)
        #expect(hour >= GoalReminderPlanner.earliestHour)
        #expect(hour <= GoalReminderPlanner.latestHour)
    }
}

// MARK: - Recommendation accuracy fixes

@Suite("Recommendation accuracy")
@MainActor
struct RecommendationAccuracyTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func finished(_ category: WorkoutCategory, hoursAgo: Double) -> FinishedWorkout {
        let end = now.addingTimeInterval(-hoursAgo * 3600)
        return FinishedWorkout(endDate: end, name: "T", startDate: end.addingTimeInterval(-3600),
                               muscleGroup: category.rawValue, exercisesSequenceID: [])
    }

    private func bestSplit(history: [FinishedWorkout]) -> GymSplit? {
        let lastTrained = PersonalizedWorkoutGenerator.lastTrainedByBucket(history: history)
        return GymSplit.allCases.max {
            PersonalizedWorkoutGenerator.freshness(for: $0, lastTrained: lastTrained, now: now)
                < PersonalizedWorkoutGenerator.freshness(for: $1, lastTrained: lastTrained, now: now)
        }
    }

    /// Push yesterday, legs two days ago, pull three days ago → pull is due.
    /// Core never being trained must not drag leg day ahead of it.
    @Test func mostRestedPrimaryBucketWins() {
        let history = [finished(.chest, hoursAgo: 24), finished(.legs, hoursAgo: 48), finished(.back, hoursAgo: 80)]
        #expect(bestSplit(history: history) == .pull)
    }

    /// Legs left out for a week come next, even with core (part of leg day)
    /// trained today. Ranking by the capped score picked pull here.
    @Test func leftOutLegsComeNext() {
        let history = [finished(.core, hoursAgo: 2), finished(.chest, hoursAgo: 30),
                       finished(.back, hoursAgo: 50), finished(.legs, hoursAgo: 170)]
        #expect(bestSplit(history: history) == .leg)
    }

    /// After a Push + Full Body day, neither push type is next — also when
    /// the record only has its exercise ids (watch, iCloud still syncing),
    /// whose muscle group (full body) can't tell push from pull.
    @Test func pushFullBodyIsNotFollowedByPush() throws {
        let all = Set(Equipment.allCases.map(\.rawValue))
        let pool = GymExerciseCatalog.exercises(for: .pushFullbody, availableEquipment: all)
        let ids = try [TrainingBucket.push, .fullBody, .core].map { bucket in
            try #require(pool.first { $0.bucket == bucket }).id
        }
        let end = now.addingTimeInterval(-20 * 3600)
        let pushFullBody = FinishedWorkout(endDate: end, name: "Push + Full Body", startDate: end.addingTimeInterval(-3600),
                                           muscleGroup: WorkoutCategory.fullbody.rawValue, exercisesSequenceID: ids)
        let history = [pushFullBody, finished(.back, hoursAgo: 50),
                       finished(.legs, hoursAgo: 60), finished(.chest, hoursAgo: 100)]

        let next = bestSplit(history: history)
        #expect(next != .push)
        #expect(next != .pushFullbody)
        #expect(next == .leg)
    }

    /// "Arms" is ambiguous (biceps vs triceps), so it must not reset either day.
    @Test func armsDoNotResetPullDay() {
        let lastTrained = PersonalizedWorkoutGenerator.lastTrainedByBucket(history: [finished(.arms, hoursAgo: 2)])
        #expect(lastTrained[.pull] == nil)
        #expect(lastTrained[.push] == nil)
    }

    /// Regenerating must be able to produce a different selection on the same day.
    @Test func variationChangesSelection() {
        let equipment = Set(Equipment.allCases.map(\.rawValue))
        let generator = PersonalizedWorkoutGenerator(availableEquipment: equipment, history: [])
        let recovery = RecoveryEstimator.estimate(from: RecoveryInputs())
        let first = generator.generate(recovery: recovery, now: now, variation: 0)?.exercises.map(\.id)
        let second = generator.generate(recovery: recovery, now: now, variation: 1)?.exercises.map(\.id)
        #expect(first != nil)
        #expect(first != second)
    }

    /// A type the user picks in For You replaces the recommended one, and the
    /// plan still knows the recommendation for the picker.
    @Test func chosenSplitOverridesRecommendation() throws {
        let equipment = Set(Equipment.allCases.map(\.rawValue))
        let history = [finished(.chest, hoursAgo: 24), finished(.legs, hoursAgo: 48), finished(.back, hoursAgo: 80)]
        let generator = PersonalizedWorkoutGenerator(availableEquipment: equipment, history: history)
        let recovery = RecoveryEstimator.estimate(from: RecoveryInputs())

        let recommended = try #require(generator.generate(recovery: recovery, now: now))
        #expect(recommended.split == .pull)
        #expect(!recommended.isUserChosenSplit)
        #expect(Set(recommended.availableSplits) == Set(GymSplit.allCases))
        // Compared in the device language: the simulator may run in German.
        #expect(recommended.rationale == String(format: NSLocalizedString("A full %d-exercise %@ session, picked for the muscles you've rested longest.", comment: ""),
                                                recommended.exercises.count, GymSplit.pull.displayName))

        let chosen = try #require(generator.generate(recovery: recovery, now: now, split: .leg))
        #expect(chosen.split == .leg)
        #expect(chosen.recommendedSplit == .pull)
        #expect(chosen.isUserChosenSplit)
        // A chosen type wasn't picked for being rested.
        #expect(chosen.rationale == String(format: NSLocalizedString("A full %d-exercise %@ session.", comment: ""),
                                           chosen.exercises.count, GymSplit.leg.displayName))
    }

    /// Every type the For You picker offers must build when tapped, for any
    /// equipment set and readiness — otherwise the card turns into "Not
    /// enough equipment" and the picker disappears with it.
    @Test func everyOfferedSplitBuilds() {
        let kinds = Equipment.allCases.filter { $0 != .other }.map(\.rawValue)
        var sets: [Set<Int>] = [Set(kinds)]
        for (i, a) in kinds.enumerated() {
            sets.append([a, Equipment.exerciseMat.rawValue])
            for b in kinds[(i + 1)...] { sets.append([a, b]) }
        }
        let bands: [RecoveryEstimate] = [
            RecoveryEstimate(score: 85, band: .ready, factors: [], hasHealthData: true),
            RecoveryEstimate(score: 60, band: .moderate, factors: [], hasHealthData: true),
            RecoveryEstimate(score: 30, band: .rest, factors: [], hasHealthData: true)
        ]
        var failures: [String] = []
        for equipment in sets {
            let generator = PersonalizedWorkoutGenerator(availableEquipment: equipment, history: [])
            for recovery in bands {
                guard let plan = generator.generate(recovery: recovery, now: now) else { continue }
                for split in plan.availableSplits where generator.generate(recovery: recovery, now: now, split: split)?.split != split {
                    failures.append("\(split) with \(equipment.sorted()) at \(recovery.band)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) offered splits don't build, e.g. \(failures.prefix(5))")
    }

    @Test func dumbbellsOnlyRestrictsEquipment() {
        let request = KeywordWorkoutParser.parse("45 min upper body, dumbbells only")
        let all = Set(Equipment.allCases.map(\.rawValue))
        let allowed = request.allowedEquipment(available: all)
        #expect(allowed == [Equipment.dumbbells.rawValue, Equipment.exerciseMat.rawValue])

        let pool = GymExerciseCatalog.exercises(forMuscleGroups: request.focus.muscleGroups,
                                                availableEquipment: allowed)
        #expect(pool.count >= 3)
        #expect(pool.allSatisfy { Set($0.equipment).isSubset(of: allowed) })
    }

    /// Naming equipment without "only" doesn't rule the rest out.
    @Test func namingEquipmentWithoutOnlyDoesNotRestrict() {
        #expect(KeywordWorkoutParser.parse("hard leg day with a barbell").equipmentOnly.isEmpty)
    }

    /// The sleep window spans yesterday evening to today's noon, whenever the
    /// app is opened — never a trailing lookback from "now".
    @Test func lastNightWindowIsAnchoredToTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let evening = calendar.date(byAdding: .hour, value: 22, to: day)!
        let morning = calendar.date(byAdding: .hour, value: 7, to: day)!

        let eveningWindow = RecoveryMetricsProvider.lastNightWindow(now: evening, calendar: calendar)
        #expect(eveningWindow.start == calendar.date(byAdding: .hour, value: -6, to: day))
        #expect(eveningWindow.end == calendar.date(byAdding: .hour, value: 12, to: day))

        let morningWindow = RecoveryMetricsProvider.lastNightWindow(now: morning, calendar: calendar)
        #expect(morningWindow.end == morning)
    }

    // MARK: Recovery confidence

    @Test func noSignalsMeansLowConfidence() {
        let estimate = RecoveryEstimator.estimate(from: RecoveryInputs())
        #expect(estimate.signals.isEmpty)
        #expect(estimate.confidence == 0)
        #expect(estimate.isLowConfidence)
    }

    @Test func allSignalsMeansFullConfidence() {
        let estimate = RecoveryEstimator.estimate(from: RecoveryInputs(
            hrvSDNN: 60, hrvBaseline: 55, restingHR: 55, restingHRBaseline: 56,
            sleepHoursLastNight: 7.5, acuteLoad: 60, chronicLoad: 60))
        #expect(estimate.signals == Set(RecoverySignal.allCases))
        #expect(abs(estimate.confidence - 1) < 0.0001)
        #expect(!estimate.isLowConfidence)
    }

    /// Sleep + load alone isn't enough to present the score as a measurement.
    @Test func sleepAndLoadOnlyIsLowConfidence() {
        let estimate = RecoveryEstimator.estimate(from: RecoveryInputs(
            sleepHoursLastNight: 7, acuteLoad: 60, chronicLoad: 60))
        #expect(estimate.signals == [.sleep, .trainingLoad])
        #expect(estimate.isLowConfidence)
    }

    // MARK: Difficulty calibration

    private func rated(effort: Int?, predicted: Double?, hoursAgo: Double) -> FinishedWorkout {
        let fw = finished(.chest, hoursAgo: hoursAgo)
        fw.perceivedEffort = effort
        fw.predictedDifficulty = predicted
        return fw
    }

    @Test func effortScaleMapsOntoRatingScale() {
        #expect(WorkoutDifficultyPredictor.effortAsRating(1) == 1)
        #expect(WorkoutDifficultyPredictor.effortAsRating(10) == 5)
        #expect(abs(WorkoutDifficultyPredictor.effortAsRating(5) - (1 + 4.0 * 4 / 9)) < 0.0001)
    }

    @Test func noRatingsMeansNoCalibration() {
        let history = [rated(effort: nil, predicted: 3, hoursAgo: 24), rated(effort: 8, predicted: nil, hoursAgo: 48)]
        #expect(WorkoutDifficultyPredictor.calibrationOffset(history: history) == 0)
    }

    /// Sessions consistently felt harder than predicted → positive offset,
    /// shrunk for a small sample.
    @Test func consistentUnderPredictionRaisesOffset() {
        // Effort 10 → 5.0 on the rating scale; predicted 4.0 → residual +1.
        let history = (1...3).map { rated(effort: 10, predicted: 4, hoursAgo: Double($0) * 24) }
        let offset = WorkoutDifficultyPredictor.calibrationOffset(history: history)
        #expect(abs(offset - 0.5) < 0.0001) // 1 × 3 / (3 + 3)
    }

    @Test func calibrationShiftsPredictionButNotRawRating() {
        let base = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2], exerciseCount: 3, setLength: 3,
            durationMinutes: 30, recovery: 0.8, history: [])
        let calibrated = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: [2, 2, 2], exerciseCount: 3, setLength: 3,
            durationMinutes: 30, recovery: 0.8, history: [], calibration: 0.8)
        #expect(calibrated.rawRating == base.rawRating)
        #expect(abs(calibrated.rating - (base.rating + 0.8)) < 0.0001)
    }

    /// Skipped rep-based exercises don't count as trained once sets were logged.
    @Test func performedExercisesDropSkippedOnes() throws {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ctx = ModelContext(container)

        let bench = Exercise(id: "bench", difficultyInt: 2, equipment: [], muscleGroup: 7, name: "Bench")
        bench.repCount = 8
        let curl = Exercise(id: "curl", difficultyInt: 1, equipment: [], muscleGroup: 3, name: "Curl")
        curl.repCount = 10
        let plank = Exercise(id: "plank", difficultyInt: 1, equipment: [], muscleGroup: 6, name: "Plank")
        [bench, curl, plank].forEach(ctx.insert)

        let fw = FinishedWorkout(endDate: now, name: "T", startDate: now, muscleGroup: 7,
                                 exercisesSequenceID: ["bench", "curl", "plank"])
        ctx.insert(fw)
        fw.exercises = [bench, curl, plank]
        #expect(Set(fw.performedExercises.map(\.id)) == ["bench", "curl", "plank"])

        fw.setReps = ["bench": [8, 8]]
        #expect(Set(fw.performedExercises.map(\.id)) == ["bench", "plank"])
    }
}

// MARK: - Personal baselines and training load

@Suite("Personal recovery baselines")
struct PersonalBaselineTests {

    /// Four copies of `pattern` — 12 days of history with a known spread.
    private static func repeated(_ pattern: [Double]) -> [Double] {
        (0..<4).flatMap { _ in pattern }
    }

    /// The same 10% HRV dip matters more for someone whose HRV is normally
    /// very stable than for someone whose HRV swings a lot day to day.
    @Test func hrvIsJudgedAgainstPersonalSpread() {
        let stable = RecoveryInputs(hrvSDNN: 45, hrvHistory: Self.repeated([49, 50, 51]))
        let noisy = RecoveryInputs(hrvSDNN: 45, hrvHistory: Self.repeated([35, 50, 65]))
        let stableImpact = RecoveryEstimator.hrvImpact(hrv: 45, inputs: stable)!.impact
        let noisyImpact = RecoveryEstimator.hrvImpact(hrv: 45, inputs: noisy)!.impact
        #expect(stableImpact < noisyImpact)
        #expect(noisyImpact < 0)
    }

    /// Too little history falls back to the plain ratio against the baseline.
    @Test func shortHistoryFallsBackToRatio() {
        let inputs = RecoveryInputs(hrvSDNN: 50, hrvBaseline: 50, hrvHistory: [40, 60])
        #expect(RecoveryEstimator.hrvImpact(hrv: 50, inputs: inputs)!.impact == 0)
    }

    @Test func elevatedRestingHRLowersScore() {
        let history = Self.repeated([55, 56, 57])
        let normal = RecoveryEstimator.restingHRImpact(rhr: 56, inputs: RecoveryInputs(restingHRHistory: history))!
        let elevated = RecoveryEstimator.restingHRImpact(rhr: 62, inputs: RecoveryInputs(restingHRHistory: history))!
        #expect(abs(normal.impact) < 0.5)
        #expect(elevated.impact < -10)
        #expect(normal.baseline == 56)
    }

    /// The target follows the user's usual sleep but never drops below 7 h.
    @Test func sleepTargetIsPersonalButFloored() {
        #expect(RecoveryEstimator.sleepTarget(history: [8.4, 8.5, 8.6, 8.5, 8.5]) == 8.5)
        #expect(RecoveryEstimator.sleepTarget(history: [6, 6, 6, 6, 6]) == 7)
        #expect(RecoveryEstimator.sleepTarget(history: [8, 8]) == RecoveryEstimator.defaultSleepTarget)
        // Untracked nights (0) and watch-off nights don't count.
        #expect(RecoveryEstimator.sleepTarget(history: [8, 0, 8, 1, 8, 8, 8]) == 8)
    }

    @Test func sleepDebtAddsUpRecentShortNights() {
        #expect(RecoveryEstimator.sleepDebt(history: [6, 6.5, 7, 5], target: 8) == 4.5)
        #expect(RecoveryEstimator.sleepDebt(history: [0, 8, 9], target: 8) == 0)

        let rested = RecoveryEstimator.estimate(from: RecoveryInputs(sleepHoursLastNight: 8, sleepHistory: [8, 8, 8]))
        let inDebt = RecoveryEstimator.estimate(from: RecoveryInputs(sleepHoursLastNight: 8, sleepHistory: [6, 6, 6]))
        #expect(inDebt.score < rested.score)
    }

    @Test func windowAveragesAreAlignedAndHalfOpen() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = [(date: t0, value: 10.0), (date: t0.addingTimeInterval(50), value: 20),
                       (date: t0.addingTimeInterval(100), value: 99)]
        let windows = [DateInterval(start: t0, end: t0.addingTimeInterval(100)),
                       DateInterval(start: t0.addingTimeInterval(200), end: t0.addingTimeInterval(300))]
        let averages = RecoveryMetricsProvider.windowAverages(samples, windows: windows)
        #expect(averages[0] == 15)
        #expect(averages[1] == nil)
    }

    @Test func onlySamplesTakenAsleepAreKept() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = [(date: t0.addingTimeInterval(-60), value: 30.0),   // awake, before bed
                       (date: t0.addingTimeInterval(3600), value: 60),    // asleep
                       (date: t0.addingTimeInterval(8 * 3600), value: 35)] // awake again
        let asleep = [(start: t0, end: t0.addingTimeInterval(7 * 3600))]
        #expect(RecoveryMetricsProvider.samples(samples, during: asleep).map(\.value) == [60])
    }

    @Test func nightlySleepClipsToEachNight() {
        let t0 = Date(timeIntervalSince1970: 0)
        let night1 = DateInterval(start: t0, end: t0.addingTimeInterval(10 * 3600))
        let night2 = DateInterval(start: t0.addingTimeInterval(24 * 3600), end: t0.addingTimeInterval(34 * 3600))
        let asleep = [(start: t0.addingTimeInterval(-3600), end: t0.addingTimeInterval(7 * 3600)),
                      (start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5 * 3600))]
        let hours = RecoveryMetricsProvider.nightlySleepHours(asleep, windows: [night1, night2])
        #expect(hours == [7, 0])
    }
}

@Suite("Training load")
struct TrainingLoadTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(daysAgo: Double, minutes: Double = 60, effort: Double = 5) -> LoadSession {
        let end = now.addingTimeInterval(-daysAgo * 86_400)
        return LoadSession(start: end.addingTimeInterval(-minutes * 60), end: end, effort: effort)
    }

    @Test func loadIsMinutesTimesEffort() {
        #expect(session(daysAgo: 1, minutes: 60, effort: 7).load == 420)
        // A workout left running all day is capped.
        #expect(session(daysAgo: 1, minutes: 600, effort: 5).load == LoadSession.maxMinutes * 5)
    }

    /// The chronic baseline excludes the acute week (uncoupled) and is a
    /// weekly average.
    @Test func chronicIsUncoupledWeeklyAverage() {
        let sessions = [session(daysAgo: 2), session(daysAgo: 10), session(daysAgo: 17), session(daysAgo: 24)]
        let load = TrainingLoad.load(sessions: sessions, now: now)
        #expect(load.acute == 300)
        #expect(load.chronic == 300)
    }

    /// A new user's first week must not read as a spike over an empty baseline.
    @Test func noChronicLoadWithoutEnoughHistory() {
        let sessions = [session(daysAgo: 1), session(daysAgo: 3), session(daysAgo: 9)]
        #expect(TrainingLoad.load(sessions: sessions, now: now).chronic == nil)
        let estimate = RecoveryEstimator.estimate(from: RecoveryInputs(acuteLoad: 900, chronicLoad: nil))
        #expect(!estimate.signals.contains(.trainingLoad))
    }

    @Test func userRatingOverridesDefaultEffort() {
        let end = now
        let fw = FinishedWorkout(endDate: end, name: "T", startDate: end.addingTimeInterval(-3600), muscleGroup: 7,
                                 workoutType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
                                 exercisesSequenceID: [])
        #expect(TrainingLoad.sessions(history: [fw], external: [])[0].effort == 6)
        fw.perceivedEffort = 9
        #expect(TrainingLoad.sessions(history: [fw], external: [])[0].effort == 9)
    }

    /// Another app's copy of one of our sessions isn't counted twice, but its
    /// own workouts are.
    @Test func externalDuplicatesAreDropped() {
        let end = now
        let fw = FinishedWorkout(endDate: end, name: "T", startDate: end.addingTimeInterval(-3600), muscleGroup: 7,
                                 exercisesSequenceID: [])
        let duplicate = ExternalWorkout(start: end.addingTimeInterval(-3500), end: end.addingTimeInterval(60),
                                        activityType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue))
        let run = ExternalWorkout(start: end.addingTimeInterval(-86_400), end: end.addingTimeInterval(-86_400 + 1800),
                                  activityType: Int(HKWorkoutActivityType.running.rawValue))
        let sessions = TrainingLoad.sessions(history: [fw], external: [duplicate, run])
        #expect(sessions.count == 2)
    }

    @Test func easyActivitiesWeighLess() {
        let walk = TrainingLoad.defaultEffort(activityType: Int(HKWorkoutActivityType.walking.rawValue))
        let hiit = TrainingLoad.defaultEffort(activityType: Int(HKWorkoutActivityType.highIntensityIntervalTraining.rawValue))
        let yogaDay = TrainingLoad.defaultEffort(activityType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
                                                 muscleGroup: WorkoutCategory.yoga.rawValue)
        #expect(walk < hiit)
        #expect(yogaDay == 2)
    }
}

// MARK: - Workout-request parsing and coach guardrails

@Suite("Workout request parsing")
struct WorkoutRequestParsingTests {

    /// The keyword fallback must get every evaluation case right — it's what
    /// every device without Apple Intelligence uses. (The model is scored on
    /// the same cases on a device, via the DEBUG evaluation screen.)
    @Test(arguments: WorkoutParserEvalCase.all)
    func keywordParserPassesEvaluationCase(_ evalCase: WorkoutParserEvalCase) {
        let mismatches = evalCase.mismatches(in: KeywordWorkoutParser.parse(evalCase.prompt))
        #expect(mismatches.isEmpty, "\(evalCase.prompt): \(mismatches.joined(separator: "; "))")
    }

    /// Unstated values come from recovery, not a fixed guess.
    @Test func unstatedValuesFollowRecovery() {
        let request = KeywordWorkoutParser.parse("leg day")
        #expect(request.durationMinutes == nil)
        #expect(request.intensity == nil)
        #expect(request.resolved(for: .rest) == (30, .easy))
        #expect(request.resolved(for: .ready) == (40, .moderate))

        let stated = KeywordWorkoutParser.parse("hard leg day, 50 min")
        #expect(stated.resolved(for: .rest) == (50, .hard))
    }

    @Test func wordBoundariesPreventFalseMatches() {
        // "warm-up" is not "arm", "backpack" is not "back".
        #expect(KeywordWorkoutParser.parse("warm-up then legs").targetMuscles == [WorkoutCategory.legs.rawValue])
        #expect(KeywordWorkoutParser.parse("gym backpack session").targetMuscles.isEmpty)
    }

    /// Every muscle area the model can return must map to catalog groups —
    /// an unmapped value would silently drop the user's target.
    @Test func everyModelMuscleAreaMaps() {
        let areas = ["arms", "legs", "glutes", "back", "chest", "shoulders", "core", "cardio"]
        for area in areas {
            #expect(!MuscleAreaWord.groups(for: area).isEmpty, "\(area)")
        }
    }

    @Test func durationUnits() {
        #expect(KeywordWorkoutParser.parse("1.5 hours full body").durationMinutes == 90)
        #expect(KeywordWorkoutParser.parse("halbe Stunde Beine").durationMinutes == 30)
        #expect(KeywordWorkoutParser.parse("5x5 squats").durationMinutes == nil)
        #expect(KeywordWorkoutParser.parse("10 reps of everything").durationMinutes == nil)
    }
}

@Suite("Coach narrative guardrails")
@MainActor
struct CoachNarrativeTests {

    @Test func inventedNumbersAreRejected() {
        let facts = "Recovery score: 82/100\nRecovery factor: Sleep +5 points (7.9 h last night, target 7.5 h)"
        #expect(WorkoutCoach.usesOnlyKnownNumbers("You slept 7,9 h — score 82, ready to go.", facts: facts))
        #expect(!WorkoutCoach.usesOnlyKnownNumbers("This burns about 500 kcal.", facts: facts))
        #expect(WorkoutCoach.usesOnlyKnownNumbers("Great day for it!", facts: facts))
    }

    @Test func factsCarryTheReasonAndLimitedData() {
        let recovery = RecoveryEstimator.estimate(from: RecoveryInputs(sleepHoursLastNight: 5.5))
        let equipment = Set(Equipment.allCases.map(\.rawValue))
        let plan = PersonalizedWorkoutGenerator(availableEquipment: equipment, history: []).generate(recovery: recovery)!
        let facts = WorkoutCoach.facts(for: plan)
        #expect(facts.contains("Recovery data: limited"))
        #expect(facts.contains("Recovery factor:"))
        #expect(facts.contains("haven't been trained recently"))
    }
}

// MARK: - Seed deduplication (multi-device CloudKit merge)

@Suite("Seed deduplication")
@MainActor
struct SeedDeduplicationTests {

    /// Held for the test's lifetime: a context whose container has been
    /// released fails its next save ("No eligible connection available").
    private let container: ModelContainer

    init() throws {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(container)
    }

    private func seedWorkout(id: String, name: String, exerciseIDs: [String] = []) -> Workout {
        Workout(id: id, infoText: "", isUserGenerated: false, muscleGroup: 1, setLength: 3,
                straightSets: false, difficultyInt: 2, name: name, duration: 10,
                exercisesSequenceID: exerciseIDs, finishedExercisesSequence: [], plan: [],
                workoutActivityType: 0, workoutSessionLocation: 0)
    }

    /// Workouts and history reference exercises by ID. Deleting the duplicate
    /// without rewriting those IDs silently dropped exercises from workouts.
    @Test func exerciseIDsFollowTheSurvivor() throws {
        let ctx = try makeContext()
        ctx.insert(Exercise(id: "a", difficultyInt: 2, equipment: [], muscleGroup: 1, name: "Squat"))
        ctx.insert(Exercise(id: "b", difficultyInt: 2, equipment: [], muscleGroup: 1, name: "squat "))
        let workout = seedWorkout(id: "w", name: "Legs", exerciseIDs: ["b"])
        ctx.insert(workout)
        let finished = FinishedWorkout(endDate: .now, name: "Legs", startDate: .now,
                                       muscleGroup: 1, exercisesSequenceID: ["b"])
        ctx.insert(finished)
        finished.setWeights = ["b": [50, 55]]
        finished.setReps = ["b": [8, 6]]
        try ctx.save()

        deduplicateExercises(modelContext: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Exercise>()).map(\.id) == ["a"])
        #expect(workout.exercisesSequenceID == ["a"])
        #expect(finished.exercisesSequenceID == ["a"])
        #expect(finished.setWeights == ["a": [50, 55]])
        #expect(finished.setReps == ["a": [8, 6]])
    }

    /// A user's own exercise that happens to share a catalog name is not a
    /// duplicate: it must survive with its own settings, and workouts keep
    /// pointing at it. A plain second copy is still merged.
    @Test func userExerciseSharingACatalogNameIsKept() throws {
        let ctx = try makeContext()
        let catalog = Exercise(id: "squats", difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squats")
        catalog.repCount = 12
        let usersOwn = Exercise(id: UUID().uuidString, difficultyInt: 3, equipment: [6], muscleGroup: 5, name: "squats")
        usersOwn.repCount = 5
        let plainCopy = Exercise(id: UUID().uuidString, difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squats")
        plainCopy.repCount = 12
        [catalog, usersOwn, plainCopy].forEach(ctx.insert)
        let workout = seedWorkout(id: "w", name: "Legs", exerciseIDs: [usersOwn.id, plainCopy.id])
        ctx.insert(workout)
        try ctx.save()

        deduplicateExercises(modelContext: ctx)

        let remaining = Set(try ctx.fetch(FetchDescriptor<Exercise>()).map(\.id))
        #expect(remaining == ["squats", usersOwn.id])
        #expect(usersOwn.repCount == 5)
        #expect(workout.exercisesSequenceID == [usersOwn.id, "squats"])
    }

    /// Copies that differ from the kept catalog entry (because the user edited
    /// it) are still copies of each other and merge into one.
    @Test func copiesOfAnEditedCatalogExerciseMergeWithEachOther() throws {
        let ctx = try makeContext()
        let catalog = Exercise(id: "squats", difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squats")
        catalog.repCount = 15   // edited by the user
        let copyA = Exercise(id: "A" + UUID().uuidString.dropFirst(), difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squats")
        copyA.repCount = 12
        let copyB = Exercise(id: "B" + UUID().uuidString.dropFirst(), difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squats")
        copyB.repCount = 12
        [catalog, copyA, copyB].forEach(ctx.insert)
        let workout = seedWorkout(id: "w", name: "Legs", exerciseIDs: [copyB.id])
        ctx.insert(workout)
        try ctx.save()

        deduplicateExercises(modelContext: ctx)

        #expect(Set(try ctx.fetch(FetchDescriptor<Exercise>()).map(\.id)) == ["squats", copyA.id])
        #expect(catalog.repCount == 15)
        #expect(workout.exercisesSequenceID == [copyA.id])
    }

    /// Plans list their workouts by ID; the survivor must take the duplicate's
    /// place there, and a bookmark on the removed copy must carry over.
    @Test func workoutIDsInPlansFollowTheSurvivor() throws {
        let ctx = try makeContext()
        let survivor = seedWorkout(id: "w1", name: "Push")
        let duplicate = seedWorkout(id: "w2", name: "Push")
        duplicate.isSaved = true
        ctx.insert(survivor)
        ctx.insert(duplicate)
        let plan = Plan(goal: 1, infoText: "", muscleGroup: 1, name: "P", interval: [:], intervalType: "",
                        workoutsSequenceIDs: ["w2"], finishedWorkoutsSequence: ["w2"])
        ctx.insert(plan)
        try ctx.save()

        deduplicateWorkouts(modelContext: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Workout>()).map(\.id) == ["w1"])
        #expect(plan.workoutsSequenceIDs == ["w1"])
        #expect(plan.finishedWorkoutsSequence == ["w1"])
        #expect(survivor.isSaved)
    }

    /// Retired (hidden) presets share names with their replacements. They
    /// must not be merged: the old UUID sorts first and used to win, deleting
    /// the visible catalog workout while For You was showing it.
    @Test func hiddenPresetsAreNotMerged() throws {
        let ctx = try makeContext()
        let legacy = seedWorkout(id: UUID().uuidString, name: "Push")
        legacy.isHidden = true
        ctx.insert(legacy)
        ctx.insert(seedWorkout(id: "seed-workout-push-beginner", name: "Push"))
        try ctx.save()

        deduplicateWorkouts(modelContext: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Workout>()).count == 2)
    }

    /// Catalog records have fixed IDs; they must survive over UUID copies so
    /// catalog updates keyed by ID keep finding them.
    @Test func catalogIDWinsOverUUID() throws {
        let ctx = try makeContext()
        ctx.insert(seedWorkout(id: "0" + UUID().uuidString.dropFirst(), name: "Pull"))
        ctx.insert(seedWorkout(id: "seed-workout-pull-beginner", name: "Pull"))
        try ctx.save()

        deduplicateWorkouts(modelContext: ctx)

        #expect(try ctx.fetch(FetchDescriptor<Workout>()).map(\.id) == ["seed-workout-pull-beginner"])
    }
}

// MARK: - Plan reminder weekday keys

@Suite("Plan reminder weekday keys")
struct PlanReminderWeekdayTests {

    /// Plans store the weekday under the name shown when the plan was set up.
    /// Both languages must resolve regardless of the current one, or reminders
    /// break after a language change or on a synced device.
    @Test func resolvesEnglishAndGermanNames() {
        #expect(NotificationManager.weekdayNumber(for: "Sunday") == 1)
        #expect(NotificationManager.weekdayNumber(for: "Monday") == 2)
        #expect(NotificationManager.weekdayNumber(for: "Montag") == 2)
        #expect(NotificationManager.weekdayNumber(for: "samstag") == 7)
        #expect(NotificationManager.weekdayNumber(for: "nextDate") == nil)
    }
}

// MARK: - Weekly goals widget snapshot

@Suite("Weekly goals widget snapshot")
struct WeeklyGoalsWidgetSnapshotTests {

    /// Fixed calendar so the week boundary doesn't depend on the test
    /// machine's locale: weeks start Monday, Berlin time.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }()

    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .now
    }

    private func finished(_ type: HKWorkoutActivityType, endingOn end: Date) -> FinishedWorkout {
        FinishedWorkout(endDate: end, name: "T", startDate: end.addingTimeInterval(-1800),
                        muscleGroup: 1, workoutType: Int(type.rawValue), exercisesSequenceID: [])
    }

    private let goals = [WeeklyGoal(category: .gym, targetPerWeek: 2),
                         WeeklyGoal(category: .running, targetPerWeek: 1)]

    /// Counts only this week's matching sessions, with the same rule the For
    /// You card uses, and ends the week at next Monday 00:00.
    @Test func countsThisWeeksSessionsPerGoal() {
        let now = date(28)  // Wednesday
        let history = [
            finished(.traditionalStrengthTraining, endingOn: date(26)),  // Monday, this week
            finished(.running, endingOn: date(27)),
            finished(.traditionalStrengthTraining, endingOn: date(25)),  // Sunday, last week
            finished(.yoga, endingOn: date(27)),                          // no goal for yoga
        ]
        let snapshot = WeeklyGoalsWidgetSync.snapshot(goals: goals, history: history, now: now, calendar: calendar)

        #expect(snapshot.goals == [.init(id: "gym", title: GoalCategory.gym.displayName, symbolName: "dumbbell.fill",
                                         completed: 1, target: 2),
                                   .init(id: "running", title: GoalCategory.running.displayName, symbolName: "figure.run",
                                         completed: 1, target: 1)])
        #expect(snapshot.weekEnd == date(2, month: 11, hour: 0))
    }

    /// Once the week is over the widget shows a fresh week, even if the app
    /// hasn't written a new snapshot yet.
    @Test func resetsCountsWhenTheWeekEnds() {
        let snapshot = WeeklyGoalsSnapshot(goals: [.init(id: "gym", title: "Gym", symbolName: "dumbbell.fill",
                                                         completed: 2, target: 2)],
                                           weekEnd: date(2, month: 11, hour: 0))
        #expect(snapshot.goals(at: date(1, month: 11)).first?.completed == 2)
        #expect(snapshot.goals(at: date(2, month: 11, hour: 0)).first?.completed == 0)
        #expect(snapshot.goals(at: date(2, month: 11, hour: 0)).first?.target == 2)
    }

    @Test func roundTripsThroughTheSharedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = WeeklyGoalsSnapshot(goals: [.init(id: "type.46", title: "Swimming", symbolName: "figure.pool.swim",
                                                         completed: 0, target: 1)],
                                           weekEnd: date(2, month: 11, hour: 0))
        #expect(WeeklyGoalsSnapshot.load(from: url, legacyDefaults: nil) == nil)
        snapshot.save(to: url)
        #expect(WeeklyGoalsSnapshot.load(from: url, legacyDefaults: nil) == snapshot)
    }

    /// A snapshot written to shared UserDefaults by an earlier version still
    /// shows until the app writes the file.
    @Test func readsTheOldDefaultsSnapshotWithoutAFile() throws {
        let suite = "WeeklyGoalsWidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = WeeklyGoalsSnapshot(goals: [.init(id: "gym", title: "Gym", symbolName: "dumbbell.fill",
                                                         completed: 1, target: 2)],
                                           weekEnd: date(2, month: 11, hour: 0))
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "weeklyGoalsSnapshot")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
        #expect(WeeklyGoalsSnapshot.load(from: missing, legacyDefaults: defaults) == snapshot)
    }

    /// The medium widget's "days left" counts today, so the week's last day
    /// reads 1 and its first reads 7.
    @Test func countsDaysLeftInTheWeek() {
        #expect(WeeklyGoalsSnapshot.daysLeftInWeek(at: date(28), calendar: calendar) == 5)         // Wednesday
        #expect(WeeklyGoalsSnapshot.daysLeftInWeek(at: date(1, month: 11, hour: 23), calendar: calendar) == 1)  // Sunday night
        #expect(WeeklyGoalsSnapshot.daysLeftInWeek(at: date(2, month: 11, hour: 0), calendar: calendar) == 7)   // Monday 00:00
    }

    /// The widget's timeline gets one entry per midnight until the week ends.
    @Test func listsTheMidnightsUntilTheWeekEnds() {
        let days = WeeklyGoalsSnapshot.dayStarts(from: date(28), to: date(2, month: 11, hour: 0), calendar: calendar)
        #expect(days == [date(29, hour: 0), date(30, hour: 0), date(31, hour: 0), date(1, month: 11, hour: 0)])
    }

    /// A snapshot written before goals could be any sport still shows after
    /// the update, until the app writes a new one.
    @Test func decodesSnapshotsFromBeforeSports() throws {
        let json = #"{"goals":[{"category":"gym","completed":1,"target":2},{"category":"running","completed":0,"target":1}],"weekEnd":815266800}"#
        let snapshot = try JSONDecoder().decode(WeeklyGoalsSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.goals.map(\.id) == ["gym", "running"])
        #expect(snapshot.goals.map(\.symbolName) == ["dumbbell.fill", "figure.run"])
        #expect(snapshot.goals.map(\.completed) == [1, 0])
        #expect(snapshot.goals.allSatisfy { !$0.title.isEmpty })
    }
}

// MARK: - Weekly goal sports

@Suite("Weekly goal sports")
struct WeeklyGoalSportTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .now
    }

    private func finished(_ type: HKWorkoutActivityType, from start: Date, minutes: Double = 30) -> FinishedWorkout {
        FinishedWorkout(endDate: start.addingTimeInterval(minutes * 60), name: "T", startDate: start,
                        muscleGroup: 1, workoutType: Int(type.rawValue), exercisesSequenceID: [])
    }

    private func external(_ type: HKWorkoutActivityType, from start: Date, minutes: Double = 30) -> ExternalWorkout {
        ExternalWorkout(start: start, end: start.addingTimeInterval(minutes * 60), activityType: Int(type.rawValue))
    }

    private let cardio = GoalCategory(id: "group.cardio", customName: "Cardio", activityTypes: [
        Int(HKWorkoutActivityType.running.rawValue),
        Int(HKWorkoutActivityType.cycling.rawValue),
        Int(HKWorkoutActivityType.swimming.rawValue)
    ])

    /// Goals saved before any sport could be picked stored a bare category.
    @Test func decodesGoalsSavedBeforeSports() throws {
        let json = #"[{"category":"gym","targetPerWeek":2},{"category":"running","targetPerWeek":1}]"#
        let goals = try JSONDecoder().decode([WeeklyGoal].self, from: Data(json.utf8))
        #expect(goals == [WeeklyGoal(category: .gym, targetPerWeek: 2), WeeklyGoal(category: .running, targetPerWeek: 1)])
    }

    @Test func groupsRoundTrip() throws {
        let goal = WeeklyGoal(category: cardio, targetPerWeek: 3)
        let decoded = try JSONDecoder().decode(WeeklyGoal.self, from: JSONEncoder().encode(goal))
        #expect(decoded == goal)
        #expect(decoded.category.displayName == "Cardio")
        #expect(decoded.category.groupSports.map(\.id) == ["running", "type.13", "type.46"])
    }

    @Test func groupCountsAnyOfItsSports() {
        let history = [finished(.running, from: date(26)), finished(.swimming, from: date(27)), finished(.yoga, from: date(27))]
        #expect(completedThisWeek(cardio, history: history, now: date(28), calendar: calendar) == 2)
    }

    /// A swim recorded by Apple's Workout app counts — but only this week's.
    @Test func countsOtherAppsWorkouts() {
        let swimming = GoalCategory.sport(.swimming)
        let external = [external(.swimming, from: date(27)), external(.swimming, from: date(25))]  // Sunday = last week
        #expect(completedThisWeek(swimming, history: [], external: external, now: date(28), calendar: calendar) == 1)
    }

    /// The same run recorded by TrainingLab and another app is one session.
    @Test func countsASessionRecordedTwiceOnce() {
        let history = [finished(.running, from: date(27, hour: 10))]
        let external = [external(.running, from: date(27, hour: 10, minute: 1), minutes: 28),  // same run
                        external(.running, from: date(27, hour: 18))]                          // a second one
        #expect(completedThisWeek(.running, history: history, external: external, now: date(28), calendar: calendar) == 2)
    }

    @Test func runningFromTheFullListIsTheBuiltIn() {
        #expect(GoalCategory.sport(.running) == .running)
        #expect(GoalCategory.allSports.filter { $0.id == "running" }.count == 1)
    }

    /// Every sport in the picker reads as itself, not as "Other", with a
    /// symbol that exists — and no two share a name.
    @Test func everySportHasANameAndSymbol() {
        for type in HKWorkoutActivityType.selectable where type != .other {
            #expect(type.name != HKWorkoutActivityType.other.name, "\(type.rawValue) has no name")
            #expect(UIImage(systemName: type.symbolName) != nil, "\(type.symbolName) missing")
        }
        let names = GoalCategory.allSports.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    /// History and goals drop another app's copy of a TrainingLab session,
    /// and keep everything else.
    @Test func distinctDropsSessionsRecordedTwice() {
        let history = [finished(.running, from: date(27, hour: 10))]
        let copy = external(.running, from: date(27, hour: 10, minute: 1), minutes: 28)
        let other = external(.swimming, from: date(27, hour: 18))
        #expect(ExternalWorkout.distinct([copy, other], from: history).map(\.id) == [other.id])
    }

    /// The goal card says how many of a goal's sessions came from other apps.
    @Test func splitsOwnAndOtherAppsSessions() {
        let history = [finished(.running, from: date(26))]
        let external = [external(.cycling, from: date(27)), external(.swimming, from: date(25))]  // the swim was last week
        let progress = goalProgressThisWeek(cardio, history: history, external: external, now: date(28), calendar: calendar)
        #expect(progress.own == 1)
        #expect(progress.external == 1)
    }

    /// A goal sport's session is a plain timer for that activity: outdoor
    /// (GPS route) for a ride, indoor for a pool swim.
    @Test func goalSessionsMatchTheirSport() {
        let ride = GoalSessionBuilder.makeWorkout(type: .cycling, uniqueName: "Cycling")
        #expect(ride.workoutActivityType == Int(HKWorkoutActivityType.cycling.rawValue))
        #expect(ride.workoutSessionLocation == HKWorkoutSessionLocationType.outdoor.rawValue)
        #expect(ride.exercisesSequenceID.isEmpty)
        #expect(ride.muscleGroup == WorkoutCategory.cardio.rawValue)

        let swim = GoalSessionBuilder.makeWorkout(type: .swimming, uniqueName: "Swimming")
        #expect(swim.workoutSessionLocation == HKWorkoutSessionLocationType.indoor.rawValue)
        #expect(GoalSessionBuilder.muscleGroup(for: .yoga) == .yoga)
    }
}

// MARK: - Gym logging

@Suite("Per-exercise plans")
struct ExercisePlanTests {

    private func makeContext() throws -> ModelContext {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func workout(setLength: Double = 4) -> Workout {
        Workout(infoText: "", isUserGenerated: true, muscleGroup: WorkoutCategory.legs.rawValue, setLength: setLength,
                straightSets: false, difficultyInt: 2, name: "T", duration: 30, exercisesSequenceID: [],
                finishedExercisesSequence: [], workoutActivityType: 0, workoutSessionLocation: 0)
    }

    /// A workout from before per-exercise plans keeps its old sets and reps.
    @Test func exercisesWithoutAPlanUseTheOldValues() {
        let squat = Exercise(id: "squat", difficultyInt: 2, equipment: [], muscleGroup: 5, name: "Squat")
        squat.repCount = 8
        let w = workout(setLength: 4)
        #expect(w.plan(for: squat) == ExercisePlan(sets: 4, reps: 8))
        w.exercisePlans = ["squat": ExercisePlan(sets: 5, reps: 5)]
        #expect(w.plan(for: squat) == ExercisePlan(sets: 5, reps: 5))
    }

    /// Linked neighbours share a superset group; the rest have none.
    @Test func linkedExercisesFormASuperset() {
        let exercises = ["a", "b", "c", "d"].map { Exercise(id: $0, difficultyInt: 2, equipment: [], muscleGroup: 3, name: $0) }
        var items = exercises.map(PlannedExercise.init(exercise:))
        items[0].linkedToNext = true
        items[1].linkedToNext = true
        let plans = PlannedExercise.plans(items)
        #expect(plans["a"]?.supersetGroup == 0)
        #expect(plans["b"]?.supersetGroup == 0)
        #expect(plans["c"]?.supersetGroup == 0)
        #expect(plans["d"]?.supersetGroup == nil)

        let w = workout()
        w.exercisePlans = plans
        #expect(PlannedExercise.items(for: w, ordered: exercises).map(\.linkedToNext) == [true, true, false, false])
    }

    /// A hand-built gym workout is strength training, indoors — so it counts
    /// toward the Gym goal and lands in Health as such.
    @Test func detailsFollowTheMuscleGroup() {
        #expect(WorkoutDefaults.activityType(forMuscleGroup: WorkoutCategory.chest.rawValue) == .traditionalStrengthTraining)
        #expect(WorkoutDefaults.location(forMuscleGroup: WorkoutCategory.chest.rawValue) == .indoor)
        #expect(WorkoutDefaults.activityType(forMuscleGroup: WorkoutCategory.hiit.rawValue) == .highIntensityIntervalTraining)
        #expect(WorkoutDefaults.activityType(forMuscleGroup: WorkoutCategory.yoga.rawValue) == .yoga)
        #expect(GoalCategory.gym.activityTypes.contains(Int(AddWorkoutDummy().workoutActivityType)))
    }

    /// The generators and catalog updates leave a user's own edits alone.
    @Test func materializeKeepsCustomizedFields() throws {
        let context = try makeContext()
        let def = try #require(GymExerciseCatalog.all.first { $0.repCount > 0 })
        let exercise = Exercise(id: def.id, difficultyInt: def.difficultyInt, equipment: [99], muscleGroup: def.muscleGroup, name: def.name)
        exercise.repCount = def.repCount + 7
        context.insert(exercise)
        exercise.customizedFields = ["repCount", "equipment"]
        let result = def.materialize(in: context, existing: [exercise])
        #expect(result.repCount == def.repCount + 7)
        #expect(result.equipment == [99])

        exercise.customizedFields = []
        _ = def.materialize(in: context, existing: [exercise])
        #expect(exercise.repCount == def.repCount)
        #expect(exercise.equipment == def.equipment)
    }
}

@Suite("Straight-set sequencing")
struct StraightSetSequencerTests {

    private typealias Entry = StraightSetSequencer.Entry

    @Test func staysThenMovesThenFinishes() {
        let entries = [Entry(id: "a", sets: 2, supersetGroup: nil), Entry(id: "b", sets: 1, supersetGroup: nil)]
        #expect(StraightSetSequencer.next(after: 0, entries: entries, done: ["a": 1], skipped: []) == .stay)
        #expect(StraightSetSequencer.next(after: 0, entries: entries, done: ["a": 2], skipped: []) == .move(to: 1))
        #expect(StraightSetSequencer.next(after: 1, entries: entries, done: ["a": 2, "b": 1], skipped: []) == .finish)
    }

    /// A superset alternates set by set, then moves past the group.
    @Test func supersetsAlternate() {
        let entries = [Entry(id: "a", sets: 2, supersetGroup: 0), Entry(id: "b", sets: 2, supersetGroup: 0),
                       Entry(id: "c", sets: 3, supersetGroup: nil)]
        #expect(StraightSetSequencer.next(after: 0, entries: entries, done: ["a": 1], skipped: []) == .move(to: 1))
        #expect(StraightSetSequencer.next(after: 1, entries: entries, done: ["a": 1, "b": 1], skipped: []) == .move(to: 0))
        #expect(StraightSetSequencer.next(after: 1, entries: entries, done: ["a": 2, "b": 2], skipped: []) == .move(to: 2))
    }

    /// Skipped exercises count as done; one jumped past comes back at the end.
    @Test func skipsAndWrapsAround() {
        let entries = [Entry(id: "a", sets: 3, supersetGroup: nil), Entry(id: "b", sets: 1, supersetGroup: nil),
                       Entry(id: "c", sets: 1, supersetGroup: nil)]
        #expect(StraightSetSequencer.next(after: 0, entries: entries, done: [:], skipped: ["a"]) == .move(to: 1))
        #expect(StraightSetSequencer.next(after: 2, entries: entries, done: ["b": 1, "c": 1], skipped: []) == .move(to: 0))
        #expect(StraightSetSequencer.next(after: 2, entries: entries, done: ["b": 1, "c": 1], skipped: ["a"]) == .finish)
    }
}

@Suite("Set kinds, 1RM and recent sessions")
struct SetKindStatsTests {

    private let warmup = SetDetail(kind: .warmup)
    private let working = SetDetail()
    private let drop = SetDetail(kind: .drop)

    private func snapshot(_ id: String, day: Double, weights: [Double], reps: [Int], details: [SetDetail],
                          note: String? = nil) -> WorkoutStats.Snapshot {
        WorkoutStats.Snapshot(id: id, endDate: Date(timeIntervalSince1970: day * 86_400),
                              setWeights: ["bench": weights], setReps: ["bench": reps],
                              log: SessionLog(setDetails: ["bench": details], exerciseNotes: note.map { ["bench": $0] } ?? [:]))
    }

    /// Warm-ups add no volume; drop sets do.
    @Test func volumeSkipsWarmUps() {
        let s = snapshot("1", day: 1, weights: [40, 100, 70], reps: [10, 5, 10], details: [warmup, working, drop])
        #expect(WorkoutStats.volumeKilograms(s) == 100 * 5 + 70 * 10)
    }

    /// Neither a heavy warm-up nor a drop set is a PR or the next start weight.
    @Test func recordsAndStartWeightUseWorkingSets() {
        let before = snapshot("1", day: 1, weights: [100], reps: [5], details: [working])
        let today = snapshot("2", day: 2, weights: [120, 95, 60], reps: [1, 5, 10], details: [warmup, working, drop])
        #expect(WorkoutStats.personalRecordExerciseIDs(current: today, history: [before]).isEmpty)
        #expect(WorkoutStats.lastLoggedWeightKg(forExerciseID: "bench", in: [before, today]) == 95)
    }

    /// Records without details are all working sets, as before.
    @Test func oldRecordsAreWorkingSets() {
        let old = WorkoutStats.Snapshot(id: "1", endDate: .now, setWeights: ["bench": [80, 85]], setReps: ["bench": [5, 5]])
        #expect(old.workingSets("bench").count == 2)
    }

    @Test func estimatesTheOneRepMax() throws {
        let fiveReps = try #require(WorkoutStats.estimatedOneRepMaxKg(kg: 100, reps: 5))
        #expect(abs(fiveReps - 116.666) < 0.01)
        #expect(WorkoutStats.estimatedOneRepMaxKg(kg: 100, reps: 1) == 100)
        #expect(WorkoutStats.estimatedOneRepMaxKg(kg: 100, reps: 15) == nil)
        #expect(WorkoutStats.estimatedOneRepMaxKg(kg: 0, reps: 5) == nil)
    }

    @Test func recentSessionsAreNewestFirstWithNotes() {
        let history = [snapshot("1", day: 1, weights: [80], reps: [5], details: [working]),
                       snapshot("2", day: 3, weights: [40, 90], reps: [10, 3], details: [warmup, working], note: "Seat 4"),
                       snapshot("3", day: 2, weights: [85], reps: [5], details: [working])]
        let sessions = WorkoutStats.recentSessions(forExerciseID: "bench", in: history, limit: 2)
        #expect(sessions.map(\.id) == ["2", "3"])
        #expect(sessions.first?.note == "Seat 4")
        #expect(sessions.first?.bestE1RM == WorkoutStats.estimatedOneRepMaxKg(kg: 90, reps: 3))
    }

    /// Warm-up and drop sets are marked, RIR is shown, and weight on a
    /// bodyweight exercise reads as added.
    @Test @MainActor func formatsMarkedSets() {
        let unit = SettingsManager.shared.weightUnit
        let w = NSLocalizedString("W", comment: "Set marker: warm-up set, before the weight")
        let rir = String(format: NSLocalizedString("RIR %d", comment: "Set marker: reps in reserve"), 2)
        #expect(unit.formatSet(WorkoutStats.LoggedSet(kg: 40, reps: 10, detail: warmup))
                == "\(w) \(unit.formatSet(kilograms: 40, reps: 10))")
        #expect(unit.formatSet(WorkoutStats.LoggedSet(kg: 80, reps: 8, detail: SetDetail(repsInReserve: 2)))
                == "\(unit.formatSet(kilograms: 80, reps: 8)) (\(rir))")
        #expect(unit.formatSet(WorkoutStats.LoggedSet(kg: 10, reps: 8, detail: working), bodyweight: true)
                == "+\(unit.formatSet(kilograms: 10, reps: 8))")
    }

    /// Saved data from before these fields decodes.
    @Test func olderDataStillDecodes() throws {
        let log = try JSONDecoder().decode(SessionLog.self, from: Data("{}".utf8))
        #expect(log == SessionLog())
        let snapshotJSON = #"{"workoutID":"w","workoutName":"W","exerciseIndex":1,"setIndex":2,"setCount":3,"startDate":0,"loggedWeights":{},"loggedReps":{}}"#
        let snapshot = try JSONDecoder().decode(ResumeSnapshot.self, from: Data(snapshotJSON.utf8))
        #expect(snapshot.exerciseIDs == nil)
        #expect(snapshot.completedSets == nil)
    }
}

@Suite("Swap suggestions")
struct SwapSuggestionTests {

    /// Built-in exercises are offered by movement pattern, never the exercise
    /// itself or one already in the session.
    @Test func suggestsTheSameMovementPattern() throws {
        let library = GymExerciseCatalog.all.map {
            Exercise(id: $0.id, difficultyInt: $0.difficultyInt, equipment: $0.equipment, muscleGroup: $0.muscleGroup, name: $0.name)
        }
        let bench = try #require(library.first { $0.id == "seed-exercise-bench-press" })
        let pattern = GymExerciseCatalog.all.first { $0.id == bench.id }?.pattern
        let suggestions = SwapSuggestions.candidates(for: bench, library: library,
                                                     availableEquipment: Set(1...30),
                                                     excluded: ["seed-exercise-incline-bench-press"])
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            #expect(suggestion.id != bench.id)
            #expect(suggestion.id != "seed-exercise-incline-bench-press")
            #expect(GymExerciseCatalog.all.first { $0.id == suggestion.id }?.pattern == pattern)
        }
    }
}

@Suite("Progression, rest, plates and workout changes")
struct TrainingAidTests {

    private func set(_ kg: Double, _ reps: Int, rir: Int? = nil) -> WorkoutStats.LoggedSet {
        WorkoutStats.LoggedSet(kg: kg, reps: reps, detail: SetDetail(repsInReserve: rir))
    }

    @Test func addsWeightOnceEveryRepIsDone() {
        let sets = [set(60, 8), set(60, 8, rir: 2), set(60, 9)]
        #expect(ProgressionAdvisor.suggestion(lastSets: sets, targetReps: 8, stepKg: 2.5) == .addWeight(toKg: 62.5))
        // A typed weight between steps goes to the next step.
        #expect(ProgressionAdvisor.suggestion(lastSets: [set(61, 8)], targetReps: 8, stepKg: 2.5) == .addWeight(toKg: 62.5))
        // Pounds: 135 lb → 137.5 lb, though stored in kilograms.
        let lb = WeightUnit.pounds
        let suggestion = ProgressionAdvisor.suggestion(lastSets: [set(lb.toKilograms(135), 8)], targetReps: 8, stepKg: lb.toKilograms(2.5))
        guard case .addWeight(let kg)? = suggestion else { Issue.record("No suggestion in pounds"); return }
        #expect(abs(lb.fromKilograms(kg) - 137.5) < 0.001)
    }

    @Test func repeatsAfterAShortSetOrAFailedOne() {
        #expect(ProgressionAdvisor.suggestion(lastSets: [set(60, 8), set(60, 6)], targetReps: 8, stepKg: 2.5) == nil)
        #expect(ProgressionAdvisor.suggestion(lastSets: [set(60, 8), set(60, 8, rir: 0)], targetReps: 8, stepKg: 2.5) == nil)
        #expect(ProgressionAdvisor.suggestion(lastSets: [set(60, 8)], targetReps: 0, stepKg: 2.5) == nil)
        #expect(ProgressionAdvisor.suggestion(lastSets: [], targetReps: 8, stepKg: 2.5) == nil)
    }

    @Test func bodyweightWithoutLoadGetsARep() {
        let sets = [set(0, 12), set(0, 10)]
        #expect(ProgressionAdvisor.suggestion(lastSets: sets, targetReps: 10, stepKg: 2.5) == .addRep(to: 11))
    }

    private let entries = [StraightSetSequencer.Entry(id: "a", sets: 3, supersetGroup: nil),
                           StraightSetSequencer.Entry(id: "b", sets: 3, supersetGroup: 1),
                           StraightSetSequencer.Entry(id: "c", sets: 3, supersetGroup: 1)]

    @Test func restFollowsSetsButNotDropSetsOrASupersetRound() {
        #expect(RestRule.restsAfter(kind: .working, current: 0, next: .stay, entries: entries))
        #expect(RestRule.restsAfter(kind: .working, current: 0, next: .move(to: 1), entries: entries))
        #expect(RestRule.restsAfter(kind: .warmup, current: 0, next: .stay, entries: entries))
        #expect(!RestRule.restsAfter(kind: .drop, current: 0, next: .stay, entries: entries))
        #expect(!RestRule.restsAfter(kind: .working, current: 0, next: .finish, entries: entries))
        // b → c is the same round; c → b starts the next one.
        #expect(!RestRule.restsAfter(kind: .working, current: 1, next: .move(to: 2), entries: entries))
        #expect(RestRule.restsAfter(kind: .working, current: 2, next: .move(to: 1), entries: entries))
    }

    @Test func loadsPlatesHeaviestFirst() {
        let kg = PlateCalculator.availablePlates(for: .kilograms)
        #expect(PlateCalculator.perSide(total: 100, bar: 20, plates: kg).plates == [25, 15])
        #expect(PlateCalculator.perSide(total: 62.5, bar: 20, plates: kg).plates == [20, 1.25])
        #expect(PlateCalculator.perSide(total: 20, bar: 20, plates: kg).plates.isEmpty)
        let odd = PlateCalculator.perSide(total: 101, bar: 20, plates: kg)
        #expect(odd.plates == [25, 15])
        #expect(abs(odd.remainder - 1) < 0.001)
        #expect(PlateCalculator.perSide(total: 225, bar: 45, plates: PlateCalculator.availablePlates(for: .pounds)).plates == [45, 45])
    }

    @Test func barOptionsKeepTheSavedBar() {
        #expect(PlateCalculator.barOptionsKg(for: .kilograms, current: 20) == [20, 15, 10])
        // A 20 kg bar stays selectable after switching to pounds.
        let pounds = PlateCalculator.barOptionsKg(for: .pounds, current: 20)
        #expect(pounds.count == 4)
        #expect(pounds.last == 20)
        #expect(PlateCalculator.barOptionsKg(for: .pounds, current: WeightUnit.pounds.toKilograms(45)).count == 3)
    }

    @Test func difficultyLevelsShareOneScale() {
        #expect(DifficultyLevel.allCases.map(\.rawValue) == [1, 2, 3])
        // Values outside the scale read as intermediate, as before.
        #expect(DifficultyLevel.name(for: 0) == DifficultyLevel.intermediate.name)
        #expect(DifficultyLevel.name(for: 3) == DifficultyLevel.advanced.name)
    }

    private let saved = ["a": ExercisePlan(sets: 3, reps: 10), "b": ExercisePlan(sets: 4, reps: 8)]

    @Test func noChangeWhenRunAsSaved() {
        #expect(RoutineChanges.detect(savedIDs: ["a", "b"], savedPlans: saved, sessionIDs: ["a", "b"], sessionPlans: [:]) == nil)
        // A session plan equal to the saved one isn't a change either.
        #expect(RoutineChanges.detect(savedIDs: ["a", "b"], savedPlans: saved, sessionIDs: ["a", "b"],
                                      sessionPlans: ["a": ExercisePlan(sets: 3, reps: 10)]) == nil)
    }

    @Test func reorderSwapAndSetsAreChanges() throws {
        let reordered = try #require(RoutineChanges.detect(savedIDs: ["a", "b"], savedPlans: saved,
                                                           sessionIDs: ["b", "a"], sessionPlans: [:]))
        #expect(reordered.exerciseIDs == ["b", "a"])
        #expect(reordered.plans == saved)

        let swapped = try #require(RoutineChanges.detect(savedIDs: ["a", "b"], savedPlans: saved, sessionIDs: ["a", "c"],
                                                         sessionPlans: ["c": ExercisePlan(sets: 4, reps: 12)]))
        #expect(swapped.plans["c"] == ExercisePlan(sets: 4, reps: 12))
        #expect(swapped.plans["b"] == nil)

        let moreSets = try #require(RoutineChanges.detect(savedIDs: ["a", "b"], savedPlans: saved, sessionIDs: ["a", "b"],
                                                          sessionPlans: ["a": ExercisePlan(sets: 5, reps: 10)]))
        #expect(moreSets.plans["a"]?.sets == 5)
    }

    @Test func historyCSVHasOneRowPerSetAndEscapes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let log = SessionLog(setDetails: ["bench": [SetDetail(kind: .warmup), SetDetail(repsInReserve: 2)],
                                          "plank": [SetDetail(seconds: 45)]],
                             exerciseNotes: ["bench": "Seat 4, grip wide"])
        let lift = HistoryCSV.Session(name: "Push \"A\"", start: start, end: start.addingTimeInterval(3600),
                                      activity: "Strength", calories: 300.4, note: "",
                                      exercises: [(id: "bench", name: "Bench Press"), (id: "plank", name: "Plank")],
                                      setWeights: ["bench": [40, 80], "plank": [0]], setReps: ["bench": [10, 8], "plank": [0]], log: log)
        let run = HistoryCSV.Session(name: "Run", start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(88_200),
                                     activity: "Running", calories: nil, note: "Felt easy",
                                     exercises: [], setWeights: [:], setReps: [:], log: SessionLog())
        let lines = HistoryCSV.make([run, lift], unit: .kilograms).split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[0] == HistoryCSV.header.joined(separator: ","))
        #expect(lines[1].hasPrefix("2027-01-15T"))
        #expect(lines[1].contains(",\"Push \"\"A\"\"\",Strength,60,300,Bench Press,1,warmup,40,kg,10,,,\"Seat 4, grip wide\""))
        #expect(lines[2].hasSuffix("Bench Press,2,working,80,kg,8,,2,"))
        // A timed set: its hold time in seconds.
        #expect(lines[3].hasSuffix("Plank,1,working,0,kg,0,45,,"))
        #expect(lines[4].hasSuffix(",Run,Running,30,,,,,,,,,,Felt easy"))
    }

    /// A timed exercise's plan carries its hold; plans saved before holds
    /// existed still decode, and show "timed" until a length is known.
    @Test @MainActor func timedExercisePlansCarryTheirHold() throws {
        let old = try JSONDecoder().decode(ExercisePlan.self, from: Data(#"{"sets":3,"reps":0}"#.utf8))
        #expect(old.seconds == nil)
        #expect(PlannedExercisesSection.summary(sets: 3, reps: 0, seconds: 45) == "3 × 0:45")
        #expect(PlannedExercisesSection.summary(sets: 3, reps: 0, seconds: 90) == "3 × 1:30")
        #expect(PlannedExercisesSection.summary(sets: 4, reps: 8, seconds: 45) == "4 × 8")
        let plan = ExercisePlan(sets: 3, reps: 0, seconds: 60)
        let decoded = try JSONDecoder().decode(ExercisePlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded.seconds == 60)
        // Only strength workouts hold; yoga and circuits keep their own pace.
        #expect(WorkoutCategory.holdsTimedExercises(WorkoutCategory.core.rawValue))
        #expect(WorkoutCategory.holdsTimedExercises(WorkoutCategory.fullbody.rawValue))
        #expect(!WorkoutCategory.holdsTimedExercises(WorkoutCategory.yoga.rawValue))
        #expect(!WorkoutCategory.holdsTimedExercises(WorkoutCategory.hiit.rawValue))
    }

    /// A timed set shows how long it was held, after any added weight; sets
    /// logged before hold times existed still decode.
    @Test func timedSetsShowTheirHoldTime() throws {
        let unit = WeightUnit.kilograms
        let plank = WorkoutStats.LoggedSet(kg: 0, reps: 0, detail: SetDetail(seconds: 45))
        #expect(unit.formatSet(plank) == "0:45")
        let weighted = WorkoutStats.LoggedSet(kg: 10, reps: 0, detail: SetDetail(seconds: 60))
        #expect(unit.formatSet(weighted, bodyweight: true) == "+10 kg · 1:00")
        let old = try JSONDecoder().decode(SetDetail.self, from: Data(#"{"kind":"working"}"#.utf8))
        #expect(old.seconds == nil)
    }

    @Test func bodyWeightCountsForBodyweightExercisesOnly() throws {
        let log = SessionLog(bodyWeightKg: 80, bodyweightExerciseIDs: ["pullup"])
        let volume = WorkoutStats.volumeKilograms(setWeights: ["pullup": [0, 10], "row": [50]],
                                                  setReps: ["pullup": [8, 5], "row": [10]], log: log)
        #expect(volume == 80 * 8 + 90 * 5 + 50 * 10)
        // Older logs have neither field.
        let old = try JSONDecoder().decode(SessionLog.self, from: Data(#"{"sessionNote":"x"}"#.utf8))
        #expect(old.bodyWeightKg == nil)
        #expect(old.bodyweightExerciseIDs.isEmpty)
    }

    @Test func seedPlansFallIntoGoalGroups() {
        func plan(goal: PlanGoal, muscleGroup: WorkoutCategory = .fullbody) -> Plan {
            Plan(id: UUID().uuidString, goal: goal.rawValue, infoText: "", muscleGroup: muscleGroup.rawValue, name: "",
                 difficultyInt: 2, interval: [:], intervalType: "", isUserGenerated: false,
                 workoutsSequenceIDs: [], finishedWorkoutsSequence: [], workoutsInPlan: [])
        }
        #expect(PlanGroup.of(plan(goal: .muscleBuilding)) == .strength)
        #expect(PlanGroup.of(plan(goal: .strengthTraining)) == .strength)
        #expect(PlanGroup.of(plan(goal: .enduranceAndStamina, muscleGroup: .cardio)) == .cardio)
        #expect(PlanGroup.of(plan(goal: .functionalFitness)) == .bodyweight)
        #expect(PlanGroup.of(plan(goal: .flexibilityAndMobility, muscleGroup: .mobilityFlexibility)) == .flexibility)
        #expect(PlanGroup.of(plan(goal: .overallHealthAndWellness)) == .wellness)
        #expect(PlanGroup.of(plan(goal: .other, muscleGroup: .yoga)) == .flexibility)
    }
}

@Suite("App styles")
struct AppThemeTests {

    private func traits(dark: Bool, highContrast: Bool = false, theme: AppTheme = .earth,
                        intensity: ColorIntensity = .vivid) -> UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.accessibilityContrast = highContrast ? .high : .normal
            traits.appTheme = theme
            traits.colorIntensity = intensity
        }
    }

    /// Every style stays readable: its accent and quieter text on the page,
    /// on its own cards and on the panels inside them, its body text on both,
    /// and the text on its buttons — 4.5:1 (AA), and 7:1 (AAA) with Increase
    /// Contrast, in light and dark mode, vivid and subtle.
    @Test(arguments: AppTheme.allCases, ColorIntensity.allCases)
    func meetsContrast(_ theme: AppTheme, _ intensity: ColorIntensity) {
        for dark in [false, true] {
            for high in [false, true] {
                let traits = traits(dark: dark, highContrast: high, intensity: intensity)
                let minimum = high ? 7.0 : 4.5
                let context = "\(theme), \(intensity), dark \(dark), high contrast \(high)"
                let surface = theme.rgb(.surface, for: traits)
                let inset = theme.rgb(.inset, for: traits)
                let page: RGB = dark ? .black : .white
                for background in [page, surface, inset] {
                    #expect(theme.rgb(.accent, for: traits).contrast(with: background) >= minimum, "accent, \(context)")
                    #expect(theme.rgb(.accentEnd, for: traits).contrast(with: background) >= minimum, "accent end, \(context)")
                    #expect(theme.rgb(.secondaryText, for: traits).contrast(with: background) >= minimum, "secondary text, \(context)")
                }
                #expect(theme.rgb(.primaryText, for: traits).contrast(with: surface) >= 7, "body text, \(context)")
                #expect(theme.rgb(.primaryText, for: traits).contrast(with: inset) >= 7, "body text on a panel, \(context)")
                #expect(theme.rgb(.fill, for: traits).contrast(with: theme.rgb(.onFill, for: traits)) >= minimum, "button, \(context)")
                #expect(theme.rgb(.fillEnd, for: traits).contrast(with: theme.rgb(.onFill, for: traits)) >= minimum, "button end, \(context)")
            }
        }
    }

    /// Text on a tinted page stays at 4.5:1, and the cards, tinted the same
    /// hue, still stand out from it — all along the tint, on plan pages too.
    /// Frosted cards stand out by their edge and shadow instead.
    /// (With Increase Contrast there's no tint.)
    @Test(arguments: AppTheme.allCases, ColorIntensity.allCases)
    func pageTintKeepsContrast(_ theme: AppTheme, _ intensity: ColorIntensity) {
        for dark in [false, true] {
            let traits = traits(dark: dark, intensity: intensity)
            let page: RGB = dark ? .black : .white
            let surface = theme.rgb(.surface, for: traits)
            for onPlanPages in [false, true] {
                let tint = theme.pageTint(onPlanPages: onPlanPages, intensity: intensity)
                let (top, bottom) = dark ? (tint.top.dark, tint.bottom.dark) : (tint.top.light, tint.bottom.light)
                for step in 0...10 {
                    let tinted = page.mixed(with: top.mixed(with: bottom, by: Double(step) / 10),
                                            by: dark ? tint.darkOpacity : tint.lightOpacity)
                    let context = "\(theme), \(intensity), dark \(dark), plan pages \(onPlanPages), at \(step)/10"
                    for role in [AppTheme.Role.accent, .accentEnd, .secondaryText] {
                        #expect(theme.rgb(role, for: traits).contrast(with: tinted) >= 4.5, "\(role), \(context)")
                    }
                    if !theme.geometry.frostedCards {
                        #expect(surface.contrast(with: tinted) >= 1.05, "cards, \(context)")
                    }
                }
            }
        }
    }

    /// The app's colors follow the style the view carries, not a stored value.
    @Test func themedColorsFollowTheTrait() {
        let ocean = traits(dark: false, theme: .ocean)
        for role in [AppTheme.Role.fill, .surface, .inset, .primaryText] {
            let resolved = AppTheme.themed(role).resolvedColor(with: ocean)
            #expect(resolved == AppTheme.ocean.rgb(role, for: ocean).uiColor)
            #expect(resolved != AppTheme.earth.rgb(role, for: ocean).uiColor)
        }
    }

    /// Subtle keeps a style's accent and buttons and mutes its cards, text
    /// and page tint — only in the styles with tinted cards, not in Graphite,
    /// which Settings doesn't offer the switch for.
    @Test func subtleMutesOnlyTheSurroundings() {
        #expect(AppTheme.allCases.filter { !$0.followsColorIntensity } == [.graphite])
        for theme in AppTheme.allCases {
            let vivid = traits(dark: false, theme: theme)
            let subtle = traits(dark: false, theme: theme, intensity: .subtle)
            for role in [AppTheme.Role.accent, .fill, .onFill] {
                #expect(theme.rgb(role, for: subtle) == theme.rgb(role, for: vivid), "\(theme) \(role)")
            }
            let muted = theme.followsColorIntensity
            for role in [AppTheme.Role.surface, .inset, .primaryText, .secondaryText] {
                let (less, more) = (OKLCH(theme.rgb(role, for: subtle)).c, OKLCH(theme.rgb(role, for: vivid)).c)
                #expect(muted ? less < more : less == more, "\(theme) \(role)")
            }
            #expect((theme.pageTint(intensity: .subtle).lightOpacity < theme.pageTint(intensity: .vivid).lightOpacity) == muted, "\(theme) tint")
        }
    }

    /// The derived cards, panels and text are equally light in every style
    /// with tinted cards, so one style can't drift darker than another.
    @Test(arguments: [false, true])
    func derivedLayersShareLightness(dark: Bool) {
        let tinted = AppTheme.allCases.filter(\.followsColorIntensity)
        for role in [AppTheme.Role.surface, .inset, .primaryText, .secondaryText] {
            let lightness = tinted.map { OKLCH($0.rgb(role, for: traits(dark: dark, theme: $0))).l }
            #expect(lightness.max()! - lightness.min()! < 0.005, "\(role), dark \(dark): \(lightness)")
        }
    }

    /// OKLCH round-trips sRGB, and a color too vivid for the screen keeps its
    /// lightness and hue.
    @Test func oklchConverts() {
        for hex: RGB in [0x7A5234, 0x1A5BC4, 0xFF4F8B, 0xF2F3F4, 0x000000, 0xFFFFFF] {
            let back = OKLCH(hex).rgb
            #expect(abs(back.red - hex.red) < 0.001 && abs(back.green - hex.green) < 0.001 && abs(back.blue - hex.blue) < 0.001)
        }
        let white = OKLCH(.white)
        #expect(abs(white.l - 1) < 0.001 && white.c < 0.001)
        let tooVivid = OKLCH(l: 0.6, c: 0.5, h: 200)
        let fitted = OKLCH(tooVivid.rgb)
        #expect(abs(fitted.l - 0.6) < 0.01 && abs(fitted.h - 200) < 2 && fitted.c < 0.5)
    }

    /// The Live Activity's card is the style's dark card; its white text,
    /// the 62 % secondary and the accent all read on it.
    @Test(arguments: AppTheme.allCases, ColorIntensity.allCases)
    func liveActivityStaysReadable(_ theme: AppTheme, _ intensity: ColorIntensity) {
        let card = theme.rgb(.surface, for: traits(dark: true, theme: theme, intensity: intensity))
        #expect(RGB.white.contrast(with: card) >= 7, "\(theme) text")
        #expect(card.mixed(with: .white, by: 0.62).contrast(with: card) >= 4.5, "\(theme) secondary")
        #expect(theme.spec.accent.dark.contrast(with: card) >= 4.5, "\(theme) accent")
    }

    /// Status colors and the accent's shades read on the page, the cards
    /// and the panels in them: text at 4.5:1, shades as icons at 3:1.
    @Test(arguments: AppTheme.allCases)
    func statusColorsAndShadesRead(_ theme: AppTheme) {
        for dark in [false, true] {
            let traits = traits(dark: dark, theme: theme)
            let page: RGB = dark ? .black : .white
            for background in [page, theme.rgb(.surface, for: traits), theme.rgb(.inset, for: traits)] {
                for role in [AppTheme.Role.success, .warning, .danger] {
                    #expect(theme.rgb(role, for: traits).contrast(with: background) >= 4.5, "\(theme) \(role), dark \(dark)")
                }
                for tone in 0..<5 {
                    #expect(theme.tone(tone, for: traits).contrast(with: background) >= 3, "\(theme) tone \(tone), dark \(dark)")
                }
            }
        }
    }

    @Test func stylesHaveDistinctNames() {
        #expect(Set(AppTheme.allCases.map(\.name)).count == AppTheme.allCases.count)
    }

    /// "App icon in style colors" on picks the style's icon, off the primary
    /// one; every style's name is registered as an alternate icon.
    @Test @MainActor func appIconFollowsStyle() {
        #expect(AppTheme.defaultStyle == .clay)
        #expect(AppIconSync.iconName(for: .clay, enabled: true) == "AppIcon-Clay")
        #expect(AppIconSync.iconName(for: .earth, enabled: true) == "AppIcon-Earth")
        let registered = Set(((Bundle(for: SettingsManager.self).infoDictionary?["CFBundleIcons"] as? [String: Any])?[
            "CFBundleAlternateIcons"] as? [String: Any])?.keys.map { $0 } ?? [])
        for theme in AppTheme.allCases {
            #expect(AppIconSync.iconName(for: theme, enabled: false) == nil)
            if let name = AppIconSync.iconName(for: theme, enabled: true) {
                #expect(registered.contains(name), "\(name) isn't an alternate icon")
            }
        }
    }
}

@Suite("Watch ending the iPhone's workout")
struct WatchEndTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func ended(_ id: String, startedAt: Date?) -> WorkoutState {
        WorkoutState(workoutId: id, workoutName: "Run", isActive: false, startTime: startedAt)
    }

    /// The previous workout's end, delivered late — a queued `.workoutEnd`
    /// or a freshly woken watch — doesn't close the run that just began.
    @Test func anotherWorkoutsEndIsIgnored() {
        let followed = (id: "run-2", start: start)
        #expect(!iOSWorkoutObserver.watchEnded(ended("run-1", startedAt: start.addingTimeInterval(-3_600)),
                                               following: followed, watchRan: true))
    }

    /// A catalog workout keeps its id, so the last run of it has the same
    /// one: its earlier start gives it away.
    @Test func theSameWorkoutsLastRunIsIgnored() {
        let followed = (id: "catalog-push", start: start)
        #expect(!iOSWorkoutObserver.watchEnded(ended("catalog-push", startedAt: start.addingTimeInterval(-1_800)),
                                               following: followed, watchRan: true))
    }

    /// Before the watch has reported the session running, an inactive
    /// state is its placeholder or a failed start, not an end.
    @Test func anEndBeforeTheWatchRanItIsIgnored() {
        let followed = (id: "run-2", start: start)
        #expect(!iOSWorkoutObserver.watchEnded(ended("run-2", startedAt: start.addingTimeInterval(2)),
                                               following: followed, watchRan: false))
    }

    /// The watch's stop button, once it ran the session: the iPhone ends
    /// too — also with the watch's clock a little behind.
    @Test func theWatchsRealEndCounts() {
        let followed = (id: "run-2", start: start)
        #expect(iOSWorkoutObserver.watchEnded(ended("run-2", startedAt: start.addingTimeInterval(3)),
                                              following: followed, watchRan: true))
        #expect(iOSWorkoutObserver.watchEnded(ended("run-2", startedAt: start.addingTimeInterval(-10)),
                                              following: followed, watchRan: true))
        #expect(!iOSWorkoutObserver.watchEnded(WorkoutState(), following: followed, watchRan: true),
                "The placeholder state of a launching watch")
    }
}

@Suite("Loading equipment and calorie rates")
struct LoadingEquipmentAndCalorieTests {

    private func makeContext() throws -> ModelContext {
        StringArrayValueTransformer.register()
        IntArrayValueTransformer.register()
        let container = try ModelContainer(
            for: Exercise.self, Workout.self, Plan.self, FinishedWorkout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func exercise(_ equipment: [Int], id: String = UUID().uuidString) -> Exercise {
        Exercise(id: id, difficultyInt: 2, equipment: equipment, muscleGroup: 1, name: "T")
    }

    /// Sled and Smith machine carry the load like a barbell does, so the logged
    /// weight is the whole load, not weight added to the body.
    @Test func sledAndSmithMachineAreLoaded() {
        #expect(!exercise([Equipment.smithMaschine.rawValue]).isBodyweight)
        #expect(!exercise([Equipment.sled.rawValue]).isBodyweight)
        #expect(exercise([]).isBodyweight)
        #expect(exercise([Equipment.pullUpBar.rawValue]).isBodyweight)
    }

    /// The band carries the load of a band curl or pull-apart, so the body's
    /// weight must not be added to its volume. Hanging from a pull-up bar with
    /// a band (an assisted pull-up) still lifts the body.
    @Test func bandsCarryTheLoadUnlessTheyAssistAPullUp() {
        #expect(!exercise([Equipment.resistanceBands.rawValue]).isBodyweight)
        #expect(!exercise([Equipment.resistanceBands.rawValue, Equipment.exerciseMat.rawValue]).isBodyweight)
        #expect(exercise([Equipment.resistanceBands.rawValue, Equipment.pullUpBar.rawValue]).isBodyweight)
        #expect(!exercise([Equipment.resistanceBands.rawValue, Equipment.dumbbells.rawValue]).isBodyweight)
        #expect(Exercise.resistanceBandsEquipment == Equipment.resistanceBands.rawValue)
        #expect(Exercise.pullUpBarEquipment == Equipment.pullUpBar.rawValue)
    }

    @Test func catalogSmithSquatAndSledPushAreNotBodyweight() throws {
        let context = try makeContext()
        for id in ["seed-exercise-smith-machine-squat", "seed-exercise-sled-push"] {
            let def = try #require(GymExerciseCatalog.byID[id])
            #expect(!def.materialize(in: context, existing: []).isBodyweight, "\(id)")
        }
    }

    /// The catalog's figures are kcal/min; stored per second they must be
    /// small. 0.25 kcal/s is 900 kcal/h — above any listed movement.
    @Test func catalogRatesArePerSecond() {
        for def in GymExerciseCatalog.all {
            #expect(def.caloriesPerSecond > 0, "\(def.id)")
            #expect(def.caloriesPerSecond < 0.25, "\(def.id)")
        }
    }

    @Test func materializeStoresAndCorrectsTheRate() throws {
        let context = try makeContext()
        let def = try #require(GymExerciseCatalog.byID["seed-exercise-bench-press"])
        let fresh = def.materialize(in: context, existing: [])
        #expect(fresh.caloriesPerSecond == def.kcalPerMinute / 60)

        // Older installs stored the per-minute figure in the per-second field.
        let legacy = exercise(def.equipment, id: def.id)
        legacy.caloriesPerSecond = 5
        _ = def.materialize(in: context, existing: [legacy])
        #expect(legacy.caloriesPerSecond == def.caloriesPerSecond)
    }

    /// A phone-only half hour of catalog exercises gets a plausible estimate.
    @Test func catalogWorkoutGetsAnEnergyEstimate() throws {
        let context = try makeContext()
        let rates = ["seed-exercise-bench-press", "seed-exercise-smith-machine-squat", "seed-exercise-lat-pulldown"]
            .compactMap { GymExerciseCatalog.byID[$0]?.materialize(in: context, existing: []).caloriesPerSecond }
        let kcal = try #require(PhoneWorkoutHealthWriter.estimatedEnergy(caloriesPerSecond: rates, duration: 1800))
        #expect(kcal > 30 && kcal < 300)
    }

    /// Saved sessions stop counting the body on Smith/sled sets; real
    /// bodyweight exercises keep it.
    @Test func repairDropsSmithAndSledFromSavedLogs() throws {
        let context = try makeContext()
        context.insert(exercise([Equipment.smithMaschine.rawValue], id: "smith"))
        context.insert(exercise([Equipment.sled.rawValue], id: "sled"))
        context.insert(exercise([Equipment.pullUpBar.rawValue], id: "pullup"))

        let mixed = FinishedWorkout(endDate: .now, name: "T", startDate: .now, muscleGroup: 1,
                                    exercisesSequenceID: ["smith", "pullup"])
        mixed.loggingDetails = SessionLog(bodyWeightKg: 80, bodyweightExerciseIDs: ["smith", "pullup"])
        let sledOnly = FinishedWorkout(endDate: .now, name: "T", startDate: .now, muscleGroup: 1,
                                       exercisesSequenceID: ["sled"])
        sledOnly.loggingDetails = SessionLog(bodyWeightKg: 80, bodyweightExerciseIDs: ["sled"])
        context.insert(mixed)
        context.insert(sledOnly)

        #expect(removeSmithSledFromBodyweightLogs(modelContext: context))
        #expect(mixed.loggingDetails.bodyweightExerciseIDs == ["pullup"])
        #expect(mixed.loggingDetails.bodyWeightKg == 80)
        #expect(mixed.loggingDetails.load("smith", addedKg: 40) == 40)
        #expect(sledOnly.loggingDetails.bodyweightExerciseIDs.isEmpty)
        #expect(sledOnly.loggingDetails.bodyWeightKg == nil)
        #expect(!removeSmithSledFromBodyweightLogs(modelContext: context), "Idempotent")
    }
}
