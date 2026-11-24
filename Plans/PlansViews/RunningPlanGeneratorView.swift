//
//  RunningPlanGeneratorView.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 20.05.26.
//

import SwiftUI
import SwiftData
import HealthKit

struct RunningPlanGeneratorView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query private var existingPlans: [Plan]

    @State private var distanceKm: Double = 5.0
    @State private var targetDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
    @State private var weeklySessions: Int = 3
    @State private var customName = ""
    @State private var showNameAlreadyExisting = false


    private var weeksUntilTarget: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: targetDate)
        let weeks = calendar.dateComponents([.weekOfYear], from: startOfToday, to: startOfTarget).weekOfYear ?? 0
        return max(weeks, 1)
    }

    var body: some View {
        NavigationStack {
            StyledForm(onPlanPage: true) {
                Section {
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(String(format: "%.1f km", distanceKm))
                            .foregroundStyle(Theme.accent)
                            .font(.headline)
                    }
                    Slider(value: $distanceKm, in: 1...42.2, step: 0.5)
                } header: {
                    Text("Goal")
                } footer: {
                    Text("How far do you want to be able to run?")
                }

                Section {
                    DatePicker("Target date",
                               selection: $targetDate,
                               in: Date()...,
                               displayedComponents: .date)
                    HStack {
                        Text("Weeks to train")
                        Spacer()
                        Text("\(weeksUntilTarget)")
                            .foregroundStyle(Theme.accent)
                            .font(.headline)
                    }
                } header: {
                    Text("Schedule")
                }

                Section {
                    Stepper(value: $weeklySessions, in: 2...6) {
                        HStack {
                            Text("Sessions per week")
                            Spacer()
                            Text("\(weeklySessions)")
                                .foregroundStyle(Theme.accent)
                                .font(.headline)
                        }
                    }
                } header: {
                    Text("Frequency")
                }

                Section {
                    TextField("e.g. Marathon prep", text: $customName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Optional — names the plan and its runs. Leave empty for an automatic name.")
                }

                Section {
                    Button {
                        generatePlan()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "wand.and.stars")
                            Text("Generate plan")
                                .bold()
                            Spacer()
                        }
                        .foregroundStyle(Theme.onAccent)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.accentFillGradient)
                }
            }
            .navigationTitle("Running plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isPresented: $showNameAlreadyExisting) {
                Alert(title: Text("Name already existing"),
                      message: Text("A Plan with this name already exists. Please try again later."),
                      dismissButton: .default(Text("OK")))
            }
        }
    }

    private func generatePlan() {
        let weeks = weeksUntilTarget
        let goal = distanceKm
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)

        var workouts: [Workout] = []
        var workoutIDs: [String] = []

        // Build week by week, mixing session types (easy / intervals / tempo /
        // long) rather than a single ever-increasing distance. The long run is
        // the progressive endurance builder; easy runs carry volume; intervals
        // and tempo build speed. Every 4th week cuts back and the last week tapers.
        for week in 1...weeks {
            for kind in sessionTypes(for: weeklySessions) {
                let session = session(kind: kind, week: week, totalWeeks: weeks, goal: goal)

                let workoutName: String
                if trimmedName.isEmpty {
                    workoutName = String(
                        format: NSLocalizedString("Week %d · %@", comment: "Generated running workout name"),
                        week, session.title
                    )
                } else {
                    workoutName = String(format: "%@ · W%d · %@", trimmedName, week, session.title)
                }

                let workout = Workout(
                    id: UUID().uuidString,
                    infoText: session.info,
                    isUserGenerated: true,
                    isNew: true,
                    muscleGroup: WorkoutCategory.cardio.rawValue,
                    setLength: 1.0,
                    straightSets: false,
                    difficultyInt: session.difficultyInt,
                    name: workoutName,
                    duration: session.durationMin,
                    exercisesSequenceID: [],
                    finishedExercisesSequence: [],
                    exercises: [],
                    plan: [],
                    workoutActivityType: Int(HKWorkoutActivityType.running.rawValue),
                    workoutSessionLocation: Int(HKWorkoutSessionLocationType.outdoor.rawValue)
                )
                workouts.append(workout)
                workoutIDs.append(workout.id)
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: targetDate)

        let trimmedPlanName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedPlanName.isEmpty
            ? String(
                format: NSLocalizedString("Run %.1f km by %@", comment: "Generated running plan name"),
                goal, dateString
            )
            : trimmedPlanName
        let planName = uniqueName(baseName)

        let infoFormat = NSLocalizedString(
            "Progressive %d-week plan, %d runs per week — easy runs, intervals/tempo work and a weekly long run building to %.1f km by %@, with cutback and taper weeks.",
            comment: "Generated running plan info"
        )
        let infoText = String(format: infoFormat, weeks, weeklySessions, goal, dateString)

        let newPlan = Plan(
            goal: PlanGoal.enduranceAndStamina.rawValue,
            infoText: infoText,
            muscleGroup: WorkoutCategory.cardio.rawValue,
            name: planName,
            difficultyInt: 2,
            interval: [:],
            intervalType: "",
            notificationIDs: [],
            isUserGenerated: true,
            workoutsSequenceIDs: workoutIDs,
            finishedWorkoutsSequence: [],
            workoutsInPlan: workouts
        )
        newPlan.workouts = workouts
        newPlan.workoutsSequenceIDs = workoutIDs

        for workout in workouts {
            modelContext.insert(workout)
            workout.plan = [newPlan]
        }
        modelContext.insert(newPlan)

        do {
            try modelContext.save()
        } catch {
            appLog("Error saving generated running plan: \(error)")
        }

        dismiss()
    }

    private func uniqueName(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while existingPlans.contains(where: { $0.name == candidate }) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }

    // MARK: - Session planning

    private enum RunSessionKind {
        case easy, intervals, tempo, long
    }

    private struct RunSession {
        let title: String
        let info: String
        let durationMin: Int
        let difficultyInt: Int
    }

    /// The weekly mix of session types for a given weekly frequency. Always
    /// includes one long run; fills the rest with easy runs and speed work.
    private func sessionTypes(for perWeek: Int) -> [RunSessionKind] {
        switch max(perWeek, 2) {
        case 2:  return [.easy, .long]
        case 3:  return [.easy, .intervals, .long]
        case 4:  return [.easy, .intervals, .easy, .long]
        case 5:  return [.easy, .intervals, .easy, .tempo, .long]
        default: return [.easy, .intervals, .easy, .tempo, .easy, .long]
        }
    }

    /// Long-run distance for a week: ramps from ~40% of goal toward the goal,
    /// cuts back ~30% every 4th week, and tapers on the final week.
    private func longRunKm(week: Int, totalWeeks: Int, goal: Double) -> Double {
        let start = max(goal * 0.4, 2.0)
        if week == totalWeeks && totalWeeks > 1 {
            return max(goal * 0.5, 2.0) // taper before the target date
        }
        let rampWeeks = max(totalWeeks - 1, 1)
        let t = rampWeeks <= 1 ? 1.0 : Double(week - 1) / Double(rampWeeks - 1)
        var km = start + (goal - start) * min(max(t, 0), 1)
        if week % 4 == 0 { km *= 0.7 } // recovery / cutback week
        return max(km, 2.0)
    }

    /// Builds a concrete session (title / info / duration) for the given type.
    private func session(kind: RunSessionKind, week: Int, totalWeeks: Int, goal: Double) -> RunSession {
        let long = longRunKm(week: week, totalWeeks: totalWeeks, goal: goal)
        func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

        switch kind {
        case .long:
            let km = round1(long)
            return RunSession(
                title: String(format: NSLocalizedString("Long run · %.1f km", comment: "Running session title"), km),
                info: NSLocalizedString("Steady, conversational pace — your main endurance builder. Keep it easy enough to talk.", comment: "Running session info"),
                durationMin: max(Int((km * 6.5).rounded()), 10),
                difficultyInt: 2)
        case .easy:
            let km = round1(max(long * 0.55, 2.0))
            return RunSession(
                title: String(format: NSLocalizedString("Easy run · %.1f km", comment: "Running session title"), km),
                info: NSLocalizedString("Relaxed recovery pace to build your aerobic base without fatigue.", comment: "Running session info"),
                durationMin: max(Int((km * 6.5).rounded()), 10),
                difficultyInt: 1)
        case .tempo:
            let km = round1(max(long * 0.5, 3.0))
            return RunSession(
                title: String(format: NSLocalizedString("Tempo run · %.1f km", comment: "Running session title"), km),
                info: NSLocalizedString("Comfortably hard, sustained effort — around 20–30 sec/km slower than 5K pace.", comment: "Running session info"),
                durationMin: max(Int((km * 6.0).rounded()), 15),
                difficultyInt: 3)
        case .intervals:
            let reps = min(4 + week / 2, 10)
            return RunSession(
                title: String(format: NSLocalizedString("Intervals · %d × 400 m", comment: "Running session title"), reps),
                info: String(format: NSLocalizedString("Warm up 10 min, then %d × 400 m hard with 200 m easy jog between, cool down 10 min.", comment: "Running session info"), reps),
                durationMin: 20 + reps * 3,
                difficultyInt: 3)
        }
    }
}

#Preview {
    let preview = PreviewPlan()
    return RunningPlanGeneratorView()
        .modelContainer(preview.container)
}
