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
  unload. The runtime adapter intentionally throws an honest unavailable error
  until M01 qualifies a concrete device/runtime route.
- The Stylist tab shows the pinned candidates and their status. Provisioning
  controls remain disabled while M01's physical-device gate is unresolved, and
  the manual wardrobe remains usable.

## Checks run

- `swiftc -module-cache-path /private/tmp/wardrobe-m06-swift-cache -typecheck WardrobeAI/ModelProvisioning.swift` — passed.
- `swiftc -parse WardrobeAI/ModelProvisioning.swift WardrobeAI/ModelStatusView.swift WardrobeAI/ContentView.swift WardrobeAI/WardrobeAIApp.swift WardrobeAITests/ModelInferenceCoordinatorTests.swift WardrobeAITests/ModelProvisioningTests.swift` — passed.
- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed.
- `git diff --check` — passed before each commit.
- Unit tests cover rejected existing files, verified import semantics, wrong-size
  rejection and serial unload-before-switch behavior. XCTest execution is
  pending the full Xcode toolchain.

## Blocking validation

M01's PR is merged, but its runtime qualification evidence remains explicitly
blocked: no physical device has successfully run the chosen E2B image route,
and combined application memory/thermal measurements do not exist. The roadmap
forbids M06–M08 from treating this as an eligible local-AI configuration.

Consequently M06 is code-complete for the independent provisioning/lifecycle
surface, but **not accepted**. Before enabling provisioning controls or closing
this milestone, record M01's device configuration and pass its image route,
repeat combined app memory/thermal measurement with capture/model switching,
and run the full simulator/XCTest suite using Xcode 16.4.
