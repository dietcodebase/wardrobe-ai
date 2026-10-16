# M00 evidence — 16 October 2026

State: implementation and simulator acceptance passed in CI; PR review pending. Branch:
`milestone/m00-foundation`. Destination: `dietcodebase/wardrobe-ai`.

## Delivered

- SwiftUI shell with Wardrobe, Outfits and Stylist tabs, iOS 18.0 target.
- Unit target and launch/navigation UI smoke target; shared scheme.
- One local/CI command pinned to Xcode 16.4 (16F6), iPhone 16 / iOS 18.5.
- Ignore rules for local configuration, signing, models and personal data.
- Planning/reference import is a separate commit (984 existing lines); project
  metadata is separate from the handwritten app and tests.
- No injected services/fakes are needed by this static shell yet.

## Initial local verification

- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj`: passed.
- Python ElementTree parsing of shared scheme XML: passed.
- `swiftc -frontend -parse` on app and test Swift files: passed syntax parsing
  only; this does not type-check SwiftUI or XCTest against an iOS SDK.
- `bash -n scripts/check-ios.sh`: passed.
- `git diff --cached --check`: passed for each staged slice.
- `xcodebuild -version`: failed; selected tools are Command Line Tools.
- `./scripts/check-ios.sh`: stopped with the full-Xcode prerequisite message.
- No Xcode application was present under `/Applications`. The pinned toolchain
  and simulator destination are intended configuration, not observed evidence.

## Initial outstanding acceptance (superseded by CI below)

Install full Xcode 16.4 and iOS 18.5 simulator runtime, then run the documented
command from a clean checkout. Record the successful result bundle, simulator
launch, all-tab smoke result and screenshots. CI has not yet demonstrated a pass.
No build, launch, UI test or device pass is claimed. M00 must not merge until
these checks and review pass. No M01 runtime/device evidence is implied.

## Hosting evidence

Draft PR: https://github.com/dietcodebase/wardrobe-ai/pull/1 (not merged).
The configured destination was empty; the empty bootstrap `main` and milestone
branch were pushed. GitHub authentication succeeded outside the network sandbox.
CI run 38923733534 was queued; no pass is claimed here.

The account has admin permission, but GitHub's protection API returned HTTP 403:
“Upgrade to GitHub Pro or make this repository public to enable this feature.”
Required checks/review protection cannot be configured on the current private
repository plan. Preserve private visibility; resolve hosting entitlement before
relying on enforced protection.

## First CI failure and correction

Run 38923800047 built successfully and passed the unit test. The UI test launched
the app and found each navigation bar, but all four content assertions failed:
the test assumed ContentUnavailableView exposed an `otherElements` node with
the screen identifier. The correction checks each screen's visible static text
with a bounded wait and retains screenshots in the result bundle. The unused
container identifier was removed. A fresh CI run must verify this correction.

## Successful verification after correction

[CI run 38924446663](https://github.com/dietcodebase/wardrobe-ai/actions/runs/38924446663)
validated commit `8c61aec22bbc2d2671faf709140683f1849f38b6` from a clean
GitHub checkout using Xcode 16.4 (16F6), iPhone 16 / iOS 18.5 simulator.
Clean build succeeded; the unit test and all-tab UI smoke test each passed
with zero failures. The UI test launched the app, checked all three screens
and returned to Wardrobe. Screenshots are retained in the uploaded
`M00-test-results` result bundle. This supersedes the earlier unverified
simulator acceptance; local Xcode and real-device qualification remain absent.
PR review remains pending; protection is still unavailable on this hosting plan.
