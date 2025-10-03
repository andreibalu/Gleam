//
//  GleamUITests.swift
//  GleamUITests
//
//  Created by andrei on 01.10.2025.
//

import XCTest

final class GleamUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testBasicNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-skip-onboarding")
        app.launch()

        // Home tab should have scan button
        let scanButton = app.buttons["home_scan_button"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))

        // Switch to Scan tab
        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.buttons["Choose Photo"].exists)

        // Switch to History tab
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].exists)

        // Switch to Settings tab
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments.append("--uitest-skip-onboarding")
            app.launch()
        }
    }
}
