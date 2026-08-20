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

Everything the build and the release read comes out of `.env`. Copy the example
and fill it in:

```bash
cp .env.example .env
source .env
```

`.env` is gitignored, `.env.example` is not, so the shape of the file is in the
repository and the passwords are not. Every command below assumes it has been
sourced.

CI has no `.env`. There the same values arrive as repository secrets, see the
table at the end.

## Once: the signing key

```bash
keytool -genkeypair -v \
  -keystore release.jks -alias gebaerden \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Dominic Prinz, O=DGS Lernen, C=DE"
```

`release.jks` does not belong in the repository, `.gitignore` catches `*.jks`.
For GitHub Actions:

```bash
base64 -w0 release.jks
```

Store the result as the secret `ANDROID_KEYSTORE_BASE64`, together with
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.

For Play this key is the upload key. Google keeps the app signing key itself
and re-signs every bundle, which is why a Play install carries a different
signature from a GitHub one.

## Once: Google Play

The API cannot create an app, so the first release goes through the console by
hand. Create the app, work through the set-up checklist, upload one
bundle so Play App Signing is set up, then create the closed testing track and
put testers on it. `supply` creates the track object on upload but cannot
invite anyone, and a closed test without testers counts towards nothing.

After that the uploads are automatic, which needs a service account. Flutter's
deployment guide covers it and hands off to the fastlane steps:

- <https://docs.flutter.dev/deployment/cd>
- <https://docs.fastlane.tools/getting-started/android/setup/>

Short version: create a service account with a JSON key in the Google Cloud
project behind the app, invite it in the Play Console under Users and
permissions and give it release rights. For CI, store the whole JSON as the
secret `PLAY_SERVICE_ACCOUNT`.

Locally there is a second way that needs no key on disk. `gcloud` comes with
the toolchain, `mise install` puts it there:

```bash
gcloud auth application-default login --scopes=openid,email,\
https://www.googleapis.com/auth/cloud-platform,\
https://www.googleapis.com/auth/androidpublisher
```

`cloud-platform` is in there because gcloud turns the login down without it.
`supply` picks the result up on its own. With `PLAY_SERVICE_ACCOUNT_FILE` set
in `.env` the key wins, without it gcloud does.

Check it before relying on it:

```bash
bundle exec fastlane android check
```

That resolves the credentials and validates an upload without shipping
anything. It also reports what a release would do: the versionCode it read out
of `pubspec.yaml`, whether the listing texts differ from the ones Play holds
and whether a changelog for that versionCode exists.

## Raising the version

`version:` in `pubspec.yaml`, format `1.0.0+1`. The part before the plus is the
versionName, the part after it the versionCode. Play refuses a versionCode it
has already seen, so it goes up on every release.

Add the changelog for the new versionCode in both locales:

```
fastlane/metadata/android/de-DE/changelogs/<versionCode>.txt
fastlane/metadata/android/en-US/changelogs/<versionCode>.txt
```

Without it `supply` has nothing to show on the Play release.

## Release

```bash
git tag v1.0.1
git push origin v1.0.1
```

The workflow runs the full CI check, builds the bundle and the split APKs,
attaches the APKs to the GitHub release and uploads the bundle to Play closed
testing. The tag has to match `version:` in `pubspec.yaml` or the run stops
before building.

Nothing reaches production on its own. Promoting from internal testing through
closed and open to production is a click in the Play Console, on purpose: a
Play release can be halted but not taken back.

## Checking a download

Every APK and the bundle carry a build provenance attestation. It records which
workflow, which commit and which run produced the file, signed through Sigstore
with a short-lived identity, so there is no key of ours to lose.

Anyone can check a downloaded file:

```bash
gh attestation verify app-arm64-v8a-release.apk --repo DoPri/gebaerden
```

That only proves the file came out of this repository's workflow. It says
nothing about the signing certificate of the APK, which is a separate matter
and differs per channel.

## Testing a release

A tag carrying a suffix is a pre-release on GitHub. It goes to Play the same
way every other tag does.

```bash
git tag v1.0.1-rc1
git push origin v1.0.1-rc1
```

Testers on Obtainium get it if they allow pre-releases, everyone else can grab
the APK from the release page. The suffix belongs in `version:` in
`pubspec.yaml` as well, because the workflow checks that the two match.

Testers with a Google account get it through closed testing instead, once the
review is through.

The bundle is kept as a workflow artifact for 14 days, so a failed Play upload
can be retried by hand without building again.

## Changing only the listing

Texts, the video link, screenshots or the feature graphic without a new
build:

```bash
bundle exec fastlane android listing
```

This needs a release to exist already. `supply` hangs the listing off a release
and offers no way around it, so on a fresh app the first push has to be the
`closed` lane, which carries a bundle. After that the listing lane works on
its own.

Only what differs goes up, on this lane and on the release. Every image is
compared by checksum against the one Play holds, and the four texts are
compared against the live listing before anything is sent, so a run that
changes nothing uploads nothing.

F-Droid picks the same change up on its next build of this repository.

## Building locally

`tools/release.sh` is enough to try it out. On the first run the script creates
a throwaway key and builds signed APKs with it. That key is no good for a real
release.

By hand, with `.env` sourced:

```bash
flutter build appbundle --release
flutter build apk --release --split-per-abi
```

Without the keystore variables the artefacts stay unsigned. That is intended, F-Droid
signs with a key of its own.

## F-Droid (untested)

Copy `fdroid/gg.prinz.gebaerden.yml` into `metadata/` in a fork of `fdroiddata`
and check it:

```bash
fdroid readmeta
fdroid build gg.prinz.gebaerden:1
```

Flutter arrives there through a srclib. Reproducibility is fiddly with Flutter,
because build paths end up in the binary. The recipe is written but has not
been built, there is no `fdroidserver` here.

`dependenciesInfo` is switched off in `android/app/build.gradle.kts` because
F-Droid rejects the Google-signed dependency metadata. Play accepts a bundle
without it and only loses the dependency advisories in the console.

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
