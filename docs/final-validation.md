# Final validation tracker

Status: pending implementation of the remaining milestones.  
Decision: feature-first delivery approved by the project owner on 17 October 2026. Run this plan against the integrated release candidate before merging the deferred milestone PRs or making support/performance claims.

This tracker consolidates evidence; it does not waive any milestone's acceptance criteria. Record the exact command, device, OS, build/configuration, model/artifact version, date, result, raw-report location, and issue/PR for every failed or rerun check.

## Execution order

1. Stabilize the integrated candidate: resolve compilation, unit-test-host/linking, migration, and accessibility regressions.
2. Run simulator and deterministic unit/integration tests; record the full command output or CI run.
3. Run physical-device qualification and the end-to-end release scenario on the named demo device.
4. Fix failures on their owning milestone branches, repeat affected checks, then retarget/merge PRs in dependency order.

## Environment record

| Field | Record |
|---|---|
| Candidate commit / branch | pending |
| Xcode and macOS | pending |
| Simulator destination | pending |
| Demo device / iOS / storage | pending |
| Release/Profile build configuration | pending |
| Model artifacts, hashes, runtime and MTP state | pending |
| Fixture set and licensing | pending |
| Test date / operator | pending |

## Shared release checks

- [ ] Clean checkout builds the app and test targets; resolve the current test-host linker issue before calling tests passing.
- [ ] Run all deterministic unit and integration tests, including database migrations and persistence across relaunch.
- [ ] Verify a Release/Profile build on the named demo device.
- [ ] Record Instruments total and Metal peak memory, CPU, thermal state, crash/termination evidence, and raw trace paths.
- [ ] Run the complete workflow online/offline, after restart, with missing/corrupt/unavailable models, and under constrained storage/network conditions.
- [ ] Verify Dynamic Type, VoiceOver labels, permission-denial recovery, and temporary-file/data cleanup.
- [ ] Confirm no models, secrets, personal photos, or private records are committed or exposed by sharing/import paths.

## M01 runtime gates

- [ ] On the intended demo iPhone, run at least ten cold/warm loads, full image requests, capture-to-inference transitions, and generation-to-embedding-to-generation switches.
- [ ] Record peak memory and termination outcome for each repeated-use route; include MTP on/off results.
- [ ] Record the exact SDK signatures, minimum OS, preprocessing, active encoders, artifact hashes, and lifecycle/close behavior.
- [ ] Record a generation + vision pass/fail decision for M06–M08; separately decide embedding for M09 and audio for M13.
- [ ] Update [runtime qualification](runtime-qualification.md) with measurements and the supported-device policy.

## Feature acceptance matrix

| Milestone | Required final evidence | Status / evidence link |
|---|---|---|
| M00–M05 | Full regression: three tabs, CRUD/migrations, image ownership, capture/import and denied permission, outfits/wear idempotency/undo, restart persistence | pending |
| M06 | Missing, corrupt, interrupted and resumed models; restart discovery; serialized lifecycle; combined-app memory and thermal recovery | pending |
| M07 | At least 20 varied garment images: category-correct count, invalid responses, cancellations, and end-to-end p50/p95; manual edit/save fallback | pending |
| M08 | At least 10 fixed wardrobe/context cases; no nonexistent/conflicting items; sparse and one-piece wardrobes; rules fallback | pending |
| M09 | At least 20 labelled natural-language queries versus text-search baseline; index interruption, stale vectors, model/preprocessing mismatch | pending |
| M10 | Fresh/cached/stale/unavailable weather, timeout/rate-limit/missing-key behavior, unit conversion, and no secret leakage | pending |
| M11 | Permission denial/revocation; all-day, midnight/time-zone and deleted events; manual scheduling; never logs wear or writes events | pending |
| M12 | Invalid tool arguments/IDs, call-limit, timeout, duplicate-write prevention, untrusted item/calendar text, and honest error UI | pending |
| M13 | Actual audio format versus M01, denial, interruption/cancel cleanup, temporary-recording deletion, and spoken-request sample set | pending |
| M14 | Two/three separated garments, overlap, zero masks, partial error/cancel/retry, cleanup, sequential queue, actual-model peak memory | pending |
| M15 | Representative photo set; safe owned-item swaps/missing swap; online/offline, denied permissions, missing model, thermal pressure, restart; accessibility and demo guide | pending |

## Final merge and release gate

- [ ] Every matrix row has a pass/fail result and links to raw evidence or an issue with an explicit decision.
- [ ] Failed gates have been fixed, rerun, and linked from the owning milestone evidence.
- [ ] Supported device/OS, model availability, privacy behavior, and performance claims match measured evidence only.
- [ ] PRs are reviewed and retargeted to `main` as prerequisites merge; merge in dependency order.
- [ ] The final release/demo guide is reproducible from a clean checkout.
