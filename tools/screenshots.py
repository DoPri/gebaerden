#!/usr/bin/env python3
"""Takes the store screenshots on a device and files them under fastlane.

    python3 tools/screenshots.py [device]

Needs a running device or emulator. Without an argument it takes the only
Android one it finds, since flutter drive would otherwise pick the desktop and
stop.

The capture walks the app through eight screens, one feature each, and hands
the frames over raw. This script cuts the strips the system bars left empty,
lays each frame on a 1080x1920 canvas under a caption and writes one set per
locale, German captions for de-DE and English ones for en-US. The screens
themselves stay German, that is the only language the app speaks.
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STAGING = ROOT / "build" / "screenshots"
WORK = STAGING / "work"
LOCALES = ("de-DE", "en-US")
DRIVER = "test_driver/screenshots.dart"
TARGET = "test_driver/screenshots_test.dart"

# Play takes at most eight per locale, refuses a side outside these bounds and
# refuses a frame whose long side is more than twice its short one.
MAX_SHOTS = 8
MIN_EDGE = 320
MAX_EDGE = 3840
MAX_RATIO = 2

# Play's own recommendation, and 1:1.78 clears the ratio rule with room.
CANVAS = (1080, 1920)
BAND = 320
MARGIN = 90
HEAD_TOP = 80
GAP = 16
HEAD_POINTS = 52
SUB_POINTS = 34
FRAME_BOTTOM = 44
BORDER = 2

# Same values as AppColors in lib/theme.dart.
THEMES = {
    "hell": {"bg": "#FBFAF7", "fg": "#1D1A17", "muted": "#68645E", "border": "#DEDCD8"},
    "dunkel": {"bg": "#12100E", "fg": "#EEEDEA", "muted": "#9D9994", "border": "#34312D"},
}

# Keyed by the name the capture gave the frame. Every frame needs an entry,
# a missing one stops the run rather than shipping an unlabelled screenshot.
CAPTIONS = {
    "woerterbuch": {
        "de-DE": (
            "Wörterbuch mit Tausenden Gebärden",
            "Gezielt suchen, im Alphabet blättern und verwandte Gebärden entdecken",
        ),
        "en-US": (
            "A dictionary of several thousand signs",
            "Search, browse by letter, and follow related words",
        ),
    },
    "video": {
        "de-DE": (
            "Zeitlupe bis 0,25x",
            "Mit Endlosschleife, Spiegeln für Linkshänder und Bild für Bild-Steuerung",
        ),
        "en-US": (
            "Slow motion down to 0.25x",
            "Plus looping, mirroring for left-handed signers and frame stepping",
        ),
    },
    "lernen": {
        "de-DE": (
            "Vokabeltrainer nach FSRS",
            "Spaced Repetition: Der gleiche Algorithmus, den auch Anki nutzt",
        ),
        "en-US": (
            "Vocabulary trainer using FSRS",
            "Spaced repetition, the same algorithm Anki uses",
        ),
    },
    "abfrage": {
        "de-DE": (
            "Drei Abfragearten",
            "Selbsteinschätzung, Multiple Choice oder freies Eintippen",
        ),
        "en-US": (
            "Three question types",
            "Self rating, four-way multiple choice or typing",
        ),
    },
    "fingeralphabet": {
        "de-DE": (
            "Fingeralphabet und Zahlen",
            "Inklusive Umlauten, den Zahlen von 0 bis 20 und einem Modus zum Buchstabieren",
        ),
        "en-US": (
            "Fingerspelling and numbers",
            "A to Z including umlauts, the numbers 0 to 20 and a spelling mode",
        ),
    },
    "liste": {
        "de-DE": (
            "Eigene Listen mit Erinnerungen",
            "Einstiegsthemen, eigene Listen und eine Erinnerung pro Liste",
        ),
        "en-US": (
            "Your own lists with reminders",
            "Starter topics, your own lists and one reminder per list",
        ),
    },
    "statistik": {
        "de-DE": (
            "Den Fortschritt im Blick",
            "Aktueller Streak, gelernte Karten und anstehende Wiederholungen",
        ),
        "en-US": (
            "Your progress at a glance",
            "Days in a row, cards learned and what comes due next",
        ),
    },
    "offline": {
        "de-DE": (
            "Offline, werbefrei, quelloffen",
            "Einzelne Buchstaben oder das komplette Wörterbuch herunterladen",
        ),
        "en-US": (
            "Offline, ad-free, open source",
            "Download single letters or the whole dictionary to the device",
        ),
    },
}

NAME = re.compile(
    r"^\d+-(?P<name>[a-z]+)-(?P<theme>hell|dunkel)"
    r"--top(?P<top>\d+)--bottom(?P<bottom>\d+)$"
)


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


def font() -> str:
    """Roboto is what the app draws with on a device, whatever answers here is
    printed so a substituted face does not pass unseen."""
    path = subprocess.run(
        ["fc-match", "-f", "%{file}", "Roboto:style=Regular"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not path:
        sys.exit("fc-match found no font, install fontconfig and Roboto")
    return path


def edges(path: pathlib.Path) -> tuple[int, int]:
    out = subprocess.run(
        ["magick", path, "-format", "%w %h", "info:"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    return int(out[0]), int(out[1])


def cropped(shot: pathlib.Path, bars: re.Match[str], out: pathlib.Path) -> None:
    """Cuts the strips the system bars left empty as measured on the device."""
    width, height = edges(shot)
    top, bottom = int(bars["top"]), int(bars["bottom"])
    subprocess.run(
        ["magick", shot, "-crop", f"{width}x{height - top - bottom}+0+{top}", "+repage", out],
        check=True,
    )


def text(
    line: str,
    points: int,
    fill: str,
    background: str,
    face: str,
    out: pathlib.Path,
) -> int:
    """One caption line, wrapped to the canvas width. Returns its height."""
    subprocess.run(
        [
            "magick",
            "-background",
            background,
            "-fill",
            fill,
            "-font",
            face,
            "-pointsize",
            str(points),
            "-interline-spacing",
            str(round(points * 0.25)),
            "-gravity",
            "northwest",
            "-size",
            f"{CANVAS[0] - 2 * MARGIN}x",
            f"caption:{line}",
            out,
        ],
        check=True,
    )
    return edges(out)[1]


def compose(
    shot: pathlib.Path,
    locale: str,
    face: str,
    out: pathlib.Path,
) -> tuple[int, int]:
    parsed = NAME.match(shot.stem)
    if not parsed:
        sys.exit(f"{shot.name} is not named the way the capture names a frame")

    name, theme = parsed["name"], THEMES[parsed["theme"]]
    if name not in CAPTIONS:
        sys.exit(f"no caption for {name}, add one to CAPTIONS in {pathlib.Path(__file__).name}")
    headline, sub = CAPTIONS[name][locale]

    frame = WORK / f"{shot.stem}-frame.png"
    cropped(shot, parsed, frame)
    height = CANVAS[1] - BAND - FRAME_BOTTOM - 2 * BORDER
    subprocess.run(
        [
            "magick",
            frame,
            "-resize",
            f"x{height}",
            "-bordercolor",
            theme["border"],
            "-border",
            str(BORDER),
            frame,
        ],
        check=True,
    )
    width = edges(frame)[0]
    if width > CANVAS[0]:
        sys.exit(f"{shot.name} is {width} wide after scaling, wider than the canvas")

    head = WORK / f"{shot.stem}-head.png"
    tail = WORK / f"{shot.stem}-sub.png"
    head_h = text(headline, HEAD_POINTS, theme["fg"], theme["bg"], face, head)
    sub_h = text(sub, SUB_POINTS, theme["muted"], theme["bg"], face, tail)
    sub_top = HEAD_TOP + head_h + GAP
    if sub_top + sub_h > BAND - GAP:
        sys.exit(f"the caption for {name} in {locale} does not fit the band, shorten it")

    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "magick",
            "-size",
            f"{CANVAS[0]}x{CANVAS[1]}",
            f"xc:{theme['bg']}",
            head,
            "-geometry",
            f"+{MARGIN}+{HEAD_TOP}",
            "-composite",
            tail,
            "-geometry",
            f"+{MARGIN}+{sub_top}",
            "-composite",
            frame,
            "-geometry",
            f"+{(CANVAS[0] - width) // 2}+{BAND}",
            "-composite",
            # Play refuses a screenshot that carries an alpha channel.
            "-alpha",
            "remove",
            "-alpha",
            "off",
            "-strip",
            "-define",
            "png:compression-level=9",
            "-define",
            "png:compression-filter=5",
            out,
        ],
        check=True,
    )
    return edges(out)


def check(path: pathlib.Path, size: tuple[int, int]) -> None:
    short, long = min(size), max(size)
    if short < MIN_EDGE or long > MAX_EDGE:
        sys.exit(f"{path.name} is {size[0]}x{size[1]}, outside Play's bounds")
    if long > short * MAX_RATIO:
        sys.exit(f"{path.name} is {size[0]}x{size[1]}, longer than twice its short side")


def main() -> None:
    capture(sys.argv[1] if len(sys.argv) > 1 else android_device())

    shots = sorted(STAGING.glob("*.png"))
    if not shots:
        sys.exit(f"{STAGING} is empty, the capture wrote nothing")
    if len(shots) > MAX_SHOTS:
        sys.exit(f"{len(shots)} shots, Play takes {MAX_SHOTS}")

    WORK.mkdir(parents=True, exist_ok=True)
    face = font()
    print(f"drawing captions with {face}")

    for locale in LOCALES:
        out = ROOT / "fastlane/metadata/android" / locale / "images/phoneScreenshots"
        shutil.rmtree(out, ignore_errors=True)
        for number, shot in enumerate(shots, start=1):
            target = out / f"{number}.png"
            size = compose(shot, locale, face, target)
            check(target, size)
            print(f"{locale}  {number}.png  {size[0]}x{size[1]}  {shot.stem}")

    print(f"\n{len(shots)} screenshots written for {', '.join(LOCALES)}")


if __name__ == "__main__":
    main()
