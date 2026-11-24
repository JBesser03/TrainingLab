//
//  ScreenshotTests.swift
//  Tests iOS
//
//  Takes the App Store screenshots in one language on the demo data
//  (`iOS/DemoData.swift`). Skipped unless SCREENSHOT_LANG is set, so a
//  normal test run doesn't touch it. Run once per language on a freshly
//  erased simulator; the demo history is seeded in the launch language:
//
//    TEST_RUNNER_SCREENSHOT_LANG=de TEST_RUNNER_SCREENSHOT_DIR=/path/de \
//    xcodebuild test -project TrainingLab.xcodeproj -scheme "Workout App (iOS)" \
//      -destination id=<udid> -only-testing:"Tests iOS/ScreenshotTests"
//
//  Files are numbered in App Store order, not in the order they're taken.
//  Elements are found by identifier (tabs by their icon), so the same
//  steps work in English and German and on iPhone, iPad and iPhone Duo.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private var language = "en"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let environment = ProcessInfo.processInfo.environment
        guard let language = environment["SCREENSHOT_LANG"] else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOT_LANG (en or de) to take screenshots")
        }
        self.language = language
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US",
            "-UITestSkipHealthKit", "-UITestSkipWhatsNew",
            "-UITestSeedDemoData", "-UITestTheme", "clay",
            "-debug.useMockHealthData", "YES", "-SimulateNoAppleIntelligence", "YES"
        ]
        app.launch()
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        XCTAssertTrue(app.buttons[Self.tabIcons[0]].firstMatch.waitForExistence(timeout: 15), "No tabs")

        // For You: recovery, weekly goals and the generated gym workout.
        tab(0)
        let start = app.buttons["forYou.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "For You's workout card never appeared")
        settle()
        save("01-for-you")
        app.swipeUp()
        settle()
        save("09-for-you-goals")
        app.swipeDown()

        // History, then today's session and Progress from there.
        tab(3)
        let row = app.buttons.matching(identifier: "history.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No demo history")
        settle()
        save("05-history")

        // On the date: on iPad the row's empty middle doesn't take taps.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        settle(2)
        save("03-summary")
        back()

        let progress = app.buttons["history.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        progress.tap()
        settle(2)
        save("04-progress")
        back()

        // Plans: Push Pull Legs in progress at the top.
        tab(2)
        XCTAssertTrue(app.buttons["plans.add"].waitForExistence(timeout: 5))
        settle()
        save("06-plans")

        // Browse.
        tab(1)
        XCTAssertTrue(app.buttons["browse.add"].waitForExistence(timeout: 5))
        settle()
        save("07-browse")

        // Settings with the Mono style (Graphite) picked, then back to Terrakotta.
        tab(4)
        let graphite = app.buttons["settings.theme.graphite"]
        XCTAssertTrue(graphite.waitForExistence(timeout: 5))
        graphite.tap()
        settle(1.5)
        save("08-settings-mono")
        app.buttons["settings.theme.clay"].tap()
        settle(1)

        // A gym workout with one set logged. Last, because it isn't saved:
        // the app is closed instead.
        tab(0)
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        let primary = app.buttons["activeWorkout.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10), "The workout didn't start")
        settle(1)
        primary.tap()
        settle(1.5)
        save("02-workout")
        app.terminate()
    }

    // MARK: - Helpers

    /// Tab icons, which are the tabs' identifiers: For You, Browse, Plans,
    /// History, Settings. The tabs are a bottom bar on iPhone, a top bar on
    /// iPad and a side rail on iPhone Duo, so they're found by icon.
    private static let tabIcons = ["sparkles", "square.grid.2x2", "list.clipboard.fill", "chart.bar.fill", "gearshape.fill"]

    /// The system back button. It sits in the side rail on iPhone Duo, and
    /// the iPad's navigation bar has other buttons first, so it's found by id.
    @MainActor
    private func back() {
        let button = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No back button")
        button.tap()
    }

    @MainActor
    private func tab(_ index: Int) {
        app.buttons[Self.tabIcons[index]].firstMatch.tap()
    }

    /// Lets animations, charts and async loading finish before a shot.
    private func settle(_ seconds: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func save(_ name: String) {
        // The unfolded iPhone Duo runs on its inner screen, but `main` is the
        // cover screen, which is off then. SCREENSHOT_LARGEST_SCREEN=1 picks the inner one.
        let screen = ProcessInfo.processInfo.environment["SCREENSHOT_LARGEST_SCREEN"] == "1"
            ? XCUIScreen.screens.max { $0.screenshot().image.size.width * $0.screenshot().image.size.height
                                     < $1.screenshot().image.size.width * $1.screenshot().image.size.height } ?? .main
            : XCUIScreen.main
        let shot = screen.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(language)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let folder = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
