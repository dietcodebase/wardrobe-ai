# M01 runtime and device qualification

Status: **blocked; draft PR [#2](https://github.com/dietcodebase/wardrobe-ai/pull/2)**.
Updated 16 October 2026. No runtime/model/device combination is qualified.
M00 prerequisite PR #1 merged on 16 October 2026 (verified through GitHub).

## Decision and go/no-go matrix

The demo candidates supplied by the owner are **iPhone 17 or iPhone 17 Pro,
iOS 26 or iOS 27**. Exact hardware identifier, OS build, Xcode version and signing
are still to be selected and tested. A pass on one configuration does not qualify
the others. Do not infer device support from physical RAM. Keep manual/local mode.

| Capability | Evidence today | Decision / dependent work |
|---|---|---|
| Exact Swift signatures / binary linkage | Source inspected; syntax only locally; CI pending | Compile gate pending |
| E2B generation + vision | No model download or physical-device run | Untested; blocks M06–M08 |
| EmbeddingGemma 2 text + image | Probe validates dimensions/finiteness/nonzero only; not executed | Untested; blocks M09 |
| E2B audio | Decoder/format and transcription quality untested | Untested; blocks M13 |
| Tools | Fixed read-only echo probe; no device invocation | Untested; no tool support claim |
| MTP off/on | Separate run setting implemented; no measurements | Untested; default off for evaluation |
| E4B | Optional; artifact metadata only | Deferred until E2B resource safety is established |
| Capture/model switching/repeated use | File fixture switching and real-camera capture harnesses implemented; physical runs pending | Unmet acceptance requirement |

M02–M05 may proceed independently per ROADMAP. No AI capability gate is passed.

## Reproducibility and source evidence

`Qualification/artifacts.json` is the machine-readable source of runtime/model
pins and published model byte counts/SHA-256. Runtime source is pinned to
`b2f686e2ed4718fb84ec398a61dd59ca0f0aff27`; its Package.swift references binary
v0.18.0 with an SPM checksum. Model metadata was retrieved through the official
publisher's Hugging Face API with `blobs=true`; weights are not locally verified
until provisioned and checked. Neither models nor SDK binaries are vendored.

- [Pinned runtime manifest](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/Package.swift): Swift tools 5.9, SDK iOS minimum 15; probe deployment target remains iOS 18. Neither is a measured device-support policy.
- [Pinned generation lifecycle](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/swift/Engine.swift): `Engine` deletes its native handle in `deinit`; no public `close()`. Conversations retain the engine. Probe scopes both before another load. Resource release must be measured.
- [Pinned embedding lifecycle](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/swift/EmbeddingEngine.swift): explicit actor `close()` is awaited on success/error; engines run sequentially.
- [Swift guide](https://developers.google.com/edge/litert-lm/swift) and [embedding guide](https://developers.google.com/edge/litert-lm/embedding_models) informed the probe. Source inspection does not substitute for compilation or execution.

E2B/E4B use the publisher's GPU artifact; generation uses Metal with CPU vision
or CPU audio enabled only for that capability. Embeddings use GPU text/vision,
audio disabled. Generation context is 4096 tokens, maximum output 128, thinking
disabled. MTP is set before initialization, with distinct on/off runs. The probe
uses the upstream image decoder after its documented JPEG preprocessing.

Embedding queries currently use the runtime guide's `task: search query | text:`
prefix. This is an explicit experiment, not the final retrieval policy. Before
M09, compare model-card conventions and runtime-guide prefixes on a fixed labelled
query/image set, recording model revision, normalization, image preprocessing and
retrieval quality. Valid 768D vectors alone do not pass relevance qualification.

## Required physical-device protocol

Follow `Qualification/README.md` for provisioning and running the isolated app.
Archive every report with a run sheet containing exact hardware identifier/model,
iOS build, Xcode build, artifact and fixture hashes/licenses, backend/encoders,
context, MTP, cache state, battery/power, ambient conditions and initial thermal
state. Synthetic/licensed inputs only; no personal wardrobe photos or recordings.

1. Compile exact signatures, link the pinned binary, launch on the chosen phone.
   Retain compiler output and probe screenshot. Simulator CI is compilation evidence only.
2. Run E2B text and image independently, at least ten operations each (the probe
   runs 20). Manually score garment category/color outputs; retain invalid responses.
   Record cold/reused-cache load times and p50/p95 full image-request latency using
   nearest-rank percentiles, including all failures separately. Report each load pass
   and combined results; do not average away slow/failed operations.
3. Measure total peak app/Metal memory in Instruments through load, preprocessing,
   inference and release. Record thermal state and termination/jetsam evidence.
   Proposed classification p95 <=2.5 s and total peak <=3.5 GB remain provisional.
   Revise with measured rationale before downstream code relies on them.
4. Run the real-camera capture + inference harness for at least ten separate photos.
   Run the implemented
   generation→embedding→generation mode for ten cycles. Verify release, thermal recovery,
   missing/corrupt artifacts and termination behavior. The current isolated file
   probe does not implement this capture/switch acceptance test.
5. Run tools (expect exactly one echo invocation and returned sentinel), audio
   against known transcripts, and embedding text/image relevance independently.
   Record actual accepted sample rate/channels/encoding and failure cases. Audio
   failure blocks voice only; embedding failure blocks semantic search only.
6. Compare MTP off/on for the same fixture set, quality, load, latency and memory.
   Evaluate E4B only if E2B measurements justify resource headroom. A failed E2B
   qualification leaves the app in manual mode; no silent model-family substitution.

## Verification performed

- `swiftc -frontend -parse Qualification/RuntimeProbe.swift Qualification/ProbeApp.swift`: pass (syntax only).
- `plutil -lint Qualification/RuntimeProbe.xcodeproj/project.pbxproj`: pass.
- Artifact-verifier synthetic checks: valid bytes pass; wrong size and wrong hash reject.
- `git diff --check`: pass.
- `xcodebuild -version`: unavailable; selected developer directory is Command Line Tools and full Xcode is not installed locally.
- CI exact-signature build: first run failed in upstream Swift sources because main referenced a mismatched C binary. Source is now pinned to the matching v0.18.0 release commit; arm64 simulator rebuild pending. See [failed run](https://github.com/dietcodebase/wardrobe-ai/actions/runs/38925446897).
- Device execution, screenshots, peak memory, p50/p95, thermal/capture/switch tests,
  audio quality, embedding relevance and MTP comparison: **not run**.

M01 is partial implementation with device validation pending, not code-complete or
accepted. Resume this milestone after compilation and hardware are available;
merge only after the acceptance matrix has actual evidence.
