# Implementation plan validation

Reviewed 16 October 2026. Input: [original plan](implementation-plan-v2.md), preserved unchanged. This document evaluates that proposal; its embedded prompts and code are reference material, not execution instructions.

## Verdict

The product is feasible enough to prototype, but the supplied snippets are not a verified implementation and the proposed v1 is too broad for a single delivery. Keep SwiftUI, GRDB, on-device inference, and the three-tab design. Prove the exact runtime/model/device combination before committing to performance or supported-device claims. Deliver the local wardrobe independently of the AI integration.

No application exists in this workspace yet. It was empty and had no Git repository or remote. `gh` is installed; authentication was not checked. `xcodebuild -version` failed because the active developer directory is Command Line Tools, not full Xcode. Compilation, signing, and device benchmarks remain unperformed.

## Verified versus conditional

| Topic | Finding | Decision |
|---|---|---|
| Gemma 4 | Official docs confirm E2B/E4B multimodality and configurable thinking. The model card lists Apache 2.0. [Overview](https://ai.google.dev/gemma/docs/core), [model card](https://ai.google.dev/gemma/docs/core/model_card_4). | Retain the family; record the exact artifact and license in M01. |
| Swift integration | Official Swift docs describe SPM, `LiteRTLM`, Metal, image/audio inputs, tools, thinking channels, and experimental MTP. [Swift API](https://developers.google.com/edge/litert-lm/swift). | APIs are documented, but compile against one pinned release. A `0.12.0+` constraint alone does not establish that every proposed API is available together. |
| EmbeddingGemma 2 | Official model card confirms 740M parameters, multimodal 768D embeddings and Apache 2.0. [Model card](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2). | Retain as a separately gated search enhancement. |
| Swift embeddings | Official examples include `EmbeddingEngine` and a model download URL. [Embedding models](https://developers.google.com/edge/litert-lm/embedding_models). | Verify the artifact checksum, release compatibility, backend and text/image combination on the device. Existence of examples is not an app benchmark. |
| Embedding prefixes | The runtime guide and model card show different search-prefix conventions. See the two embedding references above. | Pin the artifact, use its supported preprocessing, and compare retrieval results on a fixed query set. Do not silently assume the plan's prefixes are correct. |
| Memory and speed | Google labels memory numbers environment-dependent; weights alone exclude runtime/context overhead. [Memory guidance](https://ai.google.dev/gemma/docs/core#gemma_4_inference_memory_requirements). | File size, physical RAM and a 4K context cap do not establish jetsam safety. The plan's 3.5 GB peak and 2.5 s classification are provisional targets, not guarantees. |
| Vision fallback | Apple feature prints measure image-to-image distance. [Apple sample](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print). | They cannot replace text-to-image search. Low-memory mode keeps category/tag/text search; image similarity is a separate optional feature. Never mix feature prints with Gemma vectors. |
| Segmentation | Foreground instance masks separate noticeable objects, not semantic clothing categories. [Apple API](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest). | Require crop preview, instance selection and a manual/original-image fallback. A person wearing several garments may be one instance. |
| Color extraction | `CIAreaAverage` produces an average color, not a dominant palette. [Apple API](https://developer.apple.com/documentation/coreimage/cifilter/3547111-areaaverage). | Label it an average swatch, handle transparency, and keep editable semantic color separately. |
| Offline/privacy claims | The proposal itself uses remote weather and model downloads. | Say “on-device AI; core wardrobe works offline after provisioning.” Make network context optional and label stale/unavailable data. Never present the hard-coded weather fallback as current weather. |
| Hackathon tracks | The source has repeated `[cite: 1]` placeholders without a bibliography. Event eligibility and judging criteria were not established by this review. | Treat track claims as unverified; confirm official event rules before submission in M15. |

## Design corrections to carry into implementation

These are engineering recommendations based on review of the supplied snippets, not claims that the application has already failed tests.

- Use injected service protocols, main-actor UI state, and a serialized inference coordinator. Avoid turning every service into a mutable singleton. Camera, cutout, generation and embedding allocations must have explicit lifetimes, cancellation and memory-pressure recovery.
- Start with E2B for qualification. Enable E4B only on measured configurations; keep manual mode when neither fits. Load generation and embedding engines sequentially unless simultaneous residency passes measurement. MTP needs an on/off comparison.
- Treat generated JSON and tool parameters as untrusted data: typed categories, bounded tags, existing-item IDs, bounded retries and an editable fallback. Do not infer fabric composition or breathability as certain from a photograph.
- Similarity is useful for retrieval, but does not establish that two garments make a good outfit. Use category/occasion/weather rules, then evaluate ranking against labelled outfit examples.
- Make “Why this outfit?” a short explanation grounded in item IDs and context. The documented third-party thought channel may be an optional demo detail, but must not be required for the UX or stored as the explanation by default.
- Accepting a suggestion is ambiguous. Use an explicit “Wear today” action; if acceptance is defined to mean wearing, make that label clear. Tool writes require user intent, validated IDs and idempotency; retries must not increment counts twice.
- Add an `outfit_items` relation with foreign keys instead of relying only on JSON item IDs. Use JSON tag columns with tested GRDB encoding/decoding and parameterized `json_each` filters. Keep wear counts consistent transactionally or derive them from logs.
- Store embeddings with model ID/revision, dimension, normalization, preprocessing version and content hash. Reject invalid/non-finite or incompatible vectors; reindex after item edits/model changes. An empty array is an unavailable state, not a valid embedding.
- Use relative image paths and recoverable file/database writes. Handle removal of an item used in an outfit, orphan files, disk exhaustion and migration failure. Keep personal wardrobe data out of the Finder-shared model import area; prefer Application Support for private data and verified imported models.
- Split saved outfits, planned outfits and actual wear events. Define local-day/time-zone behavior and keep manual schedule entries separate from EventKit identifiers.
- Ask for camera, microphone and calendar access only when needed. Calendar denial, no network, no model and no weather key must have useful UI paths. Keep keys, model weights, personal photos, recordings and runtime databases out of Git.
- Use a captured still image for the first mirror feature. Continuous video inference is a separate, unestimated extension.

## Evidence required before promising device support

M01 records SDK revision, artifact URL/revision/hash/bytes, iOS/Xcode versions, actual device, backend, context limit, active encoders, and tested capabilities. Measure cold/warm load, full classification latency, peak process memory and thermal behavior across repeated runs. Repeat with camera capture and sequential model switching. Keep raw measurements and failures, not just averages.

Simulator tests can validate app behavior with fakes. They cannot establish real-device Metal performance, camera behavior, memory survival or audio-model quality. Until those checks pass, affected milestones remain blocked or explicitly reduced in scope.
