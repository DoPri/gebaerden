#!/usr/bin/env python3
"""Records the store preview video on a device.

    python3 tools/preview.py [device]

Play takes a preview only as a YouTube link, so this stops at the file. Upload
build/preview/preview.mp4 and put its URL in
fastlane/metadata/android/<locale>/video.txt. The film carries no text, so both
locales point at the same one.

One take. The tour warms the whole route through once before it starts, so
nothing in the filmed pass waits on the network, and only the head and the tail
are cut. The status bar and the navigation bar are cropped off, screenrecord
films the whole display and they are not part of the app. Every tap the tour
made comes back with its position, and a ring goes over the picture there, in
place of the pointer crosshair that only a debug build draws.

screenrecord films the real display, which is why the tour is a target of its
own: the screenshot run converts the Flutter surface to an image and the
display would go black.
"""

import json
import pathlib
import subprocess
import sys
import time

from screenshots import android_device

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "preview"
TIMELINE = OUT / "timeline.json"
RAW = OUT / "raw.mp4"
FILM = OUT / "preview.mp4"
REMOTE = "/sdcard/gebaerden-preview.mp4"
PACKAGE = "gg.prinz.gebaerden"
DRIVER = "test_driver/preview.dart"
TARGET = "test_driver/preview_test.dart"

# The display runs at 60 and screenrecord follows it. Resampling to 30 took a
# frame here and dropped one there, which is what made the sign videos judder.
FPS = 60
GOP = FPS
FADE = 0.35

# The tap ring, in the accent of the light theme.
RING = OUT / "tap.png"
RING_SIZE = 120
RING_COLOR = "#955E11"
RING_HOLD = 0.42
RING_FADE = 0.12


def adb(device: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["adb", "-s", device, *args],
        check=check,
        capture_output=True,
        text=True,
    )


def clock(device: str) -> int:
    """The device clock in milliseconds, the same one the tour timestamps with."""
    return int(adb(device, "shell", "date", "+%s%3N").stdout.strip())


def drive(device: str) -> subprocess.Popen[bytes]:
    """Profile, because a debug build drops frames all through the film and
    because the pointer crosshair the test binding draws over every tap sits
    inside an assert, which profile strips."""
    return subprocess.Popen(
        [
            "flutter", "drive", "--profile", "-d", device,
            f"--driver={DRIVER}", f"--target={TARGET}",
        ],
        cwd=ROOT,
    )


def launched(device: str, drive: subprocess.Popen[bytes]) -> None:
    """Waits for the app to be on screen.

    The recording starts here rather than before the build. screenrecord stops
    by itself after 180 seconds and a gradle build plus an install ate more
    than half of that, which cut the tour off the end of the film."""
    for _ in range(300):
        if drive.poll() is not None:
            sys.exit("the drive stopped before the app came up")
        if adb(device, "shell", "pidof", PACKAGE, check=False).stdout.strip():
            return
        time.sleep(1)
    sys.exit(f"{PACKAGE} never came up")


def record(device: str) -> tuple[subprocess.Popen[bytes], int]:
    """Starts the recording and returns the device time its first frames
    carry, which is what every scene window is measured against."""
    adb(device, "shell", "rm", "-f", REMOTE)
    proc = subprocess.Popen(
        # 180 seconds is screenrecord's own ceiling and the tour runs well
        # inside it. Naming it keeps a hung run from filling the device.
        ["adb", "-s", device, "shell", "screenrecord", "--bit-rate", "12000000",
         "--time-limit", "180", REMOTE],
    )

    # screenrecord says nothing when it comes up and takes about a second to
    # get there. Waiting for the file to carry bytes pins the start close
    # enough that a cut lands on its own scene, and it keeps the tour from
    # walking into a recording that is not running yet.
    for _ in range(50):
        if proc.poll() is not None:
            sys.exit("screenrecord stopped right after it started")
        size = adb(device, "shell", "stat", "-c", "%s", REMOTE, check=False)
        if size.stdout.strip().isdigit() and int(size.stdout) > 0:
            return proc, clock(device)
        time.sleep(0.2)

    proc.kill()
    sys.exit("screenrecord wrote nothing, there is no recording to cut")


def stop(device: str, proc: subprocess.Popen[bytes]) -> None:
    """SIGINT is the only way screenrecord closes a playable file."""
    if proc.poll() is None:
        for killer in ("pkill", "killall"):
            if adb(device, "shell", killer, "-INT", "screenrecord", check=False).returncode == 0:
                break
        else:
            sys.exit("could not stop screenrecord on the device")

        try:
            proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            proc.kill()
            sys.exit("screenrecord did not finish writing")

    OUT.mkdir(parents=True, exist_ok=True)
    adb(device, "pull", REMOTE, str(RAW))
    adb(device, "shell", "rm", "-f", REMOTE)


def timeline(started: int) -> dict[str, object]:
    """The reported device timestamps as seconds inside the recording."""
    if not TIMELINE.exists():
        sys.exit(f"{TIMELINE} is missing, the tour reported no timeline")
    data = json.loads(TIMELINE.read_text())

    return {
        "start": (data["start"] - started) / 1000,
        "end": (data["end"] - started) / 1000,
        "taps": [
            {"x": t["x"], "y": t["y"], "at": (t["at"] - started) / 1000}
            for t in data["taps"]
        ],
        "top": data["top"],
        "bottom": data["bottom"],
    }


def ring() -> None:
    """A soft disc, drawn once and stamped wherever the tour tapped. No edge,
    the blur is what keeps it from reading as a debug overlay."""
    RING.parent.mkdir(parents=True, exist_ok=True)
    half = RING_SIZE // 2
    subprocess.run(
        [
            "magick", "-size", f"{RING_SIZE}x{RING_SIZE}", "xc:none",
            "-fill", f"{RING_COLOR}88", "-stroke", "none",
            "-draw", f"circle {half},{half} {half},{half - (half - 8)}",
            "-blur", f"0x{RING_SIZE // 12}",
            str(RING),
        ],
        check=True,
    )


def assemble(cut: dict[str, object], out: pathlib.Path) -> float:
    """Trims the head and the tail off the recording, crops the system bars
    away and stamps a ring on every tap."""
    top, bottom = cut["top"], cut["bottom"]
    start, end = cut["start"], cut["end"]
    taps = cut["taps"]
    length = end - start + FADE

    chain = [
        f"[0:v]trim=start={start:.2f}:end={end + FADE:.2f},setpts=PTS-STARTPTS,"
        f"crop=iw:ih-{top + bottom}:0:{top},fps={FPS}[base]"
    ]
    if taps:
        chain.append(
            f"[1:v]format=rgba,split={len(taps)}"
            + "".join(f"[m{i}]" for i in range(len(taps)))
        )
    source = "base"
    for i, tap in enumerate(taps):
        at = tap["at"] - start
        # Each copy of the disc carries its own short timeline, faded in and
        # out on the alpha channel and shifted to the moment it was tapped.
        chain.append(
            f"[m{i}]fade=t=in:st=0:d={RING_FADE}:alpha=1,"
            f"fade=t=out:st={RING_HOLD - RING_FADE:.2f}:d={RING_FADE}:alpha=1,"
            f"setpts=PTS+{at:.2f}/TB[r{i}]"
        )
        chain.append(
            f"[{source}][r{i}]overlay="
            f"x={tap['x'] - RING_SIZE // 2}:y={tap['y'] - top - RING_SIZE // 2}"
            f":eof_action=pass:repeatlast=0"
            f":enable='between(t,{at:.2f},{at + RING_HOLD:.2f})'[t{i}]"
        )
        source = f"t{i}"
    chain.append(
        f"[{source}]fade=t=in:st=0:d={FADE},"
        f"fade=t=out:st={length - FADE:.2f}:d={FADE}[out]"
    )

    ring()
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(RAW),
            "-loop", "1", "-framerate", str(FPS), "-t", str(RING_HOLD), "-i", str(RING),
            "-filter_complex", ";".join(chain), "-map", "[out]",
            "-an",
            # Explicit, so a keyframe lands every second and the film can be
            # scrubbed. The defaults put them eight seconds apart.
            "-c:v", "libx264", "-preset", "slow", "-crf", "20",
            "-g", str(GOP), "-keyint_min", str(GOP), "-sc_threshold", "0",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            "-loglevel", "error",
            str(out),
        ],
        check=True,
    )
    return length


def main() -> None:
    device = sys.argv[1] if len(sys.argv) > 1 else android_device()
    OUT.mkdir(parents=True, exist_ok=True)
    TIMELINE.unlink(missing_ok=True)

    print(f"building and installing on {device}")
    adb(device, "logcat", "-c")
    tour = drive(device)
    launched(device, tour)

    # Before anything can ask for it on camera. The downloader requests it the
    # first time a package starts, and the system dialog stood in the film.
    adb(device, "shell", "pm", "grant", PACKAGE,
        "android.permission.POST_NOTIFICATIONS", check=False)

    print("recording")
    proc, started = record(device)
    try:
        if tour.wait() != 0:
            # A profile build reports a failed expectation as "Instance of
            # FlutterErrorDetails" and nothing else. The Dart side of it only
            # exists in the device log.
            log = adb(device, "logcat", "-d", "-s", "flutter").stdout
            print("\n".join(log.splitlines()[-40:]), file=sys.stderr)
            sys.exit("the tour failed, see the device log above")
    finally:
        stop(device, proc)

    cut = timeline(started)
    print(f"one take of {cut['end'] - cut['start']:.1f}s, {len(cut['taps'])} taps")
    print(f"cropping {cut['top']} px off the top and {cut['bottom']} off the bottom")

    length = assemble(cut, FILM)
    print(f"\n{FILM.relative_to(ROOT)}  {length:.1f}s  {FILM.stat().st_size // 1024} KB")
    print("upload it to YouTube and put the URL in both video.txt, see RELEASING.md")


if __name__ == "__main__":
    main()
