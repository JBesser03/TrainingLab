//
//  ActivityRingView.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 28.12.23.
//

import SwiftUI
import HealthKitUI

struct ActivityRingView: UIViewRepresentable {
        
    var activitySummary: HKActivitySummary?
    var ringData: ActivityRingData?
    
    func makeUIView(context: Context) -> HKActivityRingView {
        let ringView = HKActivityRingView()
        ringView.setActivitySummary(activitySummary, animated: false)
        appLog("Summary: \(String(describing: activitySummary))")
        return ringView
    }
    
    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        uiView.setActivitySummary(activitySummary, animated: true)
    }
}
