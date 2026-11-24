//
//  PlanPreview.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 22.02.24.
//

import SwiftUI
import SwiftData
import HealthKit

struct PlanPreview: View {
    
    @Query var workouts: [Workout]
    
    @Bindable var plan: Plan
    
    @State private var workoutID: String = ""
    @State private var nextWorkout: Workout = Workout(id: "", infoText: "", isUserGenerated: false, muscleGroup: 100, setLength: 3.0, straightSets: false, difficultyInt: 2, name: "", duration: 0, exercisesSequenceID: [], finishedExercisesSequence: [], plan: [], workoutActivityType: Int(HKWorkoutActivityType.other.rawValue), workoutSessionLocation: HKWorkoutSessionLocationType.unknown.rawValue)
    
    @EnvironmentObject var iOSWorkoutObserver: iOSWorkoutObserver
    @EnvironmentObject var syncManager: WorkoutSyncManager
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext
    
    @State private var showEditPlan = false
    @State private var showActiveWorkoutView = false
    @State private var isSummaryPresendet = false
    @State private var showPlanCompleteAlert = false
    @State private var showNextReminderSheet = false
    
    @State private var setLength: Double = 3.0
    
    @State private var progress: Double = 0.5
    
    var weekdays = [NSLocalizedString("Sunday", comment: "Sunday, weekday"), NSLocalizedString("Monday", comment: "Monday, weekday"), NSLocalizedString("Tuesday", comment: "Tuesday, weekday"), NSLocalizedString("Wednesday", comment: "Wednesday, weekday"), NSLocalizedString("Thursday", comment: "Thursday, weekday"), NSLocalizedString("Friday", comment: "Friday, weekday"), NSLocalizedString("Saturday", comment: "Saturday, weekday")]
    
    /// The plan's workouts that still exist, in order, each with its state.
    /// A workout can be in the plan more than once, so the state is per slot.
    var workoutsInPlan: [(workout: Workout, state: PlanWorkoutRowState)] {
        let done = plan.completedSlots
        let next = plan.firstIncompleteSlot(existingIDs: existingWorkoutIDs)
        return plan.workoutsSequenceIDs.enumerated().compactMap { slot, workoutID in
            guard let workout = workouts.first(where: { $0.id == workoutID }) else { return nil }
            let state: PlanWorkoutRowState = done[slot] ? .completed : slot == next ? .current : .upcoming
            return (workout, state)
        }
    }

    private var existingWorkoutIDs: Set<String> { Set(workouts.map(\.id)) }
    
    private var difficultySymbol: String {
        switch plan.difficultyInt {
        case 1:
            return "gauge.with.dots.needle.0percent"
        case 2:
            return "gauge.with.dots.needle.50percent"
        case 3:
            return "gauge.with.dots.needle.100percent"
        default:
            return "gauge.with.dots.needle.50percent"
        }
    }
    
    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Chip(title: plan.displayDifficulty, systemImage: difficultySymbol)
                            Chip(title: WorkoutCategory.getCategoryName(from: plan.muscleGroup),
                                 systemImage: WorkoutCategory.getSymbolName(from: plan.muscleGroup))
                            Chip(title: PlanGoal.getGoalName(from: plan.goal), systemImage: "flag.pattern.checkered")
                        }
                        Spacer()
                        if !plan.workoutsSequenceIDs.isEmpty {
                            CircularProgressView(progress: Double(plan.finishedWorkoutsSequence.count), total: Double(plan.workoutsSequenceIDs.count))
                        }
                    }
                    .padding()

                    Text(plan.displayInfoText)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    HStack {
                        if formatInterval(plan.interval, intervalType: plan.intervalType) != "" {
                            Text("Reminder: \(formatInterval(plan.interval, intervalType: plan.intervalType))")
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Workouts")
                                .displayFont(.title3)
                            Spacer()
                            Text("\(plan.finishedWorkoutsSequence.count)/\(plan.workoutsSequenceIDs.count)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top)

                        let rows = workoutsInPlan
                        if !rows.isEmpty {
                            LazyVStack(spacing: 10) {
                                // By position: a workout can be in the plan more than once.
                                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                    NavigationLink {
                                        WorkoutPreviewiOS(workout: row.workout, canStartWorkout: false)
                                    } label: {
                                        PlanWorkoutTimelineRow(
                                            workout: row.workout,
                                            position: index + 1,
                                            totalCount: rows.count,
                                            state: row.state,
                                            isLast: index == rows.count - 1
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        } else {
                            Text("No workouts in this Plan")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }

                    Button {
                        showEditPlan.toggle()
                    } label: {
                        Text("Edit Plan")
                    }
                    .buttonStyle(.secondaryAction)
                    .padding()
                }
            }
            // A bar, like a workout's Start: the list scrolls under it.
            .safeAreaBar(edge: .bottom) {
                if !plan.workoutsSequenceIDs.isEmpty {
                    Button {
                        startNextWorkout()
                    } label: {
                        Label(NSLocalizedString("Start next workout", comment: "Plan: start the plan's next workout"), systemImage: "play.fill")
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("planPreview.start")
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .pageTint(onPlanPage: true)
            .navigationTitle(plan.displayName)
            .onAppear {
                
                if plan.workoutsSequenceIDs.count == 0 {
                    progress = 0
                } else {
                    progress = Double(plan.finishedWorkoutsSequence.count) / Double(plan.workoutsSequenceIDs.count)
                }
                
                if let nextWorkoutID = plan.firstIncompleteWorkoutID(existingIDs: existingWorkoutIDs) {
                    for workout in workouts {
                        if workout.id == nextWorkoutID {
                            appLog("Next workout: \(workout.name)")
                            workoutID = workout.id
                            nextWorkout = workout
                            
                            setLength = workout.setLength
                            
                            if SettingsManager.shared.appleWatchUsage {
                                appLog("AppleWatchUsage: True")
                                if syncManager.isWatchReachable {
                                    syncManager.requestWorkoutSync()
                                    
                                    iOSWorkoutObserver.previewWorkoutOnWatch(
                                        workoutName: workout.displayName,
                                        exerciseName: workout.exercises?.first?.displayName ?? NSLocalizedString("Not found", comment: "Plan: first exercise missing"),
                                        exerciseDuration: Double(workout.duration),
                                        muscleGroup: workout.muscleGroup)
                                } else {
                                    appLog("watch not reachable")
                                }
                            }
                        }
                    }
                }
            }
            .onDisappear(perform: {
                // Assign only when it changes: the same value still marks the
                // record changed and exports it to iCloud again on every visit.
                if plan.isNew {
                    withAnimation {
                        plan.isNew = false
                    }
                }
                // Always save: edits from `EditPlanView` (which doesn't save
                // itself) are persisted here.
                do {
                    try modelContext.save()
                } catch {
                    appLog("Error saving modelContext: \(error)")
                }

                
            })
            .toolbar(content: {
                // Hidden plans are retired catalog ones, kept for history.
                if !plan.isHidden {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { plan.toggleBookmark() }
                            Haptics.bookmark(saved: plan.isSaved)
                        } label: {
                            Image(systemName: plan.isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(plan.isSaved ? Theme.accent : Color.primary)
                        }
                        .accessibilityLabel(Text(plan.isSaved
                                                 ? NSLocalizedString("Remove bookmark", comment: "Workout card: unsave")
                                                 : NSLocalizedString("Bookmark", comment: "Workout card: save")))
                        .accessibilityIdentifier("planPreview.bookmark")
                    }
                }
            })
    #if os(iOS)
            .fullScreenCover(isPresented: $showActiveWorkoutView, onDismiss: presentSummary, content: {
                if !nextWorkout.id.isEmpty {
                    ActiveWorkoutView(workout: nextWorkout, plan: plan)
                } else {
                    // startNextWorkout() only presents with a resolved workout;
                    // close the cover rather than show an empty screen.
                    Color.clear
                        .onAppear {
                            showActiveWorkoutView = false
                            appLog("ID was empty")
                        }
                }
            })
            .alert("Plan complete", isPresented: $showPlanCompleteAlert) {
                Button("Restart Plan") {
                    plan.finishedWorkoutsSequence = []
                    do {
                        try modelContext.save()
                    } catch {
                        appLog("Error saving modelContext: \(error)")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You finished every workout in this plan. Restart it to go through the workouts again.")
            }
            .sheet(isPresented: $isSummaryPresendet, onDismiss: askForNextReminder, content: {
                withAnimation {
                    FinishedWorkoutView(specificWorkout: nil)
                }
            })
            .sheet(isPresented: $showNextReminderSheet) {
                NextReminderSheet(plan: plan)
                    .presentationDetents([.medium])
            }
    #endif
            .sheet(isPresented: $showEditPlan, content: {
                EditPlanView(plan: plan, onDelete: {
                    dismiss()
                })
            })
        }
    }
    
    func startNextWorkout() {
        // Resolve at tap time: `nextWorkout` is only set in onAppear, so it's
        // stale once a workout finishes while this view stays on screen.
        guard let id = plan.firstIncompleteWorkoutID(existingIDs: existingWorkoutIDs),
              let workout = workouts.first(where: { $0.id == id }) else {
            if !plan.workoutsSequenceIDs.isEmpty {
                showPlanCompleteAlert = true
            }
            return
        }
        workoutID = workout.id
        nextWorkout = workout
        setLength = workout.setLength
        Haptics.start()
        showActiveWorkoutView.toggle()

        // Same gate as WorkoutPreview: the metadata only feeds the watch.
        if SettingsManager.shared.appleWatchUsage {
            #if os(iOS)
            let workoutMetadata = WorkoutMetadata(
                workoutName: nextWorkout.displayName,
                exerciseName: nextWorkout.exercises?.first?.displayName ?? NSLocalizedString("Exercise", comment: "Fallback exercise name sent to the watch"),
                exerciseDuration: Double(nextWorkout.duration),
                muscleGroup: nextWorkout.muscleGroup
            )
            
            iOSWorkoutObserver.updateWorkoutMetadata(workoutMetadata)
            #endif
        }
        
        if SettingsManager.shared.appleWatchUsage {
            #if os(iOS)
            // The watch app may be asleep, so use the HealthKit wake path instead
            // of requiring WCSession reachability.
            if iOSWorkoutObserver.isWatchAppInstalled && iOSWorkoutObserver.currentWorkout?.isActive != true {
                startWatchWorkout()
            } else {
                appLog("Cannot start watch workout: Watch app not installed or workout already active")
            }
            #endif
            
            #if os(watchOS)
            // On watchOS, start the workout directly
            Task {
                do {
                    let workoutType = HKWorkoutActivityType(rawValue: UInt(nextWorkout.workoutActivityType)) ?? .other
                    try await watchWorkoutManager.startWorkout(type: workoutType)
                } catch {
                    appLog("Failed to start workout: \(error)")
                }
            }
            #endif
        }
    }
    
    private func startWatchWorkout() {
        #if os(iOS)
        Task {
            do {
                try await iOSWorkoutObserver.startWorkout(workout: nextWorkout)
            } catch {
                appLog("Failed to start watch workout: \(error)")
            }
        }
        #endif
    }
    
    
    
    func getNextWorkout(id: String) -> Workout? {
        if plan.firstIncompleteWorkoutID(existingIDs: existingWorkoutIDs) != nil {
            if let workout = workouts.first(where: { $0.id == id }) {
                return workout
            }
        }
        return nil
    }

    func orderedDaysStartingFromFirstWeekday(_ days: [String]) -> [String] {
        let firstDayIndex = Calendar.current.firstWeekday - 1
        
        let beforeFirstDay = Array(days.suffix(from: firstDayIndex))
        let afterFirstDay = Array(days.prefix(upTo: firstDayIndex))
        
        let orderedDays = beforeFirstDay + afterFirstDay
        return orderedDays
    }
    
    func formatInterval(_ interval: [String: Date], intervalType: String) -> String {
        
        switch intervalType {
        case "fixedDates":
            
            var consecutiveDays: [String] = []
            var selectedRanges: [String] = []

            let sortedWeekdays = orderedDaysStartingFromFirstWeekday(weekdays)

            for day in sortedWeekdays {
                if interval.keys.contains(day) {
                    consecutiveDays.append(day)
                } else {
                    if consecutiveDays.count > 1 {
                        let range = "\(consecutiveDays.first!)-\(consecutiveDays.last!)"
                        selectedRanges.append(range)
                    } else if let singleDay = consecutiveDays.first {
                        selectedRanges.append(singleDay)
                    }
                    consecutiveDays.removeAll()
                }
            }

            if consecutiveDays.count > 1 {
                let range = "\(consecutiveDays.first!)-\(consecutiveDays.last!)"
                selectedRanges.append(range)
            } else if let singleDay = consecutiveDays.first {
                selectedRanges.append(singleDay)
            }

            return selectedRanges.joined(separator: ", ")

        case "setAfterFinishedWorkout":
            guard let date = interval["nextDate"] else { return "" }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            
            let string = date.formatted(date: .long, time: .shortened)
            
            return NSLocalizedString("Next reminder: ", comment: "next reminder") + string
            
        default:
            return ""
        }
    }
    
    private func presentSummary() {
        guard ActiveWorkoutView.lastEndSaved else { return }
        isSummaryPresendet.toggle()
    }

    /// "Set reminder after you finished a workout" plans only ever have one
    /// pending reminder; after each workout the user picks the next one.
    private func askForNextReminder() {
        guard ActiveWorkoutView.lastEndSaved,
              plan.intervalType == "setAfterFinishedWorkout" else { return }
        showNextReminderSheet = true
    }
}

// MARK: - NextReminderSheet
struct NextReminderSheet: View {
    @Bindable var plan: Plan

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    @State private var nextDate: Date

    init(plan: Plan) {
        self.plan = plan
        // Two days out, at the time of day the user picked last time.
        let calendar = Calendar.current
        let inTwoDays = calendar.date(byAdding: .day, value: 2, to: .now) ?? .now
        var date = inTwoDays
        if let previous = plan.interval["nextDate"] {
            let time = calendar.dateComponents([.hour, .minute], from: previous)
            date = calendar.date(bySettingHour: time.hour ?? 18, minute: time.minute ?? 0,
                                 second: 0, of: inTwoDays) ?? inTwoDays
        }
        _nextDate = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            StyledForm(onPlanPage: true) {
                DatePicker("Select next reminder", selection: $nextDate, in: Date.now...)
            }
            .navigationTitle("Next reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set reminder") {
                        Task { await schedule() }
                    }
                    .bold()
                }
            }
        }
    }

    private func schedule() async {
        var interval = plan.interval
        interval["nextDate"] = nextDate
        plan.interval = interval
        do {
            try modelContext.save()
        } catch {
            appLog("Error saving modelContext: \(error)")
        }
        await NotificationManager.shared.refreshPlanReminders(context: modelContext)
        dismiss()
    }
}

#Preview {
    PlanPreview(plan: .init(goal: PlanGoal.strengthTraining.rawValue, infoText: "infoText that can be shorter or really long since the user can modify it in the edit view so it can contain multiple lines of text…", muscleGroup: 2, name: "name", interval: [:], intervalType: "IntervallType", workoutsSequenceIDs: ["1", "2", "3"], finishedWorkoutsSequence: ["1", "2", "3"]))
}



// MARK: - EditPlanView
struct EditPlanView: View {
    
    @Bindable var plan: Plan
    let onDelete: () -> Void
    
    @Environment(\.modelContext) var modelContext
    
    @Query var plans: [Plan]
    @Query var workouts: [Workout]
    /// Hidden workouts (For You sessions, retired presets) aren't offered.
    private var selectableWorkouts: [Workout] { workouts.filter { !$0.isHidden } }
    
    var weekdays = [NSLocalizedString("Sunday", comment: "Sunday, weekday"),
                    NSLocalizedString("Monday", comment: "Monday, weekday"),
                    NSLocalizedString("Tuesday", comment: "Tuesday, weekday"),
                    NSLocalizedString("Wednesday", comment: "Wednesday, weekday"),
                    NSLocalizedString("Thursday", comment: "Thursday, weekday"),
                    NSLocalizedString("Friday", comment: "Friday, weekday"),
                    NSLocalizedString("Saturday", comment: "Saturday, weekday")
                    ]
    
    @State private var deletePlanWarningActive = false
    
    @Environment(\.dismiss) var dismiss
    
    @StateObject var editPlanModel = EditPlanViewModel()
    
    var body: some View {
        ZStack {
            NavigationStack {
                StyledForm(onPlanPage: true) {
                    Section {
                        TextField("Name", text: $editPlanModel.name)
                        
                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Picker("Difficulty", selection: $editPlanModel.difficultyInt) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.name).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        Picker("Muscle group", selection: $editPlanModel.muscleGroup) {
                            ForEach(WorkoutCategory.allCases, id: \.self) { muscleGroup in
                                Text(muscleGroup.displayName).tag(muscleGroup.rawValue)
                            }
                        }
                        
                        Picker("Goal", selection: $editPlanModel.goal) {
                            ForEach(PlanGoal.allCases, id: \.self) { goal in
                                Text(goal.displayName).tag(goal.rawValue)
                            }
                        }
                        if #available(iOS 16.0, *) {
                            TextField("Description", text: $editPlanModel.infoText, axis: .vertical)
                                .lineLimit(100)
                        } else {
                            ScrollView {
                                TextField("Description", text: $editPlanModel.infoText)
                            }
                        }
                    }
                    
                    Section {
                        NavigationLink {
                            ChooseIntervalView(selectedInterval: $editPlanModel.interval, selectedIntervalType: $editPlanModel.intervalType, plan: plan)
                        } label: {
                            if editPlanModel.interval.isEmpty {
                                Text("Choose your interval")
                            } else {
                                Text(formatInterval(editPlanModel.interval, intervalType: editPlanModel.intervalType))
                            }
                        }
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text("When do you want to train?")
                    }
                    
                    //Displays workouts in Plan, received via id
                    if !editPlanModel.workoutsSequenceIDs.isEmpty {
                        Section("Workouts") {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(editPlanModel.workoutsSequenceIDs.indices, id: \.self) { index in
                                        WorkoutCardViewWithIndexEditPlan(id: editPlanModel.workoutsSequenceIDs[index], index: index, editPlanModel: editPlanModel)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .scrollIndicators(.hidden)
                        }
                    } else {
                        Text("Add Workouts to the plan")
                    }
                    
                    //Displays all workouts for adding to plan
                    Section {
                        if !selectableWorkouts.isEmpty {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(selectableWorkouts, id: \.self) { workout in
                                    WorkoutSelectionTileEditPlan(workout: workout, editPlanModel: editPlanModel)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        } else {
                            Text("There are no workouts.")
                        }
                    }
                    
                    Button("Delete Plan", role: .destructive) {
                        deletePlanWarningActive.toggle()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .toolbar(content: {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .disabled(editPlanModel.showDetail)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await savePlan()
                            }
                        } label: {
                            Text("Save")
                                .bold()
                                .disabled(editPlanModel.showDetail)
                        }
                    }
                })
                .confirmationDialog("Delete Plan", isPresented: $deletePlanWarningActive) {
                    Button("Delete Plan") {
                        NotificationManager.shared.cancelReminders(for: plan)
                        modelContext.delete(plan)
                        appLog("Plan deleted")                        
                        dismiss()
                        onDelete()
                    }
                }
                .alert(isPresented: $editPlanModel.showNameAlreadyExisting) {
                    Alert(title: Text("Name already existing"), message: Text("A Plan with this name is already existing"), dismissButton: .default(Text("OK")))
                }
                .navigationTitle("Edit Plan")
            }
            .onAppear(perform: {
                editPlanModel.initValues(plan)
            })
            .disabled(editPlanModel.showDetail)
            .opacity(editPlanModel.showDetail ? 0.6 : 1)
            if editPlanModel.showDetail {
                EditPlanDetailWorkoutView(editplanModel: editPlanModel)
                    .frame(width: 350)
            }
        }
    }
    
    func orderedDaysStartingFromFirstWeekday(_ days: [String]) -> [String] {
        let firstDayIndex = Calendar.current.firstWeekday - 1
        
        // Split the days array into two parts: before and after the first day of the week
        let beforeFirstDay = Array(days.suffix(from: firstDayIndex))
        let afterFirstDay = Array(days.prefix(upTo: firstDayIndex))
        
        // Combine the two parts to create the shuffled array
        let orderedDays = beforeFirstDay + afterFirstDay
        
        return orderedDays
    }
    
    func formatInterval(_ interval: [String: Date], intervalType: String) -> String {
        switch intervalType {
        case "fixedDates":
            
            var consecutiveDays: [String] = []
            var selectedRanges: [String] = []

            let sortedWeekdays = orderedDaysStartingFromFirstWeekday(weekdays)

            for day in sortedWeekdays {
                if interval.keys.contains(day) {
                    consecutiveDays.append(day)
                } else {
                    if consecutiveDays.count > 1 {
                        let range = "\(consecutiveDays.first!)-\(consecutiveDays.last!)"
                        selectedRanges.append(range)
                    } else if let singleDay = consecutiveDays.first {
                        selectedRanges.append(singleDay)
                    }
                    consecutiveDays.removeAll()
                }
            }

            if consecutiveDays.count > 1 {
                let range = "\(consecutiveDays.first!)-\(consecutiveDays.last!)"
                selectedRanges.append(range)
            } else if let singleDay = consecutiveDays.first {
                selectedRanges.append(singleDay)
            }

            return selectedRanges.joined(separator: ", ")

        case "setAfterFinishedWorkout":
            guard let date = interval["nextDate"] else { return "" }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            
            let string = date.formatted(date: .long, time: .shortened)
            
            return NSLocalizedString("Next reminder: ", comment: "next reminder") + string
            
        default:
            return ""
        }
    }
    
    func savePlan() async {
        if editPlanModel.name != "" {
            for plan in plans {
                if plan.name == editPlanModel.name && plan.name != editPlanModel.unEditedName {
                    editPlanModel.showNameAlreadyExisting = true
                    appLog("Other plan with this name existing")
                    return
                }
            }
            
            plan.name = editPlanModel.name
            plan.difficultyInt = editPlanModel.difficultyInt
            plan.goal = editPlanModel.goal
            plan.muscleGroup = editPlanModel.muscleGroup
            plan.infoText = editPlanModel.infoText
            plan.interval = editPlanModel.interval
            plan.intervalType = editPlanModel.intervalType
            plan.workoutsSequenceIDs = editPlanModel.workoutsSequenceIDs
            
            switch editPlanModel.difficultyInt {
            case 1:
                plan.difficulty = NSLocalizedString("easy", comment: "easy, Difficulty")
            case 2:
                plan.difficulty = NSLocalizedString("medium", comment: "medium, Difficulty")
            case 3:
                plan.difficulty = NSLocalizedString("hard", comment: "hard, Difficulty")
            default:
                plan.difficulty = NSLocalizedString("medium", comment: "medium, Difficulty")
            }
            
            // Each workout once in the relationship; the sequence keeps repeats.
            var seen = Set<String>()
            let addedWorkouts = editPlanModel.workoutsSequenceIDs.filter { seen.insert($0).inserted }.compactMap { workoutID in
                self.workouts.first { $0.id == workoutID }
            }.filter { workout in
                plan.workouts?.contains(workout) != true
            }
            
            if !addedWorkouts.isEmpty {
                plan.workouts = (plan.workouts ?? []) + addedWorkouts
            }
            
            let removedWorkouts = plan.workouts?.filter { workout in
                !editPlanModel.workoutsSequenceIDs.contains(workout.id)
            }
            removedWorkouts?.forEach { workout in
                if let index = plan.workouts?.firstIndex(of: workout) {
                    plan.workouts?.remove(at: index)
                }
            }
            
            // Also covers switching reminders off, which used to leave the
            // old ones scheduled.
            await NotificationManager.shared.refreshPlanReminders(context: modelContext)
            dismiss()
        } else {
            appLog("Name empty")
        }
    }
}

#Preview(body: {
    let testWorkout = Workout.samples[0]
    let plan = Plan.samples[0]
    plan.workouts = [testWorkout]
    
    return EditPlanView(plan: plan, onDelete: {})
})

// MARK: - WorkoutCardViewWithIndex
struct WorkoutCardViewWithIndexEditPlan: View {
    
    @Query var workouts: [Workout]
    
    let id: String
    let index: Int
    
    @ObservedObject var editPlanModel: EditPlanViewModel
    
    var workout: Workout? {
        for workout in workouts {
            if workout.id == id {
                return workout
            }
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            ThemedPanel()
                .frame(width: 145, height: 95)
            
            VStack {
                HStack {
                    Text("\(index + 1).")
                    
                    Spacer()
                    
                    Button {
                        editPlanModel.removeWorkoutSelection(id: id, atIndex: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .accessibilityLabel(Text(NSLocalizedString("Remove workout", comment: "Accessibility: remove a workout from the plan")))
                            .foregroundStyle(Theme.danger)
                    }
                    // The strip is one Form row; see `WorkoutSelectionTileEditPlan`.
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("planEditor.remove.\(index)")
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                Spacer()
                Text(workout?.displayName ?? "N/A")
                    .font(.title3)
                    .padding(5)
            }
        }
        .frame(width: 150, height: 100)
    }
}

#Preview {
    PlanPreview(plan: .init(goal: PlanGoal.strengthTraining.rawValue, infoText: "infoText", muscleGroup: 2, name: "name", workouts: [Workout.init(id: "id", infoText: "info", isUserGenerated: false, muscleGroup: 2, setLength: 2, straightSets: false, difficultyInt: 2, name: "workoutName", duration: 5, exercisesSequenceID: ["exID1", "exID2"], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5)], interval: [:], intervalType: "intervallType", workoutsSequenceIDs: ["id", "fds2"], workoutsInPlan: [Workout.init(id: "id", infoText: "info", isUserGenerated: false, muscleGroup: 2, setLength: 2, straightSets: false, difficultyInt: 2, name: "workoutName", duration: 5, exercisesSequenceID: ["exID1", "exID2"], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5)]))
}

struct CircularProgressView: View {
    var progress: Double
    var total: Double
    var lineWidth: CGFloat = 8
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface, lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: CGFloat(min(progress/total, 1.0)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
            // Center text
            VStack(spacing: 2) {
                Text("\(Int(progress))/\(Int(total))")
                    .displayFont(.title3)
                
                Text("Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 100, height: 100)
    }
}
#Preview(body: {
    CircularProgressView(progress: 10, total: 10)
})

enum PlanWorkoutRowState {
    case completed, current, upcoming
}

struct PlanWorkoutTimelineRow: View {

    let workout: Workout
    let position: Int
    let totalCount: Int
    let state: PlanWorkoutRowState
    let isLast: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    switch state {
                    case .completed:
                        Circle()
                            .fill(Theme.surface)
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    case .current:
                        Circle()
                            .fill(Theme.accentFillGradient)
                        Text("\(position)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                    case .upcoming:
                        Circle()
                            .stroke(Theme.hairline, lineWidth: 1.5)
                        Text("\(position)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(width: 36, height: 36)
                if !isLast {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 2)
                }
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(NSLocalizedString("Workout", comment: "Workout label")) \(position)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if state == .current {
                        Text("Up next")
                            .font(.caption2.weight(.bold))
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .controlBackground(.accent)
                            .foregroundStyle(Theme.onAccent)
                    } else if state == .completed {
                        Text("Done")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Text(workout.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(workout.duration) min · \(WorkoutCategory.getCategoryName(from: workout.muscleGroup))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
            .opacity(state == .completed ? 0.6 : 1)
        }
        .contentShape(Rectangle())
    }
}
