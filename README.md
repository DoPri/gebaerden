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
flutter test --coverage && python3 tools/coverage.py 95
```

`pre-commit install` puts format, analysis and tests in front of every commit.
Without it CI checks the same, plus coverage, a release build and the
container image.

## Device tests

`test/` runs without a device. Everything that touches the platform lives in
`integration_test/` and needs a phone or an emulator:

```bash
tools/integration.sh                                          # only device
tools/integration.sh emulator-5554                            # a named one
tools/integration.sh emulator-5554 integration_test/learn_test.dart
```

The script grants `POST_NOTIFICATIONS` as soon as the app is on the device.
The reminder cases need it and no test can do it for itself. `app_test.dart`
goes against signdict.org and checks that the API still answers the way the
app expects, `learn_test.dart` and `lists_test.dart` drive the real shell off
seeded rows.

The permission request itself is not covered by any of this.

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

## Web

signdict.org answers without an `access-control-allow-origin` header, so a
browser blocks every call to the API. The web build therefore needs a proxy in
front of it and takes its address from a define:

```bash
python3 tools/web_assets.py
python3 tools/proxy.py &
flutter run -d chrome --dart-define=api=http://localhost:8080/graphql-api
flutter build web --release --no-web-resources-cdn \
    --dart-define=api=http://localhost:8080/graphql-api
```

Without the define the app talks to signdict.org directly, which is what the
Android and iOS builds do. Without `--no-web-resources-cdn` the page pulls
CanvasKit off gstatic instead of out of its own build.

`tools/web_assets.py` writes everything the browser loads at runtime and takes
the versions out of `pubspec.lock` and out of the installed SDK, so nothing
can fall behind. `drift_worker.js` is a copy out of the drift package,
`sqlite3.wasm` comes from the release of the `sqlite3` version in the lock
file. The two font files under `web/fonts/` are the ones CanvasKit would
otherwise fetch from fonts.gstatic.com on every start, Roboto and the symbols
face for the arrow in the trainer, mirrored under the exact path the engine
asks for. `web/flutter_bootstrap.js` points the engine at that copy. All of it
is generated and not in the repository, the way `build_runner` output is not.

Offline downloads are missing in the browser. `background_downloader` has no
web implementation, so `lib/packages/manager.dart` hands the web build an empty
queue and the offline section under Mehr is not shown. Everything else is
there: dictionary, videos, trainer, fingerspelling, lists and the backup.

## Container

Every tag publishes a linux/amd64 image to ghcr:

```bash
docker run -p 8080:8080 ghcr.io/dopri/gebaerden:latest
```

It carries the same build provenance attestation as the APKs:

```bash
gh attestation verify oci://ghcr.io/dopri/gebaerden:latest --repo DoPri/gebaerden
```

`docker-compose.yml` names that image, so a deployment is

```bash
docker compose pull && docker compose up -d
```

and building it here instead is

```bash
docker compose up -d --build
```

nginx listens on 8080 as uid 101 and speaks plain HTTP, there is a reverse
proxy in front for TLS. The app and the API share one origin, `/api` goes to
signdict.org, and that is what makes the CORS question disappear. The upstream
can be moved with `-e API_UPSTREAM=...`, the client address is read from
`X-Forwarded-For`, and `/healthz` answers for a health check.

Nothing is fetched from anywhere else at runtime. CanvasKit, the drift worker,
sqlite3 and the two fonts all sit in the image, and the
`Content-Security-Policy` says `self`, so a stray request would be refused
rather than sent.

`compose.yaml` runs it with a read-only root filesystem, without capabilities
and bound to the loopback, since the proxy in front is what faces the world.
The same by hand:

```bash
docker run --read-only --tmpfs /tmp \
    --tmpfs /var/cache/nginx:rw,mode=777 \
    --tmpfs /etc/nginx/conf.d:rw,mode=777 \
    -p 127.0.0.1:8080:8080 dgs-lernen
```

## Decisions

`docs/adr/` records why the app works the way it does. Read it before touching
the API layer, the scheduler, the reminders or the routes.

## License

Code: see `LICENSE`.

The videos belong to SignDict under various CC licenses,
some with an NC clause, so commercial use is ruled out. Rights holder and
license are shown under every video.
