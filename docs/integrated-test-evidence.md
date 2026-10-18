# Integrated test regression evidence

Updated 19 October 2026. Branch: `fix/integrated-test-regressions`.

PR #20 exposed five failing unit tests and a stale UI smoke test in the current
integrated app. This branch fixes the seed photo retry behavior and updates
fixtures to match the current garment decoder and outfit composition rules.
The UI smoke test now opens Wardrobe from the Today screen, exercising the
navigation the app currently presents.

## Local verification

- Xcode 27.1 (27A9275), iPhone Duo simulator, iOS 27.1, arm64.
- Full unit target: 84 tests executed, 1 skipped, 0 failures. The combined
  test run's then-current UI smoke failed because it expected a tab bar; on this
  simulator the Today screen presents a compact side control instead.
- Updated `NavigationSmokeTests.testTodayOpensWardrobe`: passed in a separate
  simulator run. The test waits for **Browse wardrobe**, taps it, and verifies
  the Wardrobe navigation title. Result bundle:
  `/tmp/wardrobe-ui-smoke-current.xcresult` (local, not committed).
- `git diff --check`: passed.

The full unit run was stopped after the old UI failure while Xcode was
collecting simulator diagnostics. The corrected UI test passed separately.
GitHub CI on its Xcode 16.4 runner remains the cross-version check for this
branch. None of these simulator results qualify on-device Gemma or the iPhone
17 demo acceptance gate.
