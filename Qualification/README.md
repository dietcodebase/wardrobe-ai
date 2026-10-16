# M01 isolated runtime probe

This directory is qualification tooling, separate from the wardrobe application.
The manifest pins upstream source and model metadata retrieved on 16 October 2026.
Model hashes/bytes are published Hugging Face LFS metadata, not local download
verification. No weights have been downloaded or executed. E4B is optional.

Provision weights manually from the immutable `url` fields into an ignored local
folder; verify with `python3 scripts/verify-probe-artifacts.py <folder> e2b`.
The probe must verify again before initializing an engine. Never commit weights,
personal images, audio, runtime caches or device reports.
