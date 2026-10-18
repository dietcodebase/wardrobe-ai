import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testTodayOpensWardrobe() {
        let app = XCUIApplication()
        app.launch()
        let browseWardrobe = app.buttons["Browse wardrobe"]
        XCTAssertTrue(browseWardrobe.waitForExistence(timeout: 10))
        browseWardrobe.tap()
        XCTAssertTrue(app.navigationBars["Wardrobe"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Wardrobe navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
