//
//  PreviewContainer.swift
//  WorkoutApp (iOS)
//
//  Created by Justus Besser on 11.05.25.
//

import Foundation
import SwiftData

struct PreviewPlan {
    let container: ModelContainer
    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            container = try ModelContainer(for: Plan.self, configurations: config)
        } catch {
            fatalError("Could not create preview container")
        }
    }
    
    @MainActor
    func addExamples(_ examples: [Plan]) {
        examples.forEach { example in
            container.mainContext.insert(example)
        }
    }
}
