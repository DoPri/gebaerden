#!/usr/bin/env bash
# Builds signed release APKs with a throwaway key, so you can install and test
# them. Creates the keystore on first run. Never use this key for a release.
set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE="${ANDROID_KEYSTORE:-$PWD/release.jks}"
ALIAS="${ANDROID_KEY_ALIAS:-gebaerden}"
PASSWORD="${ANDROID_KEYSTORE_PASSWORD:-gebaerden}"

if [[ ! -f "$KEYSTORE" ]]; then
	echo "No key under $KEYSTORE, creating one."
	keytool -genkeypair -v \
		-keystore "$KEYSTORE" -alias "$ALIAS" \
		-keyalg RSA -keysize 4096 -validity 10000 \
		-storepass "$PASSWORD" -keypass "$PASSWORD" \
		-dname "CN=Gebaerden Test, OU=Development, O=Local, L=-, ST=-, C=DE"
	echo
	echo "Created. The key is for testing and does not belong in the repository."
fi

export ANDROID_KEYSTORE="$KEYSTORE"
export ANDROID_KEY_ALIAS="$ALIAS"
export ANDROID_KEYSTORE_PASSWORD="$PASSWORD"
export ANDROID_KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-$PASSWORD}"

flutter build apk --release --split-per-abi "$@"

echo
ls -la build/app/outputs/flutter-apk/*-release.apk | awk '{printf "%6.1f MB  %s\n", $5/1048576, $9}'
echo
echo "Onto a device:  adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
echo "Switching from debug to release needs this first: adb uninstall gg.prinz.gebaerden"
