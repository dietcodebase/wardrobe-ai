import XCTest
@testable import WardrobeAI

final class WeatherContextTests: XCTestCase {
    func testWeatherTemperatureConversionAndConditionMapping() {
        let snapshot = WeatherSnapshot(location: .init(city: "Pune"), temperatureCelsius: 20, condition: WeatherCondition(openWeatherID: 501), description: "moderate rain", fetchedAt: .now)
        XCTAssertEqual(snapshot.temperatureFahrenheit, 68, accuracy: 0.001)
        XCTAssertEqual(snapshot.condition, .rain)
    }

    func testFreshCachedAndStaleStatesAreDistinct() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let location = WeatherLocation(city: "Pune")
        let cache = InMemoryWeatherCache()
        await cache.save(WeatherSnapshot(location: location, temperatureCelsius: 24, condition: .clear, description: "clear", fetchedAt: now))
        let service = WeatherContextService(provider: FixtureProvider(), cache: cache, freshFor: 60, now: { now.addingTimeInterval(30) })
        XCTAssertEqual(await service.cachedState(for: location), .cached(WeatherSnapshot(location: location, temperatureCelsius: 24, condition: .clear, description: "clear", fetchedAt: now)))
        let stale = WeatherContextService(provider: FixtureProvider(), cache: cache, freshFor: 60, now: { now.addingTimeInterval(61) })
        guard case .stale = await stale.cachedState(for: location) else { return XCTFail("Expected stale cache") }
    }

    func testFailedRefreshKeepsStaleWeatherAndEmptyCacheIsUnavailable() async {
        let location = WeatherLocation(city: "Pune")
        let cache = InMemoryWeatherCache()
        await cache.save(WeatherSnapshot(location: location, temperatureCelsius: 24, condition: .clear, description: "clear", fetchedAt: .distantPast))
        let service = WeatherContextService(provider: FailingProvider(error: .rateLimited), cache: cache)
        guard case let .stale(_, reason) = await service.refresh(location: location) else { return XCTFail("Expected stale weather") }
        XCTAssertEqual(reason, WeatherError.rateLimited.localizedDescription)
        guard case .unavailable = await WeatherContextService(provider: FailingProvider(error: .missingAPIKey)).refresh(location: location) else { return XCTFail("Expected unavailable weather") }
    }
}

private struct FixtureProvider: WeatherProvider {
    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot { WeatherSnapshot(location: location, temperatureCelsius: 20, condition: .clear, description: "clear", fetchedAt: .now) }
}

private struct FailingProvider: WeatherProvider {
    let error: WeatherError
    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot { throw error }
}
