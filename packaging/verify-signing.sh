#!/bin/bash
# Signature assertions for a built MeetingHop.app. Two modes, per KTD16:
#
#   verify-signing.sh consistency <app>   runs anywhere, certificate or not
#   verify-signing.sh authority   <app>   runs only where the Developer ID exists
#
# Ported from AgentMenu's packaging/verify-signing.sh. `codesign --verify
# --strict --deep` is not one of these assertions: --deep never looks in
# Contents/Resources, and it reported AgentMenu's defectively signed bundle as
# valid. So every Mach-O in the bundle is found by its magic number rather than
# by where codesign expects code to be, and each one is inspected on its own.
# Today that is the app executable plus the five Mach-Os inside
# Sparkle.framework (the framework itself, Autoupdate, Updater.app and the
# two XPC services), each inspected on its own.
#
# consistency: every Mach-O was signed by this pipeline (none is linker-signed),
#   all of them carry the same team identifier (all ad-hoc, or all one team),
#   every one requested the hardened runtime, the app carries the calendar
#   entitlement and nothing else in the bundle carries entitlements (R24).
#   The app's entitlement is asserted, not merely permitted: without
#   com.apple.security.personal-information.calendars the hardened runtime
#   stops TCC from ever showing the calendar prompt, and the app ships with an
#   empty menu and no way to fix it — the v0.1.0 defect this check exists to
#   keep from recurring.
# authority: consistency, plus every Mach-O reports Developer ID authority, the
#   expected team, a secure timestamp, and no ad-hoc flag (R6).
set -euo pipefail

MODE="${1:-}"
APP="${2:-}"
TEAM_ID="${MH_TEAM_ID:-KSP2AAA5L2}"
CALENDAR_ENTITLEMENT="com.apple.security.personal-information.calendars"

if [ "$MODE" != "consistency" ] && [ "$MODE" != "authority" ] || [ ! -d "$APP" ]; then
    echo "usage: $0 consistency|authority <path/to/MeetingHop.app>" >&2
    exit 2
fi

MAIN_EXECUTABLE="$APP/Contents/MacOS/$(defaults read "$(cd "$APP" && pwd)/Contents/Info.plist" CFBundleExecutable)"

failures=0
fail() { echo "  ✗ $1" >&2; failures=$((failures + 1)); }

# Every regular file that is a Mach-O, wherever it sits. Symlinks are skipped
# so a framework's Versions/Current farm is inspected once, through its target.
machos=()
while IFS= read -r -d '' path; do
    case "$(file -b "$path")" in Mach-O*) machos+=("$path") ;; esac
done < <(find "$APP" -type f -print0 | sort -z)

if [ "${#machos[@]}" -eq 0 ]; then
    echo "error: no Mach-O found under $APP" >&2
    exit 1
fi

# One codesign -dvvv per file, parsed into what the assertions read. codesign
# writes its report to stderr.
teams=()
echo "signature ${MODE} check: $APP"
for path in "${machos[@]}"; do
    report="$(codesign -dvvv "$path" 2>&1 || true)"
    team="$(printf '%s\n' "$report" | sed -n 's/^TeamIdentifier=//p' | head -1)"
    flags="$(printf '%s\n' "$report" | sed -n 's/^CodeDirectory .*flags=\([^ ]*\).*/\1/p' | head -1)"
    authority="$(printf '%s\n' "$report" | grep -c '^Authority=Developer ID Application:' || true)"
    timestamp="$(printf '%s\n' "$report" | grep -c '^Timestamp=' || true)"
    rel="${path#"$APP"/}"
    printf '  %-56s team=%-10s flags=%s\n' "$rel" "${team:-none}" "${flags:-none}"

    [ -n "$team" ] || fail "$rel: not signed at all"
    teams+=("${team:-none}")
    # Its own seal, not only the metadata the report prints: a nested binary
    # whose signature is broken but whose bytes the app happens to seal would
    # otherwise read as fine.
    codesign --verify --strict "$path" 2>/dev/null || fail "$rel: signature does not verify"

    case "$flags" in
        *linker-signed*) fail "$rel: linker-signed — this pipeline never signed it" ;;
    esac
    case "$flags" in
        *runtime*) ;;
        *) fail "$rel: hardened runtime not requested" ;;
    esac

    entitlements="$(codesign -d --entitlements - --xml "$path" 2>/dev/null || true)"
    if [ "$path" = "$MAIN_EXECUTABLE" ]; then
        case "$entitlements" in
            *"$CALENDAR_ENTITLEMENT"*) ;;
            *) fail "$rel: lacks the $CALENDAR_ENTITLEMENT entitlement; the calendar prompt never appears without it" ;;
        esac
    else
        case "$entitlements" in
            *"<key>"*) fail "$rel: carries entitlements; only the app itself may" ;;
        esac
    fi

    if [ "$MODE" = "authority" ]; then
        [ "$authority" -gt 0 ] || fail "$rel: no Developer ID Application authority"
        [ "$team" = "$TEAM_ID" ] || fail "$rel: team is '$team', expected $TEAM_ID"
        [ "$timestamp" -gt 0 ] || fail "$rel: no secure timestamp"
        case "$flags" in
            *adhoc*) fail "$rel: ad-hoc signed" ;;
        esac
    fi
done

# All Mach-Os share one team identifier: either every one is ad-hoc ("not
# set") or every one carries the same real identity. A mix is the nested
# binary somebody forgot.
distinct="$(printf '%s\n' "${teams[@]}" | sort -u | wc -l | tr -d ' ')"
if [ "$distinct" -ne 1 ]; then
    fail "mixed signing identities across the bundle: $(printf '%s\n' "${teams[@]}" | sort -u | tr '\n' ' ')"
fi

# The seal itself: resources match what the app's signature covers. Not
# --deep — the nested code was inspected above.
if ! codesign --verify --strict --verbose=1 "$APP" 2>/dev/null; then
    fail "codesign --verify --strict failed on the app"
fi
[ -f "$MAIN_EXECUTABLE" ] || fail "main executable missing: $MAIN_EXECUTABLE"

if [ "$failures" -gt 0 ]; then
    echo "signature ${MODE} check: FAIL ($failures)" >&2
    exit 1
fi
echo "signature ${MODE} check: ok (${#machos[@]} Mach-O)"
