# M04 single-item capture and cutout evidence

Status: in review at [PR #5](https://github.com/dietcodebase/wardrobe-ai/pull/5); real-device capture, denied-permission and visual acceptance remain pending. Recorded 17 October 2026.

## Implemented behavior

- The garment editor offers an explicit photo-library picker and an on-demand camera. Camera access is requested only after choosing Camera; unavailable, denied and restricted paths explain the fallback to photo selection.
- Imported and camera images are redrawn upright and downsampled to a 1,600-pixel maximum dimension before preview or storage. The camera picker closes before preparation starts.
- Foreground instance masks produce one selectable transparent PNG preview per returned instance. The original normalized photo is always a first-class selection, including when the API finds no mask or the selected mask is incomplete.
- The preview labels its alpha-aware average swatch as an average, not a dominant color. Saving writes the selected image through the existing file/database rollback coordinator; cancelling before save never writes a temporary image.
- Saved photos render on wardrobe cards. Replacing or deleting a saved photo removes the old file after its database update succeeds.

## Verification

| Check | Result |
| --- | --- |
| `swiftc -parse WardrobeAI/*.swift WardrobeAITests/*.swift` | Passed (syntax parsing only) |
| `git diff --check` | Passed before commit |
| `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` | Pending in final verification |
| Simulator build/unit/UI tests | Blocked locally: this workspace has Command Line Tools, not the required full Xcode 16.4 |
| Real-device capture, rotation, permission denial and mask correction | Pending: requires an iPhone review |

No personal photos, model artifacts or credentials were added.
