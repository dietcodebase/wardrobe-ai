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
- Blocked: build, launch and smoke tests; full Xcode is absent locally.
- Intended toolchain: Xcode 16.4 (16F6), iPhone 16 simulator / iOS 18.5.
- Screenshots: pending simulator launch; no device/runtime claims.
- Evidence: `docs/m00-evidence.md`.

## Review and merge

- [x] No prerequisites; target is `main`.
- [x] Scope matches M00; no private data, keys or model weights.
- [ ] Required checks and acceptance criteria pass.
- [x] ROADMAP records blocked acceptance.
- [ ] Review complete; merge preserves small commits.

Draft until clean build, launch, navigation and review pass.
