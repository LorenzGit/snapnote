#!/bin/bash
# Integration test: different executable contents must retain the same identity.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/sign-app.sh --check
probe="$(mktemp -d "${TMPDIR:-/tmp}/snapnote-signing.XXXXXX")"
trap 'rm -rf "$probe"' EXIT
for variant in a b; do
    bundle="$probe/$variant.bundle"
    mkdir -p "$bundle/Contents/MacOS"
    cp Info.plist "$bundle/Contents/Info.plist"
    printf 'int main(void) { return %s; }\n' "$( [[ "$variant" == a ]] && echo 0 || echo 1 )" > "$probe/$variant.c"
    xcrun clang "$probe/$variant.c" -o "$bundle/Contents/MacOS/SnapNote"
    bash scripts/sign-app.sh "$bundle"
    codesign -d -r- "$bundle" 2>&1 | sed -n 's/^designated => //p' > "$probe/$variant.dr"
    codesign -d --verbose=4 "$bundle" 2>&1 | sed -n 's/^CDHash=//p' > "$probe/$variant.cdhash"
done
[[ -s "$probe/a.dr" && -s "$probe/b.dr" ]]
cmp "$probe/a.dr" "$probe/b.dr"
if cmp -s "$probe/a.cdhash" "$probe/b.cdhash"; then echo 'FAIL: fixtures must differ' >&2; exit 1; fi
codesign --verify --strict -R "=$(cat "$probe/a.dr")" "$probe/b.bundle"
codesign --verify --strict -R "=$(cat "$probe/b.dr")" "$probe/a.bundle"
# Wrong-bundle protection must refuse signing before adding a certificate.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.unrelated.app' "$probe/b.bundle/Contents/Info.plist"
if bash scripts/sign-app.sh "$probe/b.bundle" > "$probe/refusal.log" 2>&1; then
    echo 'FAIL: signed an unexpected bundle identifier' >&2; exit 1
fi
grep -q 'Refusing to sign unexpected bundle identifier' "$probe/refusal.log"
echo 'PASS: different binaries, identical designated requirement, reciprocal identity checks, wrong-bundle refusal.'
cat "$probe/a.dr"
