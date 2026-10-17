# Wardrobe AI roadmap

Status: M00 implemented locally; build/launch acceptance pending full Xcode. Updated 16 October 2026.

Read [validation and corrections](docs/PLAN-VALIDATION.md) before implementation. The [original proposal](docs/implementation-plan-v2.md) is preserved as reference; this roadmap is the execution plan. No time estimates are promised before runtime/device qualification.

## Build one milestone at a time

Use `$wardrobe-milestone M00` to start, then `$wardrobe-milestone next`. The repository skill is at [.agents/skills/wardrobe-milestone/SKILL.md](.agents/skills/wardrobe-milestone/SKILL.md). If it does not appear in the selector, reopen the project or say `Read .agents/skills/wardrobe-milestone/SKILL.md and build M00`.

Useful requests: `plan M07`, `status`, `resume M07`, or `merge M07`. Building opens a PR when a remote is configured; merging follows an explicit merge request or an existing instruction to build and merge. A phase is a release checkpoint containing several milestones; each milestone has its own branch and PR.

## Delivery map

| Phase | Milestones | Usable result |
|---|---|---|
| 0 — Establish feasibility | M00–M01 | Reproducible project and measured AI integration decision |
| 1 — Local wardrobe | M02–M05 | Add/edit/search clothes, save outfits, track actual wear without AI |
| 2 — On-device AI MVP | M06–M08 | Provision a model, classify garments, recommend owned outfits |
| 3 — Retrieval and context | M09–M11 | Semantic search, optional weather, calendar and outfit planning |
| 4 — Multimodal assistant | M12–M15 | Tool chat, voice, batch capture, still-photo mirror demo, release qualification |

Default delivery order is numeric. Dependencies below are the technical minimum; `next` picks the earliest unmerged eligible milestone. M02–M05 can proceed if device testing blocks M01. AI milestones cannot bypass M01 evidence.

| ID | Milestone | Branch | Depends on | State | PR |
|---|---|---|---|---|---|
| M00 | Project and delivery foundation | `milestone/m00-foundation` | — | merged | [#1](https://github.com/dietcodebase/wardrobe-ai/pull/1) · [evidence](docs/m00-evidence.md) |
| M01 | Runtime and device qualification | `milestone/m01-runtime-spike` | M00 | blocked | [#2](https://github.com/dietcodebase/wardrobe-ai/pull/2) · [evidence](docs/runtime-qualification.md) |
| M02 | Database and file storage | `milestone/m02-storage` | M00 | blocked | [#3](https://github.com/dietcodebase/wardrobe-ai/pull/3) · [evidence](docs/m02-evidence.md) |
| M03 | Wardrobe browsing and editing | `milestone/m03-wardrobe` | M02 | in-review | [#4](https://github.com/dietcodebase/wardrobe-ai/pull/4) · [evidence](docs/m03-evidence.md) |
| M04 | Single-item capture and cutout | `milestone/m04-capture` | M03 | planned | — |
| M05 | Saved outfits and wear history | `milestone/m05-outfits-wear` | M03 | planned | — |
| M06 | Model provisioning and lifecycle | `milestone/m06-model-manager` | M01, M04, M05 | planned | — |
| M07 | Automatic garment classification | `milestone/m07-classification` | M06 | planned | — |
| M08 | Outfit suggestions and explanations | `milestone/m08-recommendations` | M07 | planned | — |
| M09 | Semantic wardrobe search | `milestone/m09-semantic-search` | M08, embedding gate from M01 | planned | — |
| M10 | Optional weather context | `milestone/m10-weather` | M08 | planned | — |
| M11 | Calendar and outfit scheduling | `milestone/m11-calendar` | M05, M10 | planned | — |
| M12 | Text stylist with bounded tools | `milestone/m12-stylist-chat` | M08, M11 | planned | — |
| M13 | Voice input | `milestone/m13-voice` | M12, audio gate from M01 | planned | — |
| M14 | Batch garment capture | `milestone/m14-batch-capture` | M07 | planned | — |
| M15 | Mirror fit-check and demo release | `milestone/m15-mirror-release` | M09–M14 | planned | — |

## Git and review contract

1. Branch from updated `main` after prerequisite PRs merge. One milestone per branch and PR; no direct implementation commits or pushes to `main`. Resume an existing branch/PR instead of duplicating it. Avoid stacked branches by default.
2. Make one coherent change per commit, generally 100–250 changed handwritten lines. Treat 400 lines as a review signal: split when practical or explain why the change is indivisible. Generated Xcode metadata, lockfiles and fixtures are separate, clearly described commits. Do not split working code into intentionally broken commits just to meet a count.
3. The slices below suggest commit boundaries. Each includes its relevant tests. Keep unrelated cleanup out. If a milestone grows beyond roughly 800 handwritten lines or several distinct outcomes, split it into suffixed milestones (e.g. M08a/M08b), each with a branch and PR, and update dependencies before proceeding.
4. Verify build, relevant tests, diff and acceptance criteria. Record actual commands/results and any outstanding device checks. Required tests that cannot run are blockers, not passes. Draft PRs can preserve blocked work.
5. PRs target `main`, identify the milestone, show before/after behavior, list verification and include screenshots for UI changes. Use [.github/pull_request_template.md](.github/pull_request_template.md).
6. Merge only through the PR after required checks, review and milestone acceptance pass. Prefer merge commits to preserve small commits; rebase merge is acceptable if the repository requires it. Do not squash the entire milestone into one large commit by default. Never bypass branch protection.
7. Update the table to `in-progress`, `in-review`, `blocked`, or `merged`, with the PR URL and evidence. Merge status is verified from the host, not inferred from local code. Record a completed merge in the next roadmap update; avoid a standalone PR solely to change a status cell.

### Initial repository bootstrap

The directory currently has no Git history or remote. M00 may create one empty initial commit on `main` locally so a feature branch can have a base, then place all substantive files on its branch. A remote with that base branch is needed for a PR. Discover an existing configured destination or ask for the repository URL/owner and visibility; do not invent a public repository. The empty bootstrap commit is the only exception to the PR-only rule. No Git initialization, remote creation or application build was performed during this planning task.

## Milestone cards

### M00 — Project and delivery foundation

**Outcome:** A buildable iOS app shell and repeatable PR checks.

Commit slices: (1) Git/bootstrap documentation and existing planning files; (2) minimal SwiftUI project, iOS 18 deployment target pending SDK qualification, three tabs and test targets; (3) injected service interfaces/fakes only where needed; (4) pinned build instructions, macOS CI and ignored local configuration/model/data files.

Acceptance: select/install full Xcode as needed, record version and simulator destination; clean checkout builds and launches; smoke test navigates all three tabs; CI runs the same commands. No model downloads are required to build the shell. Resolve remote destination before creating the PR. Configure required checks/PR protection where account permissions allow.

### M01 — Runtime and device qualification

**Outcome:** A small executable probe plus a documented go/no-go matrix, not the full ML service.

Commit slices: (1) pin a LiteRT-LM revision and artifact manifest; (2) probe text and image inference; (3) probe embeddings/audio/tools and MTP independently; (4) record measurements and the chosen device/runtime policy.

Acceptance: compile the exact Swift signatures; run E2B on an actual intended demo iPhone; measure cold/warm loading, full image request latency and peak memory over at least ten repeated operations including capture/model switching. Evaluate E4B only if resources allow. Record missing hardware as untested. Proposed budgets: classification p95 <=2.5 s and total peak <=3.5 GB on the named demo device, plus no termination during repeated use; revise budgets with measured rationale before implementation relies on them. No unsupported-device promises based solely on physical RAM.

Gate: generation+vision must pass for M06–M08. Embedding and audio each get their own pass/fail; failure blocks only dependent features. Record SDK minimum OS, artifact hashes, preprocessing, active encoders, lifecycle/close semantics and MTP on/off results in `docs/runtime-qualification.md`. Preserve local/manual mode if AI qualification fails; do not silently replace the chosen model family.

### M02 — Database and file storage

**Outcome:** Reliable local records and image ownership.

Commit slices: (1) GRDB migrations for items/preferences; (2) outfits, outfit-items and wear-log relations; (3) image store with relative paths and recovery; (4) idempotent seed data and repository tests.

Acceptance: fresh/migrated database CRUD works; tag arrays round-trip and `json_each` filters are parameterized; deletion respects references; failed file/DB writes recover without broken images. Seed import does not duplicate records. Use synthetic/licensed sample assets, not personal photos.

### M03 — Wardrobe browsing and editing

**Outcome:** Browse, filter, manually add/edit and delete garments, with a style profile sheet.

Commit slices: (1) grid/empty/loading/error states; (2) item detail/editor and category/occasion taxonomy including one-piece outfits; (3) category/tag/text search and style preferences.

Acceptance: changes survive restart; deleting an item updates the UI and references; invalid input is explained; Dynamic Type and accessibility labels work. Semantic search is not advertised yet.

### M04 — Single-item capture and cutout

**Outcome:** Photograph or import one garment and save an editable preview.

Commit slices: (1) permission-aware camera/photo import; (2) orientation-correct downsampling and foreground selection; (3) preview/manual fallback, alpha-aware average swatch and save flow.

Acceptance: real-device capture and denied permission paths work; camera stops during processing; portrait/rotated photos display correctly; missing/multiple masks allow user correction; cancellation removes temporary images. No AI model is needed.

### M05 — Saved outfits and wear history

**Outcome:** Manually assemble outfits and record actual wear.

Commit slices: (1) outfit builder/favourites; (2) explicit Wear today action, transactional idempotent logs and undo; (3) history and underused-items list.

Acceptance: duplicate taps/retries do not duplicate a wear event; undo restores counts; never-worn and recently added items behave sensibly; item deletion and local-day boundaries are tested. Saving or scheduling an outfit does not silently log wear.

**Phase 1 checkpoint:** A useful offline wardrobe app. This is the fallback demo if AI work is blocked.

### M06 — Model provisioning and lifecycle

**Outcome:** A recoverable model manager and shared inference coordinator.

Commit slices: (1) manifest/checksum verification and sideload import; (2) download progress/cancel/resume, disk-space and corrupt-file handling; (3) serialized load/use/unload, memory/thermal recovery and model status UI.

Acceptance: models stay out of Git; missing/corrupt/interrupted downloads never load; restart finds verified models; manual wardrobe still works during failure. Keep private records out of the file-sharing import directory and exclude downloadable weights from backups. Use only device configurations qualified by M01; remeasure combined app memory.

### M07 — Automatic garment classification

**Outcome:** Capture suggests editable tags locally.

Commit slices: (1) classifier adapter and typed bounded output validation; (2) background processing/cancellation and error fallback; (3) capture preview integration, persisted classification provenance and corrections.

Acceptance: malformed JSON, unknown categories, timeouts and cancelled requests are handled; manual save remains available; material guesses are labelled and editable. Measure end-to-end latency on at least 20 varied garment images and report correct category count, invalid responses and p50/p95 time. No claim of sub-second classification without evidence.

### M08 — Outfit suggestions and explanations

**Outcome:** “What should I wear?” and “What goes with this?” using owned items.

Commit slices: (1) deterministic candidate rules with preferences/manual occasion and recent wear; (2) bounded model ranking over candidate IDs; (3) cards, concise explanations, save and Wear today integration.

Acceptance: no nonexistent IDs or conflicting category combinations; one-piece outfits and sparse wardrobes work; rules provide fallback if ranking fails. Compare suggestions on at least ten fixed wardrobe/context cases. Report ranking quality separately from retrieval similarity. Weather/calendar are manual context until M10/M11.

**Phase 2 checkpoint:** On-device AI MVP. Capture → editable tags → owned-item suggestions → explicit wear log must work offline after model provisioning.

### M09 — Semantic wardrobe search

**Outcome:** Search garments by natural language on qualified devices.

Commit slices: (1) embedding adapter and versioned vector storage; (2) bounded indexing/reindexing jobs with sequential engine use; (3) filtered cosine retrieval and honest unavailable/text-search fallback.

Acceptance: dimension/model/preprocessing mismatch, non-finite/zero vectors and interrupted indexing are tested; edits invalidate stale vectors. Compare top-five results against at least 20 labelled queries and the existing text-search baseline. Document prefix selection where upstream docs differ. Never compare Apple feature prints with Gemma embeddings or advertise feature prints as text search.

### M10 — Optional weather context

**Outcome:** Today's context includes weather with freshness and source.

Commit slices: (1) provider interface, fixtures and configurable city; (2) OpenWeatherMap client/cache with external local credential configuration; (3) context header and recommendation integration.

Acceptance: fresh/cached/stale/unavailable states are distinct; timeouts, rate limits and missing key leave recommendations usable. Unit conversion is tested. No fixed Bengaluru weather is shown as live. No secrets in Git; a production-distribution credential strategy must be resolved before release if weather ships publicly.

### M11 — Calendar and outfit scheduling

**Outcome:** Optional calendar context and in-app outfit plans.

Commit slices: (1) EventKit permission/reader adapter; (2) minimal event context and manual occasion editor; (3) date-to-outfit planning UI/storage.

Acceptance: permission denial/revocation, all-day/midnight/time-zone events and source-event deletion work. Manual scheduling works without EventKit. Scheduling does not record wear or write external calendar events. Minimize event details passed to the local model and avoid calendar titles in diagnostic logs.

### M12 — Text stylist with bounded tools

**Outcome:** Chat can look up owned items/context and propose useful actions.

Commit slices: (1) streaming chat, cancellation and bounded history; (2) read-only search/context/recent-wear tools; (3) explicit-intent wear action with validation and duplicate-call protection.

Acceptance: tool arguments, invalid IDs, maximum tool-call count, timeouts and duplicate writes are tested against an in-memory database. Item descriptions and calendar titles cannot redefine tool permissions. Tool errors render honestly. Explanations use final user-facing output; raw thought traces are not required or stored by default.

### M13 — Voice input

**Outcome:** Hold-to-talk sends an audio request to the qualified local runtime.

Commit slices: (1) microphone permission and audio session/recording; (2) tested format conversion and duration limit; (3) chat integration with interruption/cancel cleanup.

Acceptance: validate actual sample rate/channels/encoding against M01; denial, calls/interruption and cancellation restore UI state. Test a small set of spoken wardrobe requests on device. Delete temporary recordings; text input remains available. Do not substitute cloud transcription silently.

### M14 — Batch garment capture

**Outcome:** Preview and save selected cutouts from a single photo.

Commit slices: (1) multiple-instance selection and correction UI; (2) sequential classification queue with progress/cancel; (3) partial-success save/retry and temporary-file cleanup.

Acceptance: two or three separated garments, overlapping garments, zero masks, partial errors and cancellation are covered. Peak memory is measured with the actual model. Never assume every mask is a garment or classify all crops concurrently.

### M15 — Still-photo mirror fit-check and demo release

**Outcome:** Capture an outfit, get a context-aware critique and an owned-item swap; demonstrate the complete app.

Commit slices: (1) full-frame still capture and bounded context; (2) verified swap cards/deep links and missing-item fallback; (3) regression fixes and accessibility polish; (4) reproducible demo guide, measured support matrix and asset/dependency notices.

Acceptance: suggested swaps exist at display time; no suitable swap is a valid answer; comments address clothing rather than body judgments. Test a representative photo set. Run the complete workflow online/offline, with denied permissions, missing models, thermal pressure and restarts. Verify minimum supported device and demo device separately; remove unsupported claims. Show provisional versus measured budgets. Confirm event rules from an official source before claiming track eligibility.

If the mirror implementation plus release work exceeds the PR-size guideline, split M15a (mirror) and M15b (release qualification) before coding. Continuous video inference remains outside this milestone.

## Deferred backlog

Travel packing, shopping links/gap analysis, cloud sync/backup, a full onboarding quiz, continuous mirror video, automatic material certainty, and broad untested device support are outside these milestones. Implicit preference learning can follow explicit preferences once enough trustworthy wear history exists; it needs its own evaluation and PR.

## Definition of done

A milestone is done only when its scoped behavior and acceptance checks pass, its evidence is recorded, and its PR is merged into `main`. Implementation complete, PR open, device validation pending, and merged are distinct states. If requirements change, update this roadmap and the validation decision before expanding scope.
