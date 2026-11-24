import Foundation

public struct WorkoutMetrics: Equatable {
    // Current live heart rate (BPM)
    public var heartRate: Double?
    // Average heart rate over the workout (BPM)
    public var averageHeartRate: Double?
    // Maximum recorded heart rate (BPM)
    public var maxHeartRate: Double?
    // Active energy burned in kilocalories
    public var activeEnergyBurned: Double
    // Total energy burned in kilocalories
    public var totalEnergyBurned: Double
    // Distance in meters
    public var distance: Double
    // Step count
    public var steps: Int
    // Total workout elapsed time
    public var elapsedTime: TimeInterval
    // Current exercise elapsed time
    public var exerciseTime: TimeInterval

    public init(
        heartRate: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        activeEnergyBurned: Double = 0,
        totalEnergyBurned: Double = 0,
        distance: Double = 0,
        steps: Int = 0,
        elapsedTime: TimeInterval = 0,
        exerciseTime: TimeInterval = 0
    ) {
        self.heartRate = heartRate
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyBurned = activeEnergyBurned
        self.totalEnergyBurned = totalEnergyBurned
        self.distance = distance
        self.steps = steps
        self.elapsedTime = elapsedTime
        self.exerciseTime = exerciseTime
    }

    mutating func updateFromHealthMetrics(_ metrics: HealthMetrics) {
        if let hr = metrics.heartRate {
            heartRate = hr
            if maxHeartRate == nil || hr > maxHeartRate! {
                maxHeartRate = hr
            }
        }
        if let calories = metrics.activeCalories {
            activeEnergyBurned = calories
        }
        if let totalCal = metrics.totalCalories {
            totalEnergyBurned = totalCal
        }
        if let dist = metrics.distance {
            distance = dist
        }
        if let stepCount = metrics.steps {
            steps = stepCount
        }
    }
}
