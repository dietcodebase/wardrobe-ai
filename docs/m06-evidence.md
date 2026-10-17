# M06 provisioning and lifecycle evidence

Recorded 17 October 2026.

## Implemented behavior

- The app pins the M01 artifact identifiers, byte counts, SHA-256 values and
  download URLs in code. Model weights are neither bundled nor committed.
- Imported and downloaded files are copied into the app's Application Support
  `Models` directory only after exact size and streaming SHA-256 verification.
  Files that fail verification are removed; startup rechecks prior files before
  making them available. The model directory and files are excluded from backup.
- The download controller exposes progress, cancellation and resume-data based
  retry, checks available disk space before starting, and verifies the completed
  temporary download before it reaches permanent storage.
- `ModelInferenceCoordinator` serializes load/use/unload. Switching a model
  unloads the previous engine first; memory or thermal notifications request an
  unload. Its placeholder adapter reports that a production inference adapter is
  not configured; model-specific inference begins in M07.
- The Stylist tab shows the pinned candidates and their status. Provisioning is
  enabled under the owner's explicit M06 waiver; the manual wardrobe remains
  usable.

## Checks run

- `swiftc -module-cache-path /private/tmp/wardrobe-m06-swift-cache -typecheck WardrobeAI/ModelProvisioning.swift` — passed.
- `swiftc -parse WardrobeAI/ModelProvisioning.swift WardrobeAI/ModelStatusView.swift WardrobeAI/ContentView.swift WardrobeAI/WardrobeAIApp.swift WardrobeAITests/ModelInferenceCoordinatorTests.swift WardrobeAITests/ModelProvisioningTests.swift` — passed.
- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed.
- `git diff --check` — passed before each commit.
- `xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI -sdk iphoneos -configuration Debug -derivedDataPath /private/tmp/wardrobeai-m06-derived CODE_SIGNING_ALLOWED=NO build` — passed with Xcode 27.1 (27A9275).
- `xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination 'platform=iOS Simulator,id=56183167-984D-4BF9-9522-CB67E07B4ADD' -derivedDataPath /private/tmp/wardrobeai-m06-sim-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test` — passed on iPhone Duo, iOS 27.1.
- The same simulator suite passed again after enabling provisioning under the M01 waiver.
- The simulator suite passed after the PR review and CI fixes on Xcode 27.1,
  iPhone Duo iOS 27.1. GitHub Actions runs the repository's pinned Xcode 16.4
  workflow on the updated PR branch.
- Unit tests cover rejected existing files, verified import semantics, wrong-size
  rejection and serial unload-before-switch behavior.

PR review fixes: completed URLSession downloads are moved into an app-owned
temporary file before the delegate returns; startup hashing runs off the main
actor; the embedding SHA-256 matches `Qualification/artifacts.json`; duplicate
downloads/resumes are ignored while a transfer is active; UI smoke coverage
checks the Local AI status section.

## M01 waiver and outstanding validation

The owner explicitly authorized M06 to proceed using M01's existing probe
evidence: the named device has passed the adopted composite image route and
text generation. Provisioning controls are enabled for that route.

Combined application memory/thermal measurements and real capture/model-switch
stress remain outstanding. They must be recorded before any support claim or
before enabling an additional runtime route. Embedding, audio, and tools remain
separate gates for M09, M13, and M12 respectively.
