#!/bin/bash
# fixture meetinghop/calendar <nonce> [--event <title> <lead-minutes> <duration-minutes> <location>]
#
# Turns the journal on (fx_activate_journal, harness/fixtures/meetinghop/_lib.sh)
# and seeds a local "On My Mac" calendar via
# harness/fixtures/meetinghop/seed-calendar.applescript — one calendar,
# always, so `calendars counted: 1` is the same fact whichever scenario
# named this fixture.
#
# With no --event, this is `nothing-upcoming.sh`'s own fixture: a calendar
# that exists and holds nothing, so `upcoming counted: 0` is the whole
# point.
#
# --event <title> <lead-minutes> <duration-minutes> <location> additionally
# seeds one event, starting <lead-minutes> minutes from the moment this
# fixture runs and lasting <duration-minutes>, with <location> carrying
# whatever MeetingHopKit.MeetingLinkParser should find there (a Zoom URL,
# for `meeting-in-three.sh`) — this fixture never assumes what kind of link
# it is; that choice belongs to the scenario that names the location.
#
# The new event's `uid`, Calendar's own scripting identifier, is checked for
# being non-empty (a real integrity check: it is what proves
# seed-calendar.applescript actually created something) and then discarded.
# It is NOT what `meeting-in-three.sh` clicks by. Measured directly against
# a seeded event on 2026-09-21: this `uid` and EventKit's own
# `eventIdentifier` — what `Sources/MeetingHopKit/Support/AccessibilityID.swift`
# actually hashes for the Join button's `AXIdentifier` — are two different
# strings in two different formats, never documented as equal, and never
# actually equal. Before that unit, this fixture persisted `uid` via
# `fx_write_state` for the scenario to read back and hash, which predicted
# the wrong click target on every single run; the scenario now reads the
# app's own `id_hash` off the `card shown` journal line instead (see
# `JournalData.cardShown`'s doc comment and meeting-in-three.sh's own).
# `fx_write_state`/`fx_state_read_command`
# (harness/fixtures/meetinghop/_lib.sh) are unused by this fixture now but
# left in place: generic guest-state plumbing a later fixture may still
# want, not specific to this one's old, wrong use of it.
#
# Fails loudly rather than seeding nothing silently (this unit's own
# instruction): osacompile output aside, seed-calendar.applescript itself
# raises a real AppleScript `error` on anything it cannot do, which makes
# `osascript` exit nonzero here — under this file's own `set -euo
# pipefail`, that tears the whole fixture application down immediately, and
# `harness/lib/scenario.sh`'s `fixture` helper reports it as a harness
# error rather than letting a scenario run on against an empty or
# half-seeded calendar.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

NONCE="${1:?the calendar fixture requires the run nonce as its first argument.}"
shift

SEED_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/../seed-calendar.applescript"
CALENDAR_NAME="MeetingHop Harness"

fx_activate_journal "$NONCE"

osascript "$SEED_SCRIPT" calendar "$CALENDAR_NAME" > /dev/null

if [ $# -eq 0 ]; then
    exit 0
fi

case "$1" in
    --event)
        if [ $# -lt 5 ]; then
            echo "error: calendar fixture: --event requires <title> <lead-minutes> <duration-minutes> <location>." >&2
            exit 2
        fi
        TITLE="$2"
        LEAD_MINUTES="$3"
        DURATION_MINUTES="$4"
        LOCATION="$5"
        ;;
    *)
        echo "error: calendar fixture: unknown argument '$1'." >&2
        exit 2
        ;;
esac

case "$LEAD_MINUTES" in ''|*[!0-9]*) echo "error: calendar fixture: lead-minutes must be a non-negative integer, got '$LEAD_MINUTES'." >&2; exit 2 ;; esac
case "$DURATION_MINUTES" in ''|*[!0-9]*) echo "error: calendar fixture: duration-minutes must be a non-negative integer, got '$DURATION_MINUTES'." >&2; exit 2 ;; esac

START_EPOCH=$(( $(date +%s) + LEAD_MINUTES * 60 ))

EVENT_JSON="$(osascript "$SEED_SCRIPT" event "$CALENDAR_NAME" "$TITLE" "$START_EPOCH" "$DURATION_MINUTES" "$LOCATION")"

EVENT_UID="$(printf '%s' "$EVENT_JSON" | jq -r '.uid // empty')"
if [ -z "$EVENT_UID" ]; then
    echo "error: calendar fixture: seed-calendar.applescript reported no uid for the seeded event — got: $EVENT_JSON" >&2
    exit 3
fi
