## Milestone and behavior

Milestone ID / ROADMAP entry: M09 — semantic wardrobe search.

Adds versioned embedding storage and cosine retrieval. Until device qualification, the UI visibly keeps the existing text/category/tag fallback instead of advertising semantic availability.

## Scope and commits

- `8be5209 feat: add versioned semantic embedding index` — validated vector storage, stale-vector invalidation, sequential indexing, cosine retrieval, and tests.
- `1a7d59c feat: show semantic search fallback state` — visible fallback copy and qualification evidence.

No model weights, credentials, personal images, or generated workspace files are included.

## Verification

- Passed: Swift syntax parse, project-file plist lint, and whitespace diff check.
- The arm64 simulator build compiled app and test targets with `-only-testing:WardrobeAITests/SemanticSearchTests`.
- XCTest is not claimed as passing: the local Xcode/Simulator setup emitted a corrupted result bundle with zero recorded tests. The default dual-architecture simulator build also exposes its existing GRDB x86_64 module mismatch.
- No device or EmbeddingGemma runtime execution was performed; see `docs/m09-evidence.md`.
- Blocker: M01 embedding qualification, prefix evaluation, and the 20-query top-five comparison remain pending.

## Review and merge

- [x] Prerequisite PRs are merged; target is `main`.
- [x] Scope matches the milestone and no private data, keys or model weights are included.
- [ ] Required checks and acceptance criteria pass — device validation remains pending.
- [x] ROADMAP status/evidence is current.
- [x] Merge preserves the two small commits where repository settings permit.
