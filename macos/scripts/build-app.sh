#!/bin/bash
# Builds VisualizeAudio as a real .app bundle (not just a bare `swift build`
# executable) and ad-hoc signs it with a *stable* identifier.
#
# Why this exists: a raw SPM executable has no Info.plist and gets an ad-hoc
# code signature derived from a hash of the binary, which changes every
# rebuild. TCC (the private-API/system-audio-recording permission the
# process tap needs) can't show a real prompt or persist a grant against an
# identity that changes on every build — it just silently returns zeroed
# audio buffers instead of erroring. Signing with an explicit --identifier
# gives it a stable identity across rebuilds, so the permission prompt
# appears once and sticks.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="VisualizeAudio"
BUNDLE_ID="com.aadya.visualizeaudio"
APP_DIR=".build/${APP_NAME}.app"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "Signing with stable identifier $BUNDLE_ID..."
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "Built $APP_DIR"
