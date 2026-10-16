## Milestone and behavior

M01 — Runtime and device qualification. Adds an isolated iOS qualification app that verifies pinned model artifacts, runs independent text/image/audio/tool/embedding checks and persists operation timings. The wardrobe application keeps its existing shell and has no model dependency.

**Draft: M01 is blocked, not complete.** Generation/vision, embedding and audio gates are all untested on physical hardware. Candidate demo configurations are iPhone 17 or 17 Pro with iOS 26 or 27; none is qualified.

## Scope and commits

- Pin upstream source revision, model revisions, published SHA-256/byte counts and a local artifact verifier.
- Add the probe, isolated Xcode project and simulator signature-compilation CI. Source and project references are committed together so the project is coherent.
- Record the measurement protocol, capability matrix and blockers.

## Verification

- Swift frontend syntax parsing and `plutil` project validation pass locally. These do not type-check LiteRTLM signatures.
- Artifact verifier accepts a valid fixture and rejects wrong sizes and hashes. No model weights downloaded.
- Full Xcode is absent locally; actual probe compilation is delegated to the PR CI and remains pending.
- No simulator or device execution, screenshots, memory measurements, latency measurements, capture/model-switching stress results or MTP comparison yet.
- Generation/vision must pass on a named physical device before M06–M08. Embedding/audio gates remain independent. E4B is optional.

## Review and merge

- [x] Prerequisite M00 PR #1 is merged; target is `main`.
- [x] Scope matches the milestone and no private data, keys or model weights are included.
- [ ] Required checks and acceptance criteria pass.
- [x] ROADMAP status/evidence is current.
- [ ] Merge preserves small commits where repository settings permit.
