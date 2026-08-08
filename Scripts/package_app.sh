#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/CaptureMark.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"

SEMVER_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if [[ ! "$VERSION" =~ $SEMVER_PATTERN ]]; then
    echo "Invalid SemVer in VERSION: $VERSION" >&2
    exit 1
fi

BUNDLE_SHORT_VERSION="${VERSION%%[-+]*}"
BUNDLE_VERSION="${CAPTUREMARK_BUILD_NUMBER:-$BUNDLE_SHORT_VERSION}"
BUILD_ARGS=(-c "$CONFIGURATION")

if [[ "${CAPTUREMARK_UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

cd "$PROJECT_DIR"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BIN_DIR/CaptureMark" "$MACOS_DIR/CaptureMark"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/CaptureMark"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUNDLE_SHORT_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"

# Use a standard ad-hoc signature for local builds. macOS TCC accepts this
# identity for Screen Recording; rebuilding changes the identity, so the
# permission must be granted after the final build.
codesign --force --deep --sign - "$APP_DIR"
echo "Packaged CaptureMark $VERSION at $APP_DIR"
