#!/usr/bin/env python3
"""Puts everything the browser build loads at runtime into web/.

drift needs two files, and both belong to a package version. A mismatch shows
up as a database that never opens, so the versions are read out of
pubspec.lock instead of being written down anywhere. drift ships its worker in
the package, so that one is a copy. sqlite3 has to be compiled with Emscripten
in a particular way and is only published as a release asset.

CanvasKit brings no text font. It fetches Roboto from fonts.gstatic.com on
every start, and a symbols font for the arrow in the trainer, which Roboto
does not carry. Both are mirrored here under the path the engine asks for, and
web/flutter_bootstrap.js points it at this copy.
"""

import os
import pathlib
import re
import shutil
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
WASM = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-{}/sqlite3.wasm"
GOOGLE_FONTS = "https://fonts.gstatic.com/s/"

# Where the engine keeps the addresses it would fetch from fonts.gstatic.com.
# Read rather than written down, so a Flutter bump moves them along.
FONT_SOURCES = {
    "canvaskit/fonts.dart": r"roboto/[^'\"]+",
    "font_fallback_data.dart": r"notosanssymbols/[^'\"]+",
}


def locked(package: str) -> str:
    text = (ROOT / "pubspec.lock").read_text()
    found = re.search(rf'\n  {package}:\n(?:.*\n)*?    version: "([^"]+)"', text)
    if not found:
        sys.exit(f"{package} is not in pubspec.lock")
    return found.group(1)


def cache() -> pathlib.Path:
    return pathlib.Path(os.environ.get("PUB_CACHE", pathlib.Path.home() / ".pub-cache"))


def sdk() -> pathlib.Path:
    found = shutil.which("flutter")
    if not found:
        sys.exit("flutter is not on the PATH")
    return pathlib.Path(found).resolve().parent.parent


def fetch(url: str, into: pathlib.Path) -> None:
    into.parent.mkdir(parents=True, exist_ok=True)
    # Both hosts hang up on the urllib default agent and on a bad day on the
    # first try as well. A container build should not fail over that.
    request = urllib.request.Request(url, headers={"User-Agent": "gebaerden"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=120) as answer:
                into.write_bytes(answer.read())
            return
        except OSError as err:
            if attempt == 2:
                sys.exit(f"{url}: {err}")
            time.sleep(2 * (attempt + 1))


def main() -> None:
    drift = cache() / "hosted" / "pub.dev" / f"drift-{locked('drift')}" / "drift_worker.js"
    if not drift.exists():
        sys.exit(f"{drift} is missing, run flutter pub get first")
    shutil.copy(drift, WEB / "drift_worker.js")
    print(f"drift_worker.js from {drift.parent.name}")

    url = WASM.format(locked("sqlite3"))
    fetch(url, WEB / "sqlite3.wasm")
    print(f"sqlite3.wasm from {url.rsplit('/', 2)[1]}")

    engine = sdk() / "bin/cache/flutter_web_sdk/lib/_engine/engine"
    for source, pattern in FONT_SOURCES.items():
        found = re.search(pattern, (engine / source).read_text())
        if not found:
            sys.exit(f"no font address in {source}, the engine has moved it")
        path = found.group(0)
        fetch(GOOGLE_FONTS + path, WEB / "fonts" / path)
        print(f"fonts/{path}")


if __name__ == "__main__":
    main()
