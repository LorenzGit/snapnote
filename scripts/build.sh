#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--unsigned" ]]; then
    exec bash scripts/release.sh --unsigned
fi
if [[ $# -ne 0 ]]; then echo 'Usage: bash scripts/build.sh [--unsigned]' >&2; exit 2; fi
# Fail before building/replacing anything if the pinned identity is inaccessible.
bash scripts/sign-app.sh --check
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox
mkdir -p "$PWD/build"
stage="$(mktemp -d "$PWD/build/.snapnote-build.XXXXXX")"
app="$PWD/build/SnapNote.app"
cleanup() {
    # Restore the original if publication was interrupted between the two moves.
    if [[ ! -e "$app" && -d "$stage/previous" ]]; then mv "$stage/previous" "$app"; fi
    rm -rf "$stage"
}
trap cleanup EXIT
staged_app="$stage/SnapNote.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp .build/release/SnapNote "$staged_app/Contents/MacOS/SnapNote"
cp Info.plist "$staged_app/Contents/Info.plist"
bash scripts/sign-app.sh "$staged_app"
# Keep the canonical path stable. Publish only after signature verification.
if [[ -e "$app" ]]; then mv "$app" "$stage/previous"; fi
mv "$staged_app" "$app"
echo "$app"
