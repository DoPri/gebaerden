#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "google-api-python-client==2.198.0",
#     "google-auth-oauthlib==1.4.0",
# ]
# ///

"""Uploads the store preview to YouTube and files the link under fastlane.

    uv run tools/youtube.py [--privacy public|unlisted|private]

Play takes a preview only as a YouTube link and only a public one, so the
default here is unlisted and going public is a decision made on purpose.

Signing in opens a browser once and caches the token afterwards.

It takes the client secret JSON of an OAuth client of type "Desktop app", from
a Cloud project with the YouTube Data API enabled, at the path in
YOUTUBE_CLIENT_SECRET_FILE.

Neither of the other two credentials the release uses can stand in. A service
account cannot, a video belongs to a channel and a channel belongs to a
person. The gcloud login that serves Play cannot either: it runs on
gcloud's own OAuth client, which Google clears for cloud scopes alone, so
asking it for youtube.upload comes back as "this app is blocked".
"""

import argparse
import json
import os
import pathlib
import sys

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILM = ROOT / "build" / "preview" / "preview.mp4"
TOKEN = ROOT / ".youtube-token.json"
METADATA = ROOT / "fastlane" / "metadata" / "android"
LOCALES = ("de-DE", "en-US")

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]

CHUNK = 4 * 1024 * 1024


TITLE = "DGS Lernen: Deutsche Gebärdensprache lernen"
DESCRIPTION = """DGS Lernen ist eine werbefreie und quelloffene App zum Lernen der Deutschen Gebärdensprache.

Wörterbuch mit mehreren tausend Gebärden, Zeitlupe bis 0,25-fach, Vokabeltrainer nach FSRS, Fingeralphabet und Zahlen, eigene Listen mit Erinnerung und ein Offline-Modus.

Kein Konto, kein Abo, keine Werbung, keine Tracker. Der Fortschritt bleibt auf dem Gerät.

Quelltext unter der GNU GPL 3.0:
https://github.com/DoPri/gebaerden

Die Gebärdenvideos stammen aus dem offenen Wörterbuch SignDict und stehen unter verschiedenen Creative-Commons-Lizenzen. Rechteinhaber und Lizenz stehen in der App unter jedem Video. Diese App ist kein Angebot von SignDict."""

# YouTube keeps 500 characters for all of them together.
TAGS = [
    "Gebärdensprache",
    "Gebärdensprache lernen",
    "DGS",
    "Deutsche Gebärdensprache",
    "Gebärden lernen",
    "Fingeralphabet",
    "Gebärdensprache App",
    "Zeichensprache",
    "gehörlos",
    "Vokabeltrainer",
    "SignDict",
    "German Sign Language",
    "Open Source",
]

# 27 is Education.
CATEGORY = "27"
LANGUAGE = "de"


def credentials() -> Credentials:
    if TOKEN.exists():
        stored = Credentials.from_authorized_user_file(str(TOKEN), SCOPES)
        if stored.valid:
            return stored
        if stored.refresh_token:
            stored.refresh(Request())
            TOKEN.write_text(stored.to_json())
            return stored

    secret = os.environ.get("YOUTUBE_CLIENT_SECRET_FILE", "")
    if not secret:
        sys.exit("YOUTUBE_CLIENT_SECRET_FILE is not set, see RELEASING.md")
    if not pathlib.Path(secret).exists():
        sys.exit(f"{secret} does not exist, see RELEASING.md")

    flow = InstalledAppFlow.from_client_secrets_file(secret, SCOPES)
    fresh = flow.run_local_server(
        port=0,
        prompt="consent",
        success_message="Fertig, du kannst das Fenster schließen.",
    )
    TOKEN.write_text(fresh.to_json())
    TOKEN.chmod(0o600)
    return fresh


def upload(privacy: str) -> str:
    youtube = build("youtube", "v3", credentials=credentials())
    request = youtube.videos().insert(
        part="snippet,status",
        body={
            "snippet": {
                "title": TITLE,
                "description": DESCRIPTION,
                "tags": TAGS,
                "categoryId": CATEGORY,
                "defaultLanguage": LANGUAGE,
                "defaultAudioLanguage": LANGUAGE,
            },
            "status": {
                "privacyStatus": privacy,
                "selfDeclaredMadeForKids": False,
            },
        },
        media_body=MediaFileUpload(str(FILM), chunksize=CHUNK, resumable=True),
    )

    answer = None
    while answer is None:
        progress, answer = request.next_chunk()
        if progress:
            print(f"{int(progress.progress() * 100):3d} %")
    return str(answer["id"])


def file_link(video: str) -> None:
    url = f"https://www.youtube.com/watch?v={video}"
    for locale in LOCALES:
        path = METADATA / locale / "video.txt"
        path.write_text(url + "\n", encoding="utf-8")
        print(f"{path.relative_to(ROOT)}  {url}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Uploads build/preview/preview.mp4 to YouTube."
    )
    parser.add_argument(
        "--privacy",
        default="unlisted",
        choices=("public", "unlisted", "private"),
        help="Play takes only a public video (default: unlisted)",
    )
    privacy = parser.parse_args().privacy

    if not FILM.exists():
        sys.exit(
            f"{FILM.relative_to(ROOT)} is missing, run tools/preview.py first"
        )

    print(f"uploading {FILM.stat().st_size // 1024} KB as {privacy}")
    try:
        video = upload(privacy)
    except HttpError as broke:
        answer = json.loads(broke.content or b"{}")
        detail = answer.get("error", {}).get("message", "")
        if broke.status_code in (401, 403):
            detail += "\nsign in again, .youtube-token.json may be stale"
        sys.exit(f"YouTube said {broke.status_code}: {detail or broke}")

    file_link(video)
    if privacy != "public":
        print(f"\nthe video is {privacy}, Play takes only a public one")


if __name__ == "__main__":
    main()
