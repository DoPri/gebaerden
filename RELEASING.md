# Publishing

The app goes out through three channels. A tag drives all of them.

| Channel        | Format           | Signed by                        | Reaches             |
| -------------- | ---------------- | -------------------------------- | ------------------- |
| GitHub release | split APKs       | the key in `release.jks`         | Obtainium, sideload |
| Google Play    | AAB              | Google, through Play App Signing | Play users          |
| F-Droid        | APK, built there | F-Droid                          | F-Droid users       |

Three channels means three signatures for the same app. Android refuses to
update across them, so a user who installed from GitHub cannot switch to Play
without uninstalling first. That is unavoidable and worth saying in the release
notes.

## What the fastlane folder is

`fastlane/metadata/android/<locale>/` holds the store listing: title, both
descriptions, the changelog per versionCode, the link to the preview video, the
icon, the feature graphic and the screenshots. The layout comes from Fastlane
and has become the common one.

Two things read it. F-Droid picks it up straight out of this repository, no
tooling involved. Fastlane's `supply` uploads the same tree to Play. One set of
texts, two stores.

`fastlane/Fastfile` holds the lanes and reads the service account out of
`.env`, `fastlane/Appfile` holds the package name. Ruby is only
needed for the Play upload, nothing in the app or the tests touches it.

The icon and the feature graphic are generated, `tools/icons.py` writes them.
Do not edit them by hand. The same goes for the screenshots and the preview
video, `tools/screenshots.py` and `tools/preview.py` write those.

Between them the three scripts need `rsvg-convert`, `magick`, `ffmpeg`, `adb`
and `fc-match` on the path.

## Screenshots

Also generated, off a device or a running emulator:

```bash
source .env
flutter emulators --launch Pixel_10
python3 tools/screenshots.py
```

The script captures and files in one go. It walks the app through eight
screens, one feature each, and files them as 1 to 8. Play takes at most eight
per locale, so a second theme would spend half of them on a screen that is
already there. The dark mode gets one frame, the offline screen.

It picks the attached Android device itself and stops if there is none or more
than one, in which case name it: `python3 tools/screenshots.py emulator-5554`.
The device matters, `flutter drive` would otherwise take the Linux desktop and
stop with "No Linux desktop project configured".

The target sits in `test_driver/` rather than `integration_test/`. Taking a
screenshot needs the driver, and a plain `flutter test integration_test` would
fail on it.

It pulls real words off signdict.org, so the shots carry real footage.
`test_driver/seed.dart` wipes the test database and walks the whole index into
the entry cache before the first frame, so every frame counts the same words.

A captured frame holds the Flutter surface alone. The system bars are missing
and leave an empty strip top and bottom, so the target measures them and hands
the heights over in the file name, which `tools/screenshots.py` then cuts off.
`takeScreenshot` takes arguments only on the web, hence the file name.

Each frame then goes on a 1080x1920 canvas under a headline and a line of
explanation. The texts live in `CAPTIONS` in `tools/screenshots.py`, German for
de-DE and English for en-US. The screens themselves stay German, that is the
only language the app speaks. The canvas is also what keeps the frames inside
Play's bounds, a raw phone frame is 1080x2219 and Play refuses a long side more
than twice the short one.

## Preview video

Play takes a preview only as a YouTube link, so the last step is by hand:

```bash
python3 tools/preview.py
```

It films `test_driver/preview_test.dart` with `adb screenrecord` and writes
`build/preview/preview.mp4`, one take and no text on it. The upload goes
through

```bash
uv run tools/youtube.py --privacy public
```

which puts the link in `fastlane/metadata/android/<locale>/video.txt` for both
locales. Without `--privacy` the video goes up unlisted, and Play takes only a
public one.

`supply` reads the video files if they are there and leaves the field alone if
they are not, the same way it treats a missing changelog.

### Once: the YouTube credentials

In the Google Cloud console, signed in as the account that owns the channel.
Any project will do, the one behind the Play service account included.

First, APIs and services, Library, search for "YouTube Data API v3", Enable.

Second, the consent screen, under APIs and services, OAuth consent screen, or
Google Auth Platform in the newer console. Nobody but you ever sees it, because
yours is the only account that will ever sign in, so the entries are free
choices rather than a public profile:

| Field                         | What goes in                                         |
| ----------------------------- | ---------------------------------------------------- |
| App name                      | `DGS Lernen release`, the name on the consent screen |
| User support email            | your own address                                     |
| Audience                      | External. Internal exists only under Workspace       |
| Developer contact information | the same address again                               |

The app domain and logo fields stay empty, they matter only for verification,
which this never goes through. Two more entries follow:

- Data access, Add or remove scopes, tick
  `https://www.googleapis.com/auth/youtube.upload`. It sits under YouTube Data
  API v3 and the filter box finds it by the word `upload`.
- Audience, Test users, Add users, your own address. Publishing the app is not
  needed. A client left in testing shows one warning screen at sign in, the
  "Google hasn't verified this app" one, where Advanced and then the "go to"
  link carry on.

Third, APIs and services, Credentials, Create credentials, OAuth client ID.
Application type "Desktop app", name it anything, `gebaerden-upload` does.
Create, then Download JSON.

Fourth, save that file as `youtube-client.json` in the project root
and point `.env` at it:

```bash
export YOUTUBE_CLIENT_SECRET_FILE="$PWD/youtube-client.json"
```

The first upload opens the browser, and the token it caches in
`.youtube-token.json` does it from then on. Whichever channel consents is the
one the video lands on, so sign in as the channel owner.

Same device rules as the screenshots. It is a second target because the
screenshot run converts the Flutter surface to an image, which leaves
screenrecord filming a black display. Why it runs in profile and how the take
is trimmed is written where it happens, in that file and in `tools/preview.py`.

## Settings

Build and release configurations are read from `.env`.

```bash
cp .env.example .env
source .env
```

CI receives these values as repository secrets (see table below).

## Once: the signing key

```bash
keytool -genkeypair -v \
  -keystore release.jks -alias gebaerden \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Dominic Prinz, O=DGS Lernen, C=DE"
```

For GitHub Actions CI:

```bash
base64 -w0 release.jks
```

Store the result as `ANDROID_KEYSTORE_BASE64`, alongside `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.

Google Play manages the final app signing key and re-signs bundles, resulting in different signatures between Play and GitHub installs.

## Once: Google Play

The first release requires manual upload via the Google Play Console to establish Play App Signing and the closed testing track. Subsequent uploads are automated via a service account, as detailed in:
- <https://docs.flutter.dev/deployment/cd>
- <https://docs.fastlane.tools/getting-started/android/setup/>

1. Create a service account in the Google Cloud project.
2. Grant it release rights in the Play Console.
3. Save the JSON key.
4. Store the JSON as the `PLAY_SERVICE_ACCOUNT` secret for CI, or point `PLAY_SERVICE_ACCOUNT_FILE` in `.env` to the local file.

Alternatively, use `gcloud` locally:

```bash
gcloud auth application-default login --scopes=openid,email,\
https://www.googleapis.com/auth/cloud-platform,\
https://www.googleapis.com/auth/androidpublisher
```

Verify credentials and pending release metadata:

```bash
bundle exec fastlane android check
```

## Raising the version

Update `version:` in `pubspec.yaml` (format `1.0.0+1`). Play requires a monotonically increasing `versionCode` (the number after the plus).

Add changelogs for the new versionCode:

```
fastlane/metadata/android/de-DE/changelogs/<versionCode>.txt
fastlane/metadata/android/en-US/changelogs/<versionCode>.txt
```

## Release

```bash
git tag v1.0.1
git push origin v1.0.1
```

The workflow runs checks, builds APKs and the bundle, attaches APKs to the GitHub release, and uploads the bundle to Play closed testing. The tag must match `version:` in `pubspec.yaml`.

Promoting releases to production requires manual action in the Play Console.

## Checking a download

Every APK and bundle carries a build provenance attestation signed via Sigstore.

```bash
gh attestation verify app-arm64-v8a-release.apk --repo DoPri/gebaerden
```

## Testing a release

Tags with a suffix indicate pre-releases:

```bash
git tag v1.0.1-rc1
git push origin v1.0.1-rc1
```

Pre-releases skip Play store but are attached to the GitHub release. Obtainium testers receive them if configured to allow pre-releases.

## Changing only the listing

To update store metadata, screenshots, or the video link without a new build:

```bash
bundle exec fastlane android listing
```

Only differing files and texts are uploaded. F-Droid applies the same metadata on its next build.

## Building locally

Use `tools/release.sh` to test builds with a throwaway key.

To build manually (requires `.env`):

```bash
flutter build appbundle --release
flutter build apk --release --split-per-abi
```

Without keystore variables, artifacts remain unsigned (expected for F-Droid).

## F-Droid (untested)

Copy `fdroid/gg.prinz.gebaerden.yml` to `metadata/` in a fork of `fdroiddata`:

```bash
fdroid readmeta
fdroid build gg.prinz.gebaerden:1
```

`dependenciesInfo` is disabled in `android/app/build.gradle.kts` as F-Droid rejects Google-signed dependency metadata. Play accepts the bundle without it.

## Settings in one place

| Name                        | Locally in `.env`     | In CI as a secret         |
| --------------------------- | --------------------- | ------------------------- |
| `ANDROID_HOME`              | path to the SDK       | the runner brings its own |
| `ANDROID_KEYSTORE`          | path to `release.jks` | written from the base64   |
| `ANDROID_KEYSTORE_BASE64`   | not needed            | base64 of `release.jks`   |
| `ANDROID_KEYSTORE_PASSWORD` | yes                   | yes                       |
| `ANDROID_KEY_ALIAS`         | yes                   | yes                       |
| `ANDROID_KEY_PASSWORD`      | yes                   | yes                       |
| `PLAY_SERVICE_ACCOUNT_FILE` | path to the JSON      | not needed                |
| `PLAY_SERVICE_ACCOUNT`      | not needed            | the whole JSON            |
| `YOUTUBE_CLIENT_SECRET_FILE` | path to the JSON     | not needed                |

The Fastfile takes the file when `PLAY_SERVICE_ACCOUNT_FILE` is set and the
raw JSON otherwise, so the same lane runs in both places. The two YouTube
values are local only, the video goes up by hand and CI never touches it.
