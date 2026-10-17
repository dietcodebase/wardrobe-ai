import EventKit
import Foundation

struct CalendarEventContext: Identifiable, Equatable, Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String?

    var timeLabel: String {
        if isAllDay { return "All day" }
        return startDate.formatted(date: .omitted, time: .shortened)
    }
}

enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

protocol CalendarEventReading: Sendable {
    func accessState() -> CalendarAccessState
    func requestAccess() async -> CalendarAccessState
    func events(on day: Date, calendar: Calendar) throws -> [CalendarEventContext]
}

final class EventKitCalendarReader: CalendarEventReading, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) { self.store = store }

    func accessState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .writeOnly: return .unavailable
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    func requestAccess() async -> CalendarAccessState {
        guard accessState() == .notDetermined else { return accessState() }
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    func events(on day: Date, calendar: Calendar = .autoupdatingCurrent) throws -> [CalendarEventContext] {
        guard accessState() == .authorized else { return [] }
        let interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        return store.events(matching: store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)).map {
            CalendarEventContext(id: $0.eventIdentifier, startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay, timeZoneIdentifier: $0.timeZone?.identifier)
        }.sorted { $0.startDate < $1.startDate }
    }
}
