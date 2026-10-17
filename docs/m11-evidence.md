# M11 calendar and outfit scheduling evidence

Status: implementation complete; device validation pending.

## Implemented behavior

- Calendar access is requested only from the Outfits tab. The reader exposes event timing, all-day state, and time-zone metadata, but deliberately does not read or log event titles.
- Denied, revoked, and unavailable access retain the manual in-app planning path.
- Plans are stored in `outfit_plans` and may reference a source event identifier. They never create a wear event and never write an external calendar event.
- The plan editor states this boundary explicitly and supports a date/time and optional manual occasion.

## Verification

- `xcodebuild build -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/wardrobeai-m11-derived CODE_SIGNING_ALLOWED=NO` — passed on 18 October 2026.
- Added unit coverage for denied/revoked calendar fallback, all-day/time-zone event metadata, and the independent schedule persistence path.
- `xcodebuild test` is pending: this host has no concrete simulator runtime, so the generic simulator destination cannot run the test bundles.

## Outstanding acceptance evidence

Run on a device or available simulator: permission revocation after prior approval, all-day and midnight-crossing events in multiple time zones, source-event deletion, and the manual planning UI. Confirm no plan creates a wear log or modifies an external event.
