# M00 evidence — 16 October 2026

State: implementation prepared; acceptance blocked. Branch:
`milestone/m00-foundation`. Destination: `dietcodebase/wardrobe-ai`.

## Delivered

- SwiftUI shell with Wardrobe, Outfits and Stylist tabs, iOS 18.0 target.
- Unit target and launch/navigation UI smoke target; shared scheme.
- One local/CI command pinned to Xcode 16.4 (16F6), iPhone 16 / iOS 18.5.
- Ignore rules for local configuration, signing, models and personal data.
- Planning/reference import is a separate commit (984 existing lines); project
  metadata is separate from the handwritten app and tests.
- No injected services/fakes are needed by this static shell yet.

## Actual verification

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

## Outstanding acceptance

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
