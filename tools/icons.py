#!/usr/bin/env python3
"""Renders the icon sources into every Android, iOS, web and store size.

icon-store.svg carries the DGS lettering and is used wherever the letters still
read. icon.svg is the bare hand for the sizes below that.
"""

import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON = ROOT / "assets" / "icon.svg"
STORE = ROOT / "assets" / "icon-store.svg"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
APPICON = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WEB = ROOT / "web"
TMP = ROOT / "assets" / ".render.png"

# Adaptive icons reserve the outer third for masking, so the artwork stays small.
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# Same value as ic_launcher_background
BACKGROUND = "#FBFAF7"

# Smallest icon that still carries the DGS lettering.
LETTERED_FROM = 76


def square(
    box: int,
    fill: float,
    out: pathlib.Path,
    background: str,
) -> None:
    src = STORE if box >= LETTERED_FROM else ICON
    subprocess.run(["rsvg-convert", "-h", str(round(box * fill)), src, "-o", TMP], check=True)
    out.parent.mkdir(parents=True, exist_ok=True)
    args = ["magick", TMP, "-background", background, "-gravity", "center", "-extent", f"{box}x{box}"]
    if background != "none":
        # The App Store refuses an icon that carries an alpha channel.
        args += ["-alpha", "remove", "-alpha", "off"]
    subprocess.run(args + [out], check=True)


def feature_graphic(out: pathlib.Path) -> None:
    """Play refuses to publish a listing without one, and it is not square."""
    subprocess.run(["rsvg-convert", "-h", "340", STORE, "-o", TMP], check=True)
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["magick", TMP, "-background", BACKGROUND, "-gravity", "center", "-extent", "1024x500", "-alpha", "remove", "-alpha", "off", out],
        check=True,
    )


def ios_sizes() -> dict[str, int]:
    """Edge length per file, read off the asset catalogue rather than pinned."""
    images = json.loads((APPICON / "Contents.json").read_text())["images"]
    return {image["filename"]: round(float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x"))) for image in images}


def main() -> None:
    for name, box in FOREGROUND.items():
        square(box, 0.58, RES / f"mipmap-{name}" / "ic_launcher_foreground.png", "none")

    for name, box in LEGACY.items():
        icon = RES / f"mipmap-{name}" / "ic_launcher.png"
        square(box, 0.66, icon, BACKGROUND)
        shutil.copy(icon, RES / f"mipmap-{name}" / "ic_launcher_round.png")

    for filename, box in ios_sizes().items():
        square(box, 0.68, APPICON / filename, BACKGROUND)

    for locale in ("de-DE", "en-US"):
        images = ROOT / "fastlane/metadata/android" / locale / "images"
        square(512, 0.68, images / "icon.png", BACKGROUND)
        feature_graphic(images / "featureGraphic.png")

    for box in (192, 512):
        square(box, 0.68, WEB / "icons" / f"Icon-{box}.png", BACKGROUND)
        # A maskable icon is cropped, so the artwork stays in the safe zone.
        square(box, 0.58, WEB / "icons" / f"Icon-maskable-{box}.png", BACKGROUND)
    square(32, 0.8, WEB / "favicon.png", BACKGROUND)

    TMP.unlink(missing_ok=True)
    print("icons written")


if __name__ == "__main__":
    main()
