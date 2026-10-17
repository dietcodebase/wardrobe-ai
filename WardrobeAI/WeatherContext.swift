import Foundation

struct WeatherLocation: Codable, Equatable, Sendable {
    var city: String

    var normalizedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WeatherCondition: String, Codable, Equatable, Sendable {
    case clear, clouds, rain, snow, thunderstorm, mist, unknown

    init(openWeatherID: Int) {
        switch openWeatherID {
        case 200...299: self = .thunderstorm
        case 300...599: self = .rain
        case 600...699: self = .snow
        case 700...799: self = .mist
        case 800: self = .clear
        case 801...899: self = .clouds
        default: self = .unknown
        }
    }
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    var location: WeatherLocation
    var temperatureCelsius: Double
    var condition: WeatherCondition
    var description: String
    var fetchedAt: Date

    var temperatureFahrenheit: Double { temperatureCelsius * 9 / 5 + 32 }
}

enum WeatherContextState: Equatable, Sendable {
    case fresh(WeatherSnapshot)
    case cached(WeatherSnapshot)
    case stale(WeatherSnapshot, reason: String)
    case unavailable(reason: String)

    var snapshot: WeatherSnapshot? {
        switch self {
        case let .fresh(snapshot), let .cached(snapshot), let .stale(snapshot, _): snapshot
        case .unavailable: nil
        }
    }

    var isCurrent: Bool {
        if case .fresh = self { return true }
        return false
    }
}

enum WeatherError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidCity
    case rateLimited
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Weather is not configured on this device."
        case .invalidCity: "Choose a city before refreshing weather."
        case .rateLimited: "Weather is temporarily rate limited."
        case .unavailable: "Weather is unavailable right now."
        }
    }
}

protocol WeatherProvider: Sendable {
    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot
}

protocol WeatherCache: Sendable {
    func snapshot(for location: WeatherLocation) async -> WeatherSnapshot?
    func save(_ snapshot: WeatherSnapshot) async
}

actor InMemoryWeatherCache: WeatherCache {
    private var snapshots: [String: WeatherSnapshot] = [:]

    func snapshot(for location: WeatherLocation) -> WeatherSnapshot? { snapshots[location.normalizedCity.lowercased()] }
    func save(_ snapshot: WeatherSnapshot) { snapshots[snapshot.location.normalizedCity.lowercased()] = snapshot }
}

actor UserDefaultsWeatherCache: WeatherCache {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot(for location: WeatherLocation) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: key(for: location)) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    func save(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: snapshot.location))
    }

    private func key(for location: WeatherLocation) -> String {
        "weather-cache-v1-\(location.normalizedCity.lowercased())"
    }
}

actor WeatherContextService {
    private let provider: any WeatherProvider
    private let cache: any WeatherCache
    private let freshFor: TimeInterval
    private let now: @Sendable () -> Date

    init(provider: any WeatherProvider, cache: any WeatherCache = UserDefaultsWeatherCache(), freshFor: TimeInterval = 30 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.cache = cache
        self.freshFor = freshFor
        self.now = now
    }

    func cachedState(for location: WeatherLocation) async -> WeatherContextState? {
        guard let snapshot = await cache.snapshot(for: location) else { return nil }
        return now().timeIntervalSince(snapshot.fetchedAt) <= freshFor ? .cached(snapshot) : .stale(snapshot, reason: "Update needed")
    }

    func refresh(location: WeatherLocation) async -> WeatherContextState {
        guard !location.normalizedCity.isEmpty else { return .unavailable(reason: WeatherError.invalidCity.localizedDescription) }
        do {
            let snapshot = try await provider.weather(for: location)
            await cache.save(snapshot)
            return .fresh(snapshot)
        } catch {
            if let snapshot = await cache.snapshot(for: location) {
                return .stale(snapshot, reason: (error as? LocalizedError)?.errorDescription ?? WeatherError.unavailable.localizedDescription)
            }
            return .unavailable(reason: (error as? LocalizedError)?.errorDescription ?? WeatherError.unavailable.localizedDescription)
        }
    }
}

struct OpenWeatherMapProvider: WeatherProvider {
    private let apiKey: String?
    private let transport: any WeatherTransport

    init(apiKey: String? = ProcessInfo.processInfo.environment["OPENWEATHERMAP_API_KEY"], transport: any WeatherTransport = URLSessionWeatherTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    func weather(for location: WeatherLocation) async throws -> WeatherSnapshot {
        guard !location.normalizedCity.isEmpty else { throw WeatherError.invalidCity }
        guard let apiKey, !apiKey.isEmpty else { throw WeatherError.missingAPIKey }
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [URLQueryItem(name: "q", value: location.normalizedCity), URLQueryItem(name: "units", value: "metric"), URLQueryItem(name: "appid", value: apiKey)]
        let response = try await transport.data(from: components.url!)
        if response.statusCode == 429 { throw WeatherError.rateLimited }
        guard (200...299).contains(response.statusCode) else { throw WeatherError.unavailable }
        let payload = try JSONDecoder().decode(OpenWeatherResponse.self, from: response.data)
        guard let weather = payload.weather.first else { throw WeatherError.unavailable }
        return WeatherSnapshot(location: location, temperatureCelsius: payload.main.temp, condition: WeatherCondition(openWeatherID: weather.id), description: weather.description, fetchedAt: Date())
    }
}

protocol WeatherTransport: Sendable {
    func data(from url: URL) async throws -> (data: Data, statusCode: Int)
}

struct URLSessionWeatherTransport: WeatherTransport {
    func data(from url: URL) async throws -> (data: Data, statusCode: Int) {
        let (data, response) = try await URLSession.shared.data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

private struct OpenWeatherResponse: Decodable {
    struct Main: Decodable { let temp: Double }
    struct Condition: Decodable { let id: Int; let description: String }
    let main: Main
    let weather: [Condition]
}
