# M10 optional weather-context evidence

Status: **implementation complete; runtime and release validation pending**. Updated 18 October 2026.

## Behavior

- The Stylist tab accepts a user-configured city and shows an explicitly sourced
  OpenWeatherMap reading only after an optional refresh.
- The API key is read locally from `OPENWEATHERMAP_API_KEY`; no credential,
  city, or weather fallback is committed to the project. A missing key, timeout,
  invalid response, or rate limit leaves wardrobe recommendations usable.
- Weather snapshots are cached on-device by city. The UI and domain model
  distinguish fresh, cached, stale, and unavailable states. Stale weather is
  visibly labelled and is not used to adjust recommendation order.
- Fresh cold/rain context modestly favors owned outerwear in the deterministic
  candidate ordering and identifies the city, condition, and temperature in the
  explanation. It never claims live weather without a successful request.

## Verification

- `swiftc -parse WardrobeAI/WeatherContext.swift WardrobeAI/OutfitRecommendations.swift WardrobeAI/WardrobeStore.swift WardrobeAI/ModelStatusView.swift WardrobeAITests/WeatherContextTests.swift WardrobeAITests/OutfitRecommendationsTests.swift` — passed on 18 October 2026.
- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed on 18 October 2026.
- `git diff --check` — passed on 18 October 2026.
- Focused `xcodebuild test` was attempted, but dependency resolution could not
  fetch GRDB because this environment cannot resolve `github.com`; no XCTest
  result is claimed.

## Remaining acceptance evidence

Run fresh/cached/stale/unavailable flows on the integrated device candidate;
exercise timeout, rate-limit, and missing-key paths; verify Celsius/Fahrenheit
display policy and no secret leakage. Resolve a production credential strategy
before any public weather-enabled distribution.
