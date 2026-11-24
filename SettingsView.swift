//
//  SettingsView.swift
//  Workout in CoreData
//
//  Created by Justus Besser on 26.12.21.
//

import SwiftUI
import HealthKit
import SwiftData

struct SettingsView: View {

    @StateObject private var settings = SettingsManager.shared

    @EnvironmentObject private var healthManager: HealthKitManager

    @State private var showGymEquipmentPicker = false
    @State private var showDisclaimer = false

    @Environment(\.modelContext) private var modelContext
    @State private var showRestoreConfirm = false
    @State private var showDeleteCustomConfirm = false

    @StateObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var pingResult: String = "—"
    @State private var pingInFlight = false

    /// Apple Health's latest body weight; it wins over the typed one.
    @State private var healthBodyWeightKg: Double?
    @State private var showBodyWeightEntry = false
    @State private var bodyWeightText = ""
    @State private var exportFile: ExportFile?

    /// Legal document URLs. Point these at wherever the HTML pages in the repo
    /// (privacy-policy.html / impressum.html) are hosted.
    private enum Legal {
        static let privacyPolicy = URL(string: "https://traininglab.besser-siegen.de/privacy-policy.html")!
        static let imprint = URL(string: "https://traininglab.besser-siegen.de/impressum.html")!
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        StyledList {
            // First, so picking a color — which rebuilds the app — doesn't
            // scroll the list back up under the user.
            Section {
                stylePicker
                // Graphite looks the same either way.
                if settings.appTheme.followsColorIntensity {
                    Picker(NSLocalizedString("Color", comment: "Settings: how much of the app the style colors"),
                           selection: $settings.colorIntensity) {
                        ForEach(ColorIntensity.allCases) { intensity in
                            Text(intensity.name).tag(intensity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.colorIntensity")
                    .sensoryFeedback(.selection, trigger: settings.colorIntensity)
                }
                Toggle(NSLocalizedString("App icon in style colors", comment: "Settings: the home screen icon follows the chosen style"),
                       isOn: $settings.appIconMatchesStyle)
                    .accessibilityIdentifier("settings.appIcon")
            } header: {
                Text(NSLocalizedString("Appearance", comment: "Settings: section"))
            } footer: {
                Text(NSLocalizedString("Each style sets the colors, the shapes and the font of titles and numbers. Subtle keeps cards and text neutral, Vivid colors them too. The widget and Apple Watch take on its accent.",
                                       comment: "Settings: style picker footer"))
            }

            Section {
                Toggle("Enable Notifications", isOn: $settings.notifications)
                    .onChange(of: settings.notifications) {
                        // Master switch for weekly-goal reminders. Plan
                        // reminders are left alone — they are scheduled and
                        // cancelled from the plan screens themselves.
                        Task {
                            if settings.notifications {
                                await GoalReminderScheduler.shared.requestAuthorization()
                                await GoalReminderScheduler.shared.refresh(context: modelContext)
                            } else {
                                await GoalReminderScheduler.shared.cancelAll()
                            }
                        }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Turning this off also stops weekly-goal reminders.")
            }
            
            Section {
                Picker(NSLocalizedString("Rest timer", comment: "Settings: rest between the sets of a strength workout"),
                       selection: $settings.restTimerSeconds) {
                    Text(NSLocalizedString("Off", comment: "Settings: rest timer off")).tag(0)
                    ForEach([60, 90, 120, 180], id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))).tag(seconds)
                    }
                }
                .accessibilityIdentifier("settings.restTimer")
                .onChange(of: settings.restTimerSeconds) { old, new in
                    if old == 0, new > 0 { Task { await RestNotification.requestPermission() } }
                }

                Picker(NSLocalizedString("Rest between circuit rounds", comment: "Settings: default rest of new cardio/HIIT workouts"),
                       selection: $settings.pauseTime) {
                    Text("No Pause").tag(0)
                    Text("5 Seconds").tag(5)
                    Text("10 Seconds").tag(10)
                    Text("15 Seconds").tag(15)
                    Text("30 Seconds").tag(30)
                    Text("45 Seconds").tag(45)
                    Text("60 Seconds").tag(60)
                }

                Picker("Weight unit", selection: $settings.weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            } header: {
                Text("Workout")
            } footer: {
                Text(NSLocalizedString("The rest timer starts after each set of a strength workout, also on your Lock Screen and Apple Watch. Circuit rest is the default for new cardio and HIIT workouts; each workout can change it on its detail screen.",
                                       comment: "Settings: workout section footer"))
            }
            
            Section(NSLocalizedString("Apple Health", comment: "Settings: section")) {
                Toggle(NSLocalizedString("Connect Apple Health", comment: "Settings: HealthKit toggle"), isOn: $settings.tryEnableHealthKit)
                    .onChange(of: settings.tryEnableHealthKit) {
                        
                        if settings.tryEnableHealthKit {
                            if !settings.accessHealthKitSucceeded {
                                Task {
                                    do {
                                        try await healthManager.requestAuthorization()
                                        settings.accessHealthKitSucceeded = true
                                    } catch {
                                        appLog("error requesting healthkit authorization: \(error)")
                                    }
                                }
                            }
                        }
                    }
            }
            
            Section {
                Toggle(NSLocalizedString("Use Apple Watch", comment: "Settings: watch toggle"),
                       isOn: Binding(get: { settings.appleWatchUsage }, set: { settings.setAppleWatchUsage($0) }))
            } header: {
                Text(NSLocalizedString("Apple Watch", comment: "Settings: section"))
            } footer: {
                Text(NSLocalizedString("Turns on by itself once TrainingLab is installed on your Apple Watch.", comment: "Settings: watch footer"))
            }

            #if DEBUG
            // Internal tooling — only visible in dev builds. Don't ship
            // raw WCSession diagnostics to end users; they're noise and
            // expose implementation details (activation state, error
            // strings) that don't help a customer.
            Section {
                LabeledContent("State", value: watchConnectivity.connectionState)
                LabeledContent("Reachable", value: watchConnectivity.isWatchReachable ? "yes" : "no")
                #if os(iOS)
                LabeledContent("App installed", value: watchConnectivity.isWatchAppInstalled ? "yes" : "no")
                #endif
                LabeledContent("Last error", value: watchConnectivity.lastError ?? "—")
                LabeledContent("Last ping", value: pingResult)

                Button {
                    Task { await runPing() }
                } label: {
                    HStack {
                        Text("Ping watch")
                        Spacer()
                        if pingInFlight {
                            ProgressView()
                        }
                    }
                }
                .disabled(pingInFlight)
            } header: {
                Text("Watch diagnostics")
            } footer: {
                Text("Internal diagnostics (DEBUG builds only).")
            }
            #endif

            Section {
                Button {
                    showGymEquipmentPicker = true
                } label: {
                    HStack {
                        Text("My gym equipment")
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(settings.availableGymEquipment.count)")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Picker(NSLocalizedString("Barbell", comment: "Settings: weight of the bar for the plate calculator"),
                       selection: $settings.barbellWeightKg) {
                    ForEach(PlateCalculator.barOptionsKg(for: settings.weightUnit, current: settings.barbellWeightKg), id: \.self) { kg in
                        Text(settings.weightUnit.format(kilograms: kg)).tag(kg)
                    }
                }

                Button {
                    bodyWeightText = settings.bodyWeightKg.map { settings.weightUnit.displayNumber(kilograms: $0) } ?? ""
                    showBodyWeightEntry = true
                } label: {
                    HStack {
                        Text(NSLocalizedString("Body weight", comment: "Settings: the user's body weight"))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(bodyWeightSummary)
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.bodyWeight")
            } header: {
                Text("Gym")
            } footer: {
                Text(NSLocalizedString("Generated gym plans only use exercises your equipment allows. The barbell weight is used by the plate calculator. Bodyweight exercises count your body weight toward a session's total weight — Apple Health's latest weight when there is one.",
                                       comment: "Settings: gym section footer"))
            }

            Section {
                Button {
                    exportFile = ExportFile.history(context: modelContext)
                } label: {
                    Label(NSLocalizedString("Export workout history", comment: "Settings row: save the history as a CSV file"),
                          systemImage: "square.and.arrow.up")
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("settings.export")
                Button {
                    showRestoreConfirm = true
                } label: {
                    Label(NSLocalizedString("Restore preloaded workouts & plans", comment: "Settings row"),
                          systemImage: "arrow.counterclockwise")
                        .foregroundColor(.primary)
                }
                Button(role: .destructive) {
                    showDeleteCustomConfirm = true
                } label: {
                    Label(NSLocalizedString("Delete all custom workouts & plans", comment: "Settings row"),
                          systemImage: "trash")
                }
            } header: {
                Text("Data")
            } footer: {
                Text(NSLocalizedString("The export is a CSV file with every set you logged, for a spreadsheet or another app. Restoring resets the preloaded content to its original state without touching your own workouts. Deleting removes everything you created — your workout history stays.",
                                       comment: "Settings: data section footer"))
            }

            Section {
                Button {
                    showDisclaimer = true
                } label: {
                    Label(NSLocalizedString("Health & fitness disclaimer", comment: "Settings row"),
                          systemImage: "heart.text.square")
                        .foregroundColor(.primary)
                }
                Link(destination: Legal.privacyPolicy) {
                    Label(NSLocalizedString("Privacy Policy", comment: "Settings row"),
                          systemImage: "hand.raised")
                }
                Link(destination: Legal.imprint) {
                    Label(NSLocalizedString("Impressum", comment: "Settings row"),
                          systemImage: "info.circle")
                }
                LabeledContent(NSLocalizedString("Version", comment: "Settings row"), value: appVersion)
            } header: {
                Text("About & Legal")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showGymEquipmentPicker) {
            GymEquipmentPickerView()
        }
        .sheet(isPresented: $showDisclaimer) {
            HealthDisclaimerSheet()
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert(NSLocalizedString("Body weight", comment: "Settings: the user's body weight"), isPresented: $showBodyWeightEntry) {
            TextField(settings.weightUnit.abbreviation, text: $bodyWeightText)
                .keyboardType(.decimalPad)
            Button(NSLocalizedString("Save", comment: "")) {
                let text = bodyWeightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                if let value = Double(text), value > 0 {
                    settings.bodyWeightKg = settings.weightUnit.toKilograms(value)
                } else if text.isEmpty {
                    settings.bodyWeightKg = nil
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            if healthBodyWeightKg != nil {
                Text(NSLocalizedString("Used when Apple Health has no recent weight.", comment: "Settings: body weight entry hint"))
            }
        }
        .task {
            if settings.accessHealthKitSucceeded {
                healthBodyWeightKg = await BodyWeight.latestFromHealth()
            }
        }
        .confirmationDialog(NSLocalizedString("Restore preloaded content?", comment: "Settings: restore dialog title"),
                            isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("Restore", comment: "Settings: restore confirm")) {
                removePreloadedContent(modelContext: modelContext)
                seedDefaultContent(modelContext: modelContext)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Preloaded workouts and plans are reset to their original state. Your own content is not affected.",
                                   comment: "Settings: restore dialog message"))
        }
        .confirmationDialog(NSLocalizedString("Delete all custom content?", comment: "Settings: delete dialog title"),
                            isPresented: $showDeleteCustomConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("Delete", comment: "Settings: delete confirm"), role: .destructive) {
                deleteCustomContent(modelContext: modelContext)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("All workouts and plans you created will be deleted. Your workout history is kept. This cannot be undone.",
                                   comment: "Settings: delete dialog message"))
        }
    }

    /// The styles as tiles, three to a row — each in its own card color,
    /// corners, font and accent — above a preview of the chosen one.
    private var stylePicker: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                ForEach(AppTheme.allCases) { theme in
                    styleTile(theme)
                }
            }
            .padding(.vertical, 8)
            .sensoryFeedback(.selection, trigger: settings.appTheme)

            stylePreview
        }
        .padding(.bottom, 8)
    }

    private func styleTile(_ theme: AppTheme) -> some View {
        let isSelected = settings.appTheme == theme
        // The style's own corners, a little tighter to fit the tile.
        let tile = RoundedRectangle(cornerRadius: min(theme.geometry.cardRadius, 16), style: .continuous)
        return Button {
            settings.appTheme = theme
        } label: {
            VStack(spacing: 4) {
                tile
                    .fill(theme.color(.surface))
                    .frame(height: 58)
                    .overlay(alignment: .topLeading) {
                        // The style's title font, the way its cards set it.
                        Text(verbatim: "Aa")
                            .font(theme.typography.title(.title2))
                            .foregroundStyle(theme.color(.primaryText))
                            .padding(.leading, 9)
                            .padding(.top, 6)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // A small button: the style's accent, in its shape.
                        RoundedRectangle(cornerRadius: min(theme.geometry.controlRadius, 7), style: .continuous)
                            .fill(LinearGradient(colors: [theme.color(.fill), theme.color(.fillEnd)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 14)
                            .padding(7)
                    }
                    .overlay {
                        tile.strokeBorder(isSelected ? theme.color(.accent) : Theme.hairline,
                                          lineWidth: isSelected ? 2.5 : 1)
                    }
                Text(theme.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(theme.character)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(theme.name), \(theme.character)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.theme.\(theme.rawValue)")
    }

    /// The chosen style on a card: a title and a number in its font, an icon,
    /// a selected chip and the main button. Decorative — the app around it
    /// changes too.
    private var stylePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBadge(systemName: "figure.strengthtraining.traditional", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Push", comment: "Settings: style preview, a workout type"))
                        .displayFont(.headline)
                    Text(String(format: NSLocalizedString("%d min", comment: "Workout card: duration in minutes"), 45))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "8")
                        .displayNumberFont(size: 30)
                    Text("reps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            HStack(spacing: 10) {
                Chip(title: NSLocalizedString("Push", comment: "Settings: style preview, a workout type"),
                     systemImage: "arrow.up.right", isSelected: true)
                Spacer(minLength: 0)
                Label(NSLocalizedString("Start", comment: "Settings: style preview button"), systemImage: "play.fill")
                    .displayFont(.subheadline, weight: .semibold)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .controlBackground(.accent)
            }
        }
        .padding(12)
        // Inset: the row around it is in the card color already.
        .cardBackground(.inset)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.2), value: settings.appTheme)
    }

    private var bodyWeightSummary: String {
        if let healthBodyWeightKg {
            return String(format: NSLocalizedString("%@ · Apple Health", comment: "Settings: body weight read from Apple Health"),
                          settings.weightUnit.format(kilograms: healthBodyWeightKg))
        }
        return settings.bodyWeightKg.map { settings.weightUnit.format(kilograms: $0) }
            ?? NSLocalizedString("Not set", comment: "Settings: no body weight")
    }

    private func runPing() async {
        pingInFlight = true
        pingResult = "Sending…"
        let result = await watchConnectivity.pingWatch()
        switch result {
        case .success(let rtt):
            pingResult = String(format: "%.0f ms", rtt * 1000)
        case .failure(let error):
            pingResult = "Failed: \(error.localizedDescription)"
        }
        pingInFlight = false
    }
}

// MARK: - Health disclaimer

/// In-app health/fitness disclaimer, mirroring the website's disclaimer page.
struct HealthDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(NSLocalizedString("TrainingLab is not a medical device and does not provide medical advice. Its readiness score, recovery estimate, difficulty prediction and workout suggestions are informational fitness guidance only.", comment: "Disclaimer intro"))
                        .font(.callout)

                    disclaimerBlock(
                        NSLocalizedString("Estimates, not measurements", comment: "Disclaimer heading"),
                        NSLocalizedString("Readiness and recovery are calculated from signals like heart-rate variability, resting heart rate, sleep and training load. These signals are noisy and vary between individuals, so the results are approximate indicators — not clinical measurements — and may be inaccurate.", comment: "Disclaimer body"))

                    disclaimerBlock(
                        NSLocalizedString("Consult a professional", comment: "Disclaimer heading"),
                        NSLocalizedString("Consult your physician before starting any exercise program, especially if you are pregnant, have a heart condition, an injury, or another medical concern. Stop and seek medical attention if you feel pain, dizziness or shortness of breath.", comment: "Disclaimer body"))

                    disclaimerBlock(
                        NSLocalizedString("Assumption of risk", comment: "Disclaimer heading"),
                        NSLocalizedString("Exercise carries inherent risks. You use TrainingLab at your own risk. To the fullest extent permitted by law, the provider is not liable for injury or damage arising from use of the app.", comment: "Disclaimer body"))
                }
                .padding()
            }
            .pageTint()
            .navigationTitle(NSLocalizedString("Disclaimer", comment: "Disclaimer screen title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func disclaimerBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}

// MARK: - Export

/// A file to hand to the share sheet.
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }

    /// The whole workout history as CSV, written to a temporary file.
    @MainActor
    static func history(context: ModelContext) -> ExportFile? {
        let finished = (try? context.fetch(FetchDescriptor<FinishedWorkout>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let names = Dictionary(exercises.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let sessions = finished.map { workout in
            // In the session's order, then anything logged outside it.
            var ids = workout.exercisesSequenceID
            ids += workout.setWeights.keys.filter { !ids.contains($0) }.sorted()
            var seen = Set<String>()
            let ordered = ids.filter { seen.insert($0).inserted }
            return HistoryCSV.Session(
                name: workout.name,
                start: workout.startDate,
                end: workout.endDate,
                activity: HKWorkoutActivityType(rawValue: UInt(workout.workoutType))?.name ?? "",
                calories: workout.caloriesBurned,
                note: workout.loggingDetails.sessionNote,
                exercises: ordered.map { (id: $0, name: names[$0] ?? $0) },
                setWeights: workout.setWeights,
                setReps: workout.setReps,
                log: workout.loggingDetails)
        }
        let csv = HistoryCSV.make(sessions, unit: SettingsManager.shared.weightUnit)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TrainingLab history.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return ExportFile(url: url)
        } catch {
            appLog("History export failed: \(error)")
            return nil
        }
    }
}

/// The system share sheet: AirDrop, Files, Mail, other apps.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
