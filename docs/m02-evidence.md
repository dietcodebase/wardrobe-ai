# M02 storage evidence

Status: code complete; acceptance verification blocked by the unavailable full Xcode toolchain. Recorded 16 October 2026.

## Implemented behavior

- GRDB migrations create garments, style preferences, outfits, outfit-item links and wear logs with foreign keys.
- Garment tags are JSON arrays, and the repository's `json_each` tag filter binds its input as a SQL parameter.
- Garments used by an outfit or wear log cannot be deleted. Deleting an outfit removes only its links and leaves related wear history intact.
- Image paths are validated relative paths beneath Application Support. Atomic file writes are rolled back if the accompanying database insert fails; orphan scanning removes files that were not recorded.
- Synthetic wardrobe seeds are keyed and installed transactionally, so a second import returns the same records instead of duplicating them.

## Verification

| Check | Result |
| --- | --- |
| `swiftc -parse` over the new storage sources and `StorageTests.swift` | Passed (syntax parsing only) |
| `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` | Passed |
| `git diff --check origin/main...HEAD` | Passed |
| `xcodebuild -list -project WardrobeAI.xcodeproj` | Blocked: active developer directory is Command Line Tools; no Xcode app is installed |
| Storage XCTest suite | Unrun: requires full Xcode and resolving the GRDB package |
| PR #3 CI | The initial run compiled x86_64 against arm64-only GRDB. A later run showed `-arch arm64` conflicts with the simulator destination's implied architecture. The script now constrains `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` through build settings without a second architecture selector; rerun pending. |

The new `StorageTests` cover item CRUD, parameterized tag filtering, preference round-trips, foreign-key deletion behavior, persistent database reopening, idempotent seeds, image rollback and orphan recovery. They are not acceptance evidence until they run under the specified Xcode toolchain.

No personal photos, model artifacts, credentials or sample image files were added.
