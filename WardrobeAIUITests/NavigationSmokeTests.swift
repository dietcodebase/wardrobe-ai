import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testAllTabsCanBeOpened() {
        let app = XCUIApplication()
        app.launch()
        let destinations = [
            ("Wardrobe", "Your wardrobe starts here"),
            ("Outfits", "Your saved outfits will appear here"),
            ("Stylist", "Your personal stylist is coming soon"),
            ("Wardrobe", "Your wardrobe starts here")
        ]
        for (title, message) in destinations {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(title) tab"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
