#!/bin/bash
# A public build is always isolated from the privately signed development app.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != '--unsigned' || $# -ne 1 ]]; then
    echo 'Usage: bash scripts/release.sh --unsigned' >&2
    echo 'Creates a universal, ad-hoc-signed build; no notarization or developer identity.' >&2
    exit 2
fi
root="$PWD"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
mkdir -p dist
stage="$(mktemp -d "$root/dist/.release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
for arch in arm64 x86_64; do
    swift build -c release --disable-sandbox --triple "$arch-apple-macosx14.0" \
        --scratch-path "$stage/$arch" \
        -Xswiftc -gnone -Xswiftc -debug-prefix-map -Xswiftc "$root=."
    bin="$(swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path "$stage/$arch" --show-bin-path)"
    cp "$bin/SnapNote" "$stage/SnapNote-$arch"
done
app="$stage/package/SnapNote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "$stage/SnapNote-arm64" "$stage/SnapNote-x86_64" -output "$app/Contents/MacOS/SnapNote"
strip -S "$app/Contents/MacOS/SnapNote"
cp Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
# Explicitly unsigned distribution: never use the maintainer's development cert.
codesign --force --sign - --identifier local.snapnote.app "$app"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/SnapNote" -verify_arch arm64 x86_64
cp LICENSE "$stage/package/LICENSE"
cat > "$stage/package/INSTALL.txt" <<'INSTALL'
SnapNote — macOS 14 or later, Apple Silicon and Intel

Move SnapNote.app to Applications and open it.
This build is not notarized. If macOS blocks it, after attempting to launch,
open System Settings > Privacy & Security > Open Anyway.
Only do this for a download you trust. Managed Macs may prohibit exceptions.
Apple instructions: https://support.apple.com/en-us/102445

Press Command+Shift+2 to capture a region. Grant Screen Recording permission
when prompted. macOS may ask you to restart SnapNote afterward.
Ad-hoc builds may require a new capture-permission grant after updates.

Closing the window keeps SnapNote running. More > Quit or Command+Q quits it.
Edits are held in memory; copy or save before quitting or opening another image.

Source and license: https://github.com/LorenzGit/snapnote
INSTALL
archive="SnapNote-$version-macos-universal.zip"
(cd "$stage/package" && COPYFILE_DISABLE=1 /usr/bin/zip -q -r "$stage/$archive" SnapNote.app LICENSE INSTALL.txt)
# Update only public outputs; never touch build/SnapNote.app.
mkdir -p "$root/dist/unsigned"
if [[ -d "$root/dist/unsigned/SnapNote.app" ]]; then
    mv "$root/dist/unsigned/SnapNote.app" "$stage/previous.app"
fi
mv "$app" "$root/dist/unsigned/SnapNote.app"
mv "$stage/$archive" "$root/dist/$archive"
(cd "$root/dist" && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "$root/dist/$archive"
