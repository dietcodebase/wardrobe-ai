import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testAllTabsCanBeOpened() {
        let app = XCUIApplication()
        app.launch()
        for title in ["Wardrobe", "Outfits", "Stylist", "Wardrobe"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.otherElements["screen.\(title)"].exists)
        }
    }
}
