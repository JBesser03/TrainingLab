//
//  WatchSyncManager.swift
//  Workout Watch App
//
//  Created by Justus Besser on 22.08.25.
//

import Foundation
import Combine

// MARK: - Watch-side WorkoutSyncManager

/// Lightweight sync manager for the watch app UI.
/// The full WorkoutSyncManager lives in the iOS target.
@MainActor
class WorkoutSyncManager: ObservableObject {
    static let shared = WorkoutSyncManager()

    private init() {}

    /// Hook called by `WatchAppDelegate.handleBackgroundRefresh`. Intentionally
    /// a no-op: CloudKit handles SwiftData replication automatically and
    /// `WatchConnectivityManager` handles workout-state sync — there's
    /// nothing left to do here. The function exists so the background-refresh
    /// task can complete cleanly. (There is no sync status to show: CloudKit
    /// doesn't report one, so the watch UI no longer pretends to.)
    func syncInBackground() async {}
}
