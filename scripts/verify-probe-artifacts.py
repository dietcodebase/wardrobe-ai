#!/usr/bin/env python3
"""Verify manually provisioned probe weights; never downloads or loads a model."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(path, artifact):
    if path.stat().st_size != artifact['bytes']:
        raise ValueError(f"{artifact['id']}: byte count mismatch")
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != artifact['sha256']:
        raise ValueError(f"{artifact['id']}: SHA-256 mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('model', choices=['e2b', 'embedding', 'e4b'])
    args = parser.parse_args()
    manifest = json.loads((Path(__file__).resolve().parents[1] /
                           'Qualification/artifacts.json').read_text())
    artifact = next(x for x in manifest['models'] if x['id'] == args.model)
    verify(args.directory / artifact['filename'], artifact)
    print(f"Verified {args.model} at {artifact['revision']}")


if __name__ == '__main__':
    main()
