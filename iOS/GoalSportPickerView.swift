//
//  GoalSportPickerView.swift
//  Workout App (iOS)
//
//  Picking what a new weekly goal tracks: a sport from the catalog (popular
//  ones first, then every HealthKit activity type the app offers) or a named
//  group of sports (`GoalGroupEditorView`). Everything here maps to activity
//  types, so progress is counted automatically — there is deliberately no
//  free-text sport, which nothing could count.
//

import SwiftUI
import HealthKit

struct GoalSportPickerView: View {

    /// Ids of goals that already exist; those sports aren't offered again.
    let excluded: Set<String>
    let onPick: (GoalCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showGroupEditor = false

    private var available: [GoalCategory] {
        GoalCategory.allSports.filter { !excluded.contains($0.id) }
    }

    private var popular: [GoalCategory] {
        GoalCategory.featured.filter { !excluded.contains($0.id) }
    }

    /// Everything not already listed under Popular.
    private var others: [GoalCategory] {
        let popularIDs = Set(GoalCategory.featured.map(\.id))
        return available.filter { !popularIDs.contains($0.id) }
    }

    private var matches: [GoalCategory] {
        available.filter { $0.displayName.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            StyledList {
                if search.isEmpty {
                    Section {
                        Button {
                            showGroupEditor = true
                        } label: {
                            Label(NSLocalizedString("New group", comment: "Goal picker: create a group of sports"),
                                  systemImage: "square.stack.3d.up.fill")
                        }
                    } footer: {
                        Text(NSLocalizedString("Several sports in one goal, e.g. running, cycling and swimming as “Cardio”.",
                                               comment: "Goal picker: what a group is"))
                    }
                    if !popular.isEmpty {
                        Section(NSLocalizedString("Popular", comment: "Goal picker: featured sports")) {
                            sportRows(popular)
                        }
                    }
                    Section(NSLocalizedString("All sports", comment: "Goal picker: every sport")) {
                        sportRows(others)
                    }
                } else {
                    sportRows(matches)
                }
            }
            .searchable(text: $search, prompt: Text(NSLocalizedString("Search sports", comment: "Goal picker: search prompt")))
            .navigationTitle(NSLocalizedString("Add goal", comment: "Weekly goals: add a goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showGroupEditor) {
                GoalGroupEditorView(group: nil) { group in
                    onPick(group)
                    dismiss()
                }
            }
        }
    }

    private func sportRows(_ sports: [GoalCategory]) -> some View {
        ForEach(sports) { sport in
            Button {
                onPick(sport)
                dismiss()
            } label: {
                SportLabel(sport: sport)
            }
            .tint(.primary)
        }
    }
}

/// Name and settings of a group of sports counted as one goal. `group` nil
/// creates a new one.
struct GoalGroupEditorView: View {

    let group: GoalCategory?
    let onSave: (GoalCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// Ids of the picked catalog sports, in the order they were picked — the
    /// first one gives the group its symbol.
    @State private var selected: [String]

    init(group: GoalCategory?, onSave: @escaping (GoalCategory) -> Void) {
        self.group = group
        self.onSave = onSave
        _name = State(initialValue: group?.customName ?? "")
        _selected = State(initialValue: group?.groupSports.map(\.id) ?? [])
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var popular: [GoalCategory] { GoalCategory.featured }

    private var others: [GoalCategory] {
        let popularIDs = Set(popular.map(\.id))
        return GoalCategory.allSports.filter { !popularIDs.contains($0.id) }
    }

    var body: some View {
        StyledForm {
            Section {
                TextField(NSLocalizedString("Group name", comment: "Goal group editor: name field"), text: $name)
            }
            Section(NSLocalizedString("Popular", comment: "Goal picker: featured sports")) {
                toggleRows(popular)
            }
            Section(NSLocalizedString("All sports", comment: "Goal picker: every sport")) {
                toggleRows(others)
            }
        }
        .navigationTitle(group == nil
                         ? NSLocalizedString("New group", comment: "Goal picker: create a group of sports")
                         : (group?.customName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if group != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(NSLocalizedString("Save", comment: "")) { save() }
                    .bold()
                    .disabled(trimmedName.isEmpty || selected.isEmpty)
            }
        }
    }

    private func toggleRows(_ sports: [GoalCategory]) -> some View {
        ForEach(sports) { sport in
            Button {
                if let index = selected.firstIndex(of: sport.id) {
                    selected.remove(at: index)
                } else {
                    selected.append(sport.id)
                }
            } label: {
                HStack {
                    SportLabel(sport: sport)
                    Spacer()
                    if selected.contains(sport.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                            .fontWeight(.semibold)
                    }
                }
            }
            .tint(.primary)
        }
    }

    private func save() {
        let byID = Dictionary(uniqueKeysWithValues: GoalCategory.allSports.map { ($0.id, $0) })
        var types: [Int] = []
        for sport in selected.compactMap({ byID[$0] }) {
            types += sport.activityTypes.filter { !types.contains($0) }
        }
        onSave(GoalCategory(id: group?.id ?? "group.\(UUID().uuidString)",
                            customName: trimmedName,
                            activityTypes: types))
        dismiss()
    }
}

private struct SportLabel: View {
    let sport: GoalCategory

    var body: some View {
        Label {
            Text(sport.displayName)
        } icon: {
            Image(systemName: sport.symbolName)
                .foregroundStyle(Theme.accent)
        }
    }
}
