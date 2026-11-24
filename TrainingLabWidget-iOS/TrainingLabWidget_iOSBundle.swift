//
//  TrainingLabWidget_iOSBundle.swift
//  TrainingLabWidget-iOS
//
//  Created by Justus Besser on 21.09.26.
//

import WidgetKit
import SwiftUI

@main
struct TrainingLabWidget_iOSBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
        WeeklyGoalsWidget()
    }
}
