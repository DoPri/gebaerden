# DGS Lernen

App for learning German Sign Language, built on the [SignDict](https://signdict.org) API. Runs entirely on-device. Progress and lists stay local.

## Install

[<img src="https://github.com/NeoApplications/Neo-Backup/blob/034b226cea5c1b30eb4f6a6f313e4dadcbb0ece4/badge_github.png?raw=true"
    alt="Get it on GitHub"
    height="80">](https://github.com/DoPri/gebaerden/releases/latest)
[<img src="https://raw.githubusercontent.com/ImranR98/Obtainium/b1c8ac6f2ab08497189721a788a5763e28ff64cd/assets/graphics/badge_obtainium.png"
    alt="Get it on Obtainium"
    height="80">](https://apps.obtainium.imranr.dev/redirect?r=obtainium%3A%2F%2Fapp%2F%257B%2522id%2522%253A%2522gg.prinz.gebaerden%2522%252C%2522url%2522%253A%2522https%253A%252F%252Fgithub.com%252FDoPri%252Fgebaerden%2522%252C%2522author%2522%253A%2522DoPri%2522%252C%2522name%2522%253A%2522DGS%2520Lernen%2522%252C%2522preferredApkIndex%2522%253A0%252C%2522additionalSettings%2522%253A%2522%257B%255C%2522includePrereleases%255C%2522%253Afalse%252C%255C%2522fallbackToOlderReleases%255C%2522%253Atrue%252C%255C%2522autoApkFilterByArch%255C%2522%253Atrue%252C%255C%2522versionDetection%255C%2522%253Atrue%257D%2522%257D)

The GitHub release provides one APK per architecture. Obtainium follows these releases automatically.

Verify the build provenance attestation:

```bash
gh attestation verify app-arm64-v8a-release.apk --repo DoPri/gebaerden
```

## Development

```bash
flutter pub get
dart run build_runner build
flutter run
```

`build_runner` regenerates the database after changes to `lib/db/tables.dart`.

```bash
flutter analyze
flutter test
flutter test --coverage && python3 tools/coverage.py 95
```

`pre-commit install` adds format, analysis, and tests to every commit.

## Device tests

`test/` runs headless. `integration_test/` requires a phone or emulator:

```bash
tools/integration.sh                                          # Any device
tools/integration.sh emulator-5554                            # Specific device
tools/integration.sh emulator-5554 integration_test/learn_test.dart
```

The script grants `POST_NOTIFICATIONS` on start to enable reminder tests. `app_test.dart` verifies the live signdict.org API. `learn_test.dart` and `lists_test.dart` drive the shell using seeded data.

## Builds

```bash
flutter build apk --release --split-per-abi
flutter build ipa
```

Android requires SDK 37 and JDK 17+.

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
sdkmanager "platform-tools" "platforms;android-37" "build-tools;36.0.0"
```

The release APK remains unsigned without `ANDROID_KEYSTORE` in the environment, supporting F-Droid distribution. See `RELEASING.md`.

## Web

The web build uses a proxy to bypass signdict.org CORS restrictions. See the "Container" section for deployment.

## Container

Every tag publishes a linux/amd64 image to ghcr:

```bash
docker run -p 8080:8080 ghcr.io/dopri/gebaerden:latest
```

Verify the image attestation:

```bash
gh attestation verify oci://ghcr.io/dopri/gebaerden:latest --repo DoPri/gebaerden
```

Deploy using `docker-compose.yml`:

```bash
docker compose pull && docker compose up -d
```

Build locally:

```bash
docker compose up -d --build
```

## Decisions

`docs/adr/` documents architecture decisions.

## License

Code: see `LICENSE`.

Videos belong to SignDict under various CC licenses. Rights holder and license appear below every video.
