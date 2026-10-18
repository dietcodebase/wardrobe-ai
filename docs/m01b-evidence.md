# M01b qualification harness evidence

Updated 19 October 2026. Branch: `milestone/m01b-device-gate-current`.
The physical iPhone 17 gate remains open.

## Implemented

- A versioned [mind map](mindmap.md) and roadmap status checked against merged PRs #1–#19 and current `main`.
- Ten serialized generation → embedding → generation cycles with JSON checkpoints.
- A camera run that asks permission on use, dismisses the camera before inference, and records ten separate E2B image requests. Failed captures are retained in the report and can be retried; fewer than ten successes leave an incomplete suite.
- A corrected Swift package resolution pin: the tracked file previously referenced `file:///private/tmp/litert-lm-minimal/`; it now resolves the declared official LiteRT-LM revision `b2f686e2ed4718fb84ec398a61dd59ca0f0aff27`.

## Checks

- Xcode 27.1 (27A9275) selected locally.
- `swiftc -frontend -parse Qualification/RuntimeProbe.swift Qualification/ProbeApp.swift`: passed; syntax only.
- `plutil -lint Qualification/RuntimeProbe.xcodeproj/project.pbxproj`: passed.
- `xcodebuild -resolvePackageDependencies -project Qualification/RuntimeProbe.xcodeproj -scheme RuntimeProbe -derivedDataPath /tmp/wardrobe-probe-derived`: passed against the official revision.
- `xcodebuild -project WardrobeAI.xcodeproj -scheme WardrobeAI -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/wardrobe-app-derived CODE_SIGNING_ALLOWED=NO build`: passed on current `main`. This does not compile source files absent from the app target or qualify physical-device AI.
- `xcodebuild -project Qualification/RuntimeProbe.xcodeproj -scheme RuntimeProbe -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/wardrobe-probe-derived CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`: passed. A generic simulator build without the arm64 override reached the linker but failed because the pinned binary lacks an x86_64 simulator slice.
- iPhone 17 execution, JSON report, Instruments peak memory/thermal trace, and end-to-end scan → outfit run: pending user device run.

The E2B vision, embedding relevance, audio, tools and MTP behavior cannot be called qualified until the exported physical-device evidence is reviewed. The deterministic/manual wardrobe remains the fallback.
