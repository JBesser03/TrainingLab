//
//  WorkoutParserEvaluation.swift
//  TrainingLab (iOS)
//
//  A fixed set of "Describe a workout" requests with the result each should
//  produce, used two ways:
//   • Unit tests run the keyword parser against every case on each build.
//   • The DEBUG-only evaluation screen (For You → Debug) runs the on-device
//     model against the same cases. The model can't run in unit tests or on
//     the Simulator, so this is how to measure a prompt or schema change on a
//     real device: run it before and after, and compare the scores.
//
//  Cases compare what the request *does* — which muscle groups get trained,
//  for how long, how hard, with what equipment — not how the parser got
//  there, so "arm day" parsed as focus upperBody or push both pass as long as
//  the targets are arms.
//

#if DEBUG
import SwiftUI

struct WorkoutParserEvalCase: Identifiable {
    let prompt: String
    let expected: ParsedWorkoutRequest
    var id: String { prompt }

    /// Every piece of equipment, so "no restriction" and "dumbbells only"
    /// produce different allowed sets.
    static let allEquipment = Set(Equipment.allCases.map(\.rawValue))

    /// The parts of a request that change the generated workout.
    struct Outcome: Equatable {
        let groups: Set<Int>
        let durationMinutes: Int?
        let intensity: NLIntensity?
        let equipment: Set<Int>

        init(_ request: ParsedWorkoutRequest) {
            groups = Set(request.targetGroups)
            durationMinutes = request.durationMinutes
            intensity = request.intensity
            equipment = request.allowedEquipment(available: WorkoutParserEvalCase.allEquipment)
        }
    }

    /// Field-by-field comparison; empty when the parse is fully correct.
    func mismatches(in actual: ParsedWorkoutRequest) -> [String] {
        let want = Outcome(expected), got = Outcome(actual)
        var out: [String] = []
        if want.groups != got.groups {
            out.append("muscles \(names(want.groups)) ≠ \(names(got.groups))")
        }
        if want.durationMinutes != got.durationMinutes {
            out.append("duration \(want.durationMinutes.map(String.init) ?? "–") ≠ \(got.durationMinutes.map(String.init) ?? "–")")
        }
        if want.intensity != got.intensity {
            out.append("intensity \(want.intensity.map { "\($0)" } ?? "–") ≠ \(got.intensity.map { "\($0)" } ?? "–")")
        }
        if want.equipment != got.equipment {
            out.append("equipment differs")
        }
        return out
    }

    private func names(_ groups: Set<Int>) -> String {
        groups.compactMap { WorkoutCategory(rawValue: $0).map { "\($0)" } }.sorted().joined(separator: "+")
    }

    private static func request(_ focus: NLFocus, targets: [WorkoutCategory] = [], minutes: Int? = nil,
                                _ intensity: NLIntensity? = nil, bodyweight: Bool = false,
                                excluding: [WorkoutCategory] = [], only: [Equipment] = []) -> ParsedWorkoutRequest {
        ParsedWorkoutRequest(focus: focus,
                             targetMuscles: targets.flatMap { $0 == .cardio ? [$0.rawValue, WorkoutCategory.hiit.rawValue] : [$0.rawValue] },
                             durationMinutes: minutes,
                             intensity: intensity,
                             bodyweightOnly: bodyweight,
                             excluded: Set(excluding.map(\.rawValue)),
                             equipmentOnly: Set(only.map(\.rawValue)))
    }

    static let all: [WorkoutParserEvalCase] = [
        // English
        .init(prompt: "45 min upper body, dumbbells only", expected: request(.upperBody, minutes: 45, only: [.dumbbells])),
        .init(prompt: "quick core session at home", expected: request(.core, targets: [.core], minutes: 20, bodyweight: true)),
        .init(prompt: "hard leg day", expected: request(.legs, targets: [.legs], .hard)),
        .init(prompt: "30 minute full body, no equipment", expected: request(.fullBody, minutes: 30, bodyweight: true)),
        .init(prompt: "arm day", expected: request(.upperBody, targets: [.arms])),
        .init(prompt: "chest and triceps, heavy", expected: request(.push, targets: [.chest, .arms], .hard)),
        .init(prompt: "easy recovery session, 20 minutes", expected: request(.fullBody, minutes: 20, .easy)),
        .init(prompt: "push day without shoulders", expected: request(.push, excluding: [.shoulders])),
        .init(prompt: "upper body but skip arms, one hour", expected: request(.upperBody, minutes: 60, excluding: [.arms])),
        .init(prompt: "just kettlebells, full body, 40 min", expected: request(.fullBody, minutes: 40, only: [.kettlebells])),
        .init(prompt: "back and biceps", expected: request(.pull, targets: [.back, .arms])),
        .init(prompt: "shoulder workout, light", expected: request(.upperBody, targets: [.shoulders], .easy)),
        .init(prompt: "5x5 strength, legs", expected: request(.legs, targets: [.legs])),
        .init(prompt: "hiit 25 min", expected: request(.cardio, targets: [.cardio], minutes: 25)),
        .init(prompt: "pull day with a barbell", expected: request(.pull)),
        .init(prompt: "an hour of full body, intense", expected: request(.fullBody, minutes: 60, .hard)),
        .init(prompt: "3 sets of 10, chest", expected: request(.push, targets: [.chest])),
        .init(prompt: "at home with dumbbells only", expected: request(.fullBody, bodyweight: true, only: [.dumbbells])),
        // German
        .init(prompt: "30 Minuten Ganzkörper ohne Geräte", expected: request(.fullBody, minutes: 30, bodyweight: true)),
        .init(prompt: "Beintraining, hart", expected: request(.legs, targets: [.legs], .hard)),
        .init(prompt: "Schultern und Arme, locker", expected: request(.upperBody, targets: [.shoulders, .arms], .easy)),
        .init(prompt: "Oberkörper nur mit Kurzhanteln, 45 Minuten", expected: request(.upperBody, minutes: 45, only: [.dumbbells])),
        .init(prompt: "Oberkörper nur mit Kurzhanteln", expected: request(.upperBody, only: [.dumbbells])),
        .init(prompt: "kurzes Bauchtraining zu Hause", expected: request(.core, targets: [.core], minutes: 20, bodyweight: true)),
        .init(prompt: "Rücken ohne Bizeps", expected: request(.pull, targets: [.back], excluding: [.arms])),
        .init(prompt: "eine Stunde Push", expected: request(.push, minutes: 60)),
        .init(prompt: "lockeres Cardio, 20 min", expected: request(.cardio, targets: [.cardio], minutes: 20, .easy)),
        .init(prompt: "Brust und Trizeps, schwer", expected: request(.push, targets: [.chest, .arms], .hard))
    ]
}

// MARK: - Evaluation screen

/// Runs every case through the on-device model and the keyword parser and
/// shows the score for each, with the mismatches per case.
struct WorkoutParserEvaluationView: View {

    private struct Result: Identifiable {
        let evalCase: WorkoutParserEvalCase
        let modelMismatches: [String]?   // nil = model unavailable or failed
        let keywordMismatches: [String]
        var id: String { evalCase.id }
    }

    @State private var parser = WorkoutRequestParser()
    @State private var results: [Result] = []
    @State private var isRunning = false
    @State private var elapsed: Duration?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label(isRunning ? "Running…" : "Run \(WorkoutParserEvalCase.all.count) cases", systemImage: "play.fill")
                }
                .disabled(isRunning)
                if !parser.isModelAvailable {
                    Text("Apple Intelligence is unavailable here — only the keyword parser is scored. Run on a supported device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !results.isEmpty {
                Section("Score (fully correct cases)") {
                    LabeledContent("Apple Intelligence", value: score(\.modelMismatches))
                    LabeledContent("Keyword parser", value: score { $0.keywordMismatches })
                    if let elapsed {
                        LabeledContent("Model time", value: elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))
                    }
                }
                Section("Cases") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.evalCase.prompt).font(.subheadline.weight(.semibold))
                            row("AI", result.modelMismatches)
                            row("Keywords", result.keywordMismatches)
                        }
                    }
                }
            }
        }
        .navigationTitle("Parser evaluation")
        .task { parser.prewarm() }
    }

    private func row(_ label: String, _ mismatches: [String]?) -> some View {
        let text: String
        switch mismatches {
        case nil: text = "—"
        case let list? where list.isEmpty: text = "✓"
        case let list?: text = "✗ " + list.joined(separator: "; ")
        }
        return Text("\(label): \(text)")
            .font(.caption.monospaced())
            .foregroundStyle(mismatches?.isEmpty == false ? .red : .secondary)
    }

    private func score(_ mismatches: (Result) -> [String]?) -> String {
        let scored = results.compactMap(mismatches)
        guard !scored.isEmpty else { return "—" }
        return "\(scored.filter(\.isEmpty).count)/\(scored.count)"
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        results = []
        let clock = ContinuousClock()
        var modelTime = Duration.zero
        for evalCase in WorkoutParserEvalCase.all {
            let start = clock.now
            let modelParse = await parser.parseWithModel(evalCase.prompt)
            modelTime += clock.now - start
            results.append(Result(evalCase: evalCase,
                                  modelMismatches: modelParse.map(evalCase.mismatches(in:)),
                                  keywordMismatches: evalCase.mismatches(in: KeywordWorkoutParser.parse(evalCase.prompt))))
        }
        elapsed = parser.isModelAvailable ? modelTime : nil
    }
}
#endif
