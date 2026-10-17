## Milestone and behavior

M05 — Saved outfits and wear history.

Users can assemble named outfits from owned garments, mark favorites, and explicitly select **Wear today**. Saving or scheduling an outfit never records wear. Retrying the action on the same local day returns the same event, and Undo removes its logs.

## Scope and commits

1. `feat: add idempotent wear event storage` — local-day transactional wear events, history/underused queries, undo, and repository tests.
2. `feat: add outfit builder and wear history UI` — Outfits tab, editor, favorites, Wear today, undo, history, and underused-items UI.
3. Documentation/evidence — roadmap state and validation record.

## Verification

- `swiftc -parse ...` passed for the modified Swift sources.
- `git diff --check` passed before commits.
- Tests cover duplicate retries, undo restoring counts, never-worn ordering, and a local-day boundary.
- Full `scripts/check-ios.sh` is blocked: this host has Command Line Tools rather than required Xcode 16.4. No device testing is required for M05.

## Review and merge

- [x] Prerequisite M03 is merged; target is `main`.
- [x] Scope is limited to M05; no private data, keys, or model weights are included.
- [ ] Required simulator build and XCTest checks pass (blocked by missing full Xcode).
- [x] ROADMAP state and evidence are current.
- [x] Merge can preserve the small commits.
