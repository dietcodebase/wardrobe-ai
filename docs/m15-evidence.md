# M15 mirror fit-check and demo-release evidence

Status: implementation complete; simulator, physical-device, model, and release
qualification pending.

## Implemented behavior

- A still-photo mirror flow starts from saved outfits and keeps the selected
  full-frame image in sheet memory only. Closing the sheet discards it.
- The captured image is passed to the existing on-device Vision garment
  classifier. Feedback uses its recognized category to compare the photographed
  clothing with the selected outfit and optional user-entered context. If
  recognition fails, the UI says so and keeps the outfit as a manual reference.
- Feedback is constrained to clothing and context. It explicitly avoids body
  judgments and makes no generative visual-model claim.
- Swap cards are generated only from currently owned, same-category alternatives
  not already in the selected outfit. Each card navigates to a detail view that
  verifies the available replacement; no-swap is an explicit valid response.
- The accompanying demo guide records setup, safety boundary, support matrix,
  asset rules, dependencies, and out-of-scope continuous video.

## Verification

- git diff --check — passed on 18 October 2026.
- swiftc -parse for the M15 Swift sources and unit-test source — passed on 18
  October 2026.
- Added deterministic unit coverage for verified owned swaps and no-swap fallback.
- Updated the generated camera purpose string to describe wardrobe garment
  photos and mirror fit-check outfit photos.
- Review follow-up: mirror checks now classify the captured still with the
  existing on-device Vision garment classifier before showing the category
  comparison. Category recognition failure is surfaced as a manual-reference
  fallback.
- \`xcodebuild test -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination
  'generic/platform=iOS Simulator' -derivedDataPath
  /private/tmp/wardrobeai-m15-review-fix-derived CODE_SIGNING_ALLOWED=NO\` — did
  not reach compilation because CoreSimulatorService was unavailable and package
  resolution could not resolve GitHub hosts.
- xcodebuild test for the WardrobeAI scheme against a generic iOS Simulator did
  not compile in the task sandbox: CoreSimulatorService was unavailable and Swift
  package resolution could not resolve GitHub hosts. Xcode 27.1 is installed.

## Outstanding acceptance evidence

On the named demo device, exercise a representative licensed/synthetic photo
set; camera and library denial paths; empty wardrobe and no-swap states; restart
cleanup; missing-model and offline behavior; memory/thermal pressure; Dynamic
Type and VoiceOver. Wire and validate measured weather/model context only after
M01's relevant gates pass. Record raw commands, device/build/model configuration,
support decisions, and any regressions in docs/final-validation.md. Do not
claim supported-device, visual-critique, performance, or event-track status
before that evidence is recorded.
