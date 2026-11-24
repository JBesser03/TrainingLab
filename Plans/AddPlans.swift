//
//  AddPlans.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 30.12.23.
//

import SwiftUI
import SwiftData

struct AddPlans: View {
    
    @Query var workouts: [Workout]
    @Query var plans: [Plan]
    /// Hidden workouts (For You sessions, retired presets) aren't offered.
    private var selectableWorkouts: [Workout] { workouts.filter { !$0.isHidden } }
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var showNoWorkoutsInfo: Bool = false
    @State private var showNameAlreadyExisting: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    var weekdays = [NSLocalizedString("Sunday", comment: "Sunday, weekday"),
                    NSLocalizedString("Monday", comment: "Monday, weekday"),
                    NSLocalizedString("Tuesday", comment: "Tuesday, weekday"),
                    NSLocalizedString("Wednesday", comment: "Wednesday, weekday"),
                    NSLocalizedString("Thursday", comment: "Thursday, weekday"),
                    NSLocalizedString("Friday", comment: "Friday, weekday"),
                    NSLocalizedString("Saturday", comment: "Saturday, weekday")
    ]
    
    var goals: [String] = [
        NSLocalizedString("Muscle Building", comment: "Goal"),
        NSLocalizedString("Strength Training", comment: "Goal"),
        NSLocalizedString("Weight Loss", comment: "Goal"),
        NSLocalizedString("Endurance and Stamina", comment: "Goal"),
        NSLocalizedString("Flexibility and Mobility", comment: "Goal"),
        NSLocalizedString("Functional Fitness", comment: "Goal"),
        NSLocalizedString("Sport-Specific Training", comment: "Goal"),
        NSLocalizedString("Rehabilitation and Injury Prevention", comment: "Goal"),
        NSLocalizedString("Mind-Body Connection", comment: "Goal"),
        NSLocalizedString("Overall Health and Wellness", comment: "Goal")
    ]
    
    @StateObject var addPlanModel = AddPlanViewModel()
    
    var body: some View {
        ZStack {
            NavigationStack {
                StyledForm(onPlanPage: true) {
                    Section {
                        TextField("Name", text: $addPlanModel.name)
                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Picker("Difficulty", selection: $addPlanModel.difficultyInt) {
                                ForEach(DifficultyLevel.allCases) { level in
                                    Text(level.name).tag(level.rawValue)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        Picker("Muscle group", selection: $addPlanModel.muscleGroup) {
                            ForEach(WorkoutCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category.rawValue)
                            }
                        }
                        
                        Picker("Goal", selection: $addPlanModel.goal) {
                            ForEach(PlanGoal.allCases, id: \.self) { goal in
                                Text(goal.displayName).tag(goal.rawValue)
                            }
                        }
                        
                        if #available(iOS 16.0, *) {
                            TextField("Description", text: $addPlanModel.infoText, axis: .vertical)
                                .lineLimit(100)
                        } else {
                            ScrollView {
                                TextField("Description", text: $addPlanModel.infoText)
                            }
                        }
                    }
                    
                    Section {
                        NavigationLink {
                            ChooseIntervalView(selectedInterval: $addPlanModel.interval, selectedIntervalType: $addPlanModel.intervalType, plan: nil)
                        } label: {
                            if addPlanModel.interval.isEmpty {
                                Text("Choose your interval")
                            } else {
                                Text(formatInterval(addPlanModel.interval, intervalType: addPlanModel.intervalType))
                            }
                        }
                    } header: {
                        Text("Interval")
                    } footer: {
                        Text("How often do you want to train?")
                    }
                    
                    if !addPlanModel.workoutsSequenceIDs.isEmpty {
                        Section("Workouts") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(addPlanModel.workoutsSequenceIDs.indices, id: \.self) { index in
                                        WorkoutCardWithIndexAddPlanView(id: addPlanModel.workoutsSequenceIDs[index], index: index, addPlanModel: addPlanModel)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.clear)
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        Text("Add Workouts to the plan")
                    }
                    
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
                                    WorkoutSelectionTileAddPlan(workout: workout, addPlanModel: addPlanModel)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        } else {
                            Text("There are no workouts.")
                        }
                    }
                }
                .navigationTitle("Add Plan")
                .toolbar(content: {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await savePlan()
                            }
                        } label: {
                            Text("Save")
                                .bold()
                                .disabled(addPlanModel.showDetail)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .disabled(addPlanModel.showDetail)
                        }
                    }
                })
                .alert(isPresented: $showNoWorkoutsInfo) {
                    Alert(title: Text("No workouts available"), message: Text("Add your own workouts first or restore default workouts in settings"), dismissButton: .default(Text("OK")))
                }
                .alert(isPresented: $showNameAlreadyExisting) {
                    Alert(title: Text("Name already existing"), message: Text("A Plan with this name is already existing"), dismissButton: .default(Text("OK")))
                }
            }
            .disabled(addPlanModel.showDetail)
            .opacity(addPlanModel.showDetail ? 0.6 : 1)
            if addPlanModel.showDetail {
                DetailWorkoutView(addPlanModel: addPlanModel)
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
        if addPlanModel.name != "" { // Name not empty
            for plan in plans {
                if plan.name == addPlanModel.name {
                    showNameAlreadyExisting = true
                    return
                }
            }
            
            let newPlan = Plan(goal: addPlanModel.goal, infoText: addPlanModel.infoText, muscleGroup: addPlanModel.muscleGroup, name: addPlanModel.name, difficultyInt: addPlanModel.difficultyInt, interval: addPlanModel.interval, intervalType: addPlanModel.intervalType, isUserGenerated: true, finishedWorkoutsSequence: [])
            
            newPlan.workoutsSequenceIDs = addPlanModel.workoutsSequenceIDs
            // Each workout once in the relationship; the sequence keeps repeats.
            var seen = Set<String>()
            let workouts = addPlanModel.workoutsSequenceIDs.filter { seen.insert($0).inserted }.compactMap { workoutID in
                self.workouts.first { $0.id == workoutID }
            }
            newPlan.workouts = workouts
            
            newPlan.workouts?.forEach {
                $0.plan?.append(newPlan)
            }
            
            modelContext.insert(newPlan)
            
            do {
                try modelContext.save()
            } catch {
                appLog("Error saving modelContext in AddPlans: \(error)")
            }
            
            await NotificationManager.shared.refreshPlanReminders(context: modelContext)
            dismiss()
        }
    }
}

struct WorkoutCardWithIndexAddPlanView: View {
    
    @Query var workouts: [Workout]
    
    let id: String
    let index: Int
    
    @ObservedObject var addPlanModel: AddPlanViewModel
    
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
            ThemedPanel(fill: .inset)

            VStack {
                HStack {
                    Text("\(index + 1).")
                    
                    Spacer()
                    
                    Button {
                        addPlanModel.removeWorkoutSelection(id: id, atIndex: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .accessibilityLabel(Text(NSLocalizedString("Remove workout", comment: "Accessibility: remove a workout from the plan")))
                            .foregroundStyle(Theme.danger)
                    }
                    // The strip is one Form row too; see the + button.
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("planEditor.remove.\(index)")
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                Spacer()
                Text(workout?.displayName ?? "N/A")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 150, height: 100)
    }
}

struct WorkoutSelectionTileAddPlan: View {
    
    @Bindable var workout: Workout
    @ObservedObject var addPlanModel: AddPlanViewModel

    /// How often the workout is in the plan; it can be added more than once.
    private var timesAdded: Int { addPlanModel.workoutsSequenceIDs.filter { $0 == workout.id }.count }
    
    var body: some View {
        ZStack {
            ThemedPanel(fill: .inset)
            
            VStack(spacing: 0) {
                HStack {
                    // Borderless: the whole grid is one Form row, and with the
                    // default style a tap there fired every tile's button, adding
                    // all workouts at once.
                    Button {
                        addPlanModel.addWorkoutSelection(workout.id)
                    } label: {
                        Image(systemName: timesAdded > 0 ? "plus.circle.fill" : "plus.circle")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("planEditor.add.\(workout.id)")
                    if timesAdded > 0 {
                        Text(verbatim: "\(timesAdded)×")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("planEditor.count.\(workout.id)")
                    }
                    
                    Spacer()
                    Image(systemName: "ellipsis")
                        .imageScale(.large)
                        .frame(width: 44, height: 44)
                        .onTapGesture {
                            addPlanModel.showWorkoutDetail(workout)
                        }
                }
                
                Spacer(minLength: 0)
                
                Text(workout.displayName)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }
}

struct WorkoutSelectionTileEditPlan: View {
    
    @Bindable var workout: Workout
    @ObservedObject var editPlanModel: EditPlanViewModel

    /// How often the workout is in the plan; it can be added more than once.
    private var timesAdded: Int { editPlanModel.workoutsSequenceIDs.filter { $0 == workout.id }.count }
    
    var body: some View {
        ZStack {
            ThemedPanel(fill: .inset)
            
            VStack(spacing: 0) {
                HStack {
                    // Borderless: the whole grid is one Form row, and with the
                    // default style a tap there fired every tile's button, adding
                    // all workouts at once.
                    Button {
                        editPlanModel.addWorkoutSelection(workout.id)
                    } label: {
                        Image(systemName: timesAdded > 0 ? "plus.circle.fill" : "plus.circle")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("planEditor.add.\(workout.id)")
                    if timesAdded > 0 {
                        Text(verbatim: "\(timesAdded)×")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("planEditor.count.\(workout.id)")
                    }
                    
                    Spacer()
                    Image(systemName: "ellipsis")
                        .imageScale(.large)
                        .frame(width: 44, height: 44)
                        .onTapGesture {
                            editPlanModel.showWorkoutDetail(workout)
                        }
                }
                
                Spacer(minLength: 0)
                
                Text(workout.displayName)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }
}

#Preview {
    WorkoutSelectionTileEditPlan(workout: Workout.init(id: "id", infoText: "infoText", isUserGenerated: false, muscleGroup: 100, setLength: 3, straightSets: false, difficultyInt: 2, name: "name", duration: 10, exercisesSequenceID: ["id1", "id2"], finishedExercisesSequence: [], workoutActivityType: 5, workoutSessionLocation: 5), editPlanModel: .init())
}


struct ChooseIntervalView: View {
    
    var days = [NSLocalizedString("Sunday", comment: "Sunday, weekday"), NSLocalizedString("Monday", comment: "Monday, weekday"), NSLocalizedString("Tuesday", comment: "Tuesday, weekday"), NSLocalizedString("Wednesday", comment: "Wednesday, weekday"), NSLocalizedString("Thursday", comment: "Thursday, weekday"), NSLocalizedString("Friday", comment: "Friday, weekday"), NSLocalizedString("Saturday", comment: "Saturday, weekday")]
    
    @Binding var selectedInterval: [String: Date]
    @Binding var selectedIntervalType: String
    
    @State private var selectedRollingInterval = "Select Interval"
    @State private var selectedDate: Date = Date()
    
    let plan: Plan?
    
    var notificationsEnabled = SettingsManager.shared.notifications
    
    var body: some View {
        StyledForm(onPlanPage: true) {
            Section("Fixed days") {
                Button {
                    withAnimation {
                        selectedIntervalType = "fixedDates"
                        selectedRollingInterval = "Select Interval"
                        selectedInterval.removeValue(forKey: "nextDate")
                    }
                } label: {
                    VStack {
                        HStack {
                            Image(systemName: selectedIntervalType == "fixedDates" ? "checkmark.circle" : "circle")
                            Spacer()
                            Text("Select fixed dates and times to get reminded")
                                .foregroundColor(.primary)
                        }
                        .padding(5)
                        
                        HStack(spacing: 10) {
                            ForEach(orderedDaysStartingFromFirstWeekday(days), id: \.self) { day in
                                Button {
                                    if selectedInterval[day] != nil {
                                        selectedInterval.removeValue(forKey: day)
                                    } else {
                                        selectedInterval[day] = Date()
                                        withAnimation {
                                            selectedIntervalType = "fixedDates"
                                            selectedRollingInterval = "Select Interval"
                                        }
                                    }
                                } label: {
                                    ZStack {
                                        if selectedInterval[day] != nil {
                                            Circle()
                                                .fill(.blue.opacity(0.7))
                                            Text(day.prefix(2))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text(day.prefix(2))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                }
                                .frame(maxWidth: UIScreen.activeBounds.width, alignment: .center)
                                .frame(height: 40)
                                .buttonStyle(.borderless)
                            }
                        }
                        .disabled(selectedIntervalType == "setAfterFinishedWorkout")
                        
                        if selectedIntervalType == "fixedDates" && !selectedInterval.isEmpty {
                            
                            Divider()
                            
                            List {
                                ForEach(Array(selectedInterval.keys), id: \.self) { day in
                                    HStack {
                                        Text("\(day)")
                                        
                                        DatePicker("", selection: Binding<Date>(
                                            get: {
                                                selectedInterval[day] ?? Date()
                                            },
                                            set: { newValue in
                                                selectedInterval[day] = newValue
                                            }
                                        ), displayedComponents: .hourAndMinute)
                                    }
                                    .onChange(of: selectedInterval[day]) { oldValue, newValue in
                                        selectedInterval[day] = newValue ?? Date()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("New reminder after workout") {
                Button {
                    withAnimation {
                        selectedIntervalType = "setAfterFinishedWorkout"
                    }
                } label: {
                    VStack {
                        HStack {
                            Image(systemName: selectedIntervalType == "setAfterFinishedWorkout" ? "checkmark.circle" : "circle")
                            Spacer()
                            Text("Set reminder after you finished a workout")
                                .foregroundColor(.primary)
                        }
                        .padding(5)
                        
                        if selectedIntervalType == "setAfterFinishedWorkout" {
                            DatePicker("Select next reminder", selection: $selectedDate)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            Section {
                Button {
                    withAnimation {
                        selectedIntervalType = ""
                        selectedRollingInterval = "Select Interval"
                        selectedInterval = [:]
                    }
                } label: {
                    Text("Remove notifications")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .onAppear(perform: {
            if !notificationsEnabled {
                UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .badge, .alert]) { granted, error in
                    if granted {
                        appLog("Permission granted")
                        // The callback runs on a background queue; the setting
                        // publishes to SwiftUI, so update it on the main actor.
                        Task { @MainActor in
                            SettingsManager.shared.notifications = true
                        }
                    } else {
                        appLog("Permission denied, error: \(String(describing: error))")
                    }
                }
            }
        })
        .onDisappear(perform: {
            if selectedIntervalType == "setAfterFinishedWorkout" {
                selectedInterval["nextDate"] = selectedDate
            }
            appLog(selectedInterval)
        })
        .sensoryFeedback(.selection, trigger: selectedIntervalType)
        .navigationTitle("Choose Interval")
    }
    
    func orderedDaysStartingFromFirstWeekday(_ days: [String]) -> [String] {
        // Get the first weekday index, subtracting 1 as Calendar.weekdaySymbols is zero-based
        let firstWeekdayIndex = Calendar.current.firstWeekday - 1
        
        // Ensure the first weekday index is within the bounds of the weekday symbols array
        guard firstWeekdayIndex >= 0 && firstWeekdayIndex < days.count else {
            return days // Return the original array if the first weekday index is invalid
        }
        
        // Split the days array into two parts: those after the first day of the week and those before it
        let orderedDays = Array(days.suffix(from: firstWeekdayIndex)) + Array(days.prefix(upTo: firstWeekdayIndex))
        
        return orderedDays
    }
}

#Preview {
    AddPlans()
}
