//
//  Logger.swift
//  Workout Multiplatform
//
//  Created by Justus Besser on 18.10.23.
//

import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    #if os(watchOS)
    static let shared = Logger(subsystem: subsystem, category: "MirroringWorkoutsSampleForWatch")
    #else
    static let shared = Logger(subsystem: subsystem, category: "MirroringWorkoutsSample")
    #endif
}

/// Debug-only logging shim. Mirrors `print`'s variadic signature so it's a
/// drop-in replacement, but routes to the unified log and compiles to a no-op
/// in release builds — so diagnostic output (including any health details)
/// never ships to end users.
func appLog(_ items: Any..., separator: String = " ") {
    #if DEBUG
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    Logger.shared.debug("\(message, privacy: .public)")
    #endif
}
