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
descriptions, the changelog per versionCode, the icon, the feature graphic and
the screenshots. The layout comes from Fastlane and has become the common one.

Two things read it. F-Droid picks it up straight out of this repository, no
tooling involved. Fastlane's `supply` uploads the same tree to Play. One set of
texts, two stores.

`fastlane/Fastfile` holds the lanes and reads the service account out of
`.env`, `fastlane/Appfile` holds the package name. Ruby is only
needed for the Play upload, nothing in the app or the tests touches it.

The icon and the feature graphic are generated, `tools/icons.py` writes them.
Do not edit them by hand.

## Screenshots

Also generated, off a device or a running emulator:

```bash
source .env
flutter emulators --launch Pixel_10
python3 tools/screenshots.py
```

The script captures and files in one go. It walks the app through four screens
twice, once light and once dark, then numbers the eight frames 1 to 8 and
copies them into both locales. Play takes at most eight per locale, so four
screens in two themes is the ceiling.

It picks the attached Android device itself and stops if there is none or more
than one, in which case name it: `python3 tools/screenshots.py emulator-5554`.
The device matters, `flutter drive` would otherwise take the Linux desktop and
stop with "No Linux desktop project configured".

The target sits in `test_driver/` rather than `integration_test/`. Taking a
screenshot needs the driver, and a plain `flutter test integration_test` would
fail on it.

It pulls real words off signdict.org, so the shots carry real footage.

A captured frame holds the Flutter surface alone. The system bars are missing
and leave an empty strip top and bottom, so the target measures them and hands
the heights over in the file name, which `tools/screenshots.py` then cuts off.
`takeScreenshot` takes arguments only on the web, hence the file name.

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
bundle so Play App Signing is set up, then create the internal testing track.

After that the uploads are automatic, which needs a service account. Flutter's
deployment guide covers it and hands off to the fastlane steps:

- <https://docs.flutter.dev/deployment/cd>
- <https://docs.fastlane.tools/getting-started/android/setup/>

Short version: create a service account with a JSON key in the Google Cloud
project behind the app, invite it in the Play Console under Users and
permissions and give it release rights. Locally, point
`PLAY_SERVICE_ACCOUNT_FILE` in `.env` at that JSON. For CI, store the whole
JSON as the secret `PLAY_SERVICE_ACCOUNT`.

Check it before relying on it:

```bash
bundle exec fastlane android check
```

That resolves the credentials and validates an upload without shipping
anything.

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
attaches the APKs to the GitHub release and uploads the bundle to Play internal
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

A tag carrying a suffix is a pre-release. It goes to GitHub only and never
touches Play.

```bash
git tag v1.0.1-rc1
git push origin v1.0.1-rc1
```

Testers on Obtainium get it if they allow pre-releases, everyone else can grab
the APK from the release page. `pubspec.yaml` stays at `1.0.1`, the suffix is
only on the tag.

For testers with a Google account the internal track is the shorter way. It
needs no review and is live within minutes of the upload.

The bundle is kept as a workflow artifact for 14 days, so a failed Play upload
can be retried by hand without building again.

## Changing only the listing

Texts, screenshots or the feature graphic without a new build:

```bash
bundle exec fastlane android listing
```

This needs a release to exist already. `supply` hangs the listing off a release
and offers no way around it, so on a fresh app the first push has to be the
`internal` lane, which carries a bundle. After that the listing lane works on
its own.

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

The Fastfile takes the file when `PLAY_SERVICE_ACCOUNT_FILE` is set and the
raw JSON otherwise, so the same lane runs in both places.
