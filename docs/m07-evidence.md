# M07 classification evidence

Status: implementation in progress; physical-device acceptance is pending.

## Implemented behavior

- A captured garment photo is classified on a background task using local Apple
  Vision observations. Only labels mapping to the app's existing, typed
  taxonomy are accepted. An unmapped image offers manual entry instead.
- Category, tags, and any material guess are editable before save. Material is
  explicitly labelled a guess and no automatic material certainty is claimed.
- Requests have a 12-second timeout, support cancellation, and leave manual
  save available after an unavailable, malformed, timed-out, or cancelled
  request.
- Saved items retain the suggestion, local route, model identifier/revision,
  timestamp, and whether the person changed the suggestion before saving.

## Automated verification

- `xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/wardrobeai-m07-derived build` — passed on 17 October 2026.
- Focused `GarmentClassificationTests` and `StorageTests` are present for
  bounded JSON decoding, rejection of malformed and unknown categories,
  unavailable fallback, Vision label mapping, and provenance round-tripping.
  Their simulator run is currently blocked before test execution by the
  pre-existing GRDB undefined-symbol failure when Xcode links the app test host.

## Still required for milestone acceptance

Run the real application on the intended demo iPhone against at least 20
varied garment images. Record image count, correct category count, invalid or
unavailable responses, p50/p95 end-to-end time, and cancellation behavior.
The local Vision route must be qualified by that evidence before it is presented
as a supported device route. No sub-second performance claim is made here.
