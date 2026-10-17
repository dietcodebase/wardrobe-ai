import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testAllTabsCanBeOpened() {
        let app = XCUIApplication()
        app.launch()
        let destinations = [
            ("Wardrobe", "No garments yet"),
            ("Outfits", "No saved outfits"),
            ("Stylist", "manual-wardrobe-status"),
            ("Wardrobe", "No garments yet")
        ]
        for (title, message) in destinations {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let content = title == "Stylist"
                ? app.descendants(matching: .any)[message]
                : app.staticTexts[message]
            XCTAssertTrue(content.waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(title) tab"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
