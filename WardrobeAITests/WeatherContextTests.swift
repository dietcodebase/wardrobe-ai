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
        let cached = await service.cachedState(for: location)
        XCTAssertEqual(cached, .cached(WeatherSnapshot(location: location, temperatureCelsius: 24, condition: .clear, description: "clear", fetchedAt: now)))
        let stale = WeatherContextService(provider: FixtureProvider(), cache: cache, freshFor: 60, now: { now.addingTimeInterval(61) })
        guard case .stale = await stale.cachedState(for: location) else { return XCTFail("Expected stale cache") }
    }

    func testFreshStateExpiresUsingTheConfiguredFreshnessWindow() async {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = WeatherSnapshot(location: .init(city: "Pune"), temperatureCelsius: 24, condition: .clear, description: "clear", fetchedAt: fetchedAt)
        let service = WeatherContextService(provider: FixtureProvider(), freshFor: 60, now: { fetchedAt.addingTimeInterval(61) })

        let expired = await service.currentState(from: .fresh(snapshot))
        XCTAssertEqual(expired, .stale(snapshot, reason: "Update needed"))
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

    func testOpenWeatherProviderDecodesMetricResponseAndRateLimit() async throws {
        let body = #"{"main":{"temp":21.5},"weather":[{"id":801,"description":"few clouds"}]}"#.data(using: .utf8)!
        let provider = OpenWeatherMapProvider(apiKey: "local-test-key", transport: FixtureTransport(data: body, statusCode: 200))
        let snapshot = try await provider.weather(for: .init(city: "Pune"))
        XCTAssertEqual(snapshot.temperatureCelsius, 21.5)
        XCTAssertEqual(snapshot.condition, .clouds)
        XCTAssertEqual(snapshot.description, "few clouds")
        let rateLimited = OpenWeatherMapProvider(apiKey: "local-test-key", transport: FixtureTransport(data: Data(), statusCode: 429))
        await XCTAssertThrowsErrorAsync(try await rateLimited.weather(for: .init(city: "Pune"))) { XCTAssertEqual($0 as? WeatherError, .rateLimited) }
    }
}

private struct FixtureProvider: WeatherProvider {
    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot { WeatherSnapshot(location: location, temperatureCelsius: 20, condition: .clear, description: "clear", fetchedAt: .now) }
}

private struct FailingProvider: WeatherProvider {
    let error: WeatherError
    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot { throw error }
}

private struct FixtureTransport: WeatherTransport {
    let data: Data
    let statusCode: Int
    func data(from url: URL) async throws -> (data: Data, statusCode: Int) { (data, statusCode) }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("Expected an error") }
    catch { handler(error) }
}
