//
//  WorkoutIntelligenceView.swift
//  TrainingLab (iOS)
//
//  Foundation Models coaching layer shared by the intelligence features
//  surfaced on the "For You" tab (see ForYouView, ForYouComponents):
//  a natural-language title/summary for a `PersonalizedWorkoutPlan`, with a
//  deterministic fallback so the feature works on every device.
//
//  The model only *phrases* facts the deterministic engine already computed
//  (WorkoutIntelligence.swift); it never decides anything.
//

import Foundation
import FoundationModels

// MARK: - Availability

/// The single check every Apple Intelligence feature goes through, so the
/// fallbacks can be exercised on hardware that *does* have it: in DEBUG,
/// launch with `-SimulateNoAppleIntelligence YES` or use the toggle in For You →
/// Debug to behave like an iPhone without Apple Intelligence.
enum AppleIntelligence {
    #if DEBUG
    static let simulateUnavailableKey = "SimulateNoAppleIntelligence"
    #endif

    static var isAvailable: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: simulateUnavailableKey) { return false }
        #endif
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Available *and* able to answer in the user's language.
    static var isAvailableForUserLanguage: Bool {
        isAvailable && SystemLanguageModel.default.supportsLocale()
    }
}

// MARK: - Prewarmed sessions

/// Keeps one prewarmed `LanguageModelSession` ready so the next request
/// doesn't pay the model-load cost on the user's tap. Every `take()` hands out
/// a session with an empty transcript — reusing one would let earlier requests
/// leak into later answers and slowly fill the context window.
@MainActor
final class PreparedLanguageModelSession {
    private let makeInstructions: () -> Instructions
    private var next: LanguageModelSession?

    init(instructions: @escaping () -> Instructions) {
        self.makeInstructions = instructions
    }

    /// Loads the model and the instructions prefix ahead of time. Cheap to call
    /// repeatedly; does nothing while a prepared session is waiting.
    func prewarm() {
        guard next == nil, AppleIntelligence.isAvailable else { return }
        let session = LanguageModelSession(instructions: makeInstructions())
        session.prewarm()
        next = session
    }

    /// A fresh session — the prewarmed one if it's ready.
    func take() -> LanguageModelSession {
        defer { next = nil }
        return next ?? LanguageModelSession(instructions: makeInstructions())
    }
}

/// English name of the user's language ("German"), for telling the model
/// which language to answer in. It otherwise answers in the language of the
/// instructions and facts, which isn't reliably the user's.
func modelResponseLanguageName(locale: Locale = .current) -> String {
    let code = locale.language.languageCode?.identifier ?? "en"
    return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
}

// MARK: - Foundation Models coach

/// A short, friendly narrative for the generated session. Produced by the
/// on-device language model when Apple Intelligence is available.
struct CoachNarrative: Equatable {
    var title: String
    var summary: String
}

@Generable(description: "An encouraging summary of a single tailored gym workout")
private struct GeneratedCoachNote {
    @Guide(description: "A short motivating workout title, at most 4 words, no numbers")
    var title: String
    @Guide(description: "One or two encouraging sentences explaining why this session fits the athlete today, based on the most important fact")
    var summary: String
}

/// Wraps Foundation Models with availability handling. `narrative(...)` never
/// throws to the caller — on any failure, when the model is unavailable, or
/// when the output doesn't stick to the facts, it returns a deterministic
/// fallback built from the same facts.
@MainActor
enum WorkoutCoach {

    private static let sessions = PreparedLanguageModelSession {
        Instructions("""
        You are a concise, encouraging strength coach. You get facts about one \
        workout the app built for the person today. Write a short title and one \
        or two sentences on why this session fits them today. Base it on the \
        most important fact — usually the biggest recovery factor or how long \
        it has been since these muscles were trained.
        Rules: use only the given facts. Never add numbers, exercises or health \
        claims that aren't in the facts. If the facts say the data is limited, \
        don't sound certain. No medical advice.
        Write the title and summary in \(modelResponseLanguageName()).
        """)
    }

    /// Loads the model before the first narrative is needed.
    static func prewarm() {
        guard AppleIntelligence.isAvailableForUserLanguage else { return }
        sessions.prewarm()
    }

    static func fallback(for plan: PersonalizedWorkoutPlan) -> CoachNarrative {
        CoachNarrative(title: plan.split.displayName, summary: plan.rationale)
    }

    static func narrative(for plan: PersonalizedWorkoutPlan) async -> CoachNarrative {
        let fallback = fallback(for: plan)
        // An unsupported language would produce English (or an error) for a
        // user reading everything else in their own language.
        guard AppleIntelligence.isAvailableForUserLanguage else { return fallback }

        let facts = facts(for: plan)
        let session = sessions.take()
        defer { sessions.prewarm() }

        do {
            // Lower temperature: this is a summary of given facts, not
            // creative writing, and it keeps the model from embellishing.
            let response = try await session.respond(to: facts, generating: GeneratedCoachNote.self,
                                                     options: GenerationOptions(temperature: 0.5))
            let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleOK = !title.isEmpty && title.count <= 40 && usesOnlyKnownNumbers(title, facts: facts)
            let summaryOK = !summary.isEmpty && usesOnlyKnownNumbers(summary, facts: facts)
            return CoachNarrative(title: titleOK ? title : fallback.title,
                                  summary: summaryOK ? summary : fallback.summary)
        } catch {
            appLog("Coach narrative failed: \(error)")
            return fallback
        }
    }

    /// Everything the deterministic engine knows about why this session was
    /// picked, in the user's language (labels and details are localized), so
    /// the narrative can give a real reason instead of generic encouragement.
    static func facts(for plan: PersonalizedWorkoutPlan) -> String {
        let recovery = plan.recovery
        var lines: [String] = []
        lines.append("Workout: \(plan.split.displayName)")
        if plan.isUserChosenSplit, let recommended = plan.recommendedSplit {
            lines.append("Workout type: chosen by the user (the recommendation was \(recommended.displayName))")
        }
        lines.append("Exercises: " + plan.exercises.map { NSLocalizedString($0.name, comment: "Gym exercise name") }
            .joined(separator: ", "))
        lines.append("Recovery score: \(recovery.score)/100 (\(recovery.band.title))")
        if recovery.signals.isEmpty {
            lines.append("Recovery data: none — the score is only a default estimate")
        } else if recovery.isLowConfidence {
            lines.append("Recovery data: limited")
        }
        let topFactors = recovery.factors.sorted { abs($0.impact) > abs($1.impact) }.prefix(3)
        for factor in topFactors {
            let sign = factor.impact >= 0 ? "+" : "−"
            lines.append("Recovery factor: \(factor.label) \(sign)\(Int(abs(factor.impact).rounded())) points (\(factor.detail))")
        }
        if let hours = plan.hoursSinceTrained {
            let days = Int((hours / 24).rounded(.down))
            lines.append(days >= 1
                         ? "These muscles were last trained \(days) day\(days == 1 ? "" : "s") ago"
                         : "These muscles were trained within the last day")
        } else {
            lines.append("These muscles haven't been trained recently")
        }
        lines.append("Predicted difficulty: \(plan.prediction.label) — \(plan.prediction.rationale)")
        return lines.joined(separator: "\n")
    }

    /// True when every number in `text` also appears in `facts` — a cheap
    /// guard against the model inventing figures ("burns 500 kcal").
    /// Decimal commas are normalized so "7,9" in German matches "7.9".
    static func usesOnlyKnownNumbers(_ text: String, facts: String) -> Bool {
        let known = Set(numbers(in: facts))
        return numbers(in: text).allSatisfy(known.contains)
    }

    private static func numbers(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return [] }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }
}
