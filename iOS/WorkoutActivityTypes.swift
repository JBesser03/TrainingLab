//
//  WorkoutActivityTypes.swift
//  Workout App (iOS)
//
//  The HealthKit activity types the app offers (custom workouts, weekly
//  goals) and the SF Symbol for each. One list, so the workout editor and the
//  goal picker can't drift apart. Localized names live with the other
//  `HKWorkoutActivityType` display code in FinishedWorkoutView.swift.
//

import HealthKit

extension HKWorkoutActivityType {

    /// Every activity type a user can pick, in the workout editor's order.
    static let selectable: [HKWorkoutActivityType] = [
        .americanFootball,
        .archery,
        .australianFootball,
        .badminton,
        .baseball,
        .basketball,
        .bowling,
        .boxing,
        .climbing,
        .crossTraining,
        .curling,
        .cycling,
        .elliptical,
        .equestrianSports,
        .fencing,
        .fishing,
        .functionalStrengthTraining,
        .golf,
        .gymnastics,
        .handball,
        .hiking,
        .hockey,
        .hunting,
        .lacrosse,
        .martialArts,
        .mindAndBody,
        .paddleSports,
        .play,
        .preparationAndRecovery,
        .racquetball,
        .rowing,
        .rugby,
        .running,
        .sailing,
        .skatingSports,
        .snowSports,
        .soccer,
        .softball,
        .squash,
        .stairClimbing,
        .surfingSports,
        .swimming,
        .tableTennis,
        .tennis,
        .trackAndField,
        .traditionalStrengthTraining,
        .volleyball,
        .walking,
        .waterFitness,
        .waterPolo,
        .waterSports,
        .wrestling,
        .yoga,
        .other,

        .barre,
        .coreTraining,
        .crossCountrySkiing,
        .downhillSkiing,
        .flexibility,
        .highIntensityIntervalTraining,
        .jumpRope,
        .kickboxing,
        .pilates,
        .snowboarding,
        .stairs,
        .stepTraining,
        .wheelchairWalkPace,
        .wheelchairRunPace,

        .taiChi,
        .mixedCardio,
        .handCycling,

        .discSports,
        .fitnessGaming
    ]

    /// What a logged workout of type `current` can be changed to (in the
    /// workout's editor): the common sports first, then the rest by name.
    /// The two strength types are both named "Strength Training", so only
    /// one is offered — the workout's own if it's either. A type that isn't
    /// selectable stays among them, so the current one is always listed.
    static func pickerSections(current: HKWorkoutActivityType) -> (popular: [HKWorkoutActivityType], others: [HKWorkoutActivityType]) {
        let strength: HKWorkoutActivityType = current == .functionalStrengthTraining
            ? .functionalStrengthTraining : .traditionalStrengthTraining
        let popular: [HKWorkoutActivityType] = [strength, .highIntensityIntervalTraining, .running, .cycling,
                                                .swimming, .walking, .hiking, .yoga, .rowing]
        var others = selectable.filter {
            !popular.contains($0) && $0 != .traditionalStrengthTraining && $0 != .functionalStrengthTraining
        }
        if !popular.contains(current) && !others.contains(current) { others.append(current) }
        return (popular, others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    /// SF Symbol for the activity — Apple's own figure where there is one.
    var symbolName: String {
        switch self {
        case .americanFootball:              return "figure.american.football"
        case .archery:                       return "figure.archery"
        case .australianFootball:            return "figure.australian.football"
        case .badminton:                     return "figure.badminton"
        case .barre:                         return "figure.barre"
        case .baseball:                      return "figure.baseball"
        case .basketball:                    return "figure.basketball"
        case .bowling:                       return "figure.bowling"
        case .boxing:                        return "figure.boxing"
        case .climbing:                      return "figure.climbing"
        case .coreTraining:                  return "figure.core.training"
        case .crossCountrySkiing:            return "figure.skiing.crosscountry"
        case .crossTraining:                 return "figure.cross.training"
        case .curling:                       return "figure.curling"
        case .cycling:                       return "figure.outdoor.cycle"
        case .discSports:                    return "figure.disc.sports"
        case .downhillSkiing:                return "figure.skiing.downhill"
        case .elliptical:                    return "figure.elliptical"
        case .equestrianSports:              return "figure.equestrian.sports"
        case .fencing:                       return "figure.fencing"
        case .fishing:                       return "figure.fishing"
        case .fitnessGaming:                 return "gamecontroller.fill"
        case .flexibility, .preparationAndRecovery: return "figure.flexibility"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .golf:                          return "figure.golf"
        case .gymnastics:                    return "figure.gymnastics"
        case .handCycling:                   return "figure.hand.cycling"
        case .handball:                      return "figure.handball"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .hiking:                        return "figure.hiking"
        case .hockey:                        return "figure.hockey"
        case .hunting:                       return "figure.hunting"
        case .jumpRope:                      return "figure.jumprope"
        case .kickboxing:                    return "figure.kickboxing"
        case .lacrosse:                      return "figure.lacrosse"
        case .martialArts:                   return "figure.martial.arts"
        case .mindAndBody:                   return "figure.mind.and.body"
        case .paddleSports:                  return "oar.2.crossed"
        case .pilates:                       return "figure.pilates"
        case .play:                          return "figure.play"
        case .racquetball:                   return "figure.racquetball"
        case .rowing:                        return "figure.rower"
        case .rugby:                         return "figure.rugby"
        case .running:                       return "figure.run"
        case .sailing:                       return "figure.sailing"
        case .skatingSports:                 return "figure.skating"
        case .snowSports:                    return "snowflake"
        case .snowboarding:                  return "figure.snowboarding"
        case .soccer:                        return "figure.soccer"
        case .softball:                      return "figure.softball"
        case .squash:                        return "figure.squash"
        case .stairClimbing:                 return "figure.stair.stepper"
        case .stairs:                        return "figure.stairs"
        case .stepTraining:                  return "figure.step.training"
        case .surfingSports:                 return "figure.surfing"
        case .swimming:                      return "figure.pool.swim"
        case .tableTennis:                   return "figure.table.tennis"
        case .taiChi:                        return "figure.taichi"
        case .tennis:                        return "figure.tennis"
        case .trackAndField:                 return "figure.track.and.field"
        case .volleyball:                    return "figure.volleyball"
        case .walking:                       return "figure.walk"
        case .waterFitness:                  return "figure.water.fitness"
        case .waterPolo:                     return "figure.waterpolo"
        case .waterSports:                   return "figure.open.water.swim"
        case .wheelchairRunPace:             return "figure.roll.runningpace"
        case .wheelchairWalkPace:            return "figure.roll"
        case .wrestling:                     return "figure.wrestling"
        case .yoga:                          return "figure.yoga"
        default:                             return "figure.mixed.cardio"
        }
    }
}
