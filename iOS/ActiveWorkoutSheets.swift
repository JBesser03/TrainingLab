//
//  ActiveWorkoutSheets.swift
//  Workout App (iOS)
//
//  The sheets the strength flow of `ActiveWorkoutView` opens: the session's
//  exercise list (jump, reorder, swap, remove, add), an exercise's last
//  sessions with its estimated 1RM, a note for the current exercise and the
//  plates for a barbell. Changes made here apply to the session only — the
//  saved workout stays as it was. Also the notification that ends a rest
//  while the phone is locked.
//

import SwiftUI
import UserNotifications

// MARK: - Swap suggestions

enum SwapSuggestions {

    private static let catalogByID = Dictionary(GymExerciseCatalog.all.map { ($0.id, $0) },
                                                uniquingKeysWith: { first, _ in first })

    /// Exercises that can stand in for `exercise`: the same movement pattern
    /// first (a built-in exercise's catalog entry knows it), then the same
    /// muscle group — preferring ones the user's equipment allows. Exercises
    /// in `excluded` (already in the session) aren't offered.
    static func candidates(for exercise: Exercise, library: [Exercise],
                           availableEquipment: Set<Int>, excluded: Set<String>, limit: Int = 6) -> [Exercise] {
        let pattern = catalogByID[exercise.id]?.pattern
        let pool = library.filter { $0.id != exercise.id && !excluded.contains($0.id)
            && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        func rank(_ candidate: Exercise) -> Int? {
            let samePattern = pattern != nil && catalogByID[candidate.id]?.pattern == pattern
            let sameMuscle = candidate.muscleGroup == exercise.muscleGroup
            guard samePattern || (pattern == nil && sameMuscle) else { return nil }
            let fitsEquipment = Set(candidate.equipment).isSubset(of: availableEquipment)
            return (samePattern ? 0 : 2) + (fitsEquipment ? 0 : 1)
        }

        let ranked: [(exercise: Exercise, rank: Int)] = pool.compactMap { candidate in
            guard let value = rank(candidate) else { return nil }
            return (candidate, value)
        }
        let sorted = ranked.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.exercise.displayName.localizedStandardCompare(rhs.exercise.displayName) == .orderedAscending
        }
        return sorted.prefix(limit).map(\.exercise)
    }
}

// MARK: - Session overview

/// One exercise of the session as the overview lists it.
struct SessionOverviewRow: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let done: Int
    let planned: Int
    let isCurrent: Bool
    let isSkipped: Bool
    /// Any set logged — then it can't be swapped or removed any more.
    let hasLoggedSets: Bool
    let supersetGroup: Int?
}

struct SessionOverviewSheet: View {

    let rows: [SessionOverviewRow]
    let onJump: (Int) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onRemove: (Int) -> Void
    let swapCandidates: (Int) -> [Exercise]
    let onSwap: (Int, Exercise) -> Void
    let onAdd: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var swapIndex: Int?
    @State private var showAddPicker = false

    var body: some View {
        NavigationStack {
            StyledList {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onJump(index)
                            dismiss()
                        } label: {
                            rowLabel(row, index: index)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !row.hasLoggedSets {
                                if rows.count > 1 {
                                    Button(role: .destructive) {
                                        onRemove(index)
                                    } label: {
                                        Label(NSLocalizedString("Remove", comment: "Session overview: remove an exercise"), systemImage: "trash")
                                    }
                                }
                                Button {
                                    swapIndex = index
                                } label: {
                                    Label(NSLocalizedString("Swap", comment: "Session overview: replace an exercise"),
                                          systemImage: "arrow.triangle.2.circlepath")
                                }
                                .tint(.blue)
                            }
                        }
                        .accessibilityIdentifier("sessionOverview.row.\(row.id)")
                    }
                    .onMove(perform: onMove)

                    Button {
                        showAddPicker = true
                    } label: {
                        Label(NSLocalizedString("Add exercise", comment: ""), systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text(NSLocalizedString("Tap an exercise to go to it. Swipe left to swap or remove one you haven't started. Changes apply to this session only.",
                                           comment: "Session overview: footer"))
                }
            }
            .navigationTitle(NSLocalizedString("Exercises", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .bold()
                }
            }
            .sheet(isPresented: Binding(get: { swapIndex != nil }, set: { if !$0 { swapIndex = nil } })) {
                if let index = swapIndex {
                    ExercisePickerView(mode: .single,
                                       title: String(format: NSLocalizedString("Swap %@", comment: "Session overview: picker title, e.g. 'Swap Bench Press'"),
                                                     rows[safe: index]?.name ?? ""),
                                       included: Set(rows.map(\.id)),
                                       suggestions: swapCandidates(index)) { picked in
                        if let exercise = picked.first { onSwap(index, exercise) }
                    }
                }
            }
            .sheet(isPresented: $showAddPicker) {
                ExercisePickerView(mode: .single,
                                   title: NSLocalizedString("Add exercise", comment: ""),
                                   included: Set(rows.map(\.id))) { picked in
                    if let exercise = picked.first { onAdd(exercise) }
                }
            }
        }
    }

    private func rowLabel(_ row: SessionOverviewRow, index: Int) -> some View {
        let linkedAbove = index > 0 && row.supersetGroup != nil && rows[index - 1].supersetGroup == row.supersetGroup
        let linkedBelow = row.supersetGroup != nil && rows[safe: index + 1]?.supersetGroup == row.supersetGroup
        return HStack(spacing: 12) {
            // A bar joining the members of a superset.
            Capsule()
                .fill(row.supersetGroup != nil ? Color.accentColor : Color.clear)
                .frame(width: 3)
                .padding(.top, linkedAbove ? -12 : 4)
                .padding(.bottom, linkedBelow ? -12 : 4)
            ExerciseSymbolImage(name: row.symbol)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(row.isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                Text(row.isSkipped
                     ? NSLocalizedString("Skipped", comment: "Session overview: exercise was skipped")
                     : String(format: NSLocalizedString("%d of %d sets", comment: "Session overview: sets done of planned"), row.done, row.planned))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.isCurrent {
                Text(NSLocalizedString("Now", comment: "Session overview: the current exercise"))
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            } else if !row.isSkipped && row.done >= row.planned {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Last sessions

struct LastSessionsSheet: View {

    let exerciseName: String
    let sessions: [WorkoutStats.ExerciseSession]
    let isBodyweight: Bool

    @Environment(\.dismiss) private var dismiss

    private var unit: WeightUnit { SettingsManager.shared.weightUnit }

    private var bestE1RM: Double? { sessions.compactMap(\.bestE1RM).max() }

    var body: some View {
        NavigationStack {
            StyledList {
                if let bestE1RM {
                    Section {
                        LabeledContent(NSLocalizedString("Estimated 1RM", comment: "Last sessions: best estimated one-rep max"),
                                       value: unit.format(kilograms: bestE1RM))
                    } footer: {
                        Text(NSLocalizedString("The weight you could lift once, estimated from your best working set (Epley).",
                                               comment: "Last sessions: what the estimated 1RM is"))
                    }
                }
                ForEach(sessions) { session in
                    Section {
                        Text(unit.formatSets(session.sets, bodyweight: isBodyweight))
                            .font(.subheadline.monospacedDigit())
                        if let e1RM = session.bestE1RM {
                            LabeledContent(NSLocalizedString("Estimated 1RM", comment: "Last sessions: best estimated one-rep max"),
                                           value: unit.format(kilograms: e1RM))
                                .font(.footnote)
                        }
                        if let note = session.note {
                            Label(note, systemImage: "note.text")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(session.date, format: .dateTime.weekday(.wide).day().month())
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Exercise note

struct ExerciseNoteSheet: View {

    let exerciseName: String
    /// Last session's note for the exercise, shown for reference.
    let previousNote: String?
    @Binding var note: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            StyledForm {
                Section {
                    TextField(NSLocalizedString("Seat height, grip, how it felt…", comment: "Exercise note: placeholder"),
                              text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                }
                if let previousNote {
                    Section(NSLocalizedString("Last time", comment: "Exercise note: last session's note")) {
                        Text(previousNote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .bold()
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Plates

/// The plates to load on each side of the bar for the set's weight.
struct PlateCalculatorSheet: View {

    let totalKg: Double

    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    private var unit: WeightUnit { settings.weightUnit }
    private var total: Double { unit.fromKilograms(totalKg) }
    private var bar: Double { unit.fromKilograms(settings.barbellWeightKg) }

    private var loading: (plates: [Double], remainder: Double) {
        PlateCalculator.perSide(total: total, bar: bar, plates: PlateCalculator.availablePlates(for: unit))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(unit.format(kilograms: totalKg))
                    .displayNumberFont(size: 44)

                if total <= bar {
                    Text(NSLocalizedString("Just the bar", comment: "Plate calculator: no plates needed"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        Text(NSLocalizedString("Each side", comment: "Plate calculator: plates per side of the bar"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(alignment: .center, spacing: 4) {
                            ForEach(Array(loading.plates.enumerated()), id: \.offset) { _, plate in
                                plateView(plate)
                            }
                            Capsule()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 36, height: 8)
                        }
                        Text(loading.plates.map(number).joined(separator: " + "))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("plates.list")
                        if loading.remainder > 0 {
                            Text(String(format: NSLocalizedString("%@ can't be made with standard plates", comment: "Plate calculator: weight left over"),
                                        "\(number(loading.remainder)) \(unit.abbreviation)"))
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                }

                Picker(NSLocalizedString("Bar", comment: "Plate calculator: weight of the barbell"), selection: $settings.barbellWeightKg) {
                    ForEach(PlateCalculator.barOptionsKg(for: unit, current: settings.barbellWeightKg), id: \.self) { kg in
                        Text(String(format: NSLocalizedString("%@ bar", comment: "Plate calculator: bar weight option, e.g. '20 kg bar'"),
                                    unit.format(kilograms: kg))).tag(kg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(NSLocalizedString("Plates", comment: "Active workout: open the plate calculator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// Taller for heavier plates, like on the bar.
    private func plateView(_ plate: Double) -> some View {
        let heaviest = PlateCalculator.availablePlates(for: unit).first ?? plate
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(0.35 + 0.65 * plate / heaviest))
            .frame(width: 12, height: 30 + 70 * plate / heaviest)
            .accessibilityHidden(true)
    }
}

// MARK: - Rest notification

/// Ends a rest with a notification while the phone is locked or another app
/// is open. Not while the workout is on screen: the timer there does it.
enum RestNotification {

    private static let identifier = "restTimer"

    static func schedule(at end: Date, next exerciseName: String?) {
        let seconds = end.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Rest is over", comment: "Rest timer notification title")
        if let exerciseName {
            content.body = String(format: NSLocalizedString("Next: %@", comment: "Rest timer notification: the exercise to do now"), exerciseName)
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Asked when the rest timer is switched on, so the first locked rest
    /// isn't silent. The system asks only once.
    static func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            appLog("Rest timer: notification permission request failed: \(error)")
        }
    }
}
