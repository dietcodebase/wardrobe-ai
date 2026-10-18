# M13 voice input evidence

Status: implementation complete; physical-device and qualified-runtime validation pending.

## Implemented behavior

- The Stylist tab has a hold-to-talk control that requests microphone permission only when used and records a temporary WAV request locally.
- Recording requests 16 kHz, mono, signed 16-bit PCM and validates the actual file format before it can be submitted. Requests stop at ten seconds.
- Cancellation, recording failure, automatic duration expiry, and leaving the chat clean up the temporary file and deactivate the audio session. Typed chat remains available in every failure state.
- The current voice-runtime adapter deliberately reports that audio support is unqualified, then deletes the recording. No cloud transcription or silent substitute is used.
- A successful recording now deactivates the shared audio session before submission. Audio-session interruptions reset recording state and delete the partial file. WAV validation checks the on-disk linear PCM codec, signed 16-bit representation, sample rate, channel count, and interleaving.

## Verification

- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed on 18 October 2026.
- `git diff --check` — passed on 18 October 2026.
- Added unit coverage for the 16 kHz mono / ten-second format contract and typed-input fallback messaging.
- `xcodebuild build -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/wardrobeai-m13-derived CODE_SIGNING_ALLOWED=NO` — dependency resolution was attempted; full compilation remains pending because the available build host has no usable iOS simulator service and package resolution did not complete in the task environment.

## Outstanding acceptance evidence

M01's audio gate is not yet qualified. On the named physical device, record the runtime-accepted sample rate, channel count and encoding; exercise microphone denial, an interruption/call, cancel, automatic duration expiry and cleanup; then run and score a small synthetic/licensed spoken wardrobe-request set. Do not merge or claim local audio support before recording that evidence in `docs/runtime-qualification.md` and `docs/final-validation.md`.
