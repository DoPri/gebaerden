# DGS Lernen

App for learning German Sign Language, built on the
[SignDict](https://signdict.org) API. No backend, no account. Progress and
lists stay on the device.

## Install

[<img src="https://github.com/NeoApplications/Neo-Backup/blob/034b226cea5c1b30eb4f6a6f313e4dadcbb0ece4/badge_github.png?raw=true"
    alt="Get it on GitHub"
    height="80">](https://github.com/DoPri/gebaerden/releases/latest)
[<img src="https://raw.githubusercontent.com/ImranR98/Obtainium/b1c8ac6f2ab08497189721a788a5763e28ff64cd/assets/graphics/badge_obtainium.png"
    alt="Get it on Obtainium"
    height="80">](https://apps.obtainium.imranr.dev/redirect?r=obtainium%3A%2F%2Fapp%2F%257B%2522id%2522%253A%2522gg.prinz.gebaerden%2522%252C%2522url%2522%253A%2522https%253A%252F%252Fgithub.com%252FDoPri%252Fgebaerden%2522%252C%2522author%2522%253A%2522DoPri%2522%252C%2522name%2522%253A%2522DGS%2520Lernen%2522%252C%2522preferredApkIndex%2522%253A0%252C%2522additionalSettings%2522%253A%2522%257B%255C%2522includePrereleases%255C%2522%253Afalse%252C%255C%2522fallbackToOlderReleases%255C%2522%253Atrue%252C%255C%2522autoApkFilterByArch%255C%2522%253Atrue%252C%255C%2522versionDetection%255C%2522%253Atrue%257D%2522%257D)

The GitHub release carries one APK per architecture. Obtainium follows the
same releases and picks the matching one by itself.

Each file carries a build provenance attestation, so a download can be traced
back to the workflow run that produced it:

```bash
gh attestation verify app-arm64-v8a-release.apk --repo DoPri/gebaerden
```

## Development

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

The database is generated, so `build_runner` runs again after every change to
`lib/db/tables.dart`.

```bash
flutter analyze
flutter test
flutter test --coverage && python3 tools/coverage.py 99
```

`pre-commit install` puts format, analysis and tests in front of every commit.
Without it CI checks the same, plus coverage and a release build.

## Builds

```bash
flutter build apk --release --split-per-abi
flutter build ipa
```

Android needs SDK 37 and a full JDK 17 or newer.

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
sdkmanager "platform-tools" "platforms;android-37" "build-tools;36.0.0"
```

Without `ANDROID_KEYSTORE` in the environment the release APK stays unsigned,
which is what F-Droid expects. `RELEASING.md` covers publishing.

iOS is built along but unverified, there is no device to test on.

## Decisions

`docs/adr/` records why the app works the way it does. Read it before touching
the API layer, the scheduler, the reminders or the routes.

## License

Code: see `LICENSE`.

The videos belong to SignDict under various CC licenses,
some with an NC clause, so commercial use is ruled out. Rights holder and
license are shown under every video.
