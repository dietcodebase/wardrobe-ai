# M14 batch garment capture evidence

Status: implementation complete; simulator, physical-device, and qualified-model validation pending.

## Implemented behavior

- Batch capture runs foreground-instance detection over one selected photo and presents every returned cutout for explicit inclusion. A mask is never assumed to be a garment.
- Classification is processed strictly one crop at a time. A failure is retained on that crop while later selected crops continue; stopped requests leave existing results available and mark remaining work cancelled.
- Successful classifier suggestions populate editable fields and require an explicit review confirmation before any suggested category, color, tags, or material provenance can be saved. Failed or unclassified crops use editable manual fields.
- Stopping classification keeps the active task and progress state until it actually finishes, so retry cannot overlap it. Photo preparation uses a request identity so a late result from an older photo is discarded.
- Each selected crop is saved independently through the existing recoverable image/database coordinator. Successfully saved garments remain saved when a later crop fails; failed saves remain selected for retry.
- Unclassified, failed, or cancelled crops remain saveable with a manual draft. The existing single-item flow remains available when no masks are returned or the photo is unsuitable.

## Verification

- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed on 18 October 2026.
- `git diff --check` — passed on 18 October 2026.
- Added deterministic unit coverage for sequential requests, per-crop failure continuation, suggested-draft preservation, and manual fallback.
- `xcodebuild test -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wardrobeai-m14-derived CODE_SIGNING_ALLOWED=NO` — did not reach compilation in the sandbox: Simulator services were unavailable and package resolution could not reach GitHub. A subsequent generic iOS build restored cached package checkouts but did not produce compiler/test output in this task environment.

## Outstanding acceptance evidence

On a qualified physical device with the M01 model configuration, exercise two and three separated garments, overlapping garments, zero masks, partial classification/save errors, cancellation and retry. Record actual-model peak process and Metal memory during foreground extraction and the sequential queue. Confirm temporary capture artifacts are removed on cancellation and no model requests overlap. Do not merge or claim measured batch-capture support before recording that evidence in `docs/final-validation.md`.
