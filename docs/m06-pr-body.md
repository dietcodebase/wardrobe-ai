## Milestone and behavior

M06 establishes secure, recoverable local model provisioning and a serialized
inference lifecycle. Models are verified before storage and removed if corrupt;
the Stylist tab accurately says local AI is unavailable until M01 qualifies the
runtime on a named device. Manual wardrobe flows continue without a model.

## Scope and commits

- `feat: verify provisioned model files`
- `feat: serialize model downloads and engine lifecycle`
- `feat: show qualified model lifecycle status`
- `docs: record M06 blocked qualification evidence`

## Verification

- `swiftc -module-cache-path /private/tmp/wardrobe-m06-swift-cache -typecheck WardrobeAI/ModelProvisioning.swift` — passed.
- Swift syntax parse, project property-list lint and `git diff --check` — passed.
- Device-target build passed with Xcode 27.1 (27A9275).
- Full XCTest/UI test suite passed on the iPhone Duo iOS 27.1 simulator with
  `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`.
- Unit coverage was added for verification/import and serial engine switching.

## Review and merge

- [x] Prerequisite PRs #2, #5 and #6 are merged; target is `main`.
- [x] No model weights, credentials, private records or photos are in the diff.
- [ ] M01 device/runtime acceptance and M06 combined memory measurements pass.
- [x] ROADMAP state and evidence are current.
- [ ] Keep this PR draft until the blocking validation is complete.
