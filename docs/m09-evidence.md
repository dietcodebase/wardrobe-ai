# M09 semantic wardrobe search evidence

Status: **implementation complete; device validation pending**. Updated 17 October 2026.

## Behavior

- Garment embeddings are stored separately from garment records with model ID and
  revision, dimension, normalization flag, preprocessing version, content hash,
  and indexing time.
- The repository rejects non-finite, zero, and dimension-mismatched vectors.
  Updating a garment removes its vector so an indexing job must create a fresh
  representation.
- The indexing coordinator processes one garment at a time and cancellation is
  checked before each embedding request. The shared model coordinator remains
  responsible for sequential engine residency when a qualified runtime adapter
  is added.
- Retrieval accepts only vectors with metadata exactly matching the active
  embedder and ranks candidates by cosine similarity. Apple Vision feature
  prints are never read or presented as text-search vectors.
- Until M01 records a passing EmbeddingGemma device run and retrieval-prefix
  evaluation, the app visibly shows ordinary category/tag/text matches and says
  semantic search is unavailable. It makes no semantic-search availability or
  quality claim.

## Verification

- `swiftc -parse WardrobeAI/StorageModels.swift WardrobeAI/WardrobeDatabase.swift WardrobeAI/WardrobeRepository.swift WardrobeAI/SemanticSearch.swift WardrobeAITests/SemanticSearchTests.swift` — passed.
- `plutil -lint WardrobeAI.xcodeproj/project.pbxproj` — passed.
- `git diff --check` — passed.
- `xcodebuild test -project WardrobeAI.xcodeproj -scheme WardrobeAI -destination 'platform=iOS Simulator,id=56183167-984D-4BF9-9522-CB67E07B4ADD' -derivedDataPath /private/tmp/wardrobeai-m09-derived-arm64 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:WardrobeAITests/SemanticSearchTests` — source and test targets compiled. XCTest did not report results because this Xcode/Simulator installation produced a corrupted result bundle (zero recorded tests); this is not a pass.
- The unqualified dual-architecture simulator build cannot resolve the GRDB module for x86_64. The arm64-only build avoids that pre-existing configuration issue.
- No physical-device/model/embedding measurements were run.

## Remaining acceptance evidence

Run the M01 embedding protocol on the selected iPhone, decide and record the
query/result prefixes against a labelled 20-query set, compare top-five results
with the existing text-search baseline, and record actual runtime, memory and
interrupted-indexing results in `docs/final-validation.md`.
