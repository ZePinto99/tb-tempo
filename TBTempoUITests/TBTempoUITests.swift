import XCTest

final class TBTempoUITests: XCTestCase {
    @MainActor
    func testEmptyLibraryAndPrimaryTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()

        XCTAssertTrue(app.navigationBars["TB Tempo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your next episode starts here"].exists)
        XCTAssertTrue(app.buttons["Search for a Series"].exists)

        for tab in ["Upcoming", "Shows", "Statistics", "Settings"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.exists, "Missing primary tab: \(tab)")
            button.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
}
