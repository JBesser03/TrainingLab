//
//  Tests_iOS.swift
//  Tests iOS
//
//  UI tests for the iOS Workout app. The "Tests iOS" target is configured
//  as a UI testing bundle, so these run via XCUIApplication against a
//  running app — they exercise navigation, tab switching, sheet
//  presentation, and the settings toggles. Pure-logic tests for the
//  observer/sync subsystem belong in the watch's unit-test target (or in
//  a new iOS unit-test target, which would require adding a separate
//  product to the project).
//

import XCTest

final class Tests_iOS: XCTestCase {

    private var app: XCUIApplication!

    // Main actor, where XCUIApplication has to be used.
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // The launch tests rotate the simulator and leave it in landscape,
        // where rows further down Settings are off screen.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Labels below are the English strings; pin the language so the
        // tests don't depend on the simulator's locale.
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit", "-UITestSkipWhatsNew"]
        app.launch()
        declineHealthAccessIfAsked()
    }

    // MARK: - What's New

    /// After an update the sheet appears once; once dismissed it stays away
    /// on the next launch. `-whatsNewSeenVersion 0` fakes an older version for
    /// that single launch (the argument domain only overrides while passed).
    @MainActor
    func testWhatsNewShowsOnlyOnce() throws {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UITestSkipHealthKit", "-whatsNewSeenVersion", "0"]
        app.launch()
        let title = app.staticTexts["What's New"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "What's New didn't appear after an update")
        app.buttons["Continue"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(title.waitForExistence(timeout: 3), "What's New appeared a second time")
    }

    // MARK: - Launch / Tab bar

    /// Crashes-on-launch regression test. If TabBarView fails to build —
    /// e.g. a SwiftData query crashes, ModelContainer init fails, an
    /// EnvironmentObject is missing — `tabBars.firstMatch` won't exist.
    @MainActor
    func testAppLaunchesAndTabBarIsVisible() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "Main tab bar didn't appear within 5 seconds of launch"
        )
    }

    /// Every primary destination should be reachable. If any tab tap
    /// triggers a crash or hangs forever, the corresponding assertion
    /// fails. Tab labels come from TabBarView.swift.
    @MainActor
    func testAllTabsAreReachable() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let expectedTabs = ["For You", "Browse", "Plans", "History", "Settings"]
        for label in expectedTabs {
            let button = tabBar.buttons[label]
            XCTAssertTrue(
                button.waitForExistence(timeout: 2),
                "Tab '\(label)' not found in tab bar"
            )
            button.tap()
            // No specific content assertion — just confirm tapping doesn't crash.
            XCTAssertTrue(app.exists, "App died after selecting tab '\(label)'")
        }
    }

    // MARK: - Browse tab

    /// The Browse tab has a searchable workout list. The search field's prompt
    /// text "Search for Workouts" comes from WorkoutsView.swift.
    @MainActor
    func testWorkoutsTabExposesSearchField() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()

        let (searchField, searchButton) = revealBrowseSearch()
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 3) || searchButton.waitForExistence(timeout: 3),
            "Search field 'Search for Workouts' not found on Browse tab"
        )
    }

    /// The + button in the Browse tab opens the menu every way to make a
    /// workout lives in: build, generate, describe (see WorkoutsView.swift).
    @MainActor
    func testWorkoutsAddMenuExposesManualAndGenerate() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()

        let plusButton = app.buttons["browse.add"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 3), "Add (+) button not found on Browse toolbar")
        plusButton.tap()

        // Menu items resolve as buttons in the test hierarchy.
        let manualItem = app.buttons["Build a workout"]
        // The menu's animation can take a moment on a busy simulator.
        XCTAssertTrue(
            manualItem.waitForExistence(timeout: 5),
            "'Build a workout' menu item missing"
        )
        XCTAssertTrue(app.buttons["Generate a gym workout"].exists, "'Generate a gym workout' menu item missing")
        XCTAssertTrue(app.buttons["Describe a workout (Beta)"].exists, "'Describe a workout' menu item missing")

        // Dismiss the menu so subsequent tests start clean.
        app.tap()
    }

    /// Creates a workout by hand. Rows toggle their selection, and the saved
    /// workout holds exactly the exercises still selected — deselecting one
    /// must drop it.
    @MainActor
    func testAddWorkoutManuallySavesSelectedExercises() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()
        let addButton = app.buttons["browse.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()
        let manualItem = app.buttons["Build a workout"]
        XCTAssertTrue(manualItem.waitForExistence(timeout: 2))
        manualItem.tap()

        let name = "UITest \(Int.random(in: 1000...9999))"
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        // Return dismisses the keyboard, which would otherwise cover the lower
        // rows and take their taps.
        nameField.typeText(name + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "Keyboard still covers the form")

        // Exercises come from the picker sheet now.
        let addExercises = app.buttons["plannedExercises.add"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 5), "Add exercises button not found")
        addExercises.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "exercisePicker.row."))
        XCTAssertTrue(rows.element(boundBy: 3).waitForExistence(timeout: 5), "Exercise picker rows not found")
        // Rows fully on screen, addressed by their per-exercise identifier from
        // here on. An index into the query shifts as the list loads and
        // unloads rows, and then points at a different row or none.
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.frame.maxY - 80
        let ids = rows.allElementsBoundByIndex
            .filter { $0.frame.minY > top && $0.frame.maxY < bottom }
            .map(\.identifier)
        XCTAssertGreaterThanOrEqual(ids.count, 3, "Not enough exercise rows on screen")
        func exerciseName(_ row: XCUIElement) -> String { row.staticTexts.firstMatch.label }
        let first = app.buttons[ids[0]], second = app.buttons[ids[1]], third = app.buttons[ids[2]]
        let (dropped, kept1, kept2) = (exerciseName(first), exerciseName(second), exerciseName(third))

        first.tap()
        second.tap()
        XCTAssertTrue(first.isSelected)
        XCTAssertTrue(second.isSelected)
        first.tap()
        XCTAssertFalse(first.isSelected, "Tapping a selected exercise again should deselect it")
        third.tap()
        app.buttons["Add (2)"].tap()
        XCTAssertTrue(app.staticTexts[kept1].waitForExistence(timeout: 5), "\(kept1) missing from the form")
        app.navigationBars.buttons["Save"].tap()

        // Find the new workout through Browse search and open it.
        let (search, searchButton) = revealBrowseSearch()
        if !search.waitForExistence(timeout: 3), searchButton.exists {
            searchButton.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Browse search field not found")
        search.tap()
        search.typeText(name + "\n")   // submit, so the keyboard doesn't cover the result
        // A search result row, by its identifier: the new workout also has a
        // card in the Browse rows behind the results, with the same name,
        // which can't be tapped there — and on iOS 27 even asking whether
        // it's hittable fails the test.
        let result = app.buttons.matching(identifier: "browse.searchResult")
            .matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Saved workout not shown in the search results")
        result.tap()

        XCTAssertTrue(app.staticTexts[kept1].waitForExistence(timeout: 5), "\(kept1) missing from the workout")
        XCTAssertTrue(scrollTo(app.staticTexts[kept2]), "\(kept2) missing from the workout")
        XCTAssertFalse(app.staticTexts[dropped].exists, "Deselected \(dropped) was saved anyway")
        saveScreenshot("manual-workout-saved")

        // Delete it again, so runs don't pile up test workouts.
        let edit = app.buttons["Edit Workout"]
        XCTAssertTrue(scrollTo(edit), "Edit Workout button not found")
        edit.tap()
        // A toolbar button now, no longer below every exercise.
        let deleteButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Delete Workout"))
        XCTAssertTrue(deleteButtons.firstMatch.waitForExistence(timeout: 5), "Delete Workout button not found")
        let toolbarButtonFrame = deleteButtons.firstMatch.frame
        deleteButtons.firstMatch.tap()
        // The confirmation dialog adds a second button with the same label.
        // Pick it by position — the two come in a different order on iOS 26
        // and 27.
        let confirmShown = NSPredicate(format: "count > 1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: confirmShown, object: deleteButtons)], timeout: 5),
                       .completed, "Delete confirmation didn't appear")
        let confirm = try XCTUnwrap(deleteButtons.allElementsBoundByIndex.first { $0.frame != toolbarButtonFrame },
                                    "Delete confirmation button not found")
        confirm.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
                        .waitForNonExistence(timeout: 5), "Test workout still listed after deleting it")
    }

    // MARK: - Settings tab

    /// Settings should show every section header from SettingsView.swift.
    /// Catches regressions where a section is accidentally removed.
    @MainActor
    func testSettingsShowsAllSections() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Settings"].tap()

        let nav = app.navigationBars["Settings"]
        XCTAssertTrue(nav.waitForExistence(timeout: 3), "Settings nav title missing")

        let expectedSectionHeaders = [
            "Appearance", "Notifications", "Workout", "Apple Health", "Apple Watch", "Gym", "Data"
        ]
        for header in expectedSectionHeaders {
            XCTAssertTrue(
                scrollTo(app.staticTexts[header]),
                "Settings section header '\(header)' missing"
            )
        }
    }

    /// Picking a style shows it selected and keeps the choice.
    @MainActor
    func testStyleCanBeChanged() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Settings"].tap()

        let ocean = app.buttons["settings.theme.ocean"]
        XCTAssertTrue(ocean.waitForExistence(timeout: 3), "Styles missing in Settings")
        ocean.tap()
        XCTAssertTrue(app.buttons["settings.theme.ocean"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.theme.ocean"].isSelected, "Ocean not selected after tapping it")
        XCTAssertFalse(app.buttons["settings.theme.earth"].isSelected)
        saveScreenshot("style-ocean")

        // Back to the default, so other tests see the usual style.
        app.buttons["settings.theme.clay"].tap()
        XCTAssertTrue(app.buttons["settings.theme.clay"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.theme.clay"].isSelected)
    }

    /// The bookmark in Browse's toolbar lists every saved workout; removing a
    /// bookmark there keeps the row until the list is left.
    @MainActor
    func testSavedWorkoutsListFromBrowse() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()

        let savedButton = app.buttons["browse.saved"]
        XCTAssertTrue(savedButton.waitForExistence(timeout: 3), "No saved workouts button")
        savedButton.tap()
        XCTAssertTrue(app.staticTexts["No saved workouts"].waitForExistence(timeout: 3), "No empty state")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Bookmark a card: its bookmark sits in the top trailing corner.
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Cardio & HIIT'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "No HIIT card")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()

        savedButton.tap()
        let row = app.buttons.matching(identifier: "savedWorkouts.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The bookmarked workout isn't listed")
        XCTAssertTrue(row.label.contains("Cardio & HIIT"), "Unexpected row: \(row.label)")
        XCTAssertEqual(app.buttons.matching(identifier: "savedWorkouts.row").count, 1)

        // Unbookmark it: the row stays until the list is left.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Saved Workouts"].exists || app.navigationBars["Saved Workouts"].exists)
        XCTAssertTrue(row.exists, "The row vanished right away")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        savedButton.tap()
        XCTAssertTrue(app.staticTexts["No saved workouts"].waitForExistence(timeout: 3), "The bookmark wasn't removed")
    }

    /// A workout's own page bookmarks it too — from anywhere it opens, like
    /// the carousel at the top of Browse — and the saved list follows.
    @MainActor
    func testWorkoutPageBookmarks() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()

        let featured = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Upper Body'")).firstMatch
        XCTAssertTrue(featured.waitForExistence(timeout: 3), "No carousel card")
        featured.tap()
        let bookmark = app.buttons["preview.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3), "No bookmark on the workout page")
        XCTAssertEqual(bookmark.label, "Bookmark")
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["browse.saved"].tap()
        let row = app.buttons.matching(identifier: "savedWorkouts.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The bookmarked workout isn't listed")
        XCTAssertTrue(row.label.contains("Upper Body"), "Unexpected row: \(row.label)")

        // Removed on its page, it's gone from the list on coming back.
        row.tap()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3))
        bookmark.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["No saved workouts"].waitForExistence(timeout: 3), "The list kept the workout")
    }

    /// The bookmark in the Plans toolbar lists every saved plan; a plan's
    /// own page bookmarks it, even one from the catalog list.
    @MainActor
    func testSavedPlansFromPlansTab() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Plans"].tap()

        let savedButton = app.buttons["plans.saved"]
        XCTAssertTrue(savedButton.waitForExistence(timeout: 3), "No saved plans button")
        savedButton.tap()
        XCTAssertTrue(app.staticTexts["No saved plans"].waitForExistence(timeout: 3), "No empty state")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let plan = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Full Body Starter'")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 3), "No catalog plan")
        plan.tap()
        let bookmark = app.buttons["planPreview.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 3), "No bookmark on the plan page")
        XCTAssertEqual(bookmark.label, "Bookmark")
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove bookmark")

        // A bookmark is kept even when the app is closed right away.
        func relaunchToSavedPlans() {
            app.terminate()
            app.launch()
            XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
            tabBar.buttons["Plans"].tap()
            XCTAssertTrue(savedButton.waitForExistence(timeout: 3))
            savedButton.tap()
        }
        relaunchToSavedPlans()
        let row = app.buttons.matching(identifier: "savedPlans.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "The bookmarked plan isn't listed")
        XCTAssertTrue(row.label.contains("Full Body Starter"), "Unexpected row: \(row.label)")

        // Unbookmark it: the row stays until the list is left.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(row.exists, "The row vanished right away")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        savedButton.tap()
        XCTAssertTrue(app.staticTexts["No saved plans"].waitForExistence(timeout: 3), "The bookmark wasn't removed")
        relaunchToSavedPlans()
        XCTAssertTrue(app.staticTexts["No saved plans"].waitForExistence(timeout: 3), "The removal wasn't kept")
    }

    /// The Apple Watch usage toggle gates the "Send to watch" / auto-launch
    /// behavior on the watch app. Flipping it should not crash and should
    /// land in a different state.
    @MainActor
    func testAppleWatchToggleCanBeFlipped() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Settings"].tap()

        let toggle = app.switches["Use Apple Watch"]
        XCTAssertTrue(
            scrollTo(toggle),
            "Apple Watch toggle not found in Settings"
        )

        // On iOS 26 tapping the Toggle element hits its label, not the
        // switch — tap the switch control itself.
        let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        let initialValue = (toggle.value as? String) ?? "0"
        control.tap()

        // The toggle's `value` flips between "0" and "1". Wait briefly for
        // the animation to settle.
        let predicate = NSPredicate(format: "value != %@", initialValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        let result = XCTWaiter.wait(for: [expectation], timeout: 2)
        XCTAssertEqual(result, .completed, "Apple Watch toggle didn't change state")

        // Restore so we don't leave persisted state behind for the next run.
        control.tap()
    }

    /// Tapping the "My gym equipment" row should present the equipment
    /// picker sheet (GymEquipmentPickerView). Catches regressions where
    /// the sheet binding gets disconnected.
    @MainActor
    func testGymEquipmentPickerOpens() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Settings"].tap()

        // The row's label also carries the equipment count ("My gym equipment, 5").
        let gymRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My gym equipment")).firstMatch
        XCTAssertTrue(
            scrollTo(gymRow),
            "'My gym equipment' row missing in Settings"
        )
        gymRow.tap()

        // GymEquipmentPickerView shows "Available equipment" as a section
        // header.
        XCTAssertTrue(
            app.staticTexts["Available equipment"].waitForExistence(timeout: 3),
            "Equipment picker sheet did not present"
        )
    }

    // MARK: - Plans tab

    /// Plans tab renders, groups the catalog by goal, and the level filter
    /// narrows it.
    @MainActor
    func testPlansTabRenders() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Plans"].tap()

        let nav = app.navigationBars["Plans"]
        XCTAssertTrue(nav.waitForExistence(timeout: 3), "Plans nav title missing")
        XCTAssertTrue(app.staticTexts["Strength & muscle"].waitForExistence(timeout: 5), "Goal groups missing")
        // A row is one button whose label starts with the plan's name; a
        // built-in plan's level is on its own line, not in the name.
        func rows(_ name: String, level: String) -> XCUIElementQuery {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", name, level))
        }
        XCTAssertTrue(rows("Push Pull Legs", level: "Beginner").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows("Push Pull Legs", level: "Beginner").count, 1, "A plan is listed more than once")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Legs — '")).firstMatch.exists,
                       "A plan's name still carries its level")
        saveScreenshot("plans-grouped")

        app.segmentedControls["plans.level"].buttons["Advanced"].tap()
        XCTAssertTrue(rows("Push Pull Legs", level: "Advanced").firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(rows("Push Pull Legs", level: "Beginner").firstMatch.exists, "Level filter didn't apply")
        app.segmentedControls["plans.level"].buttons["All levels"].tap()
    }

    // MARK: - Exercise library

    /// The exercise library is the "Exercise library" row at the top of Browse.
    @MainActor
    func testExerciseLibraryOpensFromBrowse() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Browse"].tap()

        let exercisesButton = app.buttons["browse.exerciseLibrary"]
        XCTAssertTrue(exercisesButton.waitForExistence(timeout: 3), "Exercise library row missing on Browse")
        exercisesButton.tap()

        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 3), "Exercise library did not open")
    }

    // MARK: - History tab

    @MainActor
    func testHistoryTabRenders() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["History"].tap()
        XCTAssertTrue(tabBar.exists, "Tab bar disappeared after History tap")
    }

    /// A workout saved as the wrong sport — a swim the watch reported as
    /// strength training — can be changed afterwards; the type decides
    /// which weekly goal it counts toward.
    @MainActor
    func testWorkoutTypeCanBeCorrected() throws {
        startCatalogWorkout("Push", level: "Advanced")
        app.buttons["activeWorkout.primary"].tap()
        app.buttons["End workout"].tap()
        app.buttons["End and save"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "No summary")
        done.tap()

        app.tabBars.firstMatch.buttons["History"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Push'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The workout isn't in History")
        row.tap()
        app.buttons["More"].tap()
        app.buttons["Edit"].tap()

        let type = app.buttons["editWorkout.type"]
        XCTAssertTrue(type.waitForExistence(timeout: 3), "No workout type row")
        XCTAssertTrue(type.label.contains("Strength Training"), "Unexpected type: \(type.label)")
        type.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3), "No search in the type list")
        search.tap()
        search.typeText("Swim")
        app.buttons["Swimming"].firstMatch.tap()
        XCTAssertTrue(type.waitForExistence(timeout: 3))
        XCTAssertTrue(type.label.contains("Swimming"), "Type not changed: \(type.label)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Swimming"].waitForExistence(timeout: 3), "The workout doesn't show its new type")

        // Leave no history behind.
        app.buttons["More"].tap()
        app.buttons["Delete workout"].tap()
        let confirm = app.buttons["Delete workout"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
    }

    // MARK: - Without Apple Intelligence

    /// For You and "Describe a workout" must be fully usable on iPhones
    /// without Apple Intelligence (anything older than the 15 Pro). The DEBUG
    /// launch argument makes the app behave that way even on a Mac or device
    /// that has it. Also covers the no-health-data case by declining HealthKit.
    @MainActor
    func testForYouAndDescribeWorkoutWorkWithoutAppleIntelligence() throws {
        app.terminate()
        app.launchArguments = ["-SimulateNoAppleIntelligence", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit", "-UITestSkipWhatsNew"]
        app.launch()
        declineHealthAccessIfAsked()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["For You"].tap()

        // The page must finish loading — nothing may wait on the model.
        let spinner = app.staticTexts["Analyzing your recovery…"]
        let startWorkout = app.buttons["Start workout"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 15), "Generated gym workout card never appeared")
        XCTAssertFalse(spinner.exists, "For You is still loading")
        saveScreenshot("foryou-top")

        app.swipeUp()
        saveScreenshot("foryou-scrolled")
        app.swipeDown()

        // Regenerate still produces a workout card without the model.
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.waitForExistence(timeout: 5))
        regenerate.tap()
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 15), "No workout after regenerating")

        // "Describe a workout" falls back to the keyword parser — in German too.
        tabBar.buttons["Browse"].tap()
        let plus = app.buttons["browse.add"]
        XCTAssertTrue(plus.waitForExistence(timeout: 3))
        plus.tap()
        let describe = app.buttons["Describe a workout (Beta)"]
        XCTAssertTrue(describe.waitForExistence(timeout: 5))
        describe.tap()

        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Oberkörper nur mit Kurzhanteln, 45 Minuten")
        app.buttons["Generate"].tap()

        XCTAssertTrue(app.staticTexts["Upper Body · 45 min"].waitForExistence(timeout: 10),
                      "Keyword parser didn't produce the expected workout")
        saveScreenshot("describe-workout")
        // The note is a footer below the exercises; Form only builds visible rows.
        app.swipeUp()
        let fallbackNote = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "basic parsing")).firstMatch
        XCTAssertTrue(fallbackNote.exists, "Fallback note missing")
    }

    /// The gym card's type chips swap the workout to another type, and the
    /// recommended chip (labelled ", recommended" for VoiceOver, and named in
    /// a note while another type is chosen) swaps it back. Without
    /// Apple Intelligence the card title is the type's name, so it shows
    /// which type the card holds.
    @MainActor
    func testForYouTypePickerSwitchesWorkout() throws {
        app.terminate()
        app.launchArguments = ["-SimulateNoAppleIntelligence", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit", "-UITestSkipWhatsNew"]
        app.launch()
        declineHealthAccessIfAsked()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["For You"].tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 15), "Generated gym workout card never appeared")

        let recommended = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", recommended")).firstMatch
        XCTAssertTrue(scrollTo(recommended), "Type picker missing")
        XCTAssertTrue(recommended.isSelected, "The recommended type should be selected at first")
        let recommendedName = recommended.label.replacingOccurrences(of: ", recommended", with: "")
        let recommendedNote = app.staticTexts["Recommended: \(recommendedName)"]
        XCTAssertFalse(recommendedNote.exists, "The note is only for when another type is chosen")

        // Any other on-screen type; the recommended one carries the suffix,
        // so it never matches a bare name here.
        let other = try XCTUnwrap(["Push", "Pull", "Legs"].map { app.buttons[$0] }.first { $0.exists && $0.isHittable },
                                  "No other type chip on screen")
        let otherName = other.label
        other.tap()
        XCTAssertTrue(app.staticTexts[otherName].waitForExistence(timeout: 5), "Card didn't switch to \(otherName)")
        XCTAssertTrue(app.buttons[otherName].isSelected)
        XCTAssertFalse(recommended.isSelected)
        XCTAssertTrue(recommendedNote.exists, "Missing the note naming the recommended type")
        saveScreenshot("foryou-type-chosen")

        recommended.tap()
        XCTAssertTrue(app.staticTexts[recommendedName].waitForExistence(timeout: 5), "Card didn't switch back to \(recommendedName)")
        XCTAssertTrue(recommended.isSelected)
        XCTAssertTrue(recommendedNote.waitForNonExistence(timeout: 5))
    }

    /// One tap on a workout's + adds that workout once, and another tap adds it
    /// again. The buttons shared one Form row, so a tap used to fire all of them.
    @MainActor
    func testAddPlanAddsOneWorkoutPerTap() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Plans"].tap()
        let addPlan = app.buttons["plans.add"]
        XCTAssertTrue(addPlan.waitForExistence(timeout: 10))
        addPlan.tap()
        let build = app.buttons["Build a plan"]
        XCTAssertTrue(build.waitForExistence(timeout: 5), "'Build a plan' menu item missing")
        build.tap()

        let addButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planEditor.add.'"))
        let first = addButtons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "No workouts to add")
        let firstID = first.identifier
        XCTAssertTrue(scrollTo(first))
        first.tap()

        let removeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planEditor.remove.'"))
        XCTAssertTrue(removeButtons.firstMatch.waitForExistence(timeout: 5), "Nothing was added")
        XCTAssertEqual(removeButtons.count, 1, "One tap added \(removeButtons.count) workouts")

        // The same workout can be in a plan twice.
        let workoutID = firstID.replacingOccurrences(of: "planEditor.add.", with: "")
        app.buttons[firstID].tap()
        XCTAssertEqual(removeButtons.count, 2, "The second tap didn't add it again")
        XCTAssertEqual(app.staticTexts["planEditor.count.\(workoutID)"].label, "2×")
        saveScreenshot("plan-added-twice")

        // − removes just one; nothing is saved without Save.
        removeButtons.firstMatch.tap()
        XCTAssertEqual(removeButtons.count, 1)
        removeButtons.firstMatch.tap()
        XCTAssertTrue(removeButtons.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["planEditor.count.\(workoutID)"].exists)
        app.buttons["Cancel"].tap()
    }

    /// A run has no exercises: no countdown or exercise controls, nothing ends
    /// it on its own, and Finish saves it to the history (removed again here).
    @MainActor
    func testRunHasNoCountdownAndFinishesManually() throws {
        app.terminate()
        // A weekly running goal (stored as JSON data) makes For You offer a run.
        let goals = Data(#"[{"category":"running","targetPerWeek":7}]"#.utf8)
        let goalsHex = goals.map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-weeklyGoals", "<\(goalsHex)>", "-appleWatchUsage", "NO",
                               "-SimulateNoAppleIntelligence", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit", "-UITestSkipWhatsNew"]
        app.launch()
        declineHealthAccessIfAsked()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["For You"].tap()
        let startRun = app.buttons["Start run"]
        XCTAssertTrue(startRun.waitForExistence(timeout: 15), "Run card never appeared")
        let runTitle = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "(Easy|Tempo|Interval) Run( \\(\\d+\\))?")).firstMatch
        XCTAssertTrue(runTitle.exists, "Run name not found")
        let runName = runTitle.label
        XCTAssertTrue(scrollTo(startRun))
        startRun.tap()

        // An outdoor run asks for location the first time. The alert is in the
        // system language; "Don't Allow" is always its last button.
        let locationAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if locationAlert.waitForExistence(timeout: 3) {
            locationAlert.buttons.element(boundBy: locationAlert.buttons.count - 1).tap()
        }

        let finish = app.buttons["Finish workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Run screen has no Finish button")
        XCTAssertFalse(app.buttons["Skip exercise"].exists)
        XCTAssertFalse(app.staticTexts["Sets"].exists)
        saveScreenshot("run-started")
        sleep(5)
        XCTAssertTrue(finish.exists, "The run ended on its own")
        saveScreenshot("run-after-5s")

        finish.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "No summary after finishing")
        saveScreenshot("run-summary")
        done.tap()

        tabBar.buttons["History"].tap()
        let entry = app.staticTexts[runName]
        XCTAssertTrue(scrollTo(entry), "\(runName) missing from the history")
        entry.press(forDuration: 1.2)
        let delete = app.buttons["Delete workout"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5), "\(runName) still in the history")
    }


    // MARK: - Gym session flow

    /// With "Use Apple Watch" on but no watch to wake — one not worn is
    /// locked, and the simulator has none — the workout stays open and says
    /// so in place. An alert from the workout's page used to dismiss the
    /// workout to show itself, leaving only the resume bar.
    @MainActor
    func testWatchThatCantBeReachedKeepsTheWorkout() throws {
        startCatalogWorkout("Push", level: "Advanced", watch: true)
        let notice = app.descendants(matching: .any)["activeWorkout.watchIssue"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "No notice about the watch")
        XCTAssertTrue(app.buttons["activeWorkout.primary"].exists, "The workout closed when the watch couldn't be reached")
        saveScreenshot("watch-unreachable")
        notice.buttons["Dismiss"].tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 3))
        endWithoutSaving()
        XCTAssertFalse(app.staticTexts["Tap to resume"].waitForExistence(timeout: 2), "A resume bar was left behind")
    }

    /// Starts a catalog workout found through Browse search. A built-in
    /// workout's name doesn't carry its level (`CatalogName`), so the result
    /// is picked by its level line too.
    @MainActor
    private func startCatalogWorkout(_ name: String, level: String, watch: Bool = false) {
        app.terminate()
        app.launchArguments = ["-SimulateNoAppleIntelligence", "YES", "-restTimerSeconds", "0", "-appleWatchUsage", watch ? "YES" : "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestSkipHealthKit", "-UITestSkipWhatsNew"]
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Browse"].tap()
        let (field, button) = revealBrowseSearch()
        (field.exists ? field : button).tap()
        app.typeText(name)
        let result = app.buttons.matching(identifier: "browse.searchResult")
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", name, level)).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["preview.start"].waitForExistence(timeout: 5))
        app.buttons["preview.start"].tap()
        XCTAssertTrue(app.buttons["activeWorkout.primary"].waitForExistence(timeout: 5))
    }

    /// Ends the session from the ✕ without saving, so no history is left behind.
    @MainActor
    private func endWithoutSaving() {
        app.buttons["End workout"].tap()
        let discard = app.buttons["End without saving"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
    }

    /// A drop set can follow an exercise's last working set — the app has
    /// moved on by then, so it's offered on the next exercise — and the last
    /// set of the workout leads to "Finish workout" instead of ending it, so
    /// a final drop set still fits.
    @MainActor
    func testDropSetAfterLastSetAndFinishStep() throws {
        startCatalogWorkout("Push", level: "Advanced")
        let primary = app.buttons["activeWorkout.primary"]
        for _ in 0..<4 { primary.tap() }
        let offer = app.buttons["activeWorkout.dropSetOffer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 3), "No drop-set offer after the last set")
        offer.tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertTrue(primary.label.contains("Log drop set"), "Not in drop-set mode: \(primary.label)")
        primary.tap()
        XCTAssertTrue(app.staticTexts["Overhead Press"].waitForExistence(timeout: 3),
                      "Not back on the next exercise after the drop set")

        // On to the last exercise, with one set left.
        for _ in 0..<4 { app.buttons["Skip exercise"].tap() }
        for _ in 0..<5 { app.buttons["Fewer sets"].tap() }
        primary.tap()
        XCTAssertTrue(app.staticTexts["All sets done"].waitForExistence(timeout: 3), "No all-done state")
        XCTAssertTrue(primary.label.contains("Finish workout"), "Primary isn't Finish: \(primary.label)")
        app.buttons["activeWorkout.setKind"].tap()
        XCTAssertTrue(primary.label.contains("Log drop set"))
        primary.tap()
        XCTAssertTrue(primary.label.contains("Finish workout"), "A final drop set ended the all-done state")
        endWithoutSaving()
    }

    /// A timed set of a strength workout (a plank) waits for "Start set"
    /// instead of counting down the moment it appears.
    @MainActor
    func testTimedSetStartsOnTap() throws {
        startCatalogWorkout("Core", level: "Intermediate")
        app.buttons["activeWorkout.overview"].tap()
        let plankRow = app.buttons["sessionOverview.row.seed-exercise-plank"]
        if !plankRow.waitForExistence(timeout: 3) {
            app.buttons["Add exercise"].tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            search.tap()
            search.typeText("Plank")
            let row = app.buttons["exercisePicker.row.seed-exercise-plank"]
            XCTAssertTrue(row.waitForExistence(timeout: 3))
            row.tap()
            XCTAssertTrue(plankRow.waitForExistence(timeout: 3))
        }
        plankRow.tap()
        let primary = app.buttons["activeWorkout.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        XCTAssertTrue(primary.label.contains("Start set"), "No Start set: \(primary.label)")
        // The hold is adjustable before the set starts: 45 s for a plank
        // without a length of its own; tapping the time lets you type one.
        let hold = app.descendants(matching: .any)["activeWorkout.hold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 3), "No hold stepper")
        XCTAssertTrue(hold.label.contains("45"), "Unexpected hold: \(hold.label)")
        hold.tap()
        let entry = app.alerts.textFields.firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "No seconds entry")
        // Empty, with "45" as its placeholder: typing replaces it.
        XCTAssertEqual(entry.placeholderValue, "45")
        entry.typeText("50")
        app.alerts.buttons["Set"].tap()
        XCTAssertTrue(hold.label.contains("50"), "The hold didn't change: \(hold.label)")
        sleep(2)
        XCTAssertTrue(primary.label.contains("Start set"), "The timed set started by itself")
        primary.tap()
        XCTAssertFalse(primary.label.contains("Start set"), "Start set didn't start it")
        // Held a moment: a 0-second hold isn't a set.
        sleep(2)
        primary.tap()
        XCTAssertTrue(app.buttons["Edit last set"].waitForExistence(timeout: 3), "The timed set wasn't logged")
        endWithoutSaving()
    }

    /// The Browse search field and the button it can show as instead. The
    /// field may render as a button until expanded, depending on the iOS
    /// version, and iOS 26+ keeps it hidden until the list is pulled down —
    /// the gesture a user makes to reveal it.
    @MainActor
    private func revealBrowseSearch() -> (field: XCUIElement, button: XCUIElement) {
        let field = app.searchFields["Search for Workouts"]
        let button = app.buttons["Search for Workouts"]
        if !field.waitForExistence(timeout: 2) && !button.exists {
            app.swipeDown()
        }
        return (field, button)
    }

    /// Form rows below the fold aren't built until scrolled into view, so
    /// swipe up until the element is on screen. Ten swipes: Settings grew,
    /// and under load a swipe scrolls less.
    @MainActor @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists, element.isHittable { return true }
        }
        return false
    }

    /// Taps "Don't Allow" on the HealthKit sheet if one still appears. The
    /// launch request is skipped via -UITestSkipHealthKit, so this is only a
    /// fallback. The sheet is system-rendered in the device language, so match
    /// its stable identifier rather than the label.
    @MainActor
    private func declineHealthAccessIfAsked() {
        let button = app.buttons["UIA.Health.DoNotAllow.Button"]
        if button.waitForExistence(timeout: 2), button.isHittable {
            button.tap()
        }
    }

    /// Attaches a screenshot to the result, and also writes it to
    /// `$SCREENSHOT_DIR` when set (pass `TEST_RUNNER_SCREENSHOT_DIR` to xcodebuild).
    @MainActor
    private func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
