//
//  PlanHorizontalScrollView.swift
//  Workout App (iOS)
//
//  Created by Justus Besser on 24.02.24.
//

import SwiftUI
import HealthKit

/// A titled row of plan cards.
struct PlanHorizontalScrollView: View {
    
    var title: String
    var plans: [Plan]
    @Namespace private var zoom
    
    var body: some View {
        
        VStack(spacing: 4) {
            Text(title)
                .sectionTitleStyle()
                .padding(.horizontal)
                .padding(.top, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(plans, id: \.self) { plan in
                        NavigationLink {
                            PlanPreview(plan: plan)
                                .navigationTransition(.zoom(sourceID: plan.id, in: zoom))
                        } label: {
                            PlanCard(plan: plan)
                                .zoomSource(id: plan.id, in: zoom)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                // As tall as the tallest card; see `HorizontalScrollView`.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            // The cards' shadows in a frosted style reach past the row.
            .scrollClipDisabled()
        }
    }
}

#Preview {
    PlanHorizontalScrollView(title: "Your plans", plans: [Plan.samples[0], Plan.samples[1]])
}

