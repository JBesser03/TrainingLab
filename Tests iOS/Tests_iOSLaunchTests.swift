//
//  Tests_iOSLaunchTests.swift
//  Tests iOS
//
//  Captures a launch screenshot via XCTAttachment so regressions to the
//  splash / first-render state are visible in the Xcode test report.
//

import XCTest

final class Tests_iOSLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipWhatsNew"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
