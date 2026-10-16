## Milestone and behavior

M00 — Project and delivery foundation. Previously this repository contained
planning only; it now includes a SwiftUI app shell with Wardrobe, Outfits and
Stylist placeholder tabs, unit tests and a launch/navigation UI smoke test.

## Scope and commits

- Import existing planning files and delivery contract (984 existing lines).
- Add app shell and test source (74 handwritten lines).
- Add Xcode app/test targets and shared scheme separately.
- Add pinned build script, macOS CI, ignore rules and acceptance evidence.

No service abstraction is needed for static placeholder screens. No model is
required. Main contains only the roadmap-authorized empty bootstrap base.

## Verification

- Passed: project plist lint, scheme XML parse, Swift syntax parse, shell syntax,
  staged whitespace checks.
- Passed in CI run 38924446663 at `8c61aec`: clean build, launch, one unit test
  and all-tab UI smoke test, zero failures. Full Xcode remains absent locally.
- Intended toolchain: Xcode 16.4 (16F6), iPhone 16 simulator / iOS 18.5.
- Screenshots: retained in CI result bundle; no real-device/runtime claims.
- Evidence: `docs/m00-evidence.md`.

## Review and merge

- [x] No prerequisites; target is `main`.
- [x] Scope matches M00; no private data, keys or model weights.
- [ ] Required checks and acceptance criteria pass.
- [x] ROADMAP records successful simulator acceptance and pending review.
- [ ] Review complete; merge preserves small commits.

Simulator acceptance passes; draft remains pending review. Branch protection
is unavailable on the current private-repository plan (GitHub API HTTP 403).
