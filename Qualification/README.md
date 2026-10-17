# M01 isolated runtime probe

This directory is qualification tooling, separate from the wardrobe application.
The manifest pins upstream source and model metadata retrieved on 16 October 2026.
Model hashes/bytes are published Hugging Face LFS metadata, not local download
verification. No weights have been downloaded or executed. E4B is optional.

Provision weights manually from the immutable `url` fields into an ignored local
folder; verify with `python3 scripts/verify-probe-artifacts.py <folder> e2b`.
The probe must verify again before initializing an engine. Never commit weights,
personal images, audio, runtime caches or device reports.

Open `RuntimeProbe.xcodeproj` with full Xcode, select the RuntimeProbe scheme,
choose a signing team and the intended physical phone. Use an Xcode release
with device support for that phone's exact iOS build (the baseline simulator CI
uses Xcode 16.4/iOS 18.5 and cannot qualify iOS 26/27 hardware). Build commands:

```sh
xcodebuild -project Qualification/RuntimeProbe.xcodeproj -scheme RuntimeProbe \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/RuntimeProbe CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Copy model files and ten synthetic/licensed JPEGs named `image-01.jpg` through
`image-10.jpg` into one folder accessible through Files. Audio uses ten known
spoken fixtures named `audio-01.wav` through `audio-10.wav`: start with mono
16-bit PCM, 16 kHz, <=10 seconds, and record whether this decoder accepts that
format. This is a test input contract, not a claim of supported runtime formats.
Retain fixture licenses, expected categories/transcripts and SHA-256 hashes
outside Git alongside each run. Embedding mode requires its own model and the
same images. No automatic download occurs.

Run E2B text first, then image, tools and audio separately. Run embeddings
separately. After those modes pass, select **switching** to run ten sequential
generation → image embedding → image generation cycles. This mode verifies both
model artifacts before starting, records each step separately, and releases one
engine before loading the next. Keep Instruments attached to the entire cycle;
the JSON does not capture memory peaks or prove native allocations were reclaimed.
For the real-camera stress check, select **capture**, choose the folder containing
the verified E2B model, grant camera access when asked, and photograph a test
garment ten times. The camera closes before each model load and image request.
Each response and elapsed time is checkpointed. A failed operation can be retried
at the same count; ending early marks the report incomplete. The probe removes
each prepared JPEG after inference. Use synthetic or licensed garments and keep
the exported report and Instruments trace outside the repository.
Select MTP off/on in separate runs with identical fixtures. Only
try E4B after E2B survives the device budget. Each run does two loads and ten
operations per load. Every run has a new compilation cache; the second load
reuses it. For a true cold-device measurement, reboot/relaunch and record cache
conditions separately. The probe does not flush the OS file cache.

Export the JSON via ShareLink or retrieve the app's Documents directory via
Xcode/Finder. The dedicated probe enables file sharing for reports only. Reports
contain synthetic fixture responses, device identifier, OS version, runtime pin,
encoder settings, thermal state and monotonic elapsed seconds; they never store
the thought channel. Hash verification is outside load timings. Image timings
include JPEG read/decode, orientation-normalizing redraw, 768-pixel longest-edge
resize, JPEG 0.85 write, conversation creation, encoder and generation. Whole
source images are decoded: this probe is not a production downsampling pipeline.

Reports are checkpointed after each operation. A missing `suite-complete` entry
is an interrupted/failed run, never a pass. Do not discard failures. Use Instruments
on a Release/Profile build for total peak process/Metal memory, thermal behavior
and lifecycle release. The JSON does not measure peak memory. Keep the Instruments
trace, termination/jetsam logs, run metadata and exact Xcode build with the report.
See `docs/runtime-qualification.md` for the outstanding acceptance protocol.
