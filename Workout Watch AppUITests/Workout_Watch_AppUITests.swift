//
//  Workout_Watch_AppUITests.swift
//  Workout Watch AppUITests
//
//  UI tests for the watch app. Drive the running app via XCUIApplication —
//  cover the workout-list landing screen and the Health row that asks for
//  HealthKit access while it's missing.
//

import XCTest

final class Workout_Watch_AppUITests: XCTestCase {

    private var app: XCUIApplication!

    // Main actor, where XCUIApplication has to be used.
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Labels below are the English strings; pin the language so the tests
        // don't depend on the simulator's locale.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    /// The workout list only builds rows that are on screen, and the watch
    /// screen is small — swipe up until the element appears.
    @MainActor @discardableResult
    /// Swipes down the list until the element is on screen, then back up:
    /// a swipe on the watch scrolls about a screen, so a row just below the
    /// last one found can end up above the top, where the list no longer
    /// keeps it.
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 5) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) { return true }
        }
        for _ in 0..<maxSwipes {
            app.swipeDown()
            if element.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    // MARK: - Launch / landing screen

    /// The watch ContentView navigation title is "Workouts". If the app
    /// crashes on launch (HealthKit init failure, duplicate ModelContainer,
    /// missing entitlement, etc.) this fails before everything else.
    @MainActor
    func testAppLaunchesAndShowsWorkoutsList() throws {
        let title = app.staticTexts["Workouts"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Watch app didn't render the Workouts list within 5s"
        )
    }

    /// All four start-workout rows must be present (HIIT, Running,
    /// Cycling, Strength). Catches regressions where ContentView's
    /// `Start New Workout` section accidentally drops a row.
    @MainActor
    func testStartNewWorkoutSectionHasAllRows() throws {
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 5))

        let expectedRows = ["HIIT", "Running", "Cycling", "Strength"]
        for label in expectedRows {
            XCTAssertTrue(
                scrollTo(app.staticTexts[label]),
                "Start-new-workout row '\(label)' is missing"
            )
        }
    }

    /// Each row exposes a "Start" button. Tapping shouldn't crash the
    /// app — even on a simulator without HK the catch in
    /// `WatchWorkoutManager.startWorkout` should populate `lastError`
    /// instead of trapping.
    @MainActor
    func testTappingStartDoesNotCrash() throws {
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 5))

        // The watch UI shows multiple "Start" buttons (one per row). Tap
        // the first available one and assert the app is still alive.
        let firstStart = app.buttons["Start"].firstMatch
        if firstStart.waitForExistence(timeout: 3) {
            firstStart.tap()
            // Either the workout view appears or an error alert does;
            // in both cases the app should remain responsive.
            XCTAssertTrue(app.exists, "App died after tapping a Start button")
        }
    }

    // MARK: - Health section

    /// While workout access is missing, a "Health" section offers to ask for
    /// it — the implicit prompt can be skipped when the iPhone launches the
    /// app in the background. Once access is granted the section is hidden,
    /// and the UI test can't read HealthKit to tell the two apart, so it skips.
    @MainActor
    func testHealthAccessSectionIsVisible() throws {
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 5))
        guard scrollTo(app.staticTexts["Health"]) else {
            throw XCTSkip("Health access is already granted on this simulator, so the Health section is hidden")
        }
        let allow = app.buttons["Allow access"]
        let deniedHint = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "HealthKit access is off")).firstMatch
        XCTAssertTrue(
            scrollTo(allow) || deniedHint.exists,
            "Health section shows neither 'Allow access' nor the hint for denied access"
        )
    }

    /// Tapping "Allow access" starts a request. The HealthKit prompt itself
    /// can't be asserted, but the app must stay alive.
    @MainActor
    func testHealthAccessTapDoesNotCrash() throws {
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 5))
        let allow = app.buttons["Allow access"]
        guard scrollTo(allow) else {
            throw XCTSkip("Health access is already granted or denied on this simulator, so there's no button to tap")
        }
        allow.tap()
        XCTAssertTrue(app.exists, "App died after tapping Allow access")
    }
}
