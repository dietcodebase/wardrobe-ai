import XCTest
@testable import WardrobeAI

final class CalendarContextTests: XCTestCase {
    func testReaderStateAllowsManualFallbackForDeniedOrRevokedAccess() async throws {
        let reader = FakeCalendarReader(state: .denied)
        XCTAssertEqual(reader.accessState(), .denied)
        let requestedState = await reader.requestAccess()
        XCTAssertEqual(requestedState, .denied)
        XCTAssertTrue(try reader.events(on: .now, calendar: .autoupdatingCurrent).isEmpty)
    }

    func testEventContextPreservesAllDayAndTimezoneWithoutTitle() throws {
        let event = CalendarEventContext(id: "event", startDate: .now, endDate: .now, isAllDay: true, timeZoneIdentifier: "Asia/Kolkata")
        XCTAssertEqual(event.timeLabel, "All day")
        XCTAssertEqual(event.timeZoneIdentifier, "Asia/Kolkata")
    }
}

private struct FakeCalendarReader: CalendarEventReading {
    let state: CalendarAccessState
    func accessState() -> CalendarAccessState { state }
    func requestAccess() async -> CalendarAccessState { state }
    func events(on day: Date, calendar: Calendar) throws -> [CalendarEventContext] { [] }
}
