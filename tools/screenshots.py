#!/usr/bin/env python3
"""Takes the store screenshots on a device and files them under fastlane.

    python3 tools/screenshots.py [device]

Needs a running device or emulator. Without an argument it takes the only
Android one it finds, since flutter drive would otherwise pick the desktop and
stop.

The capture walks the app through four screens twice, once light and once
dark. Play sorts the listing by file name, so the frames are renumbered 1..n
in the order the capture named them: the light set first, then the dark one.
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STAGING = ROOT / "build" / "screenshots"
LOCALES = ("de-DE", "en-US")
DRIVER = "test_driver/screenshots.dart"
TARGET = "test_driver/screenshots_test.dart"

# Play takes at most eight per locale and refuses a side outside these bounds.
MAX_SHOTS = 8
MIN_EDGE = 320
MAX_EDGE = 3840


def android_device() -> str:
    """The one attached Android device. Anything else is the caller's call."""
    listed = subprocess.run(
        ["flutter", "devices", "--machine"],
        check=True,
        capture_output=True,
        text=True,
        cwd=ROOT,
    ).stdout
    ids = [d["id"] for d in json.loads(listed) if d.get("targetPlatform", "").startswith("android")]
    if not ids:
        sys.exit("no Android device, start an emulator first")
    if len(ids) > 1:
        sys.exit(f"several Android devices, name one: {', '.join(ids)}")
    return ids[0]


def capture(device: str) -> None:
    shutil.rmtree(STAGING, ignore_errors=True)
    print(f"capturing on {device}")
    subprocess.run(
        ["flutter", "drive", "-d", device, f"--driver={DRIVER}", f"--target={TARGET}"],
        check=True,
        cwd=ROOT,
    )


def edges(path: pathlib.Path) -> tuple[int, int]:
    out = subprocess.run(
        ["magick", path, "-format", "%w %h", "info:"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    return int(out[0]), int(out[1])


def cropped(shot: pathlib.Path, out: pathlib.Path) -> tuple[int, int]:
    """Cuts the strips the system bars left empty as measured on the device."""
    width, height = edges(shot)
    bars = re.search(r"--top(\d+)--bottom(\d+)$", shot.stem)
    top, bottom = (int(bars[1]), int(bars[2])) if bars else (0, 0)

    subprocess.run(
        ["magick", shot, "-crop", f"{width}x{height - top - bottom}+0+{top}", "+repage", out],
        check=True,
    )
    return edges(out)


def main() -> None:
    capture(sys.argv[1] if len(sys.argv) > 1 else android_device())

    shots = sorted(STAGING.glob("*.png"))
    if not shots:
        sys.exit(f"{STAGING} is empty, the capture wrote nothing")
    if len(shots) > MAX_SHOTS:
        sys.exit(f"{len(shots)} shots, Play takes {MAX_SHOTS}")

    first = ROOT / "fastlane/metadata/android" / LOCALES[0] / "images/phoneScreenshots"
    shutil.rmtree(first, ignore_errors=True)
    first.mkdir(parents=True)

    for number, shot in enumerate(shots, start=1):
        width, height = cropped(shot, first / f"{number}.png")
        if not MIN_EDGE <= width <= MAX_EDGE or not MIN_EDGE <= height <= MAX_EDGE:
            sys.exit(f"{shot.name} is {width}x{height}, outside Play's bounds")
        print(f"{number}.png  {width}x{height}  {shot.name}")

    for locale in LOCALES[1:]:
        out = ROOT / "fastlane/metadata/android" / locale / "images/phoneScreenshots"
        shutil.rmtree(out, ignore_errors=True)
        shutil.copytree(first, out)

    print(f"\n{len(shots)} screenshots written for {', '.join(LOCALES)}")


if __name__ == "__main__":
    main()
