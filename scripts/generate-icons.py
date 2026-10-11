#!/usr/bin/env python3
"""Resize the committed Claude Replicant master into the Xcode icon set.

Usage: python3 scripts/generate-icons.py [--check]
Requires Pillow. Build and release scripts use the committed PNGs directly.
"""

import argparse
import json
from pathlib import Path

from PIL import Image

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
MASTER_PATH = REPOSITORY_ROOT / "media-sources" / "app-icon.png"
ICON_SET = REPOSITORY_ROOT / "claude-many" / "Assets.xcassets" / "AppIcon.appiconset"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify existing PNG pixels without writing")
    arguments = parser.parse_args()
    manifest = json.loads((ICON_SET / "Contents.json").read_text())

    with Image.open(MASTER_PATH) as source:
        master = source.convert("RGBA")

    largest_size = max(
        int(entry["size"].split("x")[0]) * int(entry["scale"].removesuffix("x"))
        for entry in manifest["images"]
    )
    if master.size != (largest_size, largest_size):
        raise SystemExit(f"Icon master must be {largest_size} × {largest_size} pixels")

    for entry in manifest["images"]:
        width, height = (int(value) for value in entry["size"].split("x"))
        scale = int(entry["scale"].removesuffix("x"))
        destination = ICON_SET / entry["filename"]
        expected = master.resize((width * scale, height * scale), Image.Resampling.LANCZOS)

        if not arguments.check:
            expected.save(destination, optimize=True)
            continue

        with Image.open(destination) as source:
            actual = source.convert("RGBA")
        if actual.size != expected.size or actual.tobytes() != expected.tobytes():
            raise SystemExit(f"Icon does not match the master: {destination.name}")

    print(f"{'Verified' if arguments.check else 'Generated'} {len(manifest['images'])} Claude Replicant icons")


if __name__ == "__main__":
    main()
