//
//  NaturalLanguageWorkoutView.swift
//  TrainingLab (iOS)
//
//  "Describe a workout" — the user types a request in plain language
//  ("45-min upper body, dumbbells only, medium"). When Apple Intelligence is
//  available, Foundation Models parses it into a structured spec via guided
//  generation; otherwise a lightweight keyword parser handles it, so the
//  feature works on every device (and the Simulator). The parsed request is
//  then mapped deterministically onto the existing GymExerciseCatalog.
//

import SwiftUI
import SwiftData
import HealthKit
import FoundationModels

// MARK: - Plain parsed request (LLM- and keyword-independent)

enum NLFocus: CaseIterable {
    case push, pull, legs, fullBody, upperBody, core, cardio

    var muscleGroups: [Int] {
        switch self {
        case .push:      return [WorkoutCategory.chest.rawValue, WorkoutCategory.shoulders.rawValue, WorkoutCategory.arms.rawValue]
        case .pull:      return [WorkoutCategory.back.rawValue, WorkoutCategory.arms.rawValue]
        case .legs:      return [WorkoutCategory.legs.rawValue, WorkoutCategory.core.rawValue]
        case .fullBody:  return [WorkoutCategory.fullbody.rawValue, WorkoutCategory.chest.rawValue, WorkoutCategory.back.rawValue, WorkoutCategory.legs.rawValue, WorkoutCategory.core.rawValue]
        case .upperBody: return [WorkoutCategory.chest.rawValue, WorkoutCategory.back.rawValue, WorkoutCategory.shoulders.rawValue, WorkoutCategory.arms.rawValue, WorkoutCategory.upperbody.rawValue]
        case .core:      return [WorkoutCategory.core.rawValue]
        case .cardio:    return [WorkoutCategory.cardio.rawValue, WorkoutCategory.hiit.rawValue]
        }
    }
    var primaryMuscleGroup: Int { muscleGroups.first ?? WorkoutCategory.fullbody.rawValue }

    /// A concise, human-readable title used to name the generated workout,
    /// instead of echoing the user's raw prompt back at them.
    var displayName: String {
        switch self {
        case .push:      return NSLocalizedString("Push", comment: "NL workout focus name")
        case .pull:      return NSLocalizedString("Pull", comment: "NL workout focus name")
        case .legs:      return NSLocalizedString("Leg Day", comment: "NL workout focus name")
        case .fullBody:  return NSLocalizedString("Full Body", comment: "NL workout focus name")
        case .upperBody: return NSLocalizedString("Upper Body", comment: "NL workout focus name")
        case .core:      return NSLocalizedString("Core", comment: "NL workout focus name")
        case .cardio:    return NSLocalizedString("Cardio", comment: "NL workout focus name")
        }
    }
}

enum NLIntensity {
    case easy, moderate, hard
    var maxDifficulty: Int { self == .easy ? 1 : (self == .moderate ? 2 : 3) }
    var setLength: Double { self == .easy ? 2 : (self == .moderate ? 3 : 4) }
    /// The difficulty level the selection should aim *at* (not just cap at), so
    /// "hard" actually pulls in harder movements rather than the easiest allowed.
    var targetDifficulty: Int { self == .easy ? 1 : (self == .moderate ? 2 : 3) }

    /// The intensity to use when the user didn't ask for one.
    static func matching(_ band: RecoveryBand?) -> NLIntensity {
        band == .rest ? .easy : .moderate
    }
}

struct ParsedWorkoutRequest: Equatable {
    static let durationRange = 10...90

    var focus: NLFocus
    /// Specific muscle-group raw values the user named ("arm day", "chest and
    /// triceps"), in the order they named them. Empty = use `focus`.
    var targetMuscles: [Int] = []
    /// Nil when the user didn't say — filled from recovery by `resolved(for:)`
    /// rather than guessed by the parser.
    var durationMinutes: Int?
    var intensity: NLIntensity?
    var bodyweightOnly: Bool = false
    /// Muscle-group raw values the user explicitly asked to exclude
    /// (e.g. "upper body without arms").
    var excluded: Set<Int> = []
    /// `Equipment` raw values the user restricted the session to
    /// ("dumbbells only"). Empty = no restriction, use their gym equipment.
    var equipmentOnly: Set<Int> = []

    /// The muscle groups to train, in priority order.
    var targetGroups: [Int] {
        (targetMuscles.isEmpty ? focus.muscleGroups : targetMuscles).filter { !excluded.contains($0) }
    }

    /// The equipment the session may use. Named equipment wins over
    /// "bodyweight" ("at home, dumbbells only" means dumbbells), and a mat is
    /// always allowed — nobody means to rule it out by saying "dumbbells only".
    func allowedEquipment(available: Set<Int>) -> Set<Int> {
        if !equipmentOnly.isEmpty { return equipmentOnly.union([Equipment.exerciseMat.rawValue]) }
        if bodyweightOnly { return [] }
        return available
    }

    /// Duration and intensity with anything unstated filled in from today's
    /// recovery: a tired user asking for "leg day" gets a lighter, shorter one.
    func resolved(for band: RecoveryBand?) -> (durationMinutes: Int, intensity: NLIntensity) {
        (durationMinutes ?? (band == .rest ? 30 : 40), intensity ?? NLIntensity.matching(band))
    }

    var needsRecovery: Bool { durationMinutes == nil || intensity == nil }
}

/// Maps equipment words (English and German) to `Equipment` raw values.
/// Shared by the keyword parser and the Foundation Models mapping.
enum EquipmentWord {
    static let table: [(tokens: [String], equipment: [Equipment])] = [
        (["dumbbell", "kurzhantel"], [.dumbbells]),
        (["barbell", "langhantel"], [.barbells, .weightBench]),
        (["kettlebell"], [.kettlebells]),
        (["resistance band", "band", "bänder", "widerstandsband", "fitnessband", "theraband"], [.resistanceBands]),
        (["cable", "kabel", "kabelzug"], [.cableMaschine]),
        (["machine", "maschine"], [.cableMaschine, .legPressMaschine, .smithMaschine]),
        (["pull-up bar", "pullup bar", "pull up bar", "klimmzugstange"], [.pullUpBar])
    ]

    /// Words that make named equipment exclusive — "leg day with a barbell"
    /// names equipment without ruling the rest out.
    static let exclusiveWords: Set<String> = ["only", "just", "nur", "ausschließlich", "ausschliesslich"]

    static func restriction(in text: KeywordText) -> Set<Int> {
        guard !exclusiveWords.isDisjoint(with: text.words) else { return [] }
        return Set(table.filter { entry in entry.tokens.contains(where: text.has) }
            .flatMap { $0.equipment.map(\.rawValue) })
    }
}

/// Maps a spoken muscle-area word (English or German) to the catalog
/// muscle-group raw value(s). Shared by the keyword parser and the
/// Foundation Models mapping.
enum MuscleAreaWord {
    /// Ordered so `groups(for:)` and the keyword scan agree.
    static let table: [(tokens: [String], groups: [WorkoutCategory])] = [
        (["arm", "bicep", "bizeps", "tricep", "trizeps"], [.arms]),
        (["leg", "bein*", "quad", "glute", "hamstring", "gesäß", "po"], [.legs]),
        (["back", "rücken*", "ruecken*"], [.back]),
        (["chest", "brust*"], [.chest]),
        (["shoulder", "schulter*"], [.shoulders]),
        (["core", "ab", "abs", "bauch*", "rumpf*"], [.core]),
        (["cardio", "hiit", "ausdauer*"], [.cardio, .hiit])
    ]

    /// Groups for a single word (or a `WorkoutRequestSpec.MuscleArea` raw value).
    static func groups(for word: String) -> [Int] {
        table.first { $0.tokens.contains { KeywordText.word(word, matches: $0) } }?.groups.map(\.rawValue) ?? []
    }
}

/// Lower-cased request text split into words, with the matching rules the
/// keyword parser needs. Word-based, so "warm-up" doesn't match "arm" and
/// "backpack" doesn't match "back":
///  • a plain token matches the word itself plus common English/German
///    endings ("hart" → "hartes", "arm" → "arme", "dumbbell" → "dumbbells");
///  • a token ending in `*` is a stem for German compounds ("bein*" →
///    "Beintraining");
///  • a token with a space or hyphen matches as a phrase ("full body").
struct KeywordText {
    let text: String
    let words: [String]

    static let endings: Set<String> = ["", "s", "es", "e", "en", "er", "n", "ern"]

    init(_ raw: String) {
        text = raw.lowercased()
        words = text.split { !$0.isLetter }.map(String.init)
    }

    static func word(_ word: String, matches token: String) -> Bool {
        if token.hasSuffix("*") { return word.hasPrefix(token.dropLast()) }
        return word.hasPrefix(token) && endings.contains(String(word.dropFirst(token.count)))
    }

    /// Index of the first word matching `token`, or nil (0 for a phrase).
    func index(of token: String) -> Int? {
        if token.contains(" ") || token.contains("-") {
            return text.contains(token) ? 0 : nil
        }
        return words.firstIndex { Self.word($0, matches: token) }
    }

    func has(_ token: String) -> Bool { index(of: token) != nil }
    func hasAny(_ tokens: [String]) -> Bool { tokens.contains(where: has) }
}

// MARK: - Guided-generation spec (Apple Intelligence path)

@Generable(description: "A structured gym-workout request parsed from a free-text description")
struct WorkoutRequestSpec {
    @Guide(description: "The overall training focus. Use fullBody when no area is named.")
    var focus: Focus
    @Guide(description: "Every specific muscle area the person names to train, in the order named, e.g. [arms] for 'arm day', [chest, arms] for 'chest and triceps', [legs] for 'leg day'. Empty for split names like push, pull, upper body or full body.")
    var targetMuscles: [MuscleArea]
    @Guide(description: "Length in minutes, only if the person states one ('45 min', 'an hour', 'quick' = 20). Null if not stated. Never use numbers like '5x5' or '3 sets'.")
    var durationMinutes: Int?
    @Guide(description: "Intensity only if the person states or clearly implies one ('easy', 'recovery', 'heavy', 'brutal'). Null if not stated.")
    var intensity: Intensity?
    @Guide(description: "True only if the person wants bodyweight / no-equipment exercises, e.g. 'no equipment' or 'at home'")
    var bodyweightOnly: Bool
    @Guide(description: "Muscle areas the person explicitly wants to EXCLUDE, e.g. from 'without arms' or 'no legs'. Empty if none.")
    var exclude: [MuscleArea]
    @Guide(description: "Equipment the person restricts the workout to, e.g. from 'dumbbells only' or 'just kettlebells'. Empty unless they explicitly limit it.")
    var onlyEquipment: [EquipmentKind]

    @Generable enum EquipmentKind: String {
        case dumbbells, barbell, kettlebell, resistanceBands, cableMachine, machines, pullUpBar
    }
    @Generable enum Focus: String {
        case push, pull, legs, fullBody, upperBody, core, cardio
    }
    @Generable enum Intensity: String {
        case easy, moderate, hard
    }
    @Generable enum MuscleArea: String {
        case arms, legs, glutes, back, chest, shoulders, core, cardio
    }

    var parsed: ParsedWorkoutRequest {
        let f: NLFocus
        switch focus {
        case .push: f = .push
        case .pull: f = .pull
        case .legs: f = .legs
        case .fullBody: f = .fullBody
        case .upperBody: f = .upperBody
        case .core: f = .core
        case .cardio: f = .cardio
        }
        let i: NLIntensity? = intensity.map { $0 == .easy ? .easy : ($0 == .hard ? .hard : .moderate) }
        var targets: [Int] = []
        for group in targetMuscles.flatMap({ MuscleAreaWord.groups(for: $0.rawValue) }) where !targets.contains(group) {
            targets.append(group)
        }
        let excluded = Set(exclude.flatMap { MuscleAreaWord.groups(for: $0.rawValue) })
        let equipment: [Equipment] = onlyEquipment.flatMap { kind -> [Equipment] in
            switch kind {
            case .dumbbells:       return [.dumbbells]
            case .barbell:         return [.barbells, .weightBench]
            case .kettlebell:      return [.kettlebells]
            case .resistanceBands: return [.resistanceBands]
            case .cableMachine:    return [.cableMaschine]
            case .machines:        return [.cableMaschine, .legPressMaschine, .smithMaschine]
            case .pullUpBar:       return [.pullUpBar]
            }
        }
        let range = ParsedWorkoutRequest.durationRange
        return ParsedWorkoutRequest(focus: f,
                                    targetMuscles: targets,
                                    durationMinutes: durationMinutes.map { min(max($0, range.lowerBound), range.upperBound) },
                                    intensity: i,
                                    bodyweightOnly: bodyweightOnly,
                                    excluded: excluded,
                                    equipmentOnly: Set(equipment.map(\.rawValue)))
    }
}

// MARK: - Parser

/// Turns the user's text into a `ParsedWorkoutRequest`: Foundation Models
/// when Apple Intelligence is available, the keyword parser otherwise (or if
/// the model call fails).
@MainActor
final class WorkoutRequestParser {

    private let sessions = PreparedLanguageModelSession {
        Instructions("""
        You convert a person's gym workout request into a structured spec. \
        Record only what the person actually says: leave duration and \
        intensity empty when they aren't stated — the app fills them in from \
        the person's recovery. Requests may be in English or German.

        Examples:
        "45 min upper body, dumbbells only" → focus upperBody, duration 45, onlyEquipment [dumbbells]
        "arm day" → focus upperBody, targetMuscles [arms]
        "chest and triceps, heavy" → focus push, targetMuscles [chest, arms], intensity hard
        "quick core session at home" → focus core, targetMuscles [core], duration 20, bodyweightOnly true
        "5x5 legs" → focus legs, targetMuscles [legs]
        "Schultern und Arme, locker" → focus upperBody, targetMuscles [shoulders, arms], intensity easy
        "30 Minuten Ganzkörper ohne Geräte" → focus fullBody, duration 30, bodyweightOnly true
        """)
    }

    var isModelAvailable: Bool { AppleIntelligence.isAvailable }

    func prewarm() {
        guard isModelAvailable else { return }
        sessions.prewarm()
    }

    /// The parsed request, and whether the model (rather than the keyword
    /// fallback) produced it.
    func parse(_ text: String) async -> (request: ParsedWorkoutRequest, usedModel: Bool) {
        if let parsed = await parseWithModel(text) { return (parsed, true) }
        return (KeywordWorkoutParser.parse(text), false)
    }

    /// Nil when the model is unavailable or the call fails.
    func parseWithModel(_ text: String) async -> ParsedWorkoutRequest? {
        guard isModelAvailable else { return nil }
        let session = sessions.take()
        defer { sessions.prewarm() }
        do {
            // Greedy sampling: parsing should be deterministic — the same
            // words must always produce the same workout spec.
            let response = try await session.respond(to: text, generating: WorkoutRequestSpec.self,
                                                     options: GenerationOptions(samplingMode: .greedy))
            return response.content.parsed
        } catch {
            appLog("Workout request parsing failed: \(error)")
            return nil
        }
    }
}

// MARK: - Keyword fallback parser

/// Deterministic parser used when Apple Intelligence is unavailable (or the
/// model call fails) — which is every iPhone older than the 15 Pro, so it
/// understands English and German. Checked against the same evaluation
/// cases as the model (`WorkoutParserEvaluation`).
enum KeywordWorkoutParser {

    static let negations: Set<String> = ["without", "no", "not", "except", "excluding", "skip", "minus", "sans",
                                         "ohne", "kein", "keine", "keinen", "nicht", "außer", "ausser"]

    static func parse(_ raw: String) -> ParsedWorkoutRequest {
        let t = KeywordText(raw)

        let focus: NLFocus
        if t.hasAny(["cardio", "hiit", "conditioning", "sweat", "aerobic", "ausdauer*", "kondition*"]) {
            focus = .cardio
        } else if t.hasAny(["full body", "fullbody", "full-body", "ganzkörper*", "ganzkoerper*"]) {
            focus = .fullBody
        } else if t.hasAny(["upper", "oberkörper*", "oberkoerper*"]) {
            focus = .upperBody
        } else if t.hasAny(["push", "chest", "brust*"]) {
            focus = .push
        } else if t.hasAny(["pull", "back", "rücken*", "ruecken*"]) {
            focus = .pull
        } else if t.hasAny(["leg", "squat", "lower", "bein*", "unterkörper*", "unterkoerper*"]) {
            focus = .legs
        } else if t.hasAny(["core", "abs", "bauch*", "rumpf*"]) {
            focus = .core
        } else {
            focus = .fullBody
        }

        let intensity: NLIntensity?
        if t.hasAny(["hard", "intense", "heavy", "brutal", "hart", "intensiv", "schwer", "anstrengend"]) {
            intensity = .hard
        } else if t.hasAny(["easy", "light", "recovery", "gentle", "leicht", "locker", "einfach", "regeneration", "entspannt"]) {
            intensity = .easy
        } else if t.hasAny(["moderate", "medium", "mittel", "moderat"]) {
            intensity = .moderate
        } else {
            intensity = nil
        }

        let bodyweightOnly = t.hasAny(["no equipment", "without equipment", "bodyweight", "body weight", "at home", "home",
                                       "ohne geräte", "ohne equipment", "ohne ausrüstung", "eigengewicht", "zuhause", "zu hause"])

        // Muscle areas: negated mentions ("without arms", "ohne Bizeps") are
        // exclusions, the rest are targets, kept in the order they were named.
        var excluded: Set<Int> = []
        var mentions: [(index: Int, groups: [Int])] = []
        for (wordIndex, word) in t.words.enumerated() {
            let groups = MuscleAreaWord.groups(for: word)
            guard !groups.isEmpty else { continue }
            if wordIndex > 0, negations.contains(t.words[wordIndex - 1]) {
                excluded.formUnion(groups)
            } else {
                mentions.append((wordIndex, groups))
            }
        }
        var targets: [Int] = []
        for group in mentions.sorted(by: { $0.index < $1.index }).flatMap(\.groups)
        where !targets.contains(group) && !excluded.contains(group) {
            targets.append(group)
        }

        return ParsedWorkoutRequest(focus: focus,
                                    targetMuscles: targets,
                                    durationMinutes: duration(in: t),
                                    intensity: intensity,
                                    bodyweightOnly: bodyweightOnly,
                                    excluded: excluded,
                                    equipmentOnly: EquipmentWord.restriction(in: t))
    }

    /// Minutes from "45 min", "1.5 hours", "an hour", "eine Stunde", "halbe
    /// Stunde" or "quick"; a bare number only when it isn't a set/rep count
    /// ("5x5", "3 sets of 10"). Clamped to `ParsedWorkoutRequest.durationRange`.
    static func duration(in t: KeywordText) -> Int? {
        func clamped(_ minutes: Double) -> Int {
            let range = ParsedWorkoutRequest.durationRange
            return min(max(Int(minutes.rounded()), range.lowerBound), range.upperBound)
        }
        func firstMatch(_ pattern: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: t.text, range: NSRange(t.text.startIndex..., in: t.text)),
                  let range = Range(match.range(at: 1), in: t.text) else { return nil }
            return Double(t.text[range].replacingOccurrences(of: ",", with: "."))
        }

        if let hours = firstMatch(#"(\d+(?:[.,]\d+)?)\s*(?:h|hr|hrs|hour|hours|std|stunde|stunden)\b"#) {
            return clamped(hours * 60)
        }
        if let minutes = firstMatch(#"(\d+)\s*(?:m|min|mins|minute|minutes|minuten)\b"#) {
            return clamped(minutes)
        }
        if t.hasAny(["half an hour", "halbe stunde"]) { return 30 }
        if t.hasAny(["an hour", "one hour", "eine stunde"]) { return 60 }
        if let bare = firstMatch(#"(?<![\d.,x×])(?<!of\s)(?<!x\s)(\d{2,3})(?![\d.,]|\s*(?:x|×|reps?\b|sets?\b|sätze\b|wdh\b|kg\b|lbs?\b))"#) {
            return clamped(bare)
        }
        // No stem here: "kurz*" would read "Kurzhanteln" as "kurz".
        if t.hasAny(["quick", "short", "kurz", "schnell"]) { return 20 }
        return nil
    }
}

// MARK: - Draft (materialised only on save)

/// A fully-resolved plan that hasn't touched SwiftData yet. Materialised into
/// `Exercise`/`Workout` rows only when the user taps Save, so cancelling never
/// leaves orphaned records behind.
private struct NLWorkoutDraft {
    var name: String
    var muscleGroup: Int
    var setLength: Double
    var difficultyInt: Int
    var durationMinutes: Int
    var exercises: [GymExerciseDefinition]
}

// MARK: - View

struct NaturalLanguageWorkoutView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingExercises: [Exercise]
    @Query(sort: \FinishedWorkout.endDate, order: .reverse) private var finishedWorkouts: [FinishedWorkout]
    @StateObject private var settings = SettingsManager.shared

    @State private var parser = WorkoutRequestParser()
    /// The last parse, reused by "Try another variation" — same text, same
    /// (greedy) parse, so there's no reason to wait for the model again.
    @State private var lastParse: (text: String, request: ParsedWorkoutRequest, usedModel: Bool)?
    /// Loaded only when a request leaves duration or intensity unstated.
    @State private var recoveryBand: RecoveryBand?
    /// True when the current draft's duration or intensity came from recovery.
    @State private var matchedToRecovery = false

    @State private var text = ""
    /// Dropped on Generate so the keyboard doesn't cover the result.
    @FocusState private var isTextFocused: Bool
    @State private var isGenerating = false
    @State private var draft: NLWorkoutDraft?
    @State private var errorMessage: String?
    @State private var usedBasicParser = false
    /// Bumped on every generation so "Try another variation" surfaces a
    /// different-but-equally-suitable set of exercises for the same request.
    @State private var generationCount = 0

    private let gradient = Theme.accent

    private var modelAvailable: Bool { parser.isModelAvailable }

    private let examples = [
        NSLocalizedString("45 min upper body, dumbbells only", comment: "NL workout example prompt"),
        NSLocalizedString("quick core session at home", comment: "NL workout example prompt"),
        NSLocalizedString("hard leg day", comment: "NL workout example prompt"),
        NSLocalizedString("30 minute full body, no equipment", comment: "NL workout example prompt")
    ]

    var body: some View {
        NavigationStack {
            StyledForm {
                Section {
                    TextField(NSLocalizedString("e.g. 45 min upper body, dumbbells only", comment: "NL workout prompt"),
                              text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isTextFocused)
                        .onChange(of: text) { _, _ in
                            // Editing invalidates the current draft so the user
                            // can iterate and re-generate.
                            draft = nil
                            errorMessage = nil
                        }
                } header: {
                    Text(NSLocalizedString("Describe your workout", comment: ""))
                } footer: {
                    Text(modelAvailable
                         ? NSLocalizedString("On-device AI turns your description into a workout using your gym equipment.", comment: "")
                         : NSLocalizedString("Turns your description into a workout using your gym equipment.", comment: ""))
                }

                if draft == nil {
                    Section(NSLocalizedString("Examples", comment: "")) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { text = example }
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger)
                    }
                }

                if let draft {
                    Section {
                        Text(draft.name).font(.headline)
                        ForEach(draft.exercises, id: \.id) { ex in
                            HStack {
                                Text(NSLocalizedString(ex.name, comment: "Gym exercise name"))
                                Spacer()
                                Text(ex.repCount > 0
                                     ? String(format: NSLocalizedString("%d reps", comment: ""), ex.repCount)
                                     : NSLocalizedString("timed", comment: ""))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        Label(String(format: NSLocalizedString("%d exercises · about %d min", comment: ""), draft.exercises.count, draft.durationMinutes),
                              systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await generate() }
                        } label: {
                            Label(NSLocalizedString("Try another variation", comment: ""),
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isGenerating)
                    } header: {
                        Text(NSLocalizedString("Your workout", comment: ""))
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if matchedToRecovery {
                                Text(NSLocalizedString("What you didn't specify was matched to today's recovery.", comment: "NL workout: unstated duration/intensity came from recovery"))
                            }
                            if usedBasicParser {
                                Text(NSLocalizedString("Built with basic parsing (Apple Intelligence not available).", comment: ""))
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Describe a workout", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if draft == nil {
                        Button(NSLocalizedString("Generate", comment: "")) {
                            Task { await generate() }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    } else {
                        Button(NSLocalizedString("Save", comment: "")) { save() }
                            .bold()
                    }
                }
            }
            .task { parser.prewarm() }
            .overlay {
                if isGenerating {
                    ProgressView(NSLocalizedString("Building your workout…", comment: ""))
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: Generation

    private func generate() async {
        isTextFocused = false
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }

        // Parse the request — Apple Intelligence if available, else keyword parser.
        let request: ParsedWorkoutRequest
        if let lastParse, lastParse.text == text {
            request = lastParse.request
        } else {
            let result = await parser.parse(text)
            request = result.request
            usedBasicParser = !result.usedModel
            lastParse = (text, result.request, result.usedModel)
        }

        // Fill in what the user didn't say from today's recovery.
        if request.needsRecovery && recoveryBand == nil {
            let inputs = await RecoveryMetricsProvider().loadInputs(history: finishedWorkouts)
            recoveryBand = RecoveryEstimator.estimate(from: inputs).band
        }
        let resolved = request.resolved(for: recoveryBand)
        matchedToRecovery = request.needsRecovery && recoveryBand != nil

        // Named muscles (or the focus), minus exclusions ("without arms").
        let targetGroups = request.targetGroups
        guard !targetGroups.isEmpty else {
            errorMessage = NSLocalizedString("That leaves no muscle groups to train. Try removing an exclusion.", comment: "")
            return
        }

        let equipment = request.allowedEquipment(available: settings.availableGymEquipment)
        let pool = GymExerciseCatalog.exercises(forMuscleGroups: targetGroups,
                                                availableEquipment: equipment)
        guard pool.count >= 3 else {
            errorMessage = NSLocalizedString("Not enough exercises for that request with your equipment. Try a different focus or add equipment in the gym generator.", comment: "")
            return
        }

        let targetCount = max(3, min(resolved.durationMinutes / 6, 8))
        let picked = select(from: pool, muscleGroups: targetGroups,
                            count: targetCount,
                            targetDifficulty: resolved.intensity.targetDifficulty,
                            seed: generationCount)
        guard picked.count >= 3 else {
            errorMessage = NSLocalizedString("Couldn't assemble enough exercises. Try a broader focus.", comment: "")
            return
        }

        draft = NLWorkoutDraft(
            name: workoutName(for: request, durationMinutes: resolved.durationMinutes),
            muscleGroup: targetGroups.first ?? request.focus.primaryMuscleGroup,
            setLength: resolved.intensity.setLength,
            difficultyInt: resolved.intensity.maxDifficulty,
            durationMinutes: resolved.durationMinutes,
            exercises: picked)

        // Advance the seed so the next "Try another variation" rotates the picks.
        generationCount += 1
    }

    /// Picks `count` exercises that (a) sit as close as possible to the requested
    /// intensity, (b) are balanced across the focus's muscle groups (round-robin
    /// rather than one-per-group), and (c) vary between regenerations via `seed`.
    private func select(from pool: [GymExerciseDefinition], muscleGroups: [Int],
                        count: Int, targetDifficulty: Int, seed: Int) -> [GymExerciseDefinition] {
        let grouped = Dictionary(grouping: pool, by: { $0.muscleGroup })

        // One ranked queue per targeted group: closest difficulty to the target
        // first, ties broken by id for stability, then rotated by `seed` so a
        // different (but equally suitable) exercise leads each regeneration.
        var queues: [[GymExerciseDefinition]] = muscleGroups.compactMap { group in
            guard let defs = grouped[group], !defs.isEmpty else { return nil }
            let ranked = defs.sorted {
                let d0 = abs($0.difficultyInt - targetDifficulty)
                let d1 = abs($1.difficultyInt - targetDifficulty)
                return d0 != d1 ? d0 < d1 : $0.id < $1.id
            }
            let offset = seed % ranked.count
            return Array(ranked[offset...] + ranked[..<offset])
        }

        // Round-robin across the groups so a bigger session gets balanced volume
        // (e.g. 2 chest + 2 back) instead of one movement per group plus filler.
        var picked: [GymExerciseDefinition] = []
        var pickedIDs = Set<String>()
        while picked.count < count && queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where picked.count < count {
                guard !queues[i].isEmpty else { continue }
                let def = queues[i].removeFirst()
                if pickedIDs.insert(def.id).inserted { picked.append(def) }
            }
        }
        return picked
    }

    /// A tidy, human-readable title derived from what's trained and the
    /// duration (e.g. "Upper Body · 45 min", "Arms · 30 min") rather than
    /// echoing the raw prompt back.
    private func workoutName(for request: ParsedWorkoutRequest, durationMinutes: Int) -> String {
        let named = request.targetGroups.filter { $0 != WorkoutCategory.hiit.rawValue }
        let title = request.targetMuscles.isEmpty || named.isEmpty
            ? request.focus.displayName
            : ListFormatter.localizedString(byJoining: named.map(WorkoutCategory.getCategoryName(from:)))
        return String(format: NSLocalizedString("%@ · %d min", comment: "Generated workout name: focus and duration"),
                      title, durationMinutes)
    }

    // MARK: Save

    private func save() {
        guard let draft else { return }

        let entities: [Exercise] = draft.exercises.map {
            $0.materialize(in: modelContext, existing: existingExercises)
        }

        let workout = Workout(
            id: UUID().uuidString,
            infoText: NSLocalizedString("Created from your description.", comment: ""),
            isUserGenerated: true,
            isNew: true,
            muscleGroup: draft.muscleGroup,
            setLength: draft.setLength,
            straightSets: false,
            difficultyInt: draft.difficultyInt,
            name: uniqueName(draft.name),
            duration: draft.durationMinutes,
            exercisesSequenceID: entities.map { $0.id },
            finishedExercisesSequence: [],
            exercises: entities,
            plan: [],
            workoutActivityType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
            workoutSessionLocation: Int(HKWorkoutSessionLocationType.indoor.rawValue))
        workout.isSaved = true
        modelContext.insert(workout)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = NSLocalizedString("Couldn't save the workout.", comment: "")
        }
    }

    private func uniqueName(_ base: String) -> String {
        let existing = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
        var candidate = base
        var counter = 2
        while existing.contains(where: { $0.name == candidate }) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }
}
