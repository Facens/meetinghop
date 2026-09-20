#!/bin/bash
# Assembles dist/MeetingHop.app from the built products. No Xcode.
#
#   make bundle                      Developer ID signed when the certificate
#                                    is in the keychain, ad-hoc otherwise
#   VERSION=1.2.3 make bundle
#   MH_SIGN_ID="<identity>" make bundle   sign with another identity
#   MH_SIGN_ID=- make bundle              force the ad-hoc path
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="${VERSION:-0.0.0-alpha}"
APP="dist/MeetingHop.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

# R20 / KTD10 (as amended): three release channels share one version grammar —
# stable (MAJOR.MINOR.PATCH), beta (MAJOR.MINOR.PATCH-beta.N) and alpha
# (MAJOR.MINOR.PATCH-alpha), see packaging/version.sh for the table. The two
# Info.plist version keys can no longer share one placeholder, because
# Sparkle's comparator (SUStandardVersionComparator) stops reading at the
# first "-", so 0.2.0-beta.1 and 0.2.0 would tie and a beta install could
# never be offered the final. CFBundleShortVersionString stays the human
# string, as written; CFBundleVersion is derived — the same three components
# plus a fourth that breaks the tie and keeps the sequence monotonic. Both are
# validated and derived here, before anything is built, so a malformed
# version fails before it can stamp a build number no client could order.
source "$ROOT/packaging/version.sh"
CHANNEL="$(version_channel "$VERSION")" || exit 1
BUILD="$(version_build "$VERSION")" || exit 1

echo "==> building"
swift build -c release --product MeetingHop

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp .build/release/MeetingHop "$MACOS_DIR/MeetingHop"

echo "==> icons"
swift packaging/icon/make-icons.swift >/dev/null
cp dist/icon/MeetingHop.icns "$RES_DIR/MeetingHop.icns"
# Flattened into Resources root: the app looks the template up by name through
# Bundle.main, and falls back to an SF Symbol when it is absent.
cp dist/icon/menubar/MenuBarIconTemplate*.png "$RES_DIR/"

sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" packaging/Info.plist > "$APP/Contents/Info.plist"

# ---------------------------------------------------------------------------
# Signing. Ported from AgentMenu's packaging/bundle.sh.
#
# R1 / KTD1: the release identity is the Developer ID, referenced here once.
# The team identifier is part of the designated requirement macOS keys the
# Calendar grant and the launch-at-login registration to — SMAppService
# refuses an ad-hoc build outright, which is why the toggle used to revert —
# so this line is not cheap to change once installs exist.
DEVELOPER_ID="Developer ID Application: Andrea Giannangelo (KSP2AAA5L2)"
SIGN_ID="${MH_SIGN_ID:-$DEVELOPER_ID}"

if [ "$SIGN_ID" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    if [ -n "${MH_SIGN_ID:-}" ]; then
        # An identity that was asked for by name must not degrade silently.
        echo "error: signing identity not in the keychain: $MH_SIGN_ID" >&2
        exit 1
    fi
    SIGN_ID="-"
fi

# Every signing call carries the same options: the hardened runtime (R2) and,
# with a real identity, a secure timestamp. Ad-hoc signatures cannot be
# timestamped, so that path says none rather than letting codesign skip it
# quietly.
SIGN=(codesign --force --options runtime --sign "$SIGN_ID")
if [ "$SIGN_ID" = "-" ]; then
    SIGN+=(--timestamp=none)
    # The path a fork's CI runner and an unprovisioned machine both take. It
    # produces a bundle that looks signed and is not: it runs here, fails
    # Gatekeeper anywhere else, cannot be notarized, and asks for the calendar
    # again after every rebuild. Say so where nobody can miss it.
    cat >&2 <<'BANNER'
==========================================================================
 AD-HOC SIGNED BUILD — not a release
 No Developer ID certificate in the keychain. This bundle runs on this
 machine only, will not pass Gatekeeper elsewhere, and cannot be notarized.
==========================================================================
BANNER
else
    SIGN+=(--timestamp)
    echo "==> signing with: $SIGN_ID"
fi

# KTD2 / R3: explicit, never --deep. MeetingHop has no nested executable
# today, so the app is the only signing call; when Sparkle is embedded its
# pieces are signed here first, deepest first, and the app last. No
# entitlements: MeetingHop sends no Apple Events, and EventKit under an
# unsandboxed hardened-runtime app is gated by the usage strings the plist
# already carries.
"${SIGN[@]}" "$APP"

# KTD16: the authority assertion where a Developer ID signed it, the
# consistency assertion everywhere else. Authority includes consistency.
case "$SIGN_ID" in
    "Developer ID Application:"*) "$ROOT/packaging/verify-signing.sh" authority "$APP" ;;
    *) "$ROOT/packaging/verify-signing.sh" consistency "$APP" ;;
esac

if [ "$SIGN_ID" = "-" ]; then
    echo "==> built $APP ($VERSION, channel $CHANNEL, AD-HOC signed — not a release)"
else
    echo "==> built $APP ($VERSION, channel $CHANNEL, signed by $SIGN_ID)"
fi
