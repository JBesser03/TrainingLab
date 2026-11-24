//
//  WeightUnit.swift
//  TrainingLab
//
//  The user-facing unit for entering and displaying exercise weights. Weights are
//  always *stored* in kilograms; this type only converts and formats at the UI
//  boundary, so switching units never rewrites any persisted data.
//

import Foundation

enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    /// Exact kilograms-per-pound factor (1 kg = 2.2046226218 lbs).
    private static let poundsPerKilogram = 2.2046226218

    /// Localized long name for pickers/settings.
    var displayName: String {
        switch self {
        case .kilograms: return NSLocalizedString("Kilograms", comment: "Weight unit")
        case .pounds:    return NSLocalizedString("Pounds", comment: "Weight unit")
        }
    }

    /// Short unit label shown next to a value ("kg" / "lbs").
    var abbreviation: String {
        switch self {
        case .kilograms: return NSLocalizedString("kg", comment: "Weight unit abbreviation")
        case .pounds:    return NSLocalizedString("lbs", comment: "Weight unit abbreviation")
        }
    }

    /// Converts a value the user typed in this unit into kilograms for storage.
    func toKilograms(_ displayValue: Double) -> Double {
        switch self {
        case .kilograms: return displayValue
        case .pounds:    return displayValue / Self.poundsPerKilogram
        }
    }

    /// Converts a stored kilogram value into this unit for display/entry.
    func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: return kilograms
        case .pounds:    return kilograms * Self.poundsPerKilogram
        }
    }

    /// A display string for a stored kilogram value, e.g. "60 kg" / "132 lbs".
    /// Drops the decimal for whole numbers and keeps one place otherwise.
    /// The bare display number for a stored kilogram value (no unit). Drops the
    /// decimal for whole numbers and keeps one place otherwise.
    func displayNumber(kilograms: Double) -> String {
        let value = fromKilograms(kilograms)
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    /// A display string for a stored kilogram value, e.g. "60 kg" / "132 lbs".
    func format(kilograms: Double) -> String {
        "\(displayNumber(kilograms: kilograms)) \(abbreviation)"
    }

    /// A display string for a series of per-set weights, e.g. "60 · 65 · 65 kg".
    /// Returns an empty string when there are no values.
    func format(kilogramsList values: [Double]) -> String {
        guard !values.isEmpty else { return "" }
        let numbers = values.map { displayNumber(kilograms: $0) }
        return numbers.joined(separator: " · ") + " " + abbreviation
    }

    /// A single set's display combining weight and reps, e.g. "60 kg × 8".
    /// Handles the four cases: weighted+reps, weighted only, bodyweight reps, none.
    func formatSet(kilograms: Double, reps: Int) -> String {
        let hasWeight = kilograms > 0
        let hasReps = reps > 0
        switch (hasWeight, hasReps) {
        case (true, true):  return "\(format(kilograms: kilograms)) × \(reps)"
        case (true, false): return format(kilograms: kilograms)
        case (false, true): return String(format: NSLocalizedString("%d reps", comment: ""), reps)
        case (false, false): return ""
        }
    }

    /// A display string for a full set list, e.g. "60 kg × 8 · 65 kg × 8".
    /// `reps` is index-aligned with `kilograms`; either may be shorter (older
    /// records logged weight only → reps default to 0). Empty when nothing logged.
    func formatSets(kilograms: [Double], reps: [Int]) -> String {
        let count = max(kilograms.count, reps.count)
        guard count > 0 else { return "" }
        var parts: [String] = []
        for i in 0..<count {
            let kg = i < kilograms.count ? kilograms[i] : 0
            let r = i < reps.count ? reps[i] : 0
            let s = formatSet(kilograms: kg, reps: r)
            if !s.isEmpty { parts.append(s) }
        }
        return parts.joined(separator: " · ")
    }

    /// One set with what else was logged: "W" before a warm-up, "D" before a
    /// drop set, "(RIR 2)" after a rated set, "+10 kg" for weight added to a
    /// bodyweight exercise, and the hold time of a timed set.
    func formatSet(_ set: WorkoutStats.LoggedSet, bodyweight: Bool = false) -> String {
        var text: String
        if bodyweight, set.kg > 0 {
            text = "+" + formatSet(kilograms: set.kg, reps: set.reps)
        } else {
            text = formatSet(kilograms: set.kg, reps: set.reps)
        }
        // A timed set: how long it was held, after any weight — "+10 kg · 1:00".
        if let seconds = set.detail.seconds, seconds > 0 {
            let held = Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
            text = text.isEmpty ? held : text + " · " + held
        }
        guard !text.isEmpty else { return "" }
        switch set.detail.kind {
        case .warmup:  text = NSLocalizedString("W", comment: "Set marker: warm-up set, before the weight") + " " + text
        case .drop:    text = NSLocalizedString("D", comment: "Set marker: drop set, before the weight") + " " + text
        case .working: break
        }
        if let rir = set.detail.repsInReserve {
            text += " (" + String(format: NSLocalizedString("RIR %d", comment: "Set marker: reps in reserve"), rir) + ")"
        }
        return text
    }

    /// `formatSet(_:bodyweight:)` for a list, e.g. "W 40 kg × 10 · 80 kg × 8 (RIR 2)".
    func formatSets(_ sets: [WorkoutStats.LoggedSet], bodyweight: Bool = false) -> String {
        sets.map { formatSet($0, bodyweight: bodyweight) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
