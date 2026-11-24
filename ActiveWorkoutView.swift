//
//  ContentView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 22.09.21.
//

import SwiftUI
import SwiftData
import HealthKit
import MapKit
import Dispatch
import WorkoutKit
import UIKit
import Combine

struct ActiveWorkoutView: View {
    
    var plan: Plan?
    @Bindable var workout: Workout
    
    @EnvironmentObject var workoutObserver: iOSWorkoutObserver
    
    @Query var workouts: [Workout]
    @Query var exercises: [Exercise]
    /// Finished-workout history, newest first — used to prefill each exercise's
    /// weight with what the user lifted last time ("progression prefill").
    @Query(sort: [SortDescriptor(\FinishedWorkout.endDate, order: .reverse)])
    private var finishedWorkouts: [FinishedWorkout]
    
    @Environment(\.modelContext) private var modelContext
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme

    /// Base size for the big workout timer / rep counter, scaled with the user's
    /// Dynamic Type setting so it stays readable at larger text sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var bigTimerSize: CGFloat = 72
    @ScaledMetric(relativeTo: .title) private var valueTileSize: CGFloat = 30

    @State private var workoutIsActive = false
    @State private var currentExerciseIndex = 0

    @State private var timeRemaining: CGFloat = 0
    @State private var setCount = 5
    /// 0-based set within the current exercise (straight-set / strength mode).
    @State private var currentSetIndex = 0

    @State private var pauseActive = false

    @State private var pauseTimeCounting = 0
    
    @State private var workoutStartDate: Date?
    /// When the session was paused, so the elapsed clock stops there.
    @State private var pausedAt: Date?
    /// The session's finished pauses, so Health and the energy estimate only
    /// count the time spent working out.
    @State private var pauseIntervals: [DateInterval] = []

    /// Per-set weights logged this session, keyed by exercise id (in kilograms).
    @State private var loggedWeights: [String: [Double]] = [:]
    /// Per-set reps logged this session, index-aligned with `loggedWeights`.
    @State private var loggedReps: [String: [Int]] = [:]
    /// The weight (kg) the user is about to log for the current exercise's set.
    @State private var currentSetWeightKg: Double?
    /// The reps the user is about to log for the current exercise's set.
    @State private var currentSetReps: Int?

    /// This session's changes to the workout's plans: a sets stepper tap, an
    /// exercise added or swapped in. Everything else reads the workout's own
    /// plan (see `plan(for:)`); the saved workout is never changed.
    @State private var sessionPlans: [String: ExercisePlan] = [:]
    /// Working sets finished per exercise — whether or not a weight or reps
    /// entry was recorded for them (a timed plank set has none).
    @State private var completedSets: [String: Int] = [:]
    @State private var skippedExerciseIDs: Set<String> = []
    /// Kind and reps in reserve of each logged set, index-aligned with `loggedWeights`.
    @State private var loggedDetails: [String: [SetDetail]] = [:]
    @State private var exerciseNotes: [String: String] = [:]
    /// What the next logged set is. A warm-up or drop set is extra: it doesn't
    /// count toward the exercise's sets.
    @State private var nextSetKind: SetKind = .working
    /// Reps left in reserve for the set about to be logged; nil = not rated.
    @State private var currentSetRIR: Int?
    /// The exercise the session just moved on from after its last working
    /// set. Until a set of the next one is logged, a drop set can still go on
    /// it — the usual moment for one, which moving on would otherwise skip.
    @State private var dropSetOfferID: String?
    /// Set by the drop-set offer: the exercise it returns to starts in
    /// drop-set mode once its prefill has run.
    @State private var pendingDropSet = false
    /// A timed set of a strength workout (a plank, a hang) runs only after
    /// "Start set" — not the moment the exercise appears.
    @State private var timedSetRunning = false
    /// The current exercise's last working set and note from an earlier
    /// session — looked up when the exercise changes, not on every redraw
    /// (the timer redraws ten times a second).
    @State private var lastTimeSet: WorkoutStats.LoggedSet?
    @State private var lastTimeNote: String?
    /// Circuit workouts: rounds for this session, from the sets stepper.
    @State private var sessionRounds: Int?
    @State private var showOverview = false
    @State private var showLastSessions = false
    @State private var showNoteEditor = false
    @State private var showWeightEntry = false
    @State private var showRepsEntry = false
    @State private var showSecondsEntry = false
    /// How long the next timed set of a strength workout is held; set by the
    /// prefill and the time stepper.
    @State private var currentSetSeconds: Int?
    @State private var valueEntryText = ""
    /// The current value, shown greyed in the empty field: typing replaces
    /// it instead of adding to it, and nothing typed keeps it.
    @State private var valueEntryPlaceholder = ""
    @State private var showPlates = false
    /// Strength rest between sets (Settings → Rest timer). Advisory: the
    /// next set can be logged before it's over.
    @State private var restStart: Date?
    @State private var restEnd: Date?
    /// Why the weight or reps were raised from last time, e.g. "+2.5 kg:
    /// every rep done last time".
    @State private var progressionHint: String?
    /// From Apple Health or Settings, for the volume of bodyweight exercises.
    @State private var sessionBodyWeightKg: Double?

    /// When set (and matching `workout.id`), the view restores progress from
    /// this snapshot on appear instead of starting fresh — used by the Resume flow.
    private let resumeSnapshot: ResumeSnapshot?

    /// Set at the very start of `endWorkout()`. `saveResumeSnapshot()` respects
    /// it so a resume snapshot can never be resurrected after the workout has
    /// already ended — `endWorkout()` clears it, then calls `recordCurrentSet()`,
    /// whose mutation of `loggedWeights`/`loggedReps` re-triggers the `.onChange`
    /// handlers that call `saveResumeSnapshot()`, which was silently re-creating
    /// a snapshot for a workout that had just been marked finished (the "still
    /// showing a rejoin banner after finishing" bug).
    @State private var isEnding = false
    /// Drives the X button's "save or discard" dialog.
    @State private var showEndConfirmation = false

    /// Whether the last session ended with a save. Presenters read it in their
    /// cover's `onDismiss` to skip the summary sheet after "End without saving",
    /// which would otherwise show the previous workout's summary.
    @MainActor static var lastEndSaved = true

    init(workout: Workout, plan: Plan? = nil, resumeSnapshot: ResumeSnapshot? = nil) {
        self.workout = workout
        self.plan = plan
        self.resumeSnapshot = resumeSnapshot
        let resumedIDs = resumeSnapshot?.workoutID == workout.id ? resumeSnapshot?.exerciseIDs : nil
        _exerciseIDs = State(initialValue: resumedIDs ?? workout.exercisesSequenceID)
    }

    /// The session's exercise ids in order. Starts as the workout's, decoded
    /// once — `exercisesSequenceID` decodes its JSON on every access, and the
    /// timer reads it every second. Swapping, adding, removing or reordering
    /// during the session changes only this.
    @State private var exerciseIDs: [String]
    
    /// Width used for screen-relative sizing of the timer ring and exercise
    /// artwork, capped so they don't balloon on a large iPad canvas
    /// (`UIScreen.activeBounds` is the whole screen, not the app window).
    private var layoutWidth: CGFloat { min(UIScreen.activeBounds.width, 500) }

    /// The visible height and the session content's, measured to size the ring.
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    /// The ring's fitted size; nil until measured.
    @State private var fittedRingDiameter: CGFloat?

    /// The exercise ring: what the controls leave, up to 80 % of the width
    /// and down to a minimum — below that the content scrolls. The content
    /// has no spacers, so its measured height is what it needs and the ring
    /// grows back when the controls take less room.
    private var ringDiameter: CGFloat { fittedRingDiameter ?? layoutWidth * 0.8 }

    private func fitRing() {
        guard viewportHeight > 0, contentHeight > 0 else { return }
        // Everything but the ring, as last laid out.
        let others = contentHeight - ringDiameter
        let fitted = min(layoutWidth * 0.8, max(120, viewportHeight - others))
        if abs(fitted - ringDiameter) > 1 { fittedRingDiameter = fitted }
    }
    

    /// The exercise at `currentExerciseIndex`, resolved through the canonical
    /// `exercisesSequenceID` order. The raw `workout.exercises` SwiftData
    /// relationship has no guaranteed order, so indexing into it directly
    /// causes the symbol/equipment to drift out of sync with the name.
    private var currentExercise: Exercise? {
        guard let id = exerciseIDs[safe: currentExerciseIndex] else { return nil }
        return getExercise(for: id)
    }

    private var currentExerciseID: String? { exerciseIDs[safe: currentExerciseIndex] }

    /// An exercise's plan for this session: a change made during it, else
    /// the workout's plan with its pre-plan fallbacks.
    private func plan(for id: String) -> ExercisePlan {
        if let plan = sessionPlans[id] { return plan }
        if let exercise = getExercise(for: id) { return workout.plan(for: exercise) }
        return ExercisePlan(sets: max(Int(workout.setLength), 1), reps: 0)
    }

    /// Rep target for the current exercise, if any. `nil`/`0` means the exercise is
    /// time-based and the workout timer drives it.
    private var currentExerciseRepCount: Int? {
        currentExerciseID.map { plan(for: $0).reps }
    }

    private var currentExerciseIsRepBased: Bool {
        (currentExerciseRepCount ?? 0) > 0
    }

    /// Total training volume logged so far this session (Σ weight × reps across
    /// every set recorded so far), live — shown as a running stat during the workout.
    private var sessionVolumeKg: Double {
        WorkoutStats.volumeKilograms(setWeights: loggedWeights, setReps: loggedReps,
                                     log: sessionLog(notes: [:]))
    }

    private var sessionVolumeText: String? {
        guard sessionVolumeKg > 0 else { return nil }
        return SettingsManager.shared.weightUnit.format(kilograms: sessionVolumeKg)
    }

    /// Whether the live-metrics row has anything to show. Both of its inputs
    /// arrive mid-session, so the row is faded into a reserved slot rather than
    /// inserted — see its use site.
    private var hasSessionMetrics: Bool {
        workoutObserver.currentHeartRate > 0 || sessionVolumeText != nil
    }

    /// Fraction (0...1) of this exercise's sets completed. Rep-based sets have no
    /// countdown to animate the progress ring against, so it fills as sets finish
    /// instead — mirrors the "Set x / y" label above the ring.
    private var currentSetProgress: CGFloat {
        totalSets > 0 ? CGFloat(currentSetIndex) / CGFloat(totalSets) : 0
    }

    /// Thickness of the big timer/progress ring.
    private let ringLineWidth: CGFloat = 14

    /// Label for the rep-based "complete this set" button. Straight-set workouts
    /// finish the exercise (or the whole workout) on the last set with no rest,
    /// so the label reflects what tapping it actually does.
    private var repSetButtonTitle: String {
        switch nextSetKind {
        case .warmup: return NSLocalizedString("Log warm-up", comment: "Active workout: complete a warm-up set")
        case .drop:   return NSLocalizedString("Log drop set", comment: "Active workout: complete a drop set")
        case .working: break
        }
        if allWorkDone {
            return NSLocalizedString("Finish workout", comment: "Active workout: complete final set of final exercise")
        }
        if isTimedStrengthSet && !timedSetRunning {
            return NSLocalizedString("Start set", comment: "Active workout: start the countdown of a timed set")
        }
        guard isStraightSets, let id = currentExerciseID,
              (completedSets[id] ?? 0) + 1 >= plan(for: id).sets else {
            return NSLocalizedString("Set done", comment: "Active workout: complete current set")
        }
        var done = completedSets
        done[id, default: 0] += 1
        if StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                     done: done, skipped: skippedExerciseIDs) == .finish {
            return NSLocalizedString("Last set done", comment: "Active workout: complete the final set of the workout; Finish follows")
        }
        return NSLocalizedString("Exercise done", comment: "Active workout: complete final set of exercise")
    }

    private var repSetButtonSymbol: String {
        if nextSetKind == .working && allWorkDone { return "flag.checkered" }
        if isTimedStrengthSet && !timedSetRunning && nextSetKind == .working { return "play.fill" }
        return "checkmark"
    }

    /// Every working set of every exercise is done or skipped. The session
    /// then waits for "Finish workout" rather than ending on the last set, so
    /// a drop set or an extra set can still follow.
    private var allWorkDone: Bool {
        isStraightSets && !exerciseIDs.isEmpty && exerciseIDs.allSatisfy { id in
            skippedExerciseIDs.contains(id) || (completedSets[id] ?? 0) >= max(plan(for: id).sets, 1)
        }
    }

    /// Timed sets start on a tap in strength workouts — you need to get into
    /// position. Yoga and mobility flows keep running from pose to pose.
    private var timedSetsStartOnTap: Bool {
        isStraightSets && WorkoutCategory.holdsTimedExercises(workout.muscleGroup)
    }

    /// The current exercise is a timed set of a strength workout.
    private var isTimedStrengthSet: Bool {
        timedSetsStartOnTap && !isOpenEnded && currentExerciseID != nil && !currentExerciseIsRepBased
    }

    // MARK: Weight logging

    /// Muscle groups with no meaningful weight axis — cardio/HIIT intervals,
    /// yoga poses, and mobility/flexibility work.
    private static let nonWeightedMuscleGroups = WorkoutCategory.nonWeighted

    /// Whether to offer weight logging for the current exercise. Gated on
    /// muscle group rather than the exercise's own equipment list — plenty of
    /// bodyweight strength moves (dips, push-ups, pull-ups without a listed
    /// plate/vest) are still commonly done weighted, and the old
    /// equipment-based check hid the input for exactly those.
    private var showsWeightInput: Bool {
        guard let exercise = currentExercise else { return false }
        return !Self.nonWeightedMuscleGroups.contains(exercise.muscleGroup)
    }

    /// Reps logging is offered for rep-based exercises (target repCount > 0).
    private var showsRepsInput: Bool { currentExerciseIsRepBased }

    /// Whether a set should be logged for the current exercise at all.
    private var shouldRecordSet: Bool { showsWeightInput || showsRepsInput }

    /// The weight increment per tap: 2.5 in the user's display unit, in kilograms.
    private var weightStepKg: Double {
        SettingsManager.shared.weightUnit.toKilograms(2.5)
    }

    /// The current set's weight in kilograms, falling back to the plan's target.
    private var effectiveSetWeightKg: Double {
        currentSetWeightKg ?? currentExerciseID.flatMap { plan(for: $0).targetWeightKg } ?? 0
    }

    /// The current set's reps, falling back to the plan's reps.
    private var effectiveSetReps: Int {
        currentSetReps ?? currentExerciseRepCount ?? 0
    }

    /// The weight shown in the stepper. A bodyweight exercise's weight is what's
    /// added (a vest, a plate on a dip belt), so it reads "+10 kg", and "+0 kg"
    /// rather than a confusing "0 kg".
    private var currentWeightDisplay: String {
        let text = SettingsManager.shared.weightUnit.format(kilograms: effectiveSetWeightKg)
        return currentExercise?.isBodyweight == true ? "+" + text : text
    }

    private func roundedToWeightStep(_ kg: Double) -> Double {
        (kg / weightStepKg).rounded() * weightStepKg
    }

    private func adjustWeight(by direction: Double) {
        currentSetWeightKg = max(0, effectiveSetWeightKg + direction * weightStepKg)
        Haptics.tap()
    }

    private func adjustReps(by delta: Int) {
        currentSetReps = max(0, effectiveSetReps + delta)
        Haptics.tap()
    }

    /// The newest earlier session's *working* sets of an exercise, and that
    /// session's note for it — never its warm-up or drop sets.
    private func previousSession(forExerciseID id: String) -> (sets: [WorkoutStats.LoggedSet], note: String?)? {
        for finished in finishedWorkouts {
            let snapshot = WorkoutStats.Snapshot(id: finished.id, endDate: finished.endDate,
                                                 setWeights: finished.setWeights, setReps: finished.setReps,
                                                 log: finished.loggingDetails)
            let sets = snapshot.workingSets(id)
            if !sets.isEmpty {
                let note = snapshot.log.exerciseNotes[id].flatMap { $0.isEmpty ? nil : $0 }
                return (sets, note)
            }
        }
        return nil
    }

    /// The "Last time: …" hint string (weight and/or reps), or nil if no history.
    private var lastTimeHint: String? {
        guard let set = lastTimeSet, set.kg > 0 || set.reps > 0 else { return nil }
        let text = SettingsManager.shared.weightUnit.formatSet(set, bodyweight: currentExercise?.isBodyweight == true)
        return text.isEmpty ? nil : String(format: NSLocalizedString("Last time: %@", comment: "Active workout: previous set hint"), text)
    }

    /// This session's last working set of `id`, if any.
    private func lastWorkingSetThisSession(_ id: String) -> (kg: Double, reps: Int)? {
        let weights = loggedWeights[id] ?? []
        let reps = loggedReps[id] ?? []
        guard let index = weights.indices.last(where: { detail(id, $0).kind == .working }) else { return nil }
        return (weights[index], index < reps.count ? reps[index] : 0)
    }

    private func detail(_ id: String, _ index: Int) -> SetDetail {
        guard let details = loggedDetails[id], details.indices.contains(index) else { return SetDetail() }
        return details[index]
    }

    /// Prefills the weight & reps controls when the active exercise changes.
    /// Priority: a working set already logged this session → last time → plan.
    private func prefillWeightForCurrentExercise() {
        // After the prefill: the drop-set offer returned to this exercise.
        defer {
            if pendingDropSet {
                pendingDropSet = false
                toggleSetKind(.drop)
            }
        }
        guard let id = currentExerciseID else {
            currentSetWeightKg = currentExercise?.targetWeightKg
            currentSetReps = currentExercise?.repCount
            lastTimeSet = nil
            lastTimeNote = nil
            return
        }
        let previous = previousSession(forExerciseID: id)
        lastTimeSet = previous?.sets.last
        lastTimeNote = previous?.note
        progressionHint = nil
        let plan = plan(for: id)
        if isTimedStrengthSet {
            currentSetSeconds = plannedSeconds(for: id)
            if !timedSetRunning {
                timeRemaining = CGFloat(currentSetSeconds ?? 0)
            }
        }
        if let session = lastWorkingSetThisSession(id) {
            currentSetWeightKg = session.kg
            currentSetReps = session.reps
            return
        }
        currentSetWeightKg = lastTimeSet?.kg ?? plan.targetWeightKg
        currentSetReps = lastTimeSet.map(\.reps).flatMap { $0 > 0 ? $0 : nil } ?? plan.reps
        // Last time went well: start this one a step up.
        guard isStraightSets, let previous else { return }
        switch ProgressionAdvisor.suggestion(lastSets: previous.sets, targetReps: plan.reps, stepKg: weightStepKg) {
        case .addWeight(let kg)?:
            // Up from the heaviest set, which the suggestion builds on — the
            // last one can be lighter.
            let heaviest = previous.sets.map(\.kg).max() ?? kg
            let step = SettingsManager.shared.weightUnit.format(kilograms: kg - heaviest)
            progressionHint = String(format: NSLocalizedString("+%@: every rep done last time", comment: "Active workout: weight raised from last session, e.g. '+2.5 kg: every rep done last time'"), step)
            currentSetWeightKg = kg
            currentSetReps = plan.reps
        case .addRep(let reps)?:
            progressionHint = NSLocalizedString("One more rep: every rep done last time", comment: "Active workout: reps raised from last session")
            currentSetReps = reps
        case nil:
            break
        }
    }

    /// Records weight + reps for the current exercise's just-completed set, kept
    /// index-aligned. Skips sets with neither a weight nor reps (pure timed
    /// bodyweight/cardio) so they don't pollute the history.
    private func recordCurrentSet() {
        guard shouldRecordSet || isTimedStrengthSet, let id = currentExerciseID else { return }
        let kg = showsWeightInput ? effectiveSetWeightKg : 0
        let reps = showsRepsInput ? effectiveSetReps : 0
        // A timed set keeps how long it was held.
        let seconds: Int? = isTimedStrengthSet
            ? max(Int((workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining) - timeRemaining).rounded()), 0)
            : nil
        guard kg > 0 || reps > 0 || (seconds ?? 0) > 0 else { return }
        // Any set logged ends the offer to add a drop set to the last exercise.
        dropSetOfferID = nil
        loggedWeights[id, default: []].append(kg)
        loggedReps[id, default: []].append(reps)
        // Index-aligned with the weights; sets restored from an older resume
        // snapshot have no detail and are padded as working sets.
        var details = loggedDetails[id] ?? []
        while details.count < (loggedWeights[id]?.count ?? 1) - 1 { details.append(SetDetail()) }
        details.append(SetDetail(kind: nextSetKind, repsInReserve: showsRepsInput ? currentSetRIR : nil, seconds: seconds))
        loggedDetails[id] = details
    }

    /// Whether there's a just-logged set of the *current* exercise that
    /// "Edit last set" can undo. Restricted to straight sets.
    private var canEditLastSet: Bool {
        guard isStraightSets, let id = currentExerciseID else { return false }
        return !(loggedWeights[id]?.isEmpty ?? true) || !(loggedReps[id]?.isEmpty ?? true)
    }

    /// Pops the most recently logged set for the current exercise and steps
    /// back to it, prefilling the steppers with the value being corrected
    /// (rather than resetting to a target/last-session fallback) so the user
    /// can immediately see and adjust the mistake.
    private func editLastSet() {
        guard let id = currentExerciseID else { return }
        let index = (loggedWeights[id]?.count ?? 0) - 1
        let popped = detail(id, index)
        let poppedWeight = loggedWeights[id]?.popLast()
        let poppedReps = loggedReps[id]?.popLast()
        guard poppedWeight != nil || poppedReps != nil else { return }
        if loggedDetails[id]?.indices.contains(index) == true { loggedDetails[id]?.remove(at: index) }
        if popped.kind == .working {
            completedSets[id] = max((completedSets[id] ?? 1) - 1, 0)
        }
        currentSetIndex = completedSets[id] ?? 0
        nextSetKind = popped.kind
        currentSetRIR = popped.repsInReserve
        if let poppedWeight { currentSetWeightKg = poppedWeight }
        if let poppedReps { currentSetReps = poppedReps }
        Haptics.tap()
    }

    /// Switches the next set between a working set and `kind`. A drop set
    /// starts about 20 % lighter than the last working set.
    private func toggleSetKind(_ kind: SetKind) {
        nextSetKind = nextSetKind == kind ? .working : kind
        if nextSetKind == .drop, let id = currentExerciseID, let last = lastWorkingSetThisSession(id), last.kg > 0 {
            currentSetWeightKg = roundedToWeightStep(last.kg * 0.8)
        }
        Haptics.select()
    }

    /// A large −/value/+ tile for the weight, reps or hold of the set being
    /// logged. Holding −/+ repeats; tapping the value opens `onTapValue` to
    /// type it.
    @ViewBuilder
    private func valueTile(title: String,
                           value: String,
                           accessibility: String,
                           onDecrement: @escaping () -> Void,
                           onIncrement: @escaping () -> Void,
                           onTapValue: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: Spacing.xs) {
                tileButton("minus", action: onDecrement)
                Button(action: onTapValue) {
                    Text(value)
                        .displayNumberFont(size: valueTileSize)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: value)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                tileButton("plus", action: onIncrement)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibility))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onIncrement()
            case .decrement: onDecrement()
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(NSLocalizedString("Enter value", comment: "Active workout: type the weight or reps"))) {
            onTapValue()
        }
    }

    private func tileButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background(Theme.inset, in: Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    /// A logged set's feel: crisper for an exercise's last working set.
    private func setHaptic() {
        if nextSetKind == .working, isStraightSets, let id = currentExerciseID,
           (completedSets[id] ?? 0) + 1 >= max(plan(for: id).sets, 1) {
            Haptics.exerciseDone()
        } else {
            Haptics.setDone()
        }
    }

    /// The weight, reps or hold tiles and what goes with them are showing.
    private var showsLogControls: Bool {
        (shouldRecordSet || isTimedStrengthSet) && !pauseActive
    }

    /// "Exercise 2 of 6", in a session of more than one.
    private var exercisePositionText: String? {
        guard !isOpenEnded, !pauseActive, exerciseIDs.count > 1, currentExerciseID != nil else { return nil }
        return String(format: NSLocalizedString("Exercise %d of %d", comment: "Active workout: the current exercise's place in the session"),
                      currentExerciseIndex + 1, exerciseIDs.count)
    }

    /// "Next: Overhead Press" in a strength workout: where `StraightSetSequencer`
    /// goes after this set — the partner in a superset — or else after this
    /// exercise. Nil on the last one.
    private var upNextText: String? {
        guard isStraightSets, !pauseActive, !allWorkDone, let id = currentExerciseID else { return nil }
        var done = completedSets
        done[id, default: 0] += 1
        var step = StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                             done: done, skipped: skippedExerciseIDs)
        if step == .stay {
            done[id] = max(plan(for: id).sets, 1)
            step = StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                             done: done, skipped: skippedExerciseIDs)
        }
        guard case .move(to: let index) = step, let nextID = exerciseIDs[safe: index],
              let name = getExercise(for: nextID)?.displayName else { return nil }
        return String(format: NSLocalizedString("Next: %@", comment: "Rest timer notification: the exercise to do now"), name)
    }

    /// A dot per set of the current exercise: filled when done, ringed for
    /// the one coming up.
    @ViewBuilder
    private var setDots: some View {
        let done = currentExerciseID.flatMap { completedSets[$0] } ?? 0
        if isStraightSets, totalSets <= 12 {
            HStack(spacing: 6) {
                ForEach(0..<totalSets, id: \.self) { index in
                    Circle()
                        .fill(index < done ? Theme.accent : Theme.hairline)
                        .overlay {
                            if index == done && !allWorkDone {
                                Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 8, height: 8)
                }
            }
            .animation(.snappy, value: done)
            .accessibilityHidden(true)
        }
    }

    /// Changes the hold of the next timed set, before it starts. Kept for the
    /// rest of the session, and offered for the workout at the end like any
    /// change to its sets.
    private func setHold(_ seconds: Int) {
        guard let id = currentExerciseID, !timedSetRunning else { return }
        let seconds = min(max(seconds, 5), 600)
        currentSetSeconds = seconds
        timeRemaining = CGFloat(seconds)
        var plan = plan(for: id)
        plan.seconds = seconds
        sessionPlans[id] = plan
        saveResumeSnapshot()
        sendCurrentExerciseToWatch(currentExerciseIndex)
    }

    private func adjustHold(by delta: Int) {
        setHold((currentSetSeconds ?? Int(timeRemaining)) + delta)
        Haptics.tap()
    }

    /// Takes a typed weight (in the user's unit) or rep count. Accepts a
    /// comma as the decimal separator.
    private func applyEnteredValue(weight: Bool) {
        let text = valueEntryText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if weight, let value = Double(text), value >= 0 {
            currentSetWeightKg = SettingsManager.shared.weightUnit.toKilograms(value)
        } else if !weight, let value = Int(text), value >= 0 {
            currentSetReps = value
        }
    }

    // MARK: Rest periods

    /// Automatic rest periods (the blue "Pause" countdown between exercises and
    /// sets) apply only to cardio/HIIT sessions. Every other workout advances
    /// straight through with no rest.
    private var isCardioOrHIIT: Bool {
        workout.muscleGroup == WorkoutCategory.cardio.rawValue ||
        workout.muscleGroup == WorkoutCategory.hiit.rawValue
    }

    /// Strength workouts (everything except cardio/HIIT) run straight sets: all
    /// sets of one exercise before the next, no rest between sets.
    private var isStraightSets: Bool { !isCardioOrHIIT }

    /// Sets of the current exercise (strength), or rounds (circuit).
    private var totalSets: Int {
        if isStraightSets, let id = currentExerciseID { return max(plan(for: id).sets, 1) }
        return max(sessionRounds ?? Int(workout.setLength), 1)
    }

    private var sequencerEntries: [StraightSetSequencer.Entry] {
        exerciseIDs.map { id in
            let plan = plan(for: id)
            return StraightSetSequencer.Entry(id: id, sets: max(plan.sets, 1), supersetGroup: plan.supersetGroup)
        }
    }

    /// Number of exercises in the session. The ordered `exercisesSequenceID` is
    /// what this screen walks through; the `exercises` relationship is
    /// unordered, can't hold an exercise twice and is still nil while iCloud is
    /// delivering it — counting that (with a fallback of 1) ended a
    /// multi-exercise workout after its first exercise.
    private var exerciseCount: Int {
        exerciseIDs.isEmpty ? (workout.exercises?.count ?? 0) : exerciseIDs.count
    }

    /// A session with no exercises to step through, like the runs from For
    /// You and running plans. It has no countdown and never ends on its own:
    /// it runs from the start until the user finishes it, and the history
    /// entry's duration comes from those two dates.
    private var isOpenEnded: Bool { exerciseCount == 0 }

    /// The work ring's fill. Rep-based sets have no countdown to animate it
    /// against (the timer intentionally doesn't tick for them), so it fills
    /// with sets completed instead; an open-ended session has nothing to fill.
    private var ringProgress: CGFloat {
        if isOpenEnded { return 1 }
        if currentExerciseIsRepBased { return currentSetProgress }
        return CGFloat(timeRemaining) / CGFloat(max(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining), 1))
    }

    /// The session's exercises, each once, resolved through `exerciseIDs` —
    /// not the `exercises` relationship, which is nil while iCloud is still
    /// delivering it.
    private var sessionExercises: [Exercise] {
        var seen = Set<String>()
        return exerciseIDs.compactMap { id in
            seen.insert(id).inserted ? getExercise(for: id) : nil
        }
    }

    /// Straight-set advance (strength mode): log the just-finished set, then
    /// let `StraightSetSequencer` decide — another set of this exercise, the
    /// next member of its superset, the next unfinished exercise, or the end.
    /// A warm-up or drop set is extra and never advances.
    private func advanceStraightSet(defaultTimeRemaining: Double) {
        accumulatedTime = 0
        lastTimerTick = nil
        guard let id = currentExerciseID else {
            endWorkout()
            return
        }
        let kind = nextSetKind
        recordCurrentSet()
        nextSetKind = .working
        currentSetRIR = nil
        timedSetRunning = false
        timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
        endRest(finished: false)
        let exerciseFinished = (completedSets[id] ?? 0) >= max(plan(for: id).sets, 1)
        guard kind == .working else {
            if exerciseFinished {
                // A drop set after the last working set: carry on to whatever
                // is left, resting first as after any finished exercise.
                let step = StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                                     done: completedSets, skipped: skippedExerciseIDs)
                if RestRule.restsAfter(kind: .working, current: currentExerciseIndex, next: step, entries: sequencerEntries) {
                    startRest()
                }
                if case .move(let index) = step {
                    moveToExercise(index, defaultTimeRemaining: defaultTimeRemaining)
                }
            } else if RestRule.restsAfter(kind: kind, current: currentExerciseIndex, next: .stay, entries: sequencerEntries) {
                startRest()
            }
            return
        }

        completedSets[id, default: 0] += 1
        let step = StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                             done: completedSets, skipped: skippedExerciseIDs)
        if RestRule.restsAfter(kind: kind, current: currentExerciseIndex, next: step, entries: sequencerEntries) {
            startRest()
        }
        switch step {
        case .stay:
            currentSetIndex = completedSets[id] ?? 0
        case .move(let index):
            // Drop sets are for rep-based exercises, as the set-type chips are.
            if currentExerciseIsRepBased && (completedSets[id] ?? 0) >= max(plan(for: id).sets, 1) {
                dropSetOfferID = id
            }
            moveToExercise(index, defaultTimeRemaining: defaultTimeRemaining)
        case .finish:
            // Nothing left: "Finish workout" takes over (see `allWorkDone`),
            // so a last drop set or an extra set can still follow.
            currentSetIndex = completedSets[id] ?? 0
        }
    }

    /// Goes back to the exercise just finished for a drop set; logging it
    /// returns to the workout's next exercise.
    private func addDropSet(to id: String) {
        guard let index = exerciseIDs.firstIndex(of: id) else { return }
        dropSetOfferID = nil
        pendingDropSet = true
        jumpToExercise(index)
    }

    /// Starts the countdown of a timed strength set; it ends a rest still
    /// running, like logging a set does.
    private func startTimedSet() {
        endRest(finished: false)
        timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
        accumulatedTime = 0
        lastTimerTick = nil
        timedSetRunning = true
        sendCurrentExerciseToWatch(currentExerciseIndex)
        updateLiveActivity()
    }

    // MARK: Rest timer

    private var isResting: Bool { restEnd != nil }

    /// Starts the strength rest, when it's switched on in Settings.
    private func startRest() {
        let seconds = SettingsManager.shared.restTimerSeconds
        guard seconds > 0 else { return }
        restStart = .now
        restEnd = .now.addingTimeInterval(Double(seconds))
        if SettingsManager.shared.appleWatchUsage {
            workoutObserver.updateRestState(isResting: true, remaining: Double(seconds))
        }
    }

    private func extendRest(by seconds: Double) {
        guard let end = restEnd else { return }
        restEnd = end.addingTimeInterval(seconds)
        if SettingsManager.shared.appleWatchUsage {
            workoutObserver.updateRestState(isResting: true, remaining: restEnd?.timeIntervalSinceNow ?? 0)
        }
        Haptics.tap()
    }

    /// - Parameter finished: the rest ran out, rather than being skipped or
    ///   cut short by the next set — that one gets a buzz.
    private func endRest(finished: Bool) {
        guard restEnd != nil else { return }
        restStart = nil
        restEnd = nil
        if finished {
            Haptics.restOver()
        }
        // Clears the watch's rest countdown.
        sendCurrentExerciseToWatch(currentExerciseIndex)
    }

    /// Locked or in another app, the rest ends with a notification; on screen,
    /// the timer does it.
    private func syncRestNotification(phase: ScenePhase) {
        if phase == .background, let restEnd {
            RestNotification.schedule(at: restEnd, next: currentExercise?.displayName)
        } else {
            RestNotification.cancel()
        }
    }

    private var restBanner: some View {
        HStack(spacing: 12) {
            if let restStart, let restEnd {
                Label {
                    Text(timerInterval: restStart...restEnd, countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "hourglass")
                }
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(Text(NSLocalizedString("Rest", comment: "Active workout: rest between sets")))
            }
            Button {
                extendRest(by: 15)
            } label: {
                Text(NSLocalizedString("+15 s", comment: "Active workout: make the rest 15 seconds longer"))
            }
            .accessibilityIdentifier("activeWorkout.restLonger")
            Button {
                endRest(finished: false)
            } label: {
                Text(NSLocalizedString("Skip rest", comment: "Active workout: end the rest now"))
            }
            .accessibilityIdentifier("activeWorkout.skipRest")
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .controlBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activeWorkout.rest")
    }

    /// Makes `index` the current exercise, at its next unfinished set.
    private func moveToExercise(_ index: Int, defaultTimeRemaining: Double) {
        guard exerciseIDs.indices.contains(index) else { return }
        currentExerciseIndex = index
        currentSetIndex = completedSets[exerciseIDs[index]] ?? 0
        pauseActive = false
        pauseTimeCounting = 0
        currentSetSeconds = nil
        timeRemaining = CGFloat(workSeconds(at: index, fallback: defaultTimeRemaining))
        accumulatedTime = 0
        lastTimerTick = nil
        nextSetKind = .working
        currentSetRIR = nil
        timedSetRunning = false
    }

    // MARK: Session changes (overview)

    private var overviewRows: [SessionOverviewRow] {
        exerciseIDs.enumerated().map { index, id in
            let exercise = getExercise(for: id)
            let plan = plan(for: id)
            return SessionOverviewRow(id: id,
                                      name: exercise?.displayName ?? NSLocalizedString("Exercise not found", comment: "Active workout: missing exercise"),
                                      symbol: exercise?.symbol ?? "",
                                      done: completedSets[id] ?? 0,
                                      planned: max(plan.sets, 1),
                                      isCurrent: index == currentExerciseIndex,
                                      isSkipped: skippedExerciseIDs.contains(id),
                                      hasLoggedSets: !(loggedWeights[id]?.isEmpty ?? true) || (completedSets[id] ?? 0) > 0,
                                      supersetGroup: plan.supersetGroup)
        }
    }

    private func jumpToExercise(_ index: Int) {
        guard let id = exerciseIDs[safe: index] else { return }
        // Going back to a skipped exercise picks it up again.
        skippedExerciseIDs.remove(id)
        moveToExercise(index, defaultTimeRemaining: defaultTimeRemaining)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        let currentID = currentExerciseID
        exerciseIDs.move(fromOffsets: source, toOffset: destination)
        if let currentID, let index = exerciseIDs.firstIndex(of: currentID) {
            currentExerciseIndex = index
        }
        saveResumeSnapshot()
    }

    /// Only an exercise nothing was logged for yet.
    private func removeExercise(at index: Int) {
        guard exerciseIDs.count > 1, let id = exerciseIDs[safe: index] else { return }
        let wasCurrent = index == currentExerciseIndex
        exerciseIDs.remove(at: index)
        sessionPlans[id] = nil
        if index < currentExerciseIndex { currentExerciseIndex -= 1 }
        if wasCurrent {
            moveToExercise(min(index, exerciseIDs.count - 1), defaultTimeRemaining: defaultTimeRemaining)
        }
        saveResumeSnapshot()
    }

    /// Replaces an exercise nothing was logged for yet, keeping its place,
    /// sets and superset.
    private func swapExercise(at index: Int, with exercise: Exercise) {
        guard let oldID = exerciseIDs[safe: index], !exerciseIDs.contains(exercise.id) else { return }
        let old = plan(for: oldID)
        sessionPlans[oldID] = nil
        sessionPlans[exercise.id] = ExercisePlan(sets: old.sets, reps: exercise.repCount,
                                                 targetWeightKg: exercise.targetWeightKg, supersetGroup: old.supersetGroup)
        exerciseIDs[index] = exercise.id
        if index == currentExerciseIndex {
            // Same index, so `onChange(of: currentExerciseIndex)` won't fire.
            moveToExercise(index, defaultTimeRemaining: defaultTimeRemaining)
            prefillWeightForCurrentExercise()
            sendCurrentExerciseToWatch(index)
            updateLiveActivity()
        }
        saveResumeSnapshot()
    }

    private func addExercise(_ exercise: Exercise) {
        guard !exerciseIDs.contains(exercise.id) else { return }
        exerciseIDs.append(exercise.id)
        sessionPlans[exercise.id] = ExercisePlan(sets: 3, reps: exercise.repCount, targetWeightKg: exercise.targetWeightKg)
        saveResumeSnapshot()
    }

    private func swapCandidates(at index: Int) -> [Exercise] {
        guard let id = exerciseIDs[safe: index], let exercise = getExercise(for: id) else { return [] }
        return SwapSuggestions.candidates(for: exercise, library: exercises,
                                          availableEquipment: SettingsManager.shared.availableGymEquipment,
                                          excluded: Set(exerciseIDs))
    }

    /// Tells the watch which exercise is current, from the session's own list
    /// and with this workout's planned reps.
    private func sendCurrentExerciseToWatch(_ index: Int) {
        guard SettingsManager.shared.appleWatchUsage else { return }
        workoutObserver.updateCurrentExercise(workout: workout, index: index,
                                              remainingSeconds: watchCountdownSeconds(at: index),
                                              sessionExerciseIDs: exerciseIDs,
                                              reps: exerciseIDs[safe: index].map { plan(for: $0).reps })
        // The next exercise is shown while resting before it.
        if let restEnd, restEnd > .now {
            workoutObserver.updateRestState(isResting: true, remaining: restEnd.timeIntervalSinceNow)
        }
    }

    /// Starts the next set from the first exercise immediately (no rest).
    private func advanceToNextSet(defaultTimeRemaining: Double) {
        setCount -= 1
        guard exerciseCount > 0 else { return }
        currentExerciseIndex = 0
        timeRemaining = CGFloat(workSeconds(at: 0, fallback: defaultTimeRemaining))
        pauseTimeCounting = 0
        sendCurrentExerciseToWatch(0)
    }

    /// GPS route recording for outdoor distance workouts.
    @StateObject private var runLocation = RunLocationManager()

    /// Outdoor distance workouts (running, walking, cycling, hiking) get
    /// automatic route tracking; everything else doesn't touch location.
    private var tracksRoute: Bool {
        guard workout.workoutSessionLocation != HKWorkoutSessionLocationType.indoor.rawValue else { return false }
        switch HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) {
        case .running, .walking, .cycling, .hiking:
            return true
        default:
            return false
        }
    }

    /// SF Symbol for the workout's activity type — used when the current
    /// exercise has no custom symbol (e.g. running/cycling/swimming workouts
    /// that carry no exercise list), instead of a wrong bodyweight glyph.
    private var activitySymbolName: String {
        (HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) ?? .other).symbolName
    }

    /// The glyph in the timer ring: the exercise's own symbol (custom asset or
    /// SF Symbol) when it has a valid one, otherwise the activity-type SF Symbol.
    @ViewBuilder
    private var currentExerciseSymbol: some View {
        let symbol = ExerciseSymbol(name: currentExercise?.symbol ?? "")
        if let asset = symbol?.assetName {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: symbol?.systemName ?? activitySymbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
                .padding(layoutWidth * 0.06)
        }
    }

    /// Rest between rounds for circuit (cardio/HIIT) workouts, from the workout
    /// itself. Straight-set (gym) workouts never enter the rest path, so this is
    /// effectively unused for them.
    private var pauseTime: Int { workout.restSeconds }
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let pauseTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    let timerPublisher = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var lastTimerTick: Date? = nil
    @State private var accumulatedTime: CGFloat = 0.0
    @State private var shouldProcessLogic: Bool = false
        
    /// Fallback work length for one set, derived purely from the workout's own
    /// duration, exercise count and set count.
    ///
    /// Hoisted out of `body` (where it used to be a local `let`) because the
    /// Live Activity's Lock Screen buttons call the same navigation functions
    /// from outside the view hierarchy and need the identical value.
    private var defaultTimeRemaining: Double {
        let totalSecRemaining: Double = Double(workout.duration) * 60
        // Guard against an empty exercise list (count 0) or zero duration:
        // dividing by 0 here produced an infinite `timeRemaining`, and
        // `Int(.infinity)` crashes. Clamp both to a safe minimum.
        let countExercises = max(exerciseCount, 1)
        return max(totalSecRemaining / Double(countExercises) / 5 * workout.setLength, 1)
    }

    var body: some View {
        
        // MARK: Background
        ZStack {
            Theme.background
                .ignoresSafeArea()
            PageTintBackground(onPlanPage: false)

            // Scrolls only when the session doesn't fit — a small iPhone, a
            // large text size — so nothing is pushed off screen; the ✕ and the
            // exercise list are overlays pinned to the screen below.
            ScrollView {
                VStack {
                    // Exercise name header — moved to the top of the stack so the
                    // current exercise reads as a title above the timer and controls.
                    // Fixed-height so a 2-line name doesn't shift the content below.
                    Text({
                        // During a rest period the title reads "Pause" instead of the
                        // exercise name (only cardio/HIIT sessions ever rest).
                        if pauseActive {
                            return NSLocalizedString("Pause", comment: "Active workout: rest period title")
                        }
                        if let id = exerciseIDs[safe: currentExerciseIndex] {
                            return getExercise(for: id)?.displayName ?? NSLocalizedString("Exercise not found", comment: "Active workout: missing exercise")
                        }
                        // Workouts without an exercise list (e.g. generated runs)
                        // title the session itself instead of a missing exercise.
                        return workout.displayName
                    }())
                        .displayFont(.title2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        // 72 clears the close button pinned at the top-trailing
                        // corner below (44pt wide + 20pt trailing inset), applied
                        // symmetrically so the title stays optically centred. A long
                        // two-line name used to run underneath the xmark.
                        .padding(.horizontal, 72)


                    // Where in the session this is.
                    Text(exercisePositionText ?? " ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                        .opacity(exercisePositionText == nil ? 0 : 1)
                        .accessibilityHidden(exercisePositionText == nil)

                    // The watch couldn't be reached — not worn, or no Health
                    // access. The workout goes on here.
                    if let issue = workoutObserver.lastError {
                        WatchIssueNotice(message: issue,
                                         detail: NSLocalizedString("The workout keeps recording on this iPhone.",
                                                                   comment: "Active workout: the watch couldn't be reached")) {
                            withAnimation { workoutObserver.lastError = nil }
                        }
                        .accessibilityIdentifier("activeWorkout.watchIssue")
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.s)
                        .transition(.opacity)
                    }

                    // MARK: - TopBarView

                    Group {
                        if showsLogControls && currentExerciseIsRepBased {
                            // The reps are the big control below.
                            EmptyView()
                        } else if !pauseActive,
                           let reps = currentExerciseRepCount,
                           reps > 0 {
                            // Rep-based exercises don't decrement the timer — show the target
                            // rep count and let the user tap "Set done" below when finished.
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(reps)")
                                    .displayNumberFont(size: bigTimerSize)
                                    .monospacedDigit()
                                Text("reps")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(Text("\(reps) reps"))
                        } else if isOpenEnded {
                            // Counts up from the start, like the Lock Screen's
                            // clock, and stops while paused.
                            let start = workoutStartDate ?? .now
                            Text(timerInterval: start...start.addingTimeInterval(24 * 60 * 60),
                                 pauseTime: pausedAt,
                                 countsDown: false)
                                .displayNumberFont(size: bigTimerSize)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        } else {
                            Text("\(Int(pauseActive ? CGFloat(pauseTimeCounting) : timeRemaining))")
                                .displayNumberFont(size: bigTimerSize)
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: !pauseActive))
                                .animation(.snappy, value: pauseActive ? CGFloat(pauseTimeCounting) : timeRemaining)
                                .foregroundStyle(pauseActive ? Color.secondary : Color.primary)
                                .accessibilityLabel(pauseActive
                                    ? Text("Rest \(pauseTimeCounting) seconds")
                                    : Text("Remaining \(Int(timeRemaining)) seconds"))
                        }
                    }
                    .frame(height: showsLogControls && currentExerciseIsRepBased ? 0 : 70)
                    .animation(.easeInOut, value: pauseActive)
                    .animation(.easeInOut, value: showsTransportControl)

                    // The only local effect of a pause during a rep-based set is
                    // this label plus the disabled controls below: there is no
                    // ticking timer to visibly freeze. Reachable now mainly when
                    // the *watch* pauses mid-set, since the phone hides its own
                    // pause button there — see `showsTransportControl`.
                    if !workoutIsActive {
                        Text(NSLocalizedString("Paused", comment: "Active workout: paused indicator"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .textCase(.uppercase)
                            .transition(.opacity)
                    }

                    // Live "watch is running" indicator. The iOS local timer
                    // intentionally doesn't tick during rep-based exercises
                    // (reps are user-driven), so on a gym workout the big
                    // counter above stays static. This row mirrors the watch's
                    // HK-driven elapsed time and the streamed heart rate.
                    // Each cell appears independently — heart rate is no
                    // longer gated behind the elapsed-time push so a fast
                    // HR update isn't withheld while we wait for the first
                    // 3-second elapsed broadcast.
                    // A fixed-height slot, not a conditional insertion. Both inputs
                    // arrive mid-session — the first logged set produces
                    // `sessionVolumeText`, the first watch push a heart rate — and
                    // inserting the row shoved everything below it down, including
                    // the progress ring, which read as the ring's fill stuttering.
                    // Reserve the space once and cross-fade the contents.
                    ZStack {
                        if hasSessionMetrics {
                            HStack(spacing: 8) {
                                if workoutObserver.currentHeartRate > 0 {
                                    Label("\(Int(workoutObserver.currentHeartRate))",
                                          systemImage: "heart.fill")
                                        .foregroundStyle(Theme.danger)
                                }
                                if let sessionVolumeText {
                                    Label(sessionVolumeText, systemImage: "scalemass")
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .font(.footnote.monospacedDigit())
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .controlBackground()
                            .accessibilityElement(children: .combine)
                            .transition(.opacity)
                        }
                    }
                    .frame(height: 28)
                    .padding(.top, 4)
                    .animation(.easeInOut(duration: 0.2), value: hasSessionMetrics)

                    ZStack {
                        Group {
                            VStack {
                                ZStack {
                                    Circle()
                                        .stroke(Theme.surface, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                                        .frame(width: ringDiameter, height: ringDiameter)

                                    if !pauseActive {
                                        Circle()
                                            .trim(from: 0, to: ringProgress)
                                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                                            .rotationEffect(.degrees(-90))
                                            .animation(.easeInOut, value: ringProgress)
                                            .frame(width: ringDiameter, height: ringDiameter)
                                    } else {
                                        Circle()
                                            .trim(from: 0, to: pauseTime > 0 ? CGFloat(pauseTimeCounting) / CGFloat(pauseTime) : 1)
                                            .stroke(Color.secondary, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                                            .rotationEffect(.degrees(-90))
                                            .animation(.easeInOut, value: pauseTimeCounting)
                                            .frame(width: ringDiameter, height: ringDiameter)
                                    }

                                    // Fixed square frame anchors the symbol's
                                    // bounding box regardless of the source
                                    // asset's aspect ratio — the circle below
                                    // no longer shifts up/down between exercises.
                                    currentExerciseSymbol
                                        .frame(width: ringDiameter * 0.44,
                                               height: ringDiameter * 0.44)
                                }
                                .onReceive(timerPublisher, perform: { currentTime in
                                    // Track elapsed time precisely
                                    if let lastTick = lastTimerTick {
                                        let elapsedTime = currentTime.timeIntervalSince(lastTick)
                                        // Ticks arrive every 0.1 s; a longer gap means iOS
                                        // suspended the app (phone locked).
                                        if elapsedTime > 2 && workoutIsActive {
                                            catchUpMissedSeconds(Int(elapsedTime))
                                            lastTimerTick = currentTime
                                            return
                                        }
                                        accumulatedTime += CGFloat(elapsedTime)
                                    
                                        // Process logic approximately once per second
                                        if accumulatedTime >= 1.0 {
                                            shouldProcessLogic = true
                                            accumulatedTime = 0.0
                                        }
                                    }
                                    lastTimerTick = currentTime

                                    // After the catch-up above, which needs to know a
                                    // rest was still running while the phone was locked.
                                    if let restEnd, currentTime >= restEnd {
                                        endRest(finished: true)
                                    }

                                    // Skip if workout is not active
                                    guard workoutIsActive && shouldProcessLogic else {
                                        if !workoutIsActive {
                                            // Reset accumulated time when paused
                                            accumulatedTime = 0.0
                                            lastTimerTick = nil
                                        }
                                        shouldProcessLogic = false
                                        return
                                    }
                                    shouldProcessLogic = false
                                
                                    timerStep(broadcast: true)
                                })
                                .padding()

                                // MARK: - Live route map
                                // Small live map for outdoor distance workouts —
                                // read-only, fed by the same fixes the HealthKit
                                // route is built from.
                                if tracksRoute {
                                    if !runLocation.coordinates.isEmpty {
                                        Map(initialPosition: .userLocation(fallback: .automatic), interactionModes: []) {
                                            MapPolyline(coordinates: runLocation.coordinates)
                                                .stroke(Theme.accent, lineWidth: 4)
                                            UserAnnotation()
                                        }
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: theme.geometry.cardRadius, style: .continuous))
                                        .padding(.horizontal)
                                        .transition(.opacity)
                                    } else if runLocation.permissionDenied {
                                        Label(NSLocalizedString("Allow location access in Settings to record your route.",
                                                                comment: "Active workout: location permission hint"),
                                              systemImage: "location.slash")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    .onAppear(perform: {
                        // Outdoor run/ride/walk/hike: record the GPS route
                        // (asks for location permission on first use).
                        if tracksRoute {
                            runLocation.start()
                        }
                        workoutObserver.phoneSessionOwnsSave = true
                        // An offer an earlier summary never showed doesn't belong to this one.
                        RoutineUpdateOffer.clear()
                        Task { sessionBodyWeightKg = await BodyWeight.current() }

                        setCount = Int(workout.setLength)
                        currentSetIndex = 0

                        // Resume an interrupted session: restore the exercise/set
                        // position, logged sets, and original start time so duration
                        // and history stay correct. Otherwise start fresh.
                        if let snapshot = resumeSnapshot, snapshot.workoutID == workout.id {
                            currentExerciseIndex = min(snapshot.exerciseIndex, max(exerciseIDs.count - 1, 0))
                            currentSetIndex = snapshot.setIndex
                            setCount = snapshot.setCount
                            loggedWeights = snapshot.loggedWeights
                            loggedReps = snapshot.loggedReps
                            sessionPlans = snapshot.sessionPlans ?? [:]
                            skippedExerciseIDs = snapshot.skippedExerciseIDs ?? []
                            loggedDetails = snapshot.loggedDetails ?? [:]
                            exerciseNotes = snapshot.exerciseNotes ?? [:]
                            pauseIntervals = snapshot.pauseIntervals ?? []
                            // Closed while paused: it stayed paused until now,
                            // when the resumed session starts running again.
                            if let pausedAt = snapshot.pausedAt {
                                pauseIntervals.append(DateInterval(start: pausedAt, end: max(pausedAt, .now)))
                            }
                            if let completed = snapshot.completedSets {
                                completedSets = completed
                            } else if isStraightSets, let id = currentExerciseID {
                                // A snapshot from before per-exercise progress: the
                                // exercises before the current one were done.
                                for earlier in exerciseIDs.prefix(currentExerciseIndex) {
                                    completedSets[earlier] = plan(for: earlier).sets
                                }
                                completedSets[id] = snapshot.setIndex
                            }
                            workoutStartDate = snapshot.startDate
                        } else {
                            workoutStartDate = .now
                            // The last watch session's heart rate and calories would
                            // otherwise show at start and end up in this workout's record.
                            WatchConnectivityManager.shared.latestHealthMetrics = HealthMetrics()
                        }
                        // Seed the countdown from the (possibly resumed) current exercise.
                        timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
                        prefillWeightForCurrentExercise()

                        workoutObserver.currentWorkout?.workoutName = workout.displayName
                        workoutObserver.currentWorkout?.muscleGroup = workout.muscleGroup

                        workoutIsActive = true

                        // Persist immediately so a kill right after opening still
                        // leaves a resumable snapshot.
                        saveResumeSnapshot()

                        sendCurrentExerciseToWatch(currentExerciseIndex)

                        // Live Activities can only be requested from the
                        // foreground, which `onAppear` guarantees.
                        startLiveActivity()

                        // Only when it changes: assigning the same value still marks
                        // the record changed and exports it to iCloud again.
                        if workout.isNew { workout.isNew = false }
                    })
                    .onChange(of: currentExerciseIndex) {
                        prefillWeightForCurrentExercise()
                        workoutObserver.currentWorkout?.workoutName = workout.displayName
                        workoutObserver.currentWorkout?.muscleGroup = workout.muscleGroup

                        sendCurrentExerciseToWatch(currentExerciseIndex)
                        saveResumeSnapshot()
                        updateLiveActivity()
                    }
                    // Keep the resume snapshot current as progress is made, and
                    // flush it when the app leaves the foreground (the kill case).
                    .onChange(of: currentSetIndex) {
                        saveResumeSnapshot()
                        updateLiveActivity()
                    }
                    .onChange(of: loggedWeights) { saveResumeSnapshot() }
                    .onChange(of: loggedReps) { saveResumeSnapshot() }
                    // Rest start/end and pause are the other two moments the Lock
                    // Screen has to re-anchor its countdown on.
                    .onChange(of: pauseActive) { updateLiveActivity() }
                    .onChange(of: workoutIsActive) {
                        if workoutIsActive {
                            if let pausedAt {
                                pauseIntervals.append(DateInterval(start: pausedAt, end: max(pausedAt, .now)))
                            }
                            pausedAt = nil
                        } else {
                            pausedAt = .now
                        }
                        saveResumeSnapshot()
                        updateLiveActivity()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase != .active { saveResumeSnapshot() }
                        syncRestNotification(phase: phase)
                    }
                    .onChange(of: restEnd) {
                        updateLiveActivity()
                        // "Set done" on the Lock Screen starts a rest in the background.
                        syncRestNotification(phase: scenePhase)
                    }
                    .onChange(of: workoutObserver.isWorkoutActive) { oldValue, newValue in
                        // The watch ended the session: finish here, so the single
                        // saved record keeps the sets and weights logged on the phone.
                        if oldValue && !newValue && !isEnding {
                            endWorkout(save: !workoutObserver.lastWatchEndDiscarded)
                        } else {
                            workoutIsActive = newValue
                        }
                    }
                    .onChange(of: workoutObserver.isWorkoutPaused) { _, newValue in
                        // Mirror pause state pushed back from the watch / observer.
                        // Important: this only flips `workoutIsActive`, which gates
                        // the timer loop. `pauseActive` belongs to the inter-exercise
                        // rest state and must NOT be set here — doing so makes the
                        // big timer read `pauseTimeCounting` (0) and turns the ring
                        // blue as if the user were resting.
                        workoutIsActive = !newValue
                    }
                    // Skip / restart commands sent from the wrist. Reset to nil
                    // after handling so re-issuing the same command (skip twice
                    // in a row) still fires the second time.
                    .onReceive(WatchConnectivityManager.shared.$lastExerciseControl) { command in
                        guard let command else { return }
                        // `.onReceive` also fires on appear with whatever was left
                        // over from an earlier press; only act on a fresh one.
                        guard WatchConnectivityManager.shared.isExerciseControlFresh else {
                            WatchConnectivityManager.shared.lastExerciseControl = nil
                            return
                        }
                        switch command {
                        case .skip:
                            skipExercise(defaultTimeRemaining: defaultTimeRemaining)
                        case .restart:
                            timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
                            pauseActive = false
                            pauseTimeCounting = 0
                            accumulatedTime = 0
                            lastTimerTick = nil
                        }
                        WatchConnectivityManager.shared.lastExerciseControl = nil
                    }
                    // MARK: - CircularTimerView

                    // Straight-set progress ("Set 2 / 4") for strength workouts.
                    if isStraightSets && !pauseActive && currentExercise != nil {
                        // Clamped: back on a finished exercise, the next set is an extra one.
                        Text(allWorkDone
                             ? NSLocalizedString("All sets done", comment: "Active workout: every planned set is logged")
                             : String(format: NSLocalizedString("Set %d / %d", comment: "Active workout: current set of total"),
                                      min(currentSetIndex + 1, totalSets), totalSets))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: currentSetIndex)
                        setDots
                            .padding(.bottom, 4)
                    }

                    // Equipment chips — used to live in the outer ZStack and would
                    // overlap the exercise circle. Now positioned above the circle
                    // so the two never collide.
                    if let equipment = currentExercise?.equipment,
                       !equipment.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(equipment, id: \.self) { value in
                                Image(Equipment(rawValue: value)?.symbolName ?? "")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 26, height: 26)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.surface, in: Circle())
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // Play/pause is the only control in the main transport row — the old
                    // circular forward/backward buttons read as "skip this set" /
                    // "redo last rep" (standard media-transport iconography) when they
                    // actually jumped a whole exercise, which was confusing. The
                    // exercise-level jump is still available below as clearly labeled,
                    // secondary controls: skipping past an exercise (e.g. equipment
                    // unavailable) or recovering from a misclick.
                    //
                    // Hidden mid-set on a rep-based exercise — see
                    // `showsTransportControl`. "Set done" below is the primary
                    // action there, and this button sitting above it in the larger,
                    // prominent slot inverted that hierarchy.
                    if showsTransportControl {
                        WorkoutControlButton(
                            systemImage: workoutIsActive ? "pause.fill" : "play.fill",
                            accessibilityLabel: workoutIsActive
                                ? NSLocalizedString("Pause", comment: "Active workout: pause")
                                : NSLocalizedString("Play", comment: "Active workout: resume"),
                            size: 64,
                            prominent: true
                        ) {
                            togglePlayPause()
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }

                    if isResting && !pauseActive {
                        restBanner
                            .padding(.top, 8)
                            .transition(.opacity)
                    }

                    // Weight & reps logging — compact steppers the user sets before
                    // finishing the set; the values are recorded per set into the
                    // finished-workout history.
                    if (shouldRecordSet || isTimedStrengthSet) && !pauseActive {
                        VStack(spacing: Spacing.s) {
                            HStack(spacing: Spacing.m) {
                                if showsWeightInput {
                                    valueTile(
                                        title: currentExercise?.isBodyweight == true
                                            ? NSLocalizedString("Added weight", comment: "Active workout: title of the weight added to a bodyweight exercise")
                                            : NSLocalizedString("Weight", comment: "Active workout: type the set's weight, alert title"),
                                        value: currentWeightDisplay,
                                        accessibility: (currentExercise?.isBodyweight == true
                                                        ? NSLocalizedString("Added weight", comment: "Active workout: weight added to a bodyweight exercise, a11y")
                                                        : NSLocalizedString("Set weight", comment: "Active workout: weight stepper a11y")) + " \(currentWeightDisplay)",
                                        onDecrement: { adjustWeight(by: -1) },
                                        onIncrement: { adjustWeight(by: 1) },
                                        onTapValue: {
                                            let unit = SettingsManager.shared.weightUnit
                                            valueEntryPlaceholder = unit.displayNumber(kilograms: effectiveSetWeightKg) + " " + unit.abbreviation
                                            valueEntryText = ""
                                            showWeightEntry = true
                                        })
                                }
                                if isTimedStrengthSet {
                                    // How long to hold — set before the set starts.
                                    let seconds = currentSetSeconds ?? Int(timeRemaining)
                                    valueTile(
                                        title: NSLocalizedString("Hold", comment: "Active workout: title of a timed set's hold time"),
                                        value: ExercisePlan.holdText(seconds),
                                        accessibility: String(format: NSLocalizedString("Hold %d seconds", comment: "Active workout: hold time of a timed set, a11y"), seconds),
                                        onDecrement: { adjustHold(by: -5) },
                                        onIncrement: { adjustHold(by: 5) },
                                        onTapValue: {
                                            valueEntryPlaceholder = "\(seconds)"
                                            valueEntryText = ""
                                            showSecondsEntry = true
                                        })
                                    .disabled(timedSetRunning)
                                    .opacity(timedSetRunning ? 0.4 : 1)
                                    .accessibilityIdentifier("activeWorkout.hold")
                                }
                                if showsRepsInput {
                                    valueTile(
                                        title: NSLocalizedString("Reps", comment: "Active workout: type the set's reps, alert title"),
                                        value: "\(effectiveSetReps)",
                                        accessibility: String(format: NSLocalizedString("%d reps", comment: ""), effectiveSetReps),
                                        onDecrement: { adjustReps(by: -1) },
                                        onIncrement: { adjustReps(by: 1) },
                                        onTapValue: {
                                            valueEntryPlaceholder = "\(effectiveSetReps)"
                                            valueEntryText = ""
                                            showRepsEntry = true
                                        })
                                }
                            }

                            // Warm-up / drop set and reps in reserve, for rep-based
                            // strength sets.
                            if isStraightSets && currentExerciseIsRepBased {
                                setDetailControls
                            }

                            // Progression hint — what this exercise was done at last
                            // time. Opens the last few sessions.
                            if let hint = lastTimeHint {
                                Button {
                                    showLastSessions = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(hint)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text(NSLocalizedString("Shows your last sessions of this exercise", comment: "Active workout: last-time hint a11y")))
                            }
                            if let progressionHint, (currentExerciseID.flatMap { completedSets[$0] } ?? 0) == 0 {
                                Label(progressionHint, systemImage: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityIdentifier("activeWorkout.progression")
                            }
                            if let lastTimeNote {
                                Label(lastTimeNote, systemImage: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 24)
                            }

                            // Undoes the most recently logged set of *this* exercise
                            // so a mis-entered weight/reps can be corrected without
                            // losing the other sets already logged — unlike "Previous
                            // exercise" above, which restarts the whole exercise from
                            // its first set. Only offered mid-exercise (set > 1); the
                            // cross-exercise case is what "Previous exercise" is for.
                            //
                            // Kept in the layout and faded, for the same reason as the
                            // metrics row above: `canEditLastSet` flips the instant the
                            // first set is logged, and inserting the button there pushed
                            // the ring down mid-animation.
                            // The same slot offers a drop set for the exercise just
                            // finished, until this one has a set.
                            if !canEditLastSet, let offerID = dropSetOfferID, offerID != currentExerciseID,
                               let finished = getExercise(for: offerID) {
                                Button {
                                    addDropSet(to: offerID)
                                } label: {
                                    Label(String(format: NSLocalizedString("Drop set: %@", comment: "Active workout: add a drop set to the exercise just finished, e.g. 'Drop set: Bench Press'"),
                                                 finished.displayName),
                                          systemImage: "arrow.down.right")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                                .accessibilityIdentifier("activeWorkout.dropSetOffer")
                            } else {
                                Button {
                                    editLastSet()
                                } label: {
                                    Label(NSLocalizedString("Edit last set", comment: "Active workout: undo the most recently logged set"),
                                          systemImage: "pencil.circle")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                                .opacity(canEditLastSet ? 1 : 0)
                                .disabled(!canEditLastSet)
                                .accessibilityHidden(!canEditLastSet)
                                .animation(.easeInOut(duration: 0.2), value: canEditLastSet)
                            }
                        }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, 6)
                        // Keep the steppers consistent with the paused state —
                        // logging a set while the HealthKit session is stopped
                        // would record it outside the session's own timeline.
                        .disabled(!workoutIsActive)
                        .opacity(workoutIsActive ? 1 : 0.4)
                    }

                    // Single-tap "Set done" for rep-based exercises — completes the
                    // whole set at once (with the normal rest) rather than advancing
                    // per rep.
                    if (currentExerciseIsRepBased || isTimedStrengthSet || allWorkDone) && !pauseActive {
                        Button {
                            if allWorkDone && nextSetKind == .working {
                                Haptics.success()
                                endWorkout(recordsInProgressSet: false)
                            } else if isTimedStrengthSet && !timedSetRunning && nextSetKind == .working {
                                Haptics.start()
                                startTimedSet()
                            } else if isTimedStrengthSet {
                                // Held as long as wanted: log it now.
                                setHaptic()
                                advanceStraightSet(defaultTimeRemaining: defaultTimeRemaining)
                            } else {
                                setHaptic()
                                completeRepSet(defaultTimeRemaining: defaultTimeRemaining)
                            }
                        } label: {
                            Label(repSetButtonTitle, systemImage: repSetButtonSymbol)
                                .padding(.vertical, 2)
                        }
                        .accessibilityIdentifier("activeWorkout.primary")
                        .buttonStyle(.primaryAction)
                        .disabled(!workoutIsActive)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    }


                    if let upNextText {
                        Text(upNextText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, 6)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: upNextText)
                    }

                    // Nothing else ends an open-ended session. Works while paused
                    // too, e.g. after stopping at the end of a run.
                    if isOpenEnded {
                        Button {
                            Haptics.success()
                            endWorkout()
                        } label: {
                            Label(NSLocalizedString("Finish workout", comment: "Active workout: complete final set of final exercise"),
                                  systemImage: "flag.checkered")
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.primaryAction)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                    }

                    // An open-ended session has no exercises to move between.
                    if !isOpenEnded {
                        HStack(spacing: Spacing.l) {
                            Button {
                                Haptics.tap()
                                previousOrRestart(defaultTimeRemaining: defaultTimeRemaining)
                            } label: {
                                Label(currentExerciseIndex > 0
                                        ? NSLocalizedString("Previous exercise", comment: "Active workout: go to previous exercise")
                                        : NSLocalizedString("Restart exercise", comment: "Active workout: restart current exercise"),
                                      systemImage: "arrow.uturn.backward")
                                    .padding(.vertical, 6)
                            }

                            Button {
                                Haptics.tap()
                                skipExercise(defaultTimeRemaining: defaultTimeRemaining)
                            } label: {
                                Label(NSLocalizedString("Skip exercise", comment: "Active workout: skip current exercise"),
                                      systemImage: "arrow.uturn.forward")
                                    .padding(.vertical, 6)
                            }

                            if isStraightSets, currentExerciseID != nil {
                                let hasNote = !(currentExerciseID.flatMap { exerciseNotes[$0] } ?? "").isEmpty
                                Button {
                                    showNoteEditor = true
                                } label: {
                                    Image(systemName: hasNote ? "note.text" : "square.and.pencil")
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 4)
                                }
                                .accessibilityLabel(Text(NSLocalizedString("Note", comment: "Active workout: note for the current exercise")))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .labelStyle(.titleAndIcon)
                        .padding(.top, Spacing.m)
                    }

                    // Live set-count control — adjust total sets mid-session.
                    // Straight-set workouts read `totalSets` live; circuits keep
                    // their remaining-round counter in sync via `adjustSets`.
                    if !pauseActive && !isOpenEnded {
                        HStack(spacing: 8) {
                            Text(NSLocalizedString("Sets", comment: "Active workout: sets stepper label"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Button { adjustSets(by: -1) } label: {
                                Image(systemName: "minus.circle.fill").font(.title3)
                                    .accessibilityLabel(Text(NSLocalizedString("Fewer sets", comment: "Accessibility: remove a set")))
                            }
                            .buttonStyle(.plain)
                            Text("\(totalSets)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(minWidth: 20)
                            Button { adjustSets(by: 1) } label: {
                                Image(systemName: "plus.circle.fill").font(.title3)
                                    .accessibilityLabel(Text(NSLocalizedString("More sets", comment: "Accessibility: add a set")))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.bottom, Spacing.s)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(String(format: NSLocalizedString("%d sets", comment: "Active workout: sets a11y"), totalSets)))
                    }

                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = height
                    fitRing()
                }
                .frame(minHeight: viewportHeight, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                viewportHeight = height
                fitRing()
            }
        }
        // Pinned to the screen corner instead of being the first element in the
        // scrollable content stack above — on an exercise with enough content to
        // overflow a smaller screen, the button used to scroll along with
        // everything else and could end up sitting above the visible area.
        .overlay(alignment: .topTrailing) {
            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("End workout", comment: "Active workout: close button")))
            .padding(.trailing, 20)
            .padding(.top, 8)
            .confirmationDialog(NSLocalizedString("End workout?", comment: "Active workout: end dialog title"),
                                isPresented: $showEndConfirmation, titleVisibility: .visible) {
                Button(NSLocalizedString("End and save", comment: "Active workout: end dialog, save")) {
                    Haptics.success()
                    endWorkout()
                }
                Button(NSLocalizedString("End without saving", comment: "Active workout: end dialog, discard"), role: .destructive) {
                    Haptics.discard()
                    endWorkout(save: false)
                }
                Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
            }
        }
        // The session's exercise list — jump, reorder, swap, add.
        .overlay(alignment: .topLeading) {
            if !isOpenEnded {
                Button {
                    showOverview = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("Exercises", comment: "")))
                .accessibilityIdentifier("activeWorkout.overview")
                .padding(.leading, 20)
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showOverview) {
            SessionOverviewSheet(rows: overviewRows,
                                 onJump: jumpToExercise,
                                 onMove: moveExercises,
                                 onRemove: removeExercise,
                                 swapCandidates: swapCandidates,
                                 onSwap: swapExercise,
                                 onAdd: addExercise)
        }
        .sheet(isPresented: $showLastSessions) {
            if let id = currentExerciseID {
                LastSessionsSheet(exerciseName: currentExercise?.displayName ?? "",
                                  sessions: WorkoutStats.recentSessions(forExerciseID: id,
                                                                        in: WorkoutStats.snapshots(from: finishedWorkouts)),
                                  isBodyweight: currentExercise?.isBodyweight == true)
            }
        }
        .sheet(isPresented: $showPlates) {
            PlateCalculatorSheet(totalKg: effectiveSetWeightKg)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNoteEditor) {
            if let id = currentExerciseID {
                ExerciseNoteSheet(exerciseName: currentExercise?.displayName ?? "",
                                  previousNote: lastTimeNote,
                                  note: Binding(get: { exerciseNotes[id] ?? "" },
                                                set: { exerciseNotes[id] = $0 }))
            }
        }
        .alert(NSLocalizedString("Weight", comment: "Active workout: type the set's weight, alert title"), isPresented: $showWeightEntry) {
            TextField(valueEntryPlaceholder, text: $valueEntryText)
                .keyboardType(.decimalPad)
            Button(NSLocalizedString("Set", comment: "Active workout: apply the typed value")) { applyEnteredValue(weight: true) }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        }
        .alert(NSLocalizedString("Reps", comment: "Active workout: type the set's reps, alert title"), isPresented: $showRepsEntry) {
            TextField(valueEntryPlaceholder, text: $valueEntryText)
                .keyboardType(.numberPad)
            Button(NSLocalizedString("Set", comment: "Active workout: apply the typed value")) { applyEnteredValue(weight: false) }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        }
        .alert(NSLocalizedString("Seconds", comment: "Active workout: type the hold time of a timed set, alert title"), isPresented: $showSecondsEntry) {
            TextField(valueEntryPlaceholder, text: $valueEntryText)
                .keyboardType(.numberPad)
            Button(NSLocalizedString("Set", comment: "Active workout: apply the typed value")) {
                if let seconds = Int(valueEntryText.trimmingCharacters(in: .whitespaces)), seconds > 0 {
                    setHold(seconds)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        }
        .onChange(of: exerciseNotes) { saveResumeSnapshot() }
        .onChange(of: completedSets) { saveResumeSnapshot() }
    }

    /// A barbell exercise, where the plate calculator helps.
    private var usesBarbell: Bool {
        currentExercise?.equipment.contains(Equipment.barbells.rawValue) == true
    }

    /// "Warm-up" before the first working set, "Drop set" after one, the
    /// reps-in-reserve menu and, for a barbell, the plates.
    private var setDetailControls: some View {
        let done = currentExerciseID.flatMap { completedSets[$0] } ?? 0
        let kind: SetKind = done == 0 ? .warmup : .drop
        let isOn = nextSetKind == kind
        return HStack(spacing: 8) {
            Button {
                toggleSetKind(kind)
            } label: {
                Label(kind == .warmup
                        ? NSLocalizedString("Warm-up", comment: "Active workout: next set is a warm-up")
                        : NSLocalizedString("Drop set", comment: "Active workout: next set is a drop set"),
                      systemImage: kind == .warmup ? "flame" : "arrow.down.right")
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .foregroundStyle(isOn ? Theme.onAccent : Color.secondary)
                    .controlBackground(isOn ? .accent : .surface)
            }
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("activeWorkout.setKind")

            Menu {
                Picker(NSLocalizedString("Reps left", comment: "Active workout: reps in reserve menu"),
                       selection: $currentSetRIR) {
                    Text(NSLocalizedString("Not rated", comment: "Active workout: no reps-in-reserve rating")).tag(Int?.none)
                    ForEach(0...4, id: \.self) { value in
                        Text(value == 4
                             ? NSLocalizedString("4 or more", comment: "Active workout: 4+ reps in reserve")
                             : "\(value)").tag(Int?.some(value))
                    }
                }
            } label: {
                Label(currentSetRIR.map { String(format: NSLocalizedString("RIR %d", comment: "Set marker: reps in reserve"), $0) }
                        ?? NSLocalizedString("Reps left", comment: "Active workout: reps in reserve menu"),
                      systemImage: "gauge.with.dots.needle.50percent")
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .foregroundStyle(currentSetRIR != nil ? Theme.onAccent : Color.secondary)
                    .controlBackground(currentSetRIR != nil ? .accent : .surface)
            }
            .accessibilityIdentifier("activeWorkout.rir")
            .sensoryFeedback(.selection, trigger: currentSetRIR)

            if usesBarbell {
                Button {
                    showPlates = true
                } label: {
                    Label(NSLocalizedString("Plates", comment: "Active workout: open the plate calculator"),
                          systemImage: "circle.grid.2x1")
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .controlBackground()
                }
                .accessibilityIdentifier("activeWorkout.plates")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Toggle the workout's running state. Pauses or resumes both the local timer
    /// and (through the observer) the watch's HK session.
    /// Whether the Pause/Play control has anything to act on.
    ///
    /// A rep-based set has no countdown — the timer loop returns early for it,
    /// so the big number is a static rep target. Pausing one froze nothing and
    /// its only visible effect was greying out the steppers and "Set done",
    /// i.e. disabling exactly the controls the user wanted.
    ///
    /// It stays visible while resting or on a time-based exercise, where a real
    /// countdown is running, and whenever the session is *already* paused — the
    /// watch can pause mid-set (see the `isWorkoutPaused` observer below), and
    /// without that last clause there would be no way to resume from the phone.
    private var showsTransportControl: Bool {
        !currentExerciseIsRepBased || pauseActive || !workoutIsActive
    }

    private func togglePlayPause() {
        if workoutIsActive {
            workoutObserver.pauseWorkout()
            workoutIsActive = false
        } else {
            workoutObserver.resumeWorkout()
            workoutIsActive = true
        }
    }

    /// Media-style backward action: step to the previous exercise if there is
    /// one; otherwise restart the current exercise from the top. Always clears
    /// any inter-exercise rest and resumes the workout — same semantics as Skip
    /// but in the opposite direction.
    func previousOrRestart(defaultTimeRemaining: Double) {
        // Strength: the previous exercise keeps the sets already logged for
        // it, and picks up where it left off.
        if isStraightSets {
            if currentExerciseIndex > 0 {
                jumpToExercise(currentExerciseIndex - 1)
            } else {
                timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
                accumulatedTime = 0
                lastTimerTick = nil
            }
            if workoutObserver.isWorkoutPaused {
                workoutObserver.resumeWorkout()
            }
            workoutIsActive = true
            return
        }
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
        }
        // Restart the exercise's sets from the top.
        currentSetIndex = 0
        // (If already on the first exercise, fall through — same effect as Restart.)
        pauseActive = false
        pauseTimeCounting = 0
        timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
        accumulatedTime = 0
        lastTimerTick = nil
        if workoutObserver.isWorkoutPaused {
            workoutObserver.resumeWorkout()
        }
        workoutIsActive = true
    }

    /// Completes the current rep-based set in a single tap. Cardio/HIIT sessions
    /// enter the usual rest countdown; every other workout advances straight to
    /// the next exercise/set (or ends), with no rest.
    /// One second of the workout state machine: count down, start/finish
    /// rests, advance exercises and sets, end the workout. Returns false when
    /// it can't progress on its own (a rep-based set waiting for the user, or
    /// the workout ended).
    @discardableResult
    private func timerStep(broadcast: Bool) -> Bool {
        guard !isEnding else { return false }
        // Nothing to count down; only the user ends an open-ended session.
        if isOpenEnded { return false }
        let workoutUebArrCount = exerciseCount

        // Rep-based exercises don't auto-advance — the user taps
        // the forward button when they finish the set. Skip all
        // timer logic while a rep exercise is the active one
        // and we're not currently resting between exercises.
        if currentExerciseIsRepBased && !pauseActive {
            return false
        }

        // Everything's done: only "Finish workout" is left.
        if allWorkDone {
            return false
        }

        // A timed strength set waits for "Start set".
        if isTimedStrengthSet && !timedSetRunning {
            return true
        }

        // A rest between straight sets counts down on its own clock.
        if isResting && isStraightSets {
            return true
        }

        // Case 1: Workout is active and time remaining
        if timeRemaining >= 1 && !pauseActive {
            timeRemaining -= 1
            
            // Update watch data (Note: these properties don't exist in your WorkoutState)
            // You'll need to use WorkoutMetadata instead
            let metadata = WorkoutMetadata(
                workoutName: workout.displayName,
                exerciseName: currentExercise?.displayName ?? "",
                exerciseDuration: timeRemaining,
                muscleGroup: workout.muscleGroup
            )
            // updateWorkoutMetadata already broadcasts
            // to the watch (throttled inside the
            // observer). The previous extra
            // sendWorkoutDataToWatch call was doubling
            // the WCSession traffic for no reason.
            if broadcast {
                workoutObserver.updateWorkoutMetadata(metadata)
            }
            return true
        }
        
        // Straight sets (strength): on time-up, log the set and
        // advance immediately with no rest — all sets of one
        // exercise before the next. Runs ahead of the cardio cases.
        if timeRemaining < 1 && !pauseActive && isStraightSets {
            if broadcast { setHaptic() }
            advanceStraightSet(defaultTimeRemaining: defaultTimeRemaining)
            appLog("Straight set advance")
            return true
        }

        // Case 2 (cardio/HIIT): Time up, more exercises → rest, then next.
        if timeRemaining < 1 && currentExerciseIndex < (workoutUebArrCount - 1) && !pauseActive {
            if broadcast { Haptics.setDone() }
            recordCurrentSet()
            pauseActive = true
            // Mirror the rest period to the watch (blue rest countdown).
            if SettingsManager.shared.appleWatchUsage && pauseTime > 0 {
                workoutObserver.updateRestState(isResting: true, remaining: Double(pauseTime))
            }
            appLog("Pause, new Exercise afterwards")
            return true
        }

        // Case 3 (cardio/HIIT): Time up, more rounds → rest, then next set.
        // `setCount` counts the remaining rounds including the current one,
        // so the last round is `setCount == 1` (same as `skipExercise`).
        if timeRemaining < 1 && setCount > 1 && !pauseActive {
            if broadcast { Haptics.setDone() }
            recordCurrentSet()
            pauseActive = true
            if SettingsManager.shared.appleWatchUsage && pauseTime > 0 {
                workoutObserver.updateRestState(isResting: true, remaining: Double(pauseTime))
            }
            appLog("Pause Counter, next Set")
            return true
        }
        
        // Case 4: During pause
        if pauseTimeCounting < pauseTime && pauseActive {
            pauseTimeCounting += 1
            appLog("+= 1 pause")
            return true
        }
        
        // Case 5: End of pause, new exercise
        if currentExerciseIndex < (workoutUebArrCount - 1) && pauseActive && pauseTime == pauseTimeCounting {
            if broadcast { Haptics.restOver() }
            pauseActive = false
            
            guard currentExerciseIndex + 1 < workoutUebArrCount else { return false }
            currentExerciseIndex += 1
            timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
            pauseTimeCounting = 0
            appLog("next Exercise")
            return true
        }
        
        // Case 6: End of pause, new set
        if setCount > 1 && pauseActive && pauseTime == pauseTimeCounting {
            if broadcast { Haptics.restOver() }
            pauseActive = false
            setCount -= 1
            guard workoutUebArrCount > 0 else { return false }
            currentExerciseIndex = 0
            timeRemaining = CGFloat(workSeconds(at: 0, fallback: defaultTimeRemaining))
            pauseTimeCounting = 0
            // Clear the watch rest state + seed the next countdown.
            // `onChange(currentExerciseIndex)` won't fire for a
            // single-exercise workout (index stays 0), so push explicitly.
            sendCurrentExerciseToWatch(0)
            appLog("next Set")
            return true
        }
        
        // Case 7: End of workout
        if timeRemaining < 1 && currentExerciseIndex >= (workoutUebArrCount - 1) && setCount <= 1 {
            if broadcast { Haptics.success() }
            timerPublisher.upstream.connect().cancel()
            appLog("Congrats!")
            endWorkout()
            return false
        }
        
        appLog("Unhandled timer state")
        return false
    }

    /// iOS suspends the app while the phone is locked, so no timer ticks
    /// arrive, while the Live Activity keeps counting the current phase down
    /// to its end date. On return, count the missed seconds off the current
    /// work or rest phase so the app agrees with the Lock Screen.
    ///
    /// Deliberately stops at the phase boundary, like the Lock Screen does:
    /// replaying further would advance exercises and log sets the user may
    /// not have done while the phone was locked. The next regular tick then
    /// performs the transition.
    ///
    /// Driven by the gap between timer ticks, not by scene phase: during
    /// outdoor workouts background location keeps the app (and its timer)
    /// running, so there is no gap and nothing is counted twice.
    private func catchUpMissedSeconds(_ missed: Int) {
        guard !isEnding, missed > 0 else { return }
        if pauseActive {
            let step = min(missed, max(pauseTime - pauseTimeCounting, 0))
            pauseTimeCounting += step
        } else if !currentExerciseIsRepBased && !(isStraightSets && isResting)
                    && !(isTimedStrengthSet && !timedSetRunning) && !allWorkDone {
            // A timed strength set doesn't count down during the rest before
            // it (see `timerStep`), so a rest that ran out while locked only
            // ends here; the set starts on the next tick.
            timeRemaining -= CGFloat(min(missed, Int(timeRemaining)))
        }
        accumulatedTime = 0
        updateLiveActivity()
    }

    func completeRepSet(defaultTimeRemaining: Double) {
        guard currentExerciseIsRepBased, !pauseActive, !(allWorkDone && nextSetKind == .working) else { return }

        if isCardioOrHIIT {
            recordCurrentSet()
            timeRemaining = 0
            pauseActive = true
            pauseTimeCounting = 0
            accumulatedTime = 0
            lastTimerTick = nil
            if SettingsManager.shared.appleWatchUsage && pauseTime > 0 {
                workoutObserver.updateRestState(isResting: true, remaining: Double(pauseTime))
            }
            return
        }

        // Non-cardio (straight sets): no rest. Log the set and advance straight
        // to the next set / exercise (or end). advanceStraightSet handles both the
        // recording and the terminal case.
        timeRemaining = 0
        advanceStraightSet(defaultTimeRemaining: defaultTimeRemaining)
    }

    /// Jump straight to the next exercise. If we're on the last one, end the workout.
    /// Mirrors the timer's "Case 5: end of pause, new exercise" branch but bypasses
    /// the inter-exercise rest period.
    func skipExercise(defaultTimeRemaining: Double) {
        let totalExercises = exerciseCount
        guard totalExercises > 0 else { return }

        // Resets per-exercise timer/UI state so the next exercise starts immediately.
        func startFresh() {
            pauseActive = false
            pauseTimeCounting = 0
            timeRemaining = CGFloat(workSeconds(at: currentExerciseIndex, fallback: defaultTimeRemaining))
            accumulatedTime = 0
            lastTimerTick = nil
        }

        if isStraightSets {
            // Skip abandons the rest of the current exercise → the next one
            // that isn't finished. The set on screen wasn't done, so nothing
            // is logged for it.
            guard let id = currentExerciseID else {
                endWorkout(recordsInProgressSet: false)
                return
            }
            skippedExerciseIDs.insert(id)
            switch StraightSetSequencer.next(after: currentExerciseIndex, entries: sequencerEntries,
                                             done: completedSets, skipped: skippedExerciseIDs) {
            case .move(let index):
                moveToExercise(index, defaultTimeRemaining: defaultTimeRemaining)
            case .stay, .finish:
                endWorkout(recordsInProgressSet: false)
            }
            return
        }

        // Cardio/HIIT circuit skip.
        if currentExerciseIndex >= totalExercises - 1 {
            if setCount > 1 {
                if !pauseActive { recordCurrentSet() }
                setCount -= 1
                currentExerciseIndex = 0
                startFresh()
            } else {
                endWorkout()   // records the final set itself
            }
        } else {
            if !pauseActive { recordCurrentSet() }
            currentExerciseIndex += 1
            startFresh()
        }
    }

    /// Live-edit the current exercise's sets (strength) or the rounds
    /// (circuit), for this session only — the saved workout keeps its own.
    /// Never drops below the set the user is already on.
    private func adjustSets(by delta: Int) {
        if isStraightSets {
            guard let id = currentExerciseID else { return }
            var plan = plan(for: id)
            // Not below the set the user is on — or, back on a finished
            // exercise, below the sets already done.
            let completed = completedSets[id] ?? 0
            let lowerBound = max(completed < plan.sets ? completed + 1 : completed, 1)
            let new = min(10, max(lowerBound, plan.sets + delta))
            guard new != plan.sets else { return }
            plan.sets = new
            sessionPlans[id] = plan
        } else {
            let current = totalSets
            let new = min(8, max(1, current + delta))
            guard new != current else { return }
            sessionRounds = new
            setCount = max(1, setCount + (new - current))
        }
        Haptics.tap()
        saveResumeSnapshot()
        updateLiveActivity()
    }

    /// Persist current progress so the workout can be resumed after a
    /// background/kill. No-op before the session has actually started.
    private func saveResumeSnapshot() {
        guard !isEnding, let startDate = workoutStartDate else { return }
        SettingsManager.shared.resumeSnapshot = ResumeSnapshot(
            workoutID: workout.id,
            workoutName: workout.displayName,
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex,
            setCount: setCount,
            startDate: startDate,
            loggedWeights: loggedWeights,
            loggedReps: loggedReps,
            exerciseIDs: exerciseIDs,
            sessionPlans: sessionPlans,
            completedSets: completedSets,
            skippedExerciseIDs: skippedExerciseIDs,
            loggedDetails: loggedDetails,
            exerciseNotes: exerciseNotes,
            pauseIntervals: pauseIntervals,
            pausedAt: pausedAt
        )
    }

    /// Ends the session. `save: false` (X → "End without saving") skips the
    /// history entry, the plan progress and the phone-side Health workout/route.
    /// `recordsInProgressSet: false` when the set on screen was already
    /// recorded (the last set) or wasn't done (a skip).
    func endWorkout(save: Bool = true, recordsInProgressSet: Bool = true) {
        // Runs once. The timer keeps ticking until the dismissal finishes, and
        // on the last set its next step ended the workout again — saving a
        // second history entry when no watch session flipped
        // `workoutIsActive` off in between.
        guard !isEnding else { return }
        // Must be set before anything below mutates loggedWeights/loggedReps —
        // see the doc comment on `isEnding`.
        isEnding = true
        Self.lastEndSaved = save
        workoutObserver.phoneSessionOwnsSave = false
        // A watch problem belonged to this session.
        workoutObserver.lastError = nil

        // Finishing (or the X button) ends the workout, so there's nothing left
        // to resume — clear the persisted snapshot, and take the Lock Screen
        // card down with it.
        SettingsManager.shared.resumeSnapshot = nil
        WorkoutLiveSession.shared.clear()
        WorkoutLiveActivityController.shared.end()
        RestNotification.cancel()

        // Log the final in-progress set (Case 7 / manual end reach here without a
        // trailing rest). Guarded so ending during a rest period never re-logs.
        if save && !pauseActive && recordsInProgressSet {
            recordCurrentSet()
        }

        if workoutStartDate?.timeIntervalSinceNow ?? 2 < 1 {
            appLog("Short Workout")
        }

        // Read before ending: the watch has reported a running session.
        let watchRecorded = workoutObserver.watchElapsedTime > 0
        if workoutObserver.isWorkoutActive {
            workoutObserver.endWorkout(discard: !save)
        }

        // Save the GPS route to HealthKit. Attaches to the watch's workout
        // when one was recorded, otherwise writes a phone-side HKWorkout.
        // Runs detached, so dismissing the view right after is fine.
        let end = Date.now
        var healthWorkoutHandled = watchRecorded   // the watch writes its own
        if tracksRoute {
            if save, let activityType = HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) {
                let routeSaved = runLocation.finish(activityType: activityType,
                                                    start: workoutStartDate ?? end,
                                                    end: end,
                                                    watchRecorded: watchRecorded)
                healthWorkoutHandled = healthWorkoutHandled || routeSaved
            } else {
                runLocation.discard()
            }
        }

        if save {
            let pauses = sessionPauses(until: end)
            let estimatedEnergy = watchRecorded ? nil : phoneEnergyEstimate(until: end, pauses: pauses)
            createFinishedWorkout(watchRecorded: watchRecorded, estimatedEnergy: estimatedEnergy)
            offerRoutineUpdate()

            // Phone-only session: write it to Apple Health ourselves.
            if !healthWorkoutHandled, let start = workoutStartDate {
                PhoneWorkoutHealthWriter.save(
                    activityType: HKWorkoutActivityType(rawValue: UInt(workout.workoutActivityType)) ?? .other,
                    locationType: HKWorkoutSessionLocationType(rawValue: workout.workoutSessionLocation) ?? .unknown,
                    start: start,
                    end: end,
                    pauses: pauses,
                    energyKcal: estimatedEnergy
                )
            }
        }

        dismiss()
    }

    /// The session's pauses up to `end`, including one still running.
    private func sessionPauses(until end: Date) -> [DateInterval] {
        guard let pausedAt, pausedAt < end else { return pauseIntervals }
        return pauseIntervals + [DateInterval(start: pausedAt, end: end)]
    }

    /// Estimated active energy for a phone-only session, from the exercises'
    /// catalog burn rates over the unpaused time (see
    /// `PhoneWorkoutHealthWriter.estimatedEnergy`).
    private func phoneEnergyEstimate(until end: Date, pauses: [DateInterval]) -> Double? {
        guard let start = workoutStartDate else { return nil }
        let rates = sessionExercises.compactMap(\.caloriesPerSecond)
        let active = PhoneWorkoutHealthWriter.activeDuration(start: start, end: end, pauses: pauses)
        return PhoneWorkoutHealthWriter.estimatedEnergy(caloriesPerSecond: rates, duration: active)
    }

    //MARK: createFinishedWorkout()
    func createFinishedWorkout(watchRecorded: Bool, estimatedEnergy: Double?) {
        // Started from a plan's page: that plan counts it. Otherwise it still
        // counts toward any of the user's plans whose next workout this is
        // (same rule as a plan workout finished on the watch).
        let creditedPlans: [Plan]
        if let plan {
            plan.finishedWorkoutsSequence.append(workout.id)
            creditedPlans = [plan]
        } else {
            let plans = (try? modelContext.fetch(FetchDescriptor<Plan>())) ?? []
            let existingIDs = Set(((try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []).map(\.id))
            creditedPlans = Plan.recordCompletion(ofWorkoutID: workout.id, in: plans, existingIDs: existingIDs)
        }

        // Pull live metrics from the watch if it recorded this session; without
        // one they're left over from an earlier watch workout.
        let liveMetrics = WatchConnectivityManager.shared.latestHealthMetrics
        let calories = watchRecorded
            ? liveMetrics.activeCalories ?? liveMetrics.totalCalories
            : estimatedEnergy

        // Carry the actual workout's properties through to the finished record.
        // The previous version hardcoded zeros for muscleGroup / workoutLocation /
        // workoutType, which made the summary view render "Unknown" / "Other"
        // for every workout regardless of what was performed.
        let finishedWorkout = FinishedWorkout(
            endDate: .now,
            name: workout.displayName.isEmpty
                ? (workoutObserver.currentWorkout?.workoutName ?? NSLocalizedString("Unnamed workout", comment: "Finished workout: missing name fallback"))
                : workout.displayName,
            startDate: workoutStartDate ?? .now,
            muscleGroup: workout.muscleGroup,
            workoutLocation: workout.workoutSessionLocation,
            workoutType: workout.workoutActivityType,
            caloriesBurned: calories,
            additionalData: .none,
            exercisesSequenceID: exerciseIDs
        )

        // Set only the inverse side once — SwiftData will fill in the
        // `exercise.finishedWorkouts` automatically. Appending on both sides
        // previously risked double-inserts.
        // From the ordered list, so the entry keeps its exercises even when the
        // relationship hadn't arrived from iCloud yet.
        let exercises = sessionExercises
        if !exercises.isEmpty {
            finishedWorkout.exercises = exercises
        }

        // Persist the per-set weights and reps logged during the session.
        finishedWorkout.setWeights = loggedWeights
        finishedWorkout.setReps = loggedReps
        let notes = exerciseNotes
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        let log = sessionLog(notes: notes)
        if log != SessionLog() {
            finishedWorkout.loggingDetails = log
        }
        finishedWorkout.predictedDifficulty = workout.predictedDifficulty

        modelContext.insert(finishedWorkout)
        PlanCredit.record(finishedWorkoutID: finishedWorkout.id, workoutID: workout.id, plans: creditedPlans)

        do {
            try modelContext.save()
            // This session may have just met a weekly goal — drop the pending
            // nudge rather than making the user wait for the next foreground.
            Task { await GoalReminderScheduler.shared.refresh(context: modelContext) }
            // A plan may have moved on to its next workout.
            if !creditedPlans.isEmpty {
                WatchConnectivityManager.shared.sendWorkoutLibrary(context: modelContext)
            }
        } catch {
            appLog("Error saving modelContext: \(error)")
        }
    }
    
    /// What was logged beyond weights and reps. The body weight only comes
    /// along when a bodyweight exercise was logged, which is all it's for.
    private func sessionLog(notes: [String: String]) -> SessionLog {
        var log = SessionLog(setDetails: loggedDetails, exerciseNotes: notes)
        if let sessionBodyWeightKg {
            let bodyweightIDs = Set(loggedReps.keys.filter { getExercise(for: $0)?.isBodyweight == true })
            if !bodyweightIDs.isEmpty {
                log.bodyWeightKg = sessionBodyWeightKg
                log.bodyweightExerciseIDs = bodyweightIDs
            }
        }
        return log
    }

    /// Exercises swapped, added, removed or reordered, or sets changed: the
    /// summary offers to keep that for next time.
    private func offerRoutineUpdate() {
        let savedIDs = workout.exercisesSequenceID
        var savedPlans: [String: ExercisePlan] = [:]
        for id in Set(savedIDs + exerciseIDs) {
            if let exercise = getExercise(for: id) { savedPlans[id] = workout.plan(for: exercise) }
        }
        if let changes = RoutineChanges.detect(savedIDs: savedIDs, savedPlans: savedPlans,
                                               sessionIDs: exerciseIDs, sessionPlans: sessionPlans) {
            RoutineUpdateOffer.offer(changes, forWorkoutID: workout.id)
        }
    }

    /// Work seconds for the exercise at `index`: a time-based exercise's own
    /// duration (seconds) when set, otherwise the workout-derived slice. Rep-based
    /// exercises don't use the countdown, so `fallback` is fine for them.
    private func workSeconds(at index: Int, fallback: Double) -> Double {
        guard let id = exerciseIDs[safe: index], plan(for: id).reps == 0 else { return fallback }
        // A strength workout's hold: what the stepper says for the current
        // exercise, else its plan — never the workout-length slice.
        if timedSetsStartOnTap {
            if index == currentExerciseIndex, let currentSetSeconds { return Double(currentSetSeconds) }
            return Double(plannedSeconds(for: id))
        }
        guard let seconds = getExercise(for: id)?.duration, seconds > 0 else { return fallback }
        return seconds
    }

    /// The hold a timed exercise starts from: a change made this session or
    /// the workout's plan, else last time's hold, else the exercise's own length.
    private func plannedSeconds(for id: String) -> Int {
        if let seconds = plan(for: id).seconds { return seconds }
        if let held = previousSession(forExerciseID: id)?.sets.last?.detail.seconds, held > 0 { return held }
        return getExercise(for: id).map(ExercisePlan.defaultHoldSeconds(for:)) ?? 45
    }

    /// The countdown the watch shows for the exercise at `index`: the phone's
    /// own work seconds, or 0 where the phone doesn't count down (a rep-based
    /// exercise or an open-ended session). With 0 the watch shows no countdown.
    private func watchCountdownSeconds(at index: Int) -> Double {
        if isOpenEnded { return 0 }
        if let id = exerciseIDs[safe: index], plan(for: id).reps > 0 { return 0 }
        // A timed strength set that hasn't started yet.
        if timedSetsStartOnTap && index == currentExerciseIndex && !timedSetRunning { return 0 }
        return workSeconds(at: index, fallback: defaultTimeRemaining)
    }

    // MARK: - Live Activity

    /// Snapshot of the session for the Lock Screen / Dynamic Island.
    ///
    /// Countdowns are published as an *anchored end date* rather than a
    /// remaining duration: `timeRemaining` is driven by `Timer.publish`, which
    /// stops while the app is backgrounded — precisely when the Live Activity
    /// is being looked at. An end date lets `Text(timerInterval:)` keep
    /// counting down on its own.
    private func liveActivityState() -> WorkoutActivityAttributes.ContentState {
        let nextName = exerciseIDs[safe: currentExerciseIndex + 1]
            .flatMap { getExercise(for: $0)?.displayName }

        let phaseEnd: Date?
        if pauseActive {
            phaseEnd = Date().addingTimeInterval(Double(max(pauseTime - pauseTimeCounting, 0)))
        } else if let restEnd {
            phaseEnd = restEnd
        } else if currentExerciseIsRepBased || isOpenEnded || (isTimedStrengthSet && !timedSetRunning) || allWorkDone {
            // Rep-based work has no countdown — the user sets the pace. An
            // open-ended session has none at all.
            phaseEnd = nil
        } else {
            phaseEnd = Date().addingTimeInterval(Double(max(timeRemaining, 0)))
        }

        return WorkoutActivityAttributes.ContentState(
            currentExerciseName: currentExercise?.displayName
                ?? NSLocalizedString("Workout in progress", comment: "Resume banner: fallback title"),
            nextExerciseName: nextName,
            exerciseIndex: currentExerciseIndex,
            totalExercises: max(exerciseCount, 1),
            setIndex: currentSetIndex,
            totalSets: totalSets,
            isResting: pauseActive || isResting,
            isPaused: !workoutIsActive,
            pausedAt: workoutIsActive ? nil : Date(),
            phaseEndDate: phaseEnd,
            canCompleteSet: currentExerciseIsRepBased && !pauseActive && workoutIsActive && !allWorkDone,
            loggedSetCount: loggedReps.values.reduce(0) { $0 + $1.count },
            symbolName: activitySymbolName)
    }

    /// Installs the Lock Screen button actions and opens the Live Activity.
    /// The closures are what let an intent reach this view's `@State`.
    private func startLiveActivity() {
        WorkoutLiveSession.shared.onCompleteSet = {
            completeRepSet(defaultTimeRemaining: defaultTimeRemaining)
        }
        WorkoutLiveSession.shared.onSkipExercise = {
            skipExercise(defaultTimeRemaining: defaultTimeRemaining)
        }
        WorkoutLiveActivityController.shared.start(
            workoutName: workout.displayName,
            startDate: workoutStartDate ?? .now,
            state: liveActivityState())
    }

    private func updateLiveActivity() {
        WorkoutLiveActivityController.shared.update(liveActivityState())
    }

    func getExercise(for id: String) -> Exercise? {
        for exercise in exercises {
            if exercise.id == id {
                return exercise
            }
        }
        return nil
    }

}
/*
#Preview {
    ActiveWorkoutView(workout: Workout.samples[0])
}
*/
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Watch issue

/// A watch problem, shown in place rather than as an alert: an alert
/// presented from the screen under the workout dismissed the workout to show
/// itself.
struct WatchIssueNotice: View {
    let message: String
    var detail: String?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "applewatch.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("Dismiss", comment: "Close a notice")))
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Workout Control Button

/// A circular control in the workout's playback bar. `prominent` is the
/// larger accent-filled play/pause button; the others sit on the surface color.
struct WorkoutControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let size: CGFloat
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(prominent ? Theme.onAccent : Color.primary)
                .frame(width: size, height: size)
                .background(prominent ? AnyShapeStyle(Theme.accentFillGradient) : AnyShapeStyle(Theme.surface), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

extension UIScreen {
    /// Non-deprecated replacement for `UIScreen.main`, which was deprecated in iOS 26.
    /// Resolves the screen from the app's currently-connected window scene so that
    /// screen-relative layout keeps working without the deprecation warning.
    @MainActor
    static var activeBounds: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 393, height: 852)
    }
}
