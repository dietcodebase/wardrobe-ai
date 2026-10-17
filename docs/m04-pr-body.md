## Milestone and behavior

Milestone ID / ROADMAP entry: M04 — Single-item capture and cutout.

The garment editor can now take a photo or import one from the library. It fixes portrait orientation and downscales the image before offering a selectable original preview and any foreground-instance cutouts. A user can keep the original whenever detection returns no useful mask, then save an editable garment with its average color swatch.

## Scope and commits

- `394edee` adds permission-aware camera and photo-library sources plus generated privacy strings.
- `d6c68ca` prepares upright, bounded images, alpha-aware average swatches, and Vision foreground-instance previews.
- `b3ca36a` connects preview selection to recoverable image storage, wardrobe thumbnails, a storage regression test, and the milestone evidence.

No generated images, personal photos, credentials, or model artifacts are included.

## Verification

- Commands run and results: `swiftc -parse WardrobeAI/*.swift WardrobeAITests/*.swift`, `plutil -lint WardrobeAI.xcodeproj/project.pbxproj`, and `git diff --check origin/main...HEAD` passed.
- Acceptance criteria demonstrated: source/access errors, orientation/downsampling and original-photo fallback are implemented and syntax-checked. The test suite includes old-image cleanup during replacement.
- Device / iOS / runtime / model revision: no model is required. The provisional iOS target is 18.0.
- Screenshots or demo evidence: unavailable in this environment.
- Outstanding checks or blockers: `./scripts/check-ios.sh` cannot run locally because full Xcode 16.4 is unavailable. Real-device capture, denied-permission, rotated-photo and mask-correction review remain required before merge.

## Review and merge

- [x] Prerequisite PRs are merged; target is `main`.
- [x] Scope matches the milestone and no private data, keys or model weights are included.
- [ ] Required checks and acceptance criteria pass.
- [x] ROADMAP status/evidence is current.
- [ ] Merge preserves small commits where repository settings permit.
