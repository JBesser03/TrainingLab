//
//  DemoData.swift
//  Workout App (iOS)
//
//  DEBUG-only demo content for the App Store screenshots
//  (`Tests iOS/ScreenshotTests.swift`). With `-UITestSeedDemoData` the app
//  runs on its local store (never CloudKit) and gets six weeks of training
//  history, a plan in progress, weekly goals and a body weight, so History,
//  Progress and For You look like an app in use. `-UITestTheme <id>` sets the
//  style, which lives in the App Group and can't be passed as a launch
//  argument. Compiled out of release builds.
//

#if DEBUG
import Foundation
import SwiftData
import HealthKit

@MainActor
enum DemoData {
    static let flag = "-UITestSeedDemoData"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    /// Seeds once per install (demo rows carry the `demo-` id prefix), and
    /// applies `-UITestTheme` on every launch.
    static func seedIfRequested(into context: ModelContext) {
        guard isActive else { return }
        applyTheme()
        let history = (try? context.fetch(FetchDescriptor<FinishedWorkout>())) ?? []
        guard !history.contains(where: { $0.id.hasPrefix("demo-") }) else { return }
        seedSettings()
        seedHistory(into: context)
        do {
            try context.save()
        } catch {
            appLog("Demo data: save failed: \(error)")
        }
    }

    private static func applyTheme() {
        guard let id = UserDefaults.standard.string(forKey: "UITestTheme"),
              let theme = AppTheme(rawValue: id) else { return }
        SettingsManager.shared.appTheme = theme
        SettingsManager.shared.colorIntensity = .subtle
    }

    private static func seedSettings() {
        let settings = SettingsManager.shared
        settings.weeklyGoals = [WeeklyGoal(category: .gym, targetPerWeek: 3),
                                WeeklyGoal(category: .running, targetPerWeek: 1)]
        settings.bodyWeightKg = 78
        settings.appleWatchUsage = false
        settings.restTimerSeconds = 0
        // A typical gym, so For You's "set your equipment" banner is gone.
        let missing: Set<Equipment> = [.battleRopes, .sled, .skiErg, .stairClimber, .boxingGlovesPunchingBag, .other]
        settings.availableGymEquipment = Set(Equipment.allCases.filter { !missing.contains($0) }.map(\.rawValue))
    }

    // MARK: - History

    /// Top working weights (kg) reached in the latest session. Earlier
    /// sessions climb toward them, so Progress shows a rising curve and the
    /// latest session holds a PR.
    private static let topWeights: [String: Double] = [
        // Push
        "seed-exercise-bench-press": 82.5,
        "seed-exercise-overhead-press": 52.5,
        "seed-exercise-incline-dumbbell-press": 30,
        "seed-exercise-lateral-raise": 12,
        "seed-exercise-tricep-pushdown": 32.5,
        // Pull
        "seed-exercise-barbell-row": 77.5,
        "seed-exercise-lat-pulldown": 70,
        "seed-exercise-face-pull": 25,
        "seed-exercise-shrugs": 32.5,
        "seed-exercise-hammer-curls": 18,
        // Legs
        "seed-exercise-back-squat": 110,
        "seed-exercise-romanian-deadlift": 90,
        "seed-exercise-leg-press": 120,
        "seed-exercise-leg-curl": 50,
        "seed-exercise-seated-calf-raise": 45
    ]

    private static func seedHistory(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        func workout(_ id: String) -> Workout? { workouts.first { $0.id == id } }
        guard let push = workout("seed-workout-push-intermediate"),
              let pull = workout("seed-workout-pull-intermediate"),
              let legs = workout("seed-workout-leg-intermediate") else {
            appLog("Demo data: catalog workouts missing")
            return
        }

        // Three gym days and a run a week, six weeks back; today is a gym day.
        let gymDaysAgo = (0..<42).filter { [0, 2, 4].contains($0 % 7) }.sorted(by: >)
        let runDaysAgo = (0..<42).filter { $0 % 7 == 5 }
        // Newest first: Push today, Legs before it, then Pull, and so on.
        let rotation = [push, legs, pull]
        let sessions = gymDaysAgo.enumerated().map { index, daysAgo in
            (daysAgo: daysAgo, workout: rotation[(gymDaysAgo.count - 1 - index) % rotation.count])
        }

        var sessionCount: [String: Int] = [:]
        var totalCount: [String: Int] = [:]
        for session in sessions {
            for id in session.workout.exercisesSequenceID { totalCount[id, default: 0] += 1 }
        }

        for (number, session) in sessions.enumerated() {
            let (start, end) = times(daysAgo: session.daysAgo, minutes: 52 + (number * 7) % 14,
                                     today: today, now: now, calendar: calendar)
            let source = session.workout
            let exercises = source.exercisesSequenceID.compactMap { id in source.exercises?.first { $0.id == id } }
            let entry = FinishedWorkout(
                id: "demo-gym-\(number)",
                endDate: end,
                name: source.displayName,
                startDate: start,
                muscleGroup: source.muscleGroup,
                workoutLocation: source.workoutSessionLocation,
                workoutType: source.workoutActivityType,
                caloriesBurned: end.timeIntervalSince(start) / 60 * 6.4,
                exercisesSequenceID: exercises.map(\.id)
            )
            entry.exercises = exercises

            var weights: [String: [Double]] = [:]
            var reps: [String: [Int]] = [:]
            var details: [String: [SetDetail]] = [:]
            for (position, exercise) in exercises.enumerated() {
                let plan = source.plan(for: exercise)
                let seen = sessionCount[exercise.id, default: 0]
                sessionCount[exercise.id] = seen + 1
                let progress = Double(seen) / Double(max(totalCount[exercise.id, default: 1] - 1, 1))
                let sets = max(plan.sets, 1)

                if plan.reps == 0 {
                    // Timed (a plank): held, not lifted.
                    weights[exercise.id] = Array(repeating: 0, count: sets)
                    reps[exercise.id] = Array(repeating: 0, count: sets)
                    details[exercise.id] = Array(repeating: SetDetail(seconds: 30 + Int(progress * 15)), count: sets)
                    continue
                }

                let top = topWeights[exercise.id] ?? defaultTopWeight(for: exercise)
                let weight = top == 0 ? 0 : roundToPlate(top * (0.86 + 0.14 * progress))
                var setWeights = Array(repeating: weight, count: sets)
                var setReps = (0..<sets).map { set in set == sets - 1 ? max(plan.reps - 1, 1) : plan.reps }
                var setDetails = Array(repeating: SetDetail(), count: sets)
                setDetails[sets - 1].repsInReserve = 1
                if position == 0, weight > 0 {
                    setWeights.insert(roundToPlate(weight * 0.5), at: 0)
                    setReps.insert(10, at: 0)
                    setDetails.insert(SetDetail(kind: .warmup), at: 0)
                }
                weights[exercise.id] = setWeights
                reps[exercise.id] = setReps
                details[exercise.id] = setDetails
            }
            entry.setWeights = weights
            entry.setReps = reps

            var log = SessionLog(setDetails: details)
            let bodyweightIDs = Set(exercises.filter(\.isBodyweight).map(\.id))
            if !bodyweightIDs.isEmpty {
                log.bodyWeightKg = 78
                log.bodyweightExerciseIDs = bodyweightIDs
            }
            if number == sessions.count - 1 {
                // Not a catalog string: only the screenshots need it.
                log.sessionNote = Locale.preferredLanguages.first?.hasPrefix("de") == true
                    ? "Bankdrücken lief heute richtig gut – neue Bestleistung."
                    : "Bench felt strong today – a new best."
            }
            entry.loggingDetails = log
            entry.perceivedEffort = [7, 8, 6, 7, 8][number % 5]
            context.insert(entry)
        }

        for (number, daysAgo) in runDaysAgo.enumerated() {
            let (start, end) = times(daysAgo: daysAgo, minutes: 28 + (number * 5) % 12,
                                     today: today, now: now, calendar: calendar)
            let name = number % 2 == 0 ? "Easy Run" : "Tempo Run"
            let entry = FinishedWorkout(
                id: "demo-run-\(number)",
                endDate: end,
                name: NSLocalizedString(name, comment: "Run name"),
                startDate: start,
                muscleGroup: WorkoutCategory.cardio.rawValue,
                workoutLocation: Int(HKWorkoutSessionLocationType.outdoor.rawValue),
                workoutType: Int(HKWorkoutActivityType.running.rawValue),
                caloriesBurned: end.timeIntervalSince(start) / 60 * 10.5,
                exercisesSequenceID: []
            )
            entry.perceivedEffort = number % 2 == 0 ? 4 : 7
            context.insert(entry)
        }

        // Push Pull Legs in progress: two of its three workouts done this cycle.
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        if let ppl = plans.first(where: { $0.id == "seed-plan-ppl-intermediate" }) {
            ppl.isSaved = true
            ppl.finishedWorkoutsSequence = Array(ppl.workoutsSequenceIDs.prefix(2))
        }
    }

    /// An evening session `daysAgo` days back; today's is in the morning at
    /// a fixed time, whenever the screenshots are taken.
    private static func times(daysAgo: Int, minutes: Int, today: Date, now: Date,
                              calendar: Calendar) -> (Date, Date) {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        let time = daysAgo == 0 ? DateComponents(hour: 7, minute: 15)
                                : DateComponents(hour: 18, minute: (daysAgo * 13) % 40)
        let start = calendar.date(byAdding: time, to: day) ?? day
        return (start, start.addingTimeInterval(Double(minutes * 60)))
    }

    /// A believable top weight for a lift without its own entry.
    private static func defaultTopWeight(for exercise: Exercise) -> Double {
        let equipment = Set(exercise.equipment.compactMap(Equipment.init(rawValue:)))
        if equipment.contains(.barbells) || equipment.contains(.smithMaschine) { return 60 }
        if equipment.contains(.legPressMaschine) { return 160 }
        if equipment.contains(.cableMaschine) { return 35 }
        if equipment.contains(.ezBar) { return 32.5 }
        if equipment.contains(.kettlebells) { return 20 }
        if equipment.contains(.dumbbells) { return 18 }
        return 0
    }

    private static func roundToPlate(_ kg: Double) -> Double {
        (kg / 2.5).rounded() * 2.5
    }
}
#endif
