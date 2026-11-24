//
//  WorkoutIntelligence.swift
//  TrainingLab (iOS)
//
//  On-device workout intelligence built on Apple's current frameworks:
//   • HealthKit  — HRV (SDNN), resting heart rate, sleep, active energy.
//   • SwiftData  — the user's FinishedWorkout history (training load / recency).
//   • FoundationModels (see WorkoutIntelligenceView) — the natural-language
//     coaching narrative on top of the deterministic numbers below.
//
//  Design note: per Apple's Foundation Models guidance, the on-device LLM is
//  poor at math and logic, so ALL scoring here is deterministic and testable.
//  The language model is only used to phrase the results, never to compute them.
//
//  This file lives under `iOS/` so it compiles into the iOS app target only —
//  FoundationModels and these APIs aren't part of the watchOS build.
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Small helpers

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

// MARK: - Recovery

/// A single human-readable contributor to the recovery score. `impact` is the
/// signed number of points this factor added to (or removed from) the score, so
/// the UI can show *why* recovery is where it is.
struct RecoveryFactor: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    let impact: Double
    let systemImage: String
}

enum RecoveryBand: String {
    case rest
    case moderate
    case ready

    var title: String {
        switch self {
        case .rest:     return NSLocalizedString("Take it easy", comment: "Recovery band")
        case .moderate: return NSLocalizedString("Moderate", comment: "Recovery band")
        case .ready:    return NSLocalizedString("Ready to train", comment: "Recovery band")
        }
    }

    var systemImage: String {
        switch self {
        case .rest:     return "bed.double.fill"
        case .moderate: return "figure.walk"
        case .ready:    return "bolt.heart.fill"
        }
    }
}

/// Raw signals feeding the recovery model. Every field is optional so the model
/// degrades gracefully when HealthKit has no data (e.g. no Apple Watch).
///
/// The `…History` arrays hold one value per earlier day or night, newest
/// first, measured the same way as the value they're compared against and
/// never including it.
struct RecoveryInputs {
    var hrvSDNN: Double?              // ms, last night (last 24h if nothing overnight)
    var hrvBaseline: Double?          // ms, fallback when `hrvHistory` is too short
    var hrvHistory: [Double] = []     // ms, one value per earlier night (or day)
    var restingHR: Double?            // bpm, most recent day
    var restingHRBaseline: Double?    // bpm, fallback when `restingHRHistory` is too short
    var restingHRHistory: [Double] = [] // bpm, one value per earlier day
    var sleepHoursLastNight: Double?
    var sleepHistory: [Double] = []   // hours asleep per earlier night; 0 = not tracked
    var acuteLoad: Double = 0         // session-RPE load (minutes × effort), last 7 days
    var chronicLoad: Double?          // mean weekly load over the 3 weeks before; nil until there's enough history

    var hasHealthData: Bool {
        hrvSDNN != nil || restingHR != nil || sleepHoursLastNight != nil
    }
}

/// An input the recovery model can draw on. Weighted by how much it tells us
/// about readiness, so `RecoveryEstimate.confidence` reflects which ones were
/// actually available rather than just how many.
enum RecoverySignal: CaseIterable {
    case hrv, restingHeartRate, sleep, trainingLoad

    var weight: Double {
        switch self {
        case .hrv:              return 0.35
        case .restingHeartRate: return 0.25
        case .sleep:            return 0.25
        case .trainingLoad:     return 0.15
        }
    }

    /// Lower-case so it reads naturally inside "Based on …" lists.
    var listName: String {
        switch self {
        case .hrv:              return NSLocalizedString("HRV", comment: "Recovery signal in a list")
        case .restingHeartRate: return NSLocalizedString("resting heart rate", comment: "Recovery signal in a list")
        case .sleep:            return NSLocalizedString("sleep", comment: "Recovery signal in a list")
        case .trainingLoad:     return NSLocalizedString("training load", comment: "Recovery signal in a list")
        }
    }
}

struct RecoveryEstimate {
    let score: Int            // 0…100
    let band: RecoveryBand
    let factors: [RecoveryFactor]
    let hasHealthData: Bool
    /// The inputs that contributed. Empty means the score is the neutral
    /// default, not a measurement.
    var signals: Set<RecoverySignal> = []

    /// Recovery expressed as a 0…1 readiness multiplier for downstream tuning.
    var readiness: Double { Double(score) / 100.0 }

    /// 0…1: how much of the model's evidence was available.
    var confidence: Double { signals.reduce(0) { $0 + $1.weight } }

    /// Below this, the UI flags the score as a rough estimate.
    static let lowConfidenceThreshold = 0.5
    var isLowConfidence: Bool { confidence < Self.lowConfidenceThreshold }
}

/// Deterministic recovery model. Starts from a neutral baseline and nudges the
/// score with each available signal; missing signals simply don't contribute.
///
/// HRV and resting heart rate are judged against the user's own day-to-day
/// spread (a z-score), not a fixed ratio: a 5 ms dip is noise for one person
/// and a real warning for another. HRV is log-transformed first because it's
/// right-skewed — standard practice in HRV-guided training. Until there are
/// `minBaselineDays` of history, a plain ratio to the baseline is used instead.
enum RecoveryEstimator {

    /// Days of history needed before the personal spread is trusted.
    static let minBaselineDays = 7
    /// The personal sleep target is the user's usual sleep, but never below
    /// the 7 h adult recommendation — otherwise a chronic short sleeper would
    /// always look on target — and never above 9 h.
    static let sleepTargetRange = 7.0...9.0
    static let defaultSleepTarget = 7.5
    /// Nights shorter than this are almost always a watch taken off, not a night.
    static let minTrackedNightHours = 3.0

    static func estimate(from inputs: RecoveryInputs) -> RecoveryEstimate {
        var score = 75.0
        var factors: [RecoveryFactor] = []
        var signals: Set<RecoverySignal> = []

        // Heart-rate variability — above your normal range means well recovered.
        if let hrv = inputs.hrvSDNN, let result = hrvImpact(hrv: hrv, inputs: inputs) {
            let (impact, baseline) = result
            score += impact
            signals.insert(.hrv)
            factors.append(RecoveryFactor(
                label: NSLocalizedString("Heart rate variability", comment: "Recovery factor"),
                detail: String(format: NSLocalizedString("%.0f ms vs %.0f ms baseline", comment: "HRV factor detail"), hrv, baseline),
                impact: impact,
                systemImage: "waveform.path.ecg"))
        }

        // Resting heart rate — elevated vs your normal suggests incomplete recovery.
        if let rhr = inputs.restingHR, let result = restingHRImpact(rhr: rhr, inputs: inputs) {
            let (impact, baseline) = result
            score += impact
            signals.insert(.restingHeartRate)
            factors.append(RecoveryFactor(
                label: NSLocalizedString("Resting heart rate", comment: "Recovery factor"),
                detail: String(format: NSLocalizedString("%.0f bpm vs %.0f bpm baseline", comment: "RHR factor detail"), rhr, baseline),
                impact: impact,
                systemImage: "heart.fill"))
        }

        // Sleep — measured against your own usual sleep; short sleep is a
        // strong readiness penalty.
        let sleepTarget = sleepTarget(history: inputs.sleepHistory)
        if let sleep = inputs.sleepHoursLastNight {
            let impact = clamp((sleep - sleepTarget) * 6.0, -18, 8)
            score += impact
            signals.insert(.sleep)
            factors.append(RecoveryFactor(
                label: NSLocalizedString("Sleep", comment: "Recovery factor"),
                detail: String(format: NSLocalizedString("%1$.1f h last night, target %2$.1f h", comment: "Sleep factor detail: hours slept, personal target"), sleep, sleepTarget),
                impact: impact,
                systemImage: "bed.double.fill"))
        }

        // Sleep debt — one good night doesn't cancel several short ones.
        let debt = sleepDebt(history: inputs.sleepHistory, target: sleepTarget)
        if debt >= 1.5 {
            let impact = -min(debt * 2.0, 8)
            score += impact
            factors.append(RecoveryFactor(
                label: NSLocalizedString("Sleep debt", comment: "Recovery factor"),
                detail: String(format: NSLocalizedString("%.1f h short over the 3 nights before", comment: "Sleep debt factor detail"), debt),
                impact: impact,
                systemImage: "moon.zzz.fill"))
        }

        // Training load — acute:chronic workload ratio (last 7 days vs your
        // usual week). Above ~1.3 the risk of overreaching climbs; above 1.5
        // it's a spike.
        if let chronic = inputs.chronicLoad, chronic > 0 {
            signals.insert(.trainingLoad)
            let acwr = inputs.acuteLoad / chronic
            let impact: Double
            let detail: String
            if acwr >= 1.5 {
                impact = -min(8 + (acwr - 1.5) * 24.0, 20)
                detail = NSLocalizedString("Recent load is spiking", comment: "Load factor detail")
            } else if acwr > 1.3 {
                impact = -(acwr - 1.3) * 40.0
                detail = NSLocalizedString("Load is ramping up quickly", comment: "Load factor detail")
            } else if acwr < 0.8 {
                impact = 4
                detail = NSLocalizedString("Lighter than your usual training", comment: "Load factor detail")
            } else {
                impact = 0
                detail = ""
            }
            if impact != 0 {
                score += impact
                factors.append(RecoveryFactor(
                    label: NSLocalizedString("Training load", comment: "Recovery factor"),
                    detail: detail,
                    impact: impact,
                    systemImage: "chart.line.uptrend.xyaxis"))
            }
        }

        let clamped = Int(clamp(score, 0, 100).rounded())
        let band: RecoveryBand = clamped < 45 ? .rest : (clamped < 70 ? .moderate : .ready)
        return RecoveryEstimate(score: clamped, band: band, factors: factors,
                                hasHealthData: inputs.hasHealthData, signals: signals)
    }

    /// Score impact of tonight's HRV and the baseline it was compared with.
    static func hrvImpact(hrv: Double, inputs: RecoveryInputs) -> (impact: Double, baseline: Double)? {
        guard hrv > 0 else { return nil }
        let logs = inputs.hrvHistory.filter { $0 > 0 }.map { Foundation.log($0) }
        if logs.count >= minBaselineDays {
            let stats = meanAndSD(logs)
            // Floor: a near-constant history would turn tiny changes into huge z-scores.
            let z = (Foundation.log(hrv) - stats.mean) / max(stats.sd, 0.04)
            return (clamp(z * 8.0, -22, 15), Foundation.exp(stats.mean))
        }
        guard let base = inputs.hrvBaseline, base > 0 else { return nil }
        return (clamp((hrv / base - 1.0) * 60.0, -22, 15), base)
    }

    /// Score impact of the latest resting heart rate and its baseline.
    static func restingHRImpact(rhr: Double, inputs: RecoveryInputs) -> (impact: Double, baseline: Double)? {
        guard rhr > 0 else { return nil }
        let history = inputs.restingHRHistory.filter { $0 > 0 }
        if history.count >= minBaselineDays {
            let stats = meanAndSD(history)
            let z = (rhr - stats.mean) / max(stats.sd, 1.0)
            return (clamp(-z * 5.0, -20, 10), stats.mean)
        }
        guard let base = inputs.restingHRBaseline, base > 0 else { return nil }
        return (clamp(-(rhr - base) * 1.6, -20, 10), base)
    }

    /// The user's usual sleep (median of tracked nights), within `sleepTargetRange`.
    static func sleepTarget(history: [Double]) -> Double {
        let nights = history.filter { $0 >= minTrackedNightHours }
        guard nights.count >= 5 else { return defaultSleepTarget }
        return clamp(median(nights), sleepTargetRange.lowerBound, sleepTargetRange.upperBound)
    }

    /// Hours short of `target` over the 3 nights before last night.
    static func sleepDebt(history: [Double], target: Double) -> Double {
        history.prefix(3)
            .filter { $0 >= minTrackedNightHours }
            .reduce(0) { $0 + max(0, target - $1) }
    }

    /// Sample mean and standard deviation.
    static func meanAndSD(_ values: [Double]) -> (mean: Double, sd: Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (mean, (squares / Double(max(values.count - 1, 1))).squareRoot())
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

// MARK: - HealthKit recovery signals

/// Reads the recovery signals from HealthKit. All queries are best-effort:
/// unauthorized or empty types resolve to empty results rather than throwing,
/// so a device without an Apple Watch still produces a (load-only) estimate.
struct RecoveryMetricsProvider {
    var healthStore: HKHealthStore = .shared

    /// Nights / days of history fetched for the personal baselines.
    static let baselineDays = 30
    static let sleepHistoryNights = 14

    /// Requests read access to the recovery signals. Only prompts the first
    /// time (HealthKit won't re-prompt once a decision is made); afterwards the
    /// user has to change it in Settings.
    func requestRecoveryAuthorization() async {
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.workoutType()
        ].compactMap { $0 }.reduce(into: Set<HKObjectType>()) { $0.insert($1) }
        try? await healthStore.requestAuthorization(toShare: [], read: types)
    }

    /// Main actor: `history` are main-context SwiftData models. Explicit, so it
    /// doesn't depend on build settings — without Approachable Concurrency a
    /// nonisolated async function runs on a background thread and read them
    /// there. The HealthKit queries below still run concurrently.
    @MainActor
    func loadInputs(history: [FinishedWorkout], now: Date = Date()) async -> RecoveryInputs {
        #if DEBUG
        // Simulator has no HRV / sleep sensors, so the recovery model would
        // otherwise fall back to history-only. When the debug toggle is on we
        // inject realistic signals so the AI features can be exercised.
        if DebugHealthData.isEnabled {
            return DebugHealthData.mockInputs(history: history, now: now)
        }
        #endif
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: dayStart) ?? dayStart }

        let night = Self.lastNightWindow(now: now, calendar: calendar)
        // Earlier nights / calendar days, newest first. None overlaps the
        // "recent" window it's compared against.
        let pastNights = (1...Self.baselineDays).map { Self.nightWindow(endingOn: day(-$0), calendar: calendar) }
        let pastDays = (2...Self.baselineDays + 1).map { DateInterval(start: day(-$0), end: day(-$0 + 1)) }
        let pastDayBlocks = (1...Self.baselineDays).map {
            DateInterval(start: now.addingTimeInterval(Double(-($0 + 1)) * 86_400),
                         end: now.addingTimeInterval(Double(-$0) * 86_400))
        }
        let last24h = DateInterval(start: now.addingTimeInterval(-86_400), end: now)

        let earliestNight = pastNights.map(\.start).min() ?? night.start
        let earliestBlock = pastDayBlocks.map(\.start).min() ?? last24h.start
        let earliestDay = pastDays.map(\.start).min() ?? day(-1)

        async let hrvSamples   = quantitySamples(.heartRateVariabilitySDNN, unit: hrvUnit,
                                                 from: min(earliestNight, earliestBlock), to: now)
        async let rhrSamples   = quantitySamples(.restingHeartRate, unit: bpmUnit, from: earliestDay, to: now)
        async let sleepSamples = asleepIntervals(from: earliestNight, to: night.end)
        async let external     = externalWorkouts(from: now.addingTimeInterval(-Double(TrainingLoad.historyDays) * 86_400), to: now)

        let asleep = await sleepSamples

        // HRV: readings taken while asleep are the meaningful readiness
        // signal, and they're compared with earlier readings taken the same
        // way — nighttime HRV runs higher than daytime HRV, so mixing the two
        // biases the score. Fallbacks, in order: the night window when there's
        // no sleep data, then trailing 24h blocks for users who don't wear the
        // watch to bed.
        let hrv = await hrvSamples
        let hrvDuringSleep = Self.samples(hrv, during: asleep)
        let hrvRecent: Double?
        let hrvHistory: [Double]
        if let asleepValue = Self.windowAverages(hrvDuringSleep, windows: [night])[0] {
            hrvRecent = asleepValue
            hrvHistory = Self.windowAverages(hrvDuringSleep, windows: pastNights).compactMap { $0 }
        } else if let overnight = Self.windowAverages(hrv, windows: [night])[0] {
            hrvRecent = overnight
            hrvHistory = Self.windowAverages(hrv, windows: pastNights).compactMap { $0 }
        } else {
            hrvRecent = Self.windowAverages(hrv, windows: [last24h])[0]
            hrvHistory = Self.windowAverages(hrv, windows: pastDayBlocks).compactMap { $0 }
        }

        // Resting HR: Apple Watch writes about one value per day.
        let rhr = await rhrSamples
        let rhrRecent = Self.windowAverages(rhr, windows: [DateInterval(start: day(-1), end: now)])[0]
        let rhrHistory = Self.windowAverages(rhr, windows: pastDays).compactMap { $0 }

        let lastNightSleep = Self.nightlySleepHours(asleep, windows: [night])[0]
        let sleepHistory = Self.nightlySleepHours(asleep, windows: Array(pastNights.prefix(Self.sleepHistoryNights)))

        let sessions = TrainingLoad.sessions(history: history, external: await external)
        let load = TrainingLoad.load(sessions: sessions, now: now)

        return RecoveryInputs(
            hrvSDNN: hrvRecent,
            hrvBaseline: hrvHistory.count >= 3
                ? Foundation.exp(hrvHistory.map { Foundation.log($0) }.reduce(0, +) / Double(hrvHistory.count))
                : nil,
            hrvHistory: hrvHistory,
            restingHR: rhrRecent,
            restingHRBaseline: rhrHistory.count >= 3 ? rhrHistory.reduce(0, +) / Double(rhrHistory.count) : nil,
            restingHRHistory: rhrHistory,
            sleepHoursLastNight: lastNightSleep > 0 ? lastNightSleep : nil,
            sleepHistory: sleepHistory,
            acuteLoad: load.acute,
            chronicLoad: load.chronic
        )
    }

    // MARK: Pure helpers (unit-tested)

    /// Total asleep hours from a set of (possibly overlapping) intervals,
    /// counting overlapping time only once. Factored out for unit testing —
    /// this is the fix for multi-source sleep double-counting.
    static func mergedAsleepHours(_ intervals: [(start: Date, end: Date)]) -> Double {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for iv in sorted {
            if var last = merged.last, iv.start <= last.end {
                last.end = max(last.end, iv.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(iv)
            }
        }
        let seconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        return seconds / 3600.0
    }

    /// The night that ends on the morning of `dayStart`: 18:00 the evening
    /// before → 12:00 that day.
    static func nightWindow(endingOn dayStart: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .hour, value: -6, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
        return DateInterval(start: start, end: max(start, end))
    }

    /// The window "last night" refers to: yesterday 18:00 → today 12:00, cut
    /// off at `now`. Anchored to the calendar day rather than a trailing
    /// lookback, which missed most of the night when opened in the evening and
    /// counted afternoon naps when opened at midday.
    static func lastNightWindow(now: Date, calendar: Calendar = .current) -> DateInterval {
        let full = nightWindow(endingOn: calendar.startOfDay(for: now), calendar: calendar)
        return DateInterval(start: full.start, end: max(full.start, min(now, full.end)))
    }

    /// Mean sample value inside each window (start inclusive, end exclusive),
    /// index-aligned with `windows`; nil where a window has no samples.
    static func windowAverages(_ samples: [(date: Date, value: Double)],
                               windows: [DateInterval]) -> [Double?] {
        windows.map { window in
            let values = samples.filter { $0.date >= window.start && $0.date < window.end }.map(\.value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    /// The samples taken inside any of `intervals` (start inclusive, end exclusive).
    static func samples(_ samples: [(date: Date, value: Double)],
                        during intervals: [(start: Date, end: Date)]) -> [(date: Date, value: Double)] {
        samples.filter { sample in intervals.contains { $0.start <= sample.date && sample.date < $0.end } }
    }

    /// Asleep hours per window (0 when nothing was tracked), index-aligned
    /// with `windows`. Intervals are clipped to each window before merging, so
    /// a sample starting before 18:00 doesn't count time outside the night.
    static func nightlySleepHours(_ intervals: [(start: Date, end: Date)],
                                  windows: [DateInterval]) -> [Double] {
        windows.map { window in
            mergedAsleepHours(intervals.compactMap { iv in
                let start = max(iv.start, window.start)
                let end = min(iv.end, window.end)
                return end > start ? (start: start, end: end) : nil
            })
        }
    }

    // MARK: HealthKit queries

    private var hrvUnit: HKUnit { HKUnit.secondUnit(with: .milli) }
    private var bpmUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    /// Every sample of a quantity type between `start` and `end`.
    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                                 from start: Date, to end: Date) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier), end > start else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Asleep intervals (any stage) overlapping `start…end`, from every source.
    private func asleepIntervals(from start: Date, to end: Date) async -> [(start: Date, end: Date)] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis), end > start else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                // Overlapping samples from several sources (iPhone estimate,
                // Watch stages, third-party apps) are merged per night by
                // `nightlySleepHours` — summing them is what once produced
                // impossible 14 h nights.
                let intervals = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .map { (start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: intervals)
            }
            healthStore.execute(query)
        }
    }

    /// Workouts other apps (Apple Workout, Strava, …) saved to HealthKit. This
    /// app's own workouts, from the phone or the watch extension, are skipped —
    /// they're already in the SwiftData history.
    func externalWorkouts(from start: Date, to end: Date) async -> [ExternalWorkout] {
        #if DEBUG
        // The simulator has no other fitness apps; the debug toggle stands in
        // two so goals and History can be exercised.
        if DebugHealthData.isEnabled {
            return DebugHealthData.mockExternalWorkouts(now: Date()).filter { $0.start >= start && $0.end <= end }
        }
        #endif
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? [])
                    .filter { ownBundle.isEmpty || !$0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle) }
                    .map { workout in
                        ExternalWorkout(start: workout.startDate, end: workout.endDate,
                                        activityType: Int(workout.workoutActivityType.rawValue),
                                        id: workout.uuid,
                                        sourceName: workout.sourceRevision.source.name,
                                        distanceMeters: Self.distanceMeters(of: workout))
                    }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// The workout's distance, from whichever distance type its sport records.
    private static func distanceMeters(of workout: HKWorkout) -> Double? {
        let types: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling,
                                                 .distanceSwimming, .distanceDownhillSnowSports]
        for type in types {
            if let sum = workout.statistics(for: HKQuantityType(type))?.sumQuantity() {
                return sum.doubleValue(for: .meter())
            }
        }
        return nil
    }
}

// MARK: - Training load

/// A workout another app recorded in HealthKit.
struct ExternalWorkout: Identifiable {
    let start: Date
    let end: Date
    let activityType: Int
    var id = UUID()
    /// The app or device that recorded it ("Strava", "Justus's Apple Watch").
    var sourceName = ""
    var distanceMeters: Double?

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// `external` without the sessions that are one of the app's own workouts
    /// recorded a second time (e.g. by the Workout app running alongside).
    static func distinct(_ external: [ExternalWorkout], from history: [FinishedWorkout]) -> [ExternalWorkout] {
        external.filter { ext in
            !history.contains { TrainingLoad.overlapsMostly($0.startDate, $0.endDate, ext.start, ext.end) }
        }
    }
}

/// One session's contribution to training load.
struct LoadSession {
    let start: Date
    let end: Date
    /// Effort on the 1…10 scale: the user's own rating when there is one,
    /// otherwise a typical value for the activity.
    let effort: Double

    /// Longer than this is almost always a workout left running, not training.
    static let maxMinutes = 180.0

    /// Session-RPE load (Foster): minutes × effort. Unlike raw minutes, an
    /// hour of hard intervals counts for more than an hour of walking.
    var load: Double {
        min(max(end.timeIntervalSince(start) / 60.0, 0), Self.maxMinutes) * effort
    }
}

/// Acute:chronic training load from the app's own history plus other apps'
/// HealthKit workouts.
enum TrainingLoad {
    static let acuteDays = 7
    static let chronicWeeks = 3
    /// How far back sessions are needed: the acute week plus the chronic weeks.
    static var historyDays: Int { acuteDays + chronicWeeks * 7 }
    /// Minimum history before the acute week, in weeks, before chronic load
    /// is trusted. With less, a normal first week would read as a huge spike
    /// over an empty baseline.
    static let minChronicWeeks = 1.5

    static func sessions(history: [FinishedWorkout], external: [ExternalWorkout]) -> [LoadSession] {
        let own = history.map { finished in
            LoadSession(start: finished.startDate, end: finished.endDate,
                        effort: finished.perceivedEffort.map(Double.init)
                            ?? defaultEffort(activityType: finished.workoutType, muscleGroup: finished.muscleGroup))
        }
        // An external workout that mostly overlaps one of ours is the same
        // session recorded twice (e.g. also tracked by the Workout app).
        let others = external
            .filter { ext in !own.contains { overlapsMostly($0.start, $0.end, ext.start, ext.end) } }
            .map { LoadSession(start: $0.start, end: $0.end, effort: defaultEffort(activityType: $0.activityType)) }
        return own + others
    }

    /// `acute`: load over the last 7 days. `chronic`: average weekly load over
    /// the 3 weeks before that — "uncoupled", so the acute week doesn't
    /// dilute the baseline it's compared against. Nil while the history is
    /// shorter than `minChronicWeeks` before the acute week.
    static func load(sessions: [LoadSession], now: Date) -> (acute: Double, chronic: Double?) {
        let acuteStart = now.addingTimeInterval(-Double(acuteDays) * 86_400)
        let chronicStart = now.addingTimeInterval(-Double(historyDays) * 86_400)

        let acute = sessions.filter { $0.end > acuteStart && $0.end <= now }.reduce(0) { $0 + $1.load }
        let prior = sessions.filter { $0.end > chronicStart && $0.end <= acuteStart }

        guard let earliest = sessions.map(\.end).min() else { return (acute, nil) }
        let weeksOfHistory = acuteStart.timeIntervalSince(earliest) / (7 * 86_400)
        guard weeksOfHistory >= minChronicWeeks else { return (acute, nil) }
        // A week with any session in it counts as tracked, so round up: the
        // first session rarely falls exactly at the start of tracking.
        let weeks = min(weeksOfHistory.rounded(.up), Double(chronicWeeks))
        return (acute, prior.reduce(0) { $0 + $1.load } / weeks)
    }

    /// Typical session effort (1…10) when the user hasn't rated one.
    static func defaultEffort(activityType: Int,
                              muscleGroup: Int = WorkoutCategory.undefined.rawValue) -> Double {
        switch WorkoutCategory(rawValue: muscleGroup) {
        case .yoga, .mobilityFlexibility: return 2
        case .hiit:                       return 7
        default: break
        }
        switch HKWorkoutActivityType(rawValue: UInt(max(activityType, 0))) {
        case .highIntensityIntervalTraining, .crossTraining, .mixedCardio:
            return 7
        case .traditionalStrengthTraining, .functionalStrengthTraining, .running,
             .swimming, .rowing, .stairClimbing, .coreTraining:
            return 6
        case .cycling, .elliptical, .hiking:
            return 5
        case .pilates:
            return 3
        case .walking:
            return 3
        case .yoga, .mindAndBody, .flexibility, .cooldown, .preparationAndRecovery:
            return 2
        default:
            return 5
        }
    }

    /// True when two sessions share at least half of the shorter one.
    static func overlapsMostly(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        let overlap = min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart))
        let shorter = min(aEnd.timeIntervalSince(aStart), bEnd.timeIntervalSince(bStart))
        return shorter > 0 && overlap >= shorter / 2
    }
}

// MARK: - Difficulty prediction

struct DifficultyPrediction {
    /// Perceived difficulty for *this user, right now*, 1 (easy) … 5 (very hard).
    let rating: Double
    /// `rating` before the personal calibration offset. This is what gets
    /// stored for later comparison: calibrating against the already-calibrated
    /// value would cancel the offset out and make it oscillate.
    let rawRating: Double
    let label: String
    let rationale: String

    var systemImage: String {
        switch rating {
        case ..<2.0:  return "tortoise.fill"
        case ..<3.0:  return "figure.walk"
        case ..<4.0:  return "flame.fill"
        default:      return "bolt.fill"
        }
    }
}

/// Predicts how hard a workout will feel by combining the workout's intrinsic
/// demand with the user's recent tolerance and current recovery.
enum WorkoutDifficultyPredictor {

    /// - Parameters:
    ///   - exerciseDifficulties: each exercise's `difficultyInt` (1…3).
    ///   - exerciseCount / setLength / durationMinutes: volume signals.
    ///   - recovery: current readiness (0…1). Lower recovery → feels harder.
    ///   - history: finished workouts, used to estimate the user's tolerance.
    ///   - progression: logged-volume trend in [-1, 1] from `WorkoutStats`.
    ///     `> 0` (rising volume) means the user is adapting, so it feels easier.
    ///   - calibration: personal offset from `calibrationOffset(history:)`,
    ///     added on top of the heuristic.
    static func predict(exerciseDifficulties: [Int],
                        exerciseCount: Int,
                        setLength: Double,
                        durationMinutes: Int,
                        recovery: Double,
                        history: [FinishedWorkout],
                        progression: Double = 0,
                        calibration: Double = 0) -> DifficultyPrediction {

        // 1. Intrinsic demand from the exercises themselves.
        let avgDiff = exerciseDifficulties.isEmpty
            ? 2.0
            : Double(exerciseDifficulties.reduce(0, +)) / Double(exerciseDifficulties.count)
        // Map 1…3 → 1…5.
        var rating = 1.0 + (avgDiff - 1.0) / 2.0 * 4.0

        // 2. Volume: sets and duration push it up or down.
        let volume = Double(max(exerciseCount, 1)) * max(setLength, 1)
        rating += clamp((volume - 16.0) / 16.0, -0.6, 1.0)
        rating += clamp((Double(durationMinutes) - 30.0) / 30.0 * 0.6, -0.4, 0.8)

        // 3. User tolerance: how hard are the workouts they actually complete?
        let tolerance = userTolerance(history: history)   // ~1…3
        rating -= (tolerance - 2.0) * 0.4                  // seasoned lifters feel it less

        // 4. Recovery: being under-recovered makes everything feel harder.
        rating += (1.0 - clamp(recovery, 0, 1)) * 1.3

        // 5. Progression: if the user's logged training volume is trending up
        //    they're adapting, so the same session feels a touch easier (and the
        //    reverse when volume is falling off).
        rating -= clamp(progression, -1, 1) * 0.5

        let rawRating = clamp(rating, 1, 5)

        // 6. Calibration: shift by how far off past predictions were for this
        //    user, measured against their own effort ratings.
        rating = clamp(rawRating + calibration, 1, 5)

        let label: String
        switch rating {
        case ..<2.0:  label = NSLocalizedString("Easy", comment: "Difficulty label")
        case ..<3.0:  label = NSLocalizedString("Moderate", comment: "Difficulty label")
        case ..<4.0:  label = NSLocalizedString("Challenging", comment: "Difficulty label")
        default:      label = NSLocalizedString("Very hard", comment: "Difficulty label")
        }

        let rationale: String
        if recovery < 0.45 {
            rationale = NSLocalizedString("Low recovery makes this feel harder than usual.", comment: "Difficulty rationale")
        } else if abs(calibration) >= 0.4 {
            rationale = NSLocalizedString("Adjusted to how hard your recent sessions felt.", comment: "Difficulty rationale")
        } else if progression >= 0.15 {
            rationale = NSLocalizedString("You've been building volume lately — this should feel manageable.", comment: "Difficulty rationale")
        } else if avgDiff >= 2.6 {
            rationale = NSLocalizedString("Heavy compound work drives the intensity.", comment: "Difficulty rationale")
        } else if volume >= 24 {
            rationale = NSLocalizedString("High training volume for this session.", comment: "Difficulty rationale")
        } else {
            rationale = NSLocalizedString("Matched to your recent training.", comment: "Difficulty rationale")
        }

        return DifficultyPrediction(rating: rating, rawRating: rawRating, label: label, rationale: rationale)
    }

    /// Maps a 1…10 effort rating onto the predictor's 1…5 scale.
    static func effortAsRating(_ effort: Int) -> Double {
        1.0 + (clamp(Double(effort), 1, 10) - 1.0) / 9.0 * 4.0
    }

    /// The mean gap between how hard recent sessions felt and their raw
    /// prediction, over the last `limit` rated sessions. Shrunk towards 0 when
    /// there are only a few ratings, so one odd session can't swing it, and
    /// clamped so the heuristic still does most of the work.
    static func calibrationOffset(history: [FinishedWorkout], limit: Int = 10) -> Double {
        let residuals = history
            .sorted { $0.endDate > $1.endDate }
            .compactMap { finished -> Double? in
                guard let effort = finished.perceivedEffort,
                      let predicted = finished.predictedDifficulty else { return nil }
                return effortAsRating(effort) - predicted
            }
            .prefix(limit)
        guard !residuals.isEmpty else { return 0 }
        let n = Double(residuals.count)
        let mean = residuals.reduce(0, +) / n
        return clamp(mean * n / (n + 3), -1.5, 1.5)
    }

    /// Estimates tolerance from the average difficulty of exercises in the last
    /// ~30 days of completed workouts. Defaults to 2 (medium) with no history.
    /// Not `private`: reused by `ForYouView`'s "Picked for you" ranking.
    static func userTolerance(history: [FinishedWorkout]) -> Double {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let recent = history.filter { $0.endDate >= cutoff }
        let diffs = recent.flatMap { $0.performedExercises.map { Double($0.difficultyInt) } }
        guard !diffs.isEmpty else { return 2.0 }
        return diffs.reduce(0, +) / Double(diffs.count)
    }
}

// MARK: - Personalized workout generator

/// The blueprint the generator produces: which split, which catalog exercises,
/// the session parameters, and the predicted difficulty. Materialised into a
/// SwiftData `Workout` by `makeWorkout(in:existingExercises:)`.
struct PersonalizedWorkoutPlan {
    let split: GymSplit
    let exercises: [GymExerciseDefinition]
    let setLength: Double
    let durationMinutes: Int
    let difficultyInt: Int
    let recovery: RecoveryEstimate
    let prediction: DifficultyPrediction
    /// Deterministic reason string; the LLM coach can rephrase this for the UI.
    let rationale: String
    /// Hours since the split's primary training bucket was last worked; nil
    /// when it hasn't been trained in the available history.
    var hoursSinceTrained: Double? = nil
    /// The split the generator would pick on its own (the one whose main
    /// area waited longest). Equal to `split` unless the user chose another type.
    var recommendedSplit: GymSplit? = nil
    /// Every split the user's equipment can build, for the type picker.
    var availableSplits: [GymSplit] = []

    var isUserChosenSplit: Bool { recommendedSplit.map { $0 != split } ?? false }
}

/// Builds a session tailored to the user's recovery and training history:
/// picks the type whose main muscles waited longest, scales volume and
/// intensity to readiness, and only uses exercises the user's gym equipment
/// supports.
struct PersonalizedWorkoutGenerator {

    let availableEquipment: Set<Int>
    let history: [FinishedWorkout]

    /// - Parameter variation: bumped by "Regenerate" so the same day can yield
    ///   a different (equally suitable) exercise selection. `0` = the day's default.
    /// - Parameter split: a type the user chose instead of the recommended
    ///   one. Ignored when the equipment can't build it.
    func generate(recovery: RecoveryEstimate, now: Date = Date(), variation: Int = 0,
                  split chosenSplit: GymSplit? = nil) -> PersonalizedWorkoutPlan? {

        // 1. Scale the session to readiness.
        let readiness = recovery.readiness
        let targetCount: Int
        let setLength: Double
        let maxDifficulty: Int
        switch recovery.band {
        case .ready:
            targetCount = 6; setLength = 4; maxDifficulty = 3
        case .moderate:
            targetCount = 4; setLength = 3; maxDifficulty = 2
        case .rest:
            targetCount = 3; setLength = 2; maxDifficulty = 1
        }

        // 2. Build every split the equipment supports, preferring exercises at
        //    or below the readiness-appropriate difficulty, spread across the
        //    split's target muscle groups. A split only counts once it reaches
        //    three exercises: a pool of three can still fall short, because no
        //    movement pattern repeats — and the picker must not offer a split
        //    that then can't be built.
        let lastTrained = Self.lastTrainedByBucket(history: history)
        let candidates = GymSplit.allCases.compactMap { split -> (split: GymSplit, picked: [GymExerciseDefinition], freshness: SplitFreshness)? in
            // Bucket-filtered: a pull day must not be offered tricep pushdowns
            // just because they're filed under "Arms" like bicep curls are.
            let pool = GymExerciseCatalog.exercises(for: split,
                                                    availableEquipment: availableEquipment)
            let picked = selectExercises(from: pool,
                                         split: split,
                                         count: targetCount,
                                         maxDifficulty: maxDifficulty,
                                         now: now,
                                         variation: variation)
            guard picked.count >= 3 else { return nil }
            return (split, picked, Self.freshness(for: split, lastTrained: lastTrained, now: now))
        }

        // 3. Take the split that waited longest, unless the user chose another one.
        guard let recommended = candidates.max(by: { $0.freshness < $1.freshness }) else { return nil }
        let (split, picked, freshness) = candidates.first { $0.split == chosenSplit } ?? recommended
        let isChosen = split != recommended.split

        let duration = max(picked.count * 6, 18)
        let sessionDifficulty = Int((Double(picked.map(\.difficultyInt).reduce(0, +)) / Double(picked.count)).rounded())

        // 4. Predict how hard it will feel for this user today, factoring in the
        //    logged-volume progression trend from their history.
        let progression = WorkoutStats.progressionScore(
            history: WorkoutStats.snapshots(from: history), now: now)
        let prediction = WorkoutDifficultyPredictor.predict(
            exerciseDifficulties: picked.map(\.difficultyInt),
            exerciseCount: picked.count,
            setLength: setLength,
            durationMinutes: duration,
            recovery: readiness,
            history: history,
            progression: progression,
            calibration: WorkoutDifficultyPredictor.calibrationOffset(history: history))

        let rationale = buildRationale(split: split, recovery: recovery, count: picked.count,
                                       isChosen: isChosen)

        return PersonalizedWorkoutPlan(
            split: split,
            exercises: picked,
            setLength: setLength,
            durationMinutes: duration,
            difficultyInt: max(1, min(sessionDifficulty, 3)),
            recovery: recovery,
            prediction: prediction,
            rationale: rationale,
            hoursSinceTrained: freshness.primaryHours < .greatestFiniteMagnitude ? freshness.primaryHours : nil,
            recommendedSplit: recommended.split,
            availableSplits: candidates.map(\.split))
    }

    // MARK: Selection

    /// Rotates the pick based on the day so repeated live generations vary.
    /// Delegates the actual selection algorithm to the shared
    /// `GymExerciseCatalog.select` (also used by the static preset-catalog
    /// builder, with a fixed rotation seed instead of a date-derived one).
    private func selectExercises(from pool: [GymExerciseDefinition],
                                 split: GymSplit,
                                 count: Int,
                                 maxDifficulty: Int,
                                 now: Date,
                                 variation: Int) -> [GymExerciseDefinition] {
        let daySeed = Int(now.timeIntervalSince1970 / 86_400)
        return GymExerciseCatalog.select(from: pool,
                                         targetGroups: split.targetedMuscleGroups,
                                         count: count,
                                         maxDifficulty: maxDifficulty,
                                         rotationSeed: daySeed &+ variation)
    }

    // MARK: Split freshness

    /// Hours after which a trained bucket counts as fully recovered in
    /// `score`. Capping keeps a never-trained secondary bucket (say, core on
    /// leg day) from deciding between two splits on its own.
    static let fullRecoveryHours = 72.0

    /// How rested a split is. Compared by `primaryHours` first, uncapped: the
    /// split whose main area waited longest is next, so a left-out leg day
    /// comes up, and the area just trained goes last (after Push + Full Body,
    /// neither push day). `score` only decides between splits that share their
    /// main area, like Push and Push + Full Body.
    ///
    /// Score first, capped at `fullRecoveryHours`, ranked a leg day left out
    /// for a week below a pull day from two days ago whenever core had been
    /// trained in between.
    struct SplitFreshness: Comparable {
        let score: Double
        let primaryHours: Double

        static func < (lhs: SplitFreshness, rhs: SplitFreshness) -> Bool {
            lhs.primaryHours != rhs.primaryHours ? lhs.primaryHours < rhs.primaryHours : lhs.score < rhs.score
        }
    }

    /// Priority-weighted recovery of the split's training buckets (weights 1,
    /// ½, ⅓, …), each capped at `fullRecoveryHours`.
    ///
    /// Buckets rather than muscle groups: "Arms" belongs to both push and pull
    /// days, so the old muscle-group version let a push day's tricep work
    /// reset the pull day's freshness too.
    static func freshness(for split: GymSplit,
                          lastTrained: [TrainingBucket: Date],
                          now: Date) -> SplitFreshness {
        func hours(_ bucket: TrainingBucket) -> Double {
            guard let date = lastTrained[bucket] else { return .greatestFiniteMagnitude }
            return max(now.timeIntervalSince(date) / 3600.0, 0)
        }
        var weighted = 0.0
        var totalWeight = 0.0
        for (index, bucket) in split.trainingBuckets.enumerated() {
            let weight = 1.0 / Double(index + 1)
            weighted += min(hours(bucket), fullRecoveryHours) * weight
            totalWeight += weight
        }
        let primary = split.trainingBuckets.first.map(hours) ?? 0
        return SplitFreshness(score: totalWeight > 0 ? weighted / totalWeight : 0,
                              primaryHours: primary)
    }

    /// When each training bucket was last worked, from performed exercises
    /// (catalog bucket when known, else inferred from the muscle group). A
    /// record without them still has its ordered exercise ids, which the
    /// catalog resolves for its own exercises; failing that, the workout's
    /// own muscle group.
    static func lastTrainedByBucket(history: [FinishedWorkout]) -> [TrainingBucket: Date] {
        var last: [TrainingBucket: Date] = [:]
        for finished in history {
            let exercises = finished.performedExercises
            let trained: [TrainingBucket]
            if !exercises.isEmpty {
                trained = exercises.flatMap { exercise in
                    GymExerciseCatalog.byID[exercise.id].map { [$0.bucket] }
                        ?? buckets(forMuscleGroup: exercise.muscleGroup)
                }
            } else {
                // The exercises may still be on their way from iCloud, or the
                // record came from the watch without them. Its muscle group
                // alone can't tell a Push + Full Body day from a pull one.
                let byID = finished.exercisesSequenceID.compactMap { GymExerciseCatalog.byID[$0]?.bucket }
                trained = byID.isEmpty ? buckets(forMuscleGroup: finished.muscleGroup) : byID
            }
            for bucket in trained where last[bucket].map({ $0 < finished.endDate }) ?? true {
                last[bucket] = finished.endDate
            }
        }
        return last
    }

    /// Best-effort bucket for a muscle group. "Arms" is deliberately empty —
    /// it can't be told apart (biceps are pull, triceps are push).
    static func buckets(forMuscleGroup muscleGroup: Int) -> [TrainingBucket] {
        switch WorkoutCategory(rawValue: muscleGroup) {
        case .chest, .shoulders: return [.push]
        case .back:              return [.pull]
        case .upperbody:         return [.push, .pull]
        case .legs:              return [.legs]
        case .core:              return [.core]
        case .fullbody:          return [.fullBody]
        default:                 return []
        }
    }

    private func buildRationale(split: GymSplit, recovery: RecoveryEstimate, count: Int,
                                isChosen: Bool = false) -> String {
        // With no recovery signals the score is only the neutral default —
        // don't tell the user they're "well recovered" when nothing was measured.
        if recovery.signals.isEmpty {
            // A chosen type wasn't "picked for the muscles you've rested longest".
            if isChosen {
                return String(format: NSLocalizedString("A full %d-exercise %@ session.", comment: "Generator rationale when there's no recovery data and the user chose the workout type"), count, split.displayName)
            }
            return String(format: NSLocalizedString("A full %d-exercise %@ session, picked for the muscles you've rested longest.", comment: "Generator rationale when there's no recovery data"), count, split.displayName)
        }
        switch recovery.band {
        case .ready:
            return String(format: NSLocalizedString("You're well recovered, so here's a full %d-exercise %@ session.", comment: "Generator rationale"), count, split.displayName)
        case .moderate:
            return String(format: NSLocalizedString("Recovery is moderate — a balanced %@ session that won't overreach.", comment: "Generator rationale"), split.displayName)
        case .rest:
            return String(format: NSLocalizedString("Recovery is low, so this is a lighter %@ session to keep you moving.", comment: "Generator rationale"), split.displayName)
        }
    }
}

// MARK: - What was actually trained

extension FinishedWorkout {
    /// The exercises the user actually did, as far as the record can tell.
    ///
    /// `exercises` is copied from the *planned* workout, so skipped exercises
    /// would otherwise count as trained. Rep-based sets are logged
    /// automatically, so when a session has any logged sets, a rep-based
    /// exercise without one was skipped. Timed exercises never log sets and are
    /// kept. Sessions with no logged sets at all (Apple Watch, older records)
    /// fall back to the full planned list.
    var performedExercises: [Exercise] {
        let planned = exercises ?? []
        let loggedIDs = Set(setReps.filter { !$0.value.isEmpty }.keys)
            .union(setWeights.filter { !$0.value.isEmpty }.keys)
        guard !loggedIDs.isEmpty else { return planned }
        return planned.filter { loggedIDs.contains($0.id) || $0.repCount == 0 }
    }
}

// MARK: - Materialisation into SwiftData

extension PersonalizedWorkoutPlan {

    /// Creates (or reuses) `Exercise` records and returns a ready-to-insert
    /// `Workout`. Mirrors the seed-id reuse strategy of the gym generator so we
    /// don't create duplicate exercise rows. The caller inserts + saves.
    func makeWorkout(in context: ModelContext,
                     existingExercises: [Exercise],
                     name: String) -> Workout {
        let entities: [Exercise] = exercises.map {
            $0.materialize(in: context, existing: existingExercises)
        }

        let workout = Workout(
            id: UUID().uuidString,
            infoText: rationale,
            isUserGenerated: true,
            isNew: true,
            muscleGroup: split.primaryMuscleGroup,
            setLength: setLength,
            straightSets: false,
            difficultyInt: difficultyInt,
            name: name,
            duration: durationMinutes,
            exercisesSequenceID: entities.map { $0.id },
            finishedExercisesSequence: [],
            exercises: entities,
            plan: [],
            workoutActivityType: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
            workoutSessionLocation: Int(HKWorkoutSessionLocationType.indoor.rawValue))
        workout.predictedDifficulty = prediction.rawRating
        return workout
    }
}

#if DEBUG
// MARK: - Debug mock health data (Simulator testing only)

/// DEBUG-only source of fake recovery signals. HealthKit on the Simulator has
/// no HRV / resting-HR / sleep samples (and resting HR is read-only, so it
/// can't be back-filled), so this injects realistic values directly into the
/// recovery pipeline when the toggle in the Smart-workout screen is on.
/// Entirely compiled out of release builds.
enum DebugHealthData {
    private static let key = "debug.useMockHealthData"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// A "well-recovered" profile: HRV above the normal range, low resting HR,
    /// solid sleep, balanced training load → a high recovery score. Includes
    /// two weeks of history so the personal-baseline paths are exercised.
    static func mockInputs(history: [FinishedWorkout], now: Date) -> RecoveryInputs {
        RecoveryInputs(
            hrvSDNN: 68,
            hrvHistory: [55, 52, 58, 54, 57, 53, 56, 51, 59, 55, 54, 57, 52, 56],
            restingHR: 52,
            restingHRHistory: [57, 58, 56, 59, 58, 57, 60, 58, 57, 59, 58, 56, 57, 58],
            sleepHoursLastNight: 7.8,
            sleepHistory: [7.4, 7.9, 7.2, 8.1, 7.6, 7.5, 7.8, 0, 7.3, 7.7, 8.0, 7.4, 7.6, 7.9],
            acuteLoad: 1_300,
            chronicLoad: 1_400)
    }

    /// A swim from Apple's Workout app two days ago and a Strava ride
    /// yesterday, standing in for other apps' HealthKit workouts.
    static func mockExternalWorkouts(now: Date) -> [ExternalWorkout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(daysAgo: Int, hour: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: -daysAgo, hour: hour), to: today) ?? now
        }
        let swim = at(daysAgo: 2, hour: 18), ride = at(daysAgo: 1, hour: 7)
        return [
            ExternalWorkout(start: swim, end: swim.addingTimeInterval(45 * 60),
                            activityType: Int(HKWorkoutActivityType.swimming.rawValue),
                            sourceName: "Workout", distanceMeters: 1_500),
            ExternalWorkout(start: ride, end: ride.addingTimeInterval(62 * 60),
                            activityType: Int(HKWorkoutActivityType.cycling.rawValue),
                            sourceName: "Strava", distanceMeters: 24_300)
        ]
    }
}
#endif
