//
//  Haptics.swift
//  Workout App (iOS)
//
//  The Taptic Engine's feedback, one name per kind of moment, so the app
//  feels the same wherever it happens: a light tap for a nudged value, a
//  firmer thump for a set, a crisp one for an exercise, a double knock when
//  the rest is over and the success pattern for a finished workout. iOS
//  mutes all of it when System Haptics is off in Settings → Sounds &
//  Haptics.
//

import UIKit

@MainActor
enum Haptics {
    /// A value nudged: weight, reps, sets, a hold or the rest.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// One option chosen among several: a chip, a rating, a menu, a tab.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Saved or unsaved — firmer when it's added.
    static func bookmark(saved: Bool) {
        UIImpactFeedbackGenerator(style: saved ? .medium : .light).impactOccurred()
    }

    /// A set logged, or a timed interval over.
    static func setDone() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// An exercise's last set logged: crisper than a set.
    static func exerciseDone() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
    }

    /// A workout or a timed set starting.
    static func start() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
    }

    /// The rest is over: two firm knocks, to feel without looking.
    static func restOver() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            generator.impactOccurred()
        }
    }

    /// A finished workout, a new record, a change saved for next time.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Ended without saving: soft, as nothing is kept.
    static func discard() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
