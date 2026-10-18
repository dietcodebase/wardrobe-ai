import XCTest

final class NavigationSmokeTests: XCTestCase {
    @MainActor
    func testAssistantConversationIsThePrimaryScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Wardrobe AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["assistant-welcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["assistant-prompt"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Chat-first wardrobe assistant"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
