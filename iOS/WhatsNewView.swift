//
//  WhatsNewView.swift
//  Workout App (iOS)
//
//  One-time "What's New" sheet shown after an update. It remembers the version
//  it was last shown for, so each release's sheet appears once. Fresh installs
//  skip it (`firstLaunch` marks it seen): a new user has nothing to compare to.
//

import SwiftUI

@MainActor
enum WhatsNew {
    /// Bump together with `items` to show the sheet again after a release.
    static let version = "1.3"

    private static let seenKey = "whatsNewSeenVersion"

    static var shouldShow: Bool {
        #if DEBUG
        // UI tests would otherwise find this sheet over every screen.
        if ProcessInfo.processInfo.arguments.contains("-UITestSkipWhatsNew") { return false }
        #endif
        return UserDefaults.standard.string(forKey: seenKey) != version
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: seenKey)
    }

    struct Item: Identifiable {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var id: String { symbol }
    }

    static let items: [Item] = [
        Item(symbol: "paintpalette",
             title: "A new look",
             detail: "Six styles with their own colors, fonts and shapes, subtle or vivid color, and a matching app icon — in Settings → Appearance."),
        Item(symbol: "figure.strengthtraining.traditional",
             title: "A clearer workout screen",
             detail: "Large weight and reps controls, your sets at a glance and what comes next, with a tap of the Taptic Engine for every set."),
        Item(symbol: "list.bullet.clipboard",
             title: "Log it your way",
             detail: "Sets and reps for each exercise, supersets, warm-up and drop sets, reps left and notes. Swap, add or reorder exercises during a workout."),
        Item(symbol: "timer",
             title: "Rest timer",
             detail: "Starts after each set, also on your Lock Screen and Apple Watch."),
        Item(symbol: "chart.line.uptrend.xyaxis",
             title: "Your progress",
             detail: "Every workout ends with your results and records. Progress shows your best weight or estimated one-rep max over time."),
        Item(symbol: "square.grid.2x2",
             title: "Weekly goals widget",
             detail: "This week's goals on your Home Screen and Lock Screen."),
    ]
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 6) {
                        Text("What's New")
                            .font(.largeTitle.bold())
                        Text(String(format: NSLocalizedString("Version %@", comment: "What's New: version subtitle"),
                                    WhatsNew.version))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.symbol)
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 16)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
        .pageTint()
    }
}

#Preview {
    WhatsNewView()
}
