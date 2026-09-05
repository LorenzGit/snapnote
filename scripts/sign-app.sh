#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$script_dir/signing.conf" || ! -f "$script_dir/signing.requirement" ]]; then
    echo 'Local signing is not configured. See scripts/signing.conf.example or use bash scripts/build.sh --unsigned.' >&2
    exit 1
fi
source "$script_dir/signing.conf"

# Check before touching the bundle. A sandboxed Keychain lookup may fail even
# with valid credentials; retry from a normal terminal or with sandbox approval.
identities="$(/usr/bin/security find-identity -v -p codesigning)"
if ! /usr/bin/grep -Fq "$SNAPNOTE_SIGNING_IDENTITY" <<< "$identities"; then
    echo "SnapNote's pinned signing identity is unavailable to this process." >&2
    echo "Run with Keychain access. No alternate identity or ad-hoc fallback is allowed." >&2
    exit 1
fi
if [[ "${1:-}" == '--check' ]]; then exit 0; fi
if [[ $# -ne 1 ]]; then echo "Usage: $0 <app-bundle> | --check" >&2; exit 2; fi
app="$1"
actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
if [[ "$actual_id" != "$SNAPNOTE_BUNDLE_ID" ]]; then
    echo "Refusing to sign unexpected bundle identifier: $actual_id" >&2
    exit 1
fi
requirement="$(cat "$script_dir/signing.requirement")"
/usr/bin/codesign --force --sign "$SNAPNOTE_SIGNING_IDENTITY" \
    --identifier "$SNAPNOTE_BUNDLE_ID" --timestamp=none \
    --requirements "$script_dir/signing.requirement" "$app"
/usr/bin/codesign --verify --strict -R "=${requirement#designated => }" "$app"
metadata="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)"
if ! /usr/bin/grep -Fxq "TeamIdentifier=$SNAPNOTE_SIGNING_TEAM" <<< "$metadata"; then
    echo "Signing verification failed: unexpected team." >&2
    exit 1
fi
if /usr/bin/grep -Fq 'Signature=adhoc' <<< "$metadata"; then
    echo "Signing verification failed: ad-hoc signature." >&2
    exit 1
fi
