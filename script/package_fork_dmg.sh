#!/usr/bin/env bash
# Usage: script/package_fork_dmg.sh <fork-build-number>
# Builds the upstream bundle, stamps it as <upstream-version>-vn.<n>, re-signs it, and packages a DMG.
set -euo pipefail

FORK_BUILD="${1:?Usage: $0 <fork-build-number>}"
[[ "$FORK_BUILD" =~ ^[0-9]+$ ]] || { echo "Fork build number must be an integer" >&2; exit 2; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT_DIR/dist/Wexi LoL.app"
PLIST="$BUNDLE/Contents/Info.plist"

"$ROOT_DIR/script/build_and_run.sh" --build-only
UPSTREAM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
VERSION="$UPSTREAM_VERSION-vn.$FORK_BUILD"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
codesign --force --deep --sign - --requirements '=designated => identifier "dev.local.wexilol"' "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

DMG_PATH="$ROOT_DIR/dist/Wexi.LoL-$VERSION.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/wexilol-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$BUNDLE" "$STAGING/Wexi LoL.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -quiet -volname "Wexi LoL $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"
echo "Created: $DMG_PATH"
