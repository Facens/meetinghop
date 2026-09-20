#!/bin/bash
# HARNESS_STRANGER_ONLY: answers the Calendar permission dialog, screenshots
# the HUD card and clicks its Join button by AXIdentifier — screen-driving
# work this harness confines to the stranger tier (harness/README.md, "Only
# the stranger tier drives the screen").
#
# R10/AE4: a stranger's calendar holds a Zoom meeting three minutes out.
# Once MeetingHop is granted access, the card appears before the meeting
# starts, and clicking Join fires the Zoom deep link. Stated end state
# (R11's vocabulary): `card shown` names the seeded meeting (by a hash of
# its title, never the title itself — R13) before its start time, and
# `join fired` names the deep link's scheme and host plus a hash of the
# meeting's own id. The golden image ships no Zoom client, so nothing
# actually opens; `Coordinator.join`
# (Sources/MeetingHop/Coordinator.swift) still fires the deep link and
# still journals it either way — that is what `join fired` proves, and
# `finding no-zoom-installed` records the reason a real launch could not be
# observed (Covers AE4).
#
# The meeting id hash `hud.join.<idHash>` and `join fired`'s
# `meeting_id_hash` are keyed on is assigned by EventKit at save time and
# cannot be predicted from the host (see
# harness/fixtures/meetinghop/seed-calendar.applescript's own header for
# exactly what is and is not known about it). `fixture meetinghop/calendar
# --event` seeds the meeting and persists the identifier Calendar's own
# scripting dictionary hands back; this scenario reads it with
# `fixtures_guest_capture` and hashes it with `fixtures_path_hash`
# (harness/lib/fixtures.sh) — the same algorithm
# `Sources/MeetingHopKit/Support/AccessibilityID.swift`'s `hash` uses. If
# that equivalence is wrong on the first real run, the Join click fails
# loudly with the hash it predicted, in `click`'s own error message
# (harness/lib/scenario.sh) — never silently.
#
# The onboarding card is answered first, before anything here waits on the
# meeting card. Both are borderless panels at the top centre of the screen
# and the app shows only one at a time — the meeting card takes the space
# and the onboarding card steps aside until it is gone
# (Sources/MeetingHop/App/AppDelegate.swift) — so a scenario that left the
# onboarding card up would be trying to click a control that is deliberately
# not on screen. Dismissed rather than acted on, and immediately after the
# permission is granted rather than later: the seeded meeting is three
# minutes out and the card for it appears at the lead time (two minutes by
# default), which leaves a minute to get the onboarding card out of the way
# without racing it.
#
# A password rides along in the seeded Zoom URL (obviously synthetic, never
# a real one) so that a privacy bug — the password reaching the journal —
# has something to actually be caught failing to leak
# (`JournalData.joinFired`'s own doc comment, Sources/MeetingHopKit/Harness/JournalEvent.swift).
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?meeting-in-three.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
. "$HARNESS_DIR/lib/scenario.sh"
. "$HARNESS_DIR/lib/fixtures.sh"
. "$HARNESS_DIR/fixtures/meetinghop/_lib.sh"

BUNDLE_ID="$MEETINGHOP_BUNDLE_ID"

# Fixed, synthetic meeting facts. TITLE is hashed by this scenario for the
# `card shown` assertion below and by MeetingHopKit for the journal's own
# `title_hash` — one literal, never two copies that could drift. The Zoom
# number and password are obviously made up, never a real meeting.
TITLE="Harness Standup"
ZOOM_NUMBER="5551234567"
ZOOM_PASSWORD="HarnessSyntheticPwd42"
LOCATION="https://zoom.us/j/${ZOOM_NUMBER}?pwd=${ZOOM_PASSWORD}"
LEAD_MINUTES=3
DURATION_MINUTES=30

if [ -z "${HARNESS_ASSET:-}" ]; then
    verdict fail "no --asset was given; the stranger tier installs a Developer ID preview build, not a local build."
fi

step "fixture"
fixture meetinghop/calendar "$HARNESS_NONCE" --event "$TITLE" "$LEAD_MINUTES" "$DURATION_MINUTES" "$LOCATION"

step "install"
INSTALL_JSON="$(install_app MeetingHop)"
log "installed: $(printf '%s' "$INSTALL_JSON" | jq -c '.')"

step "gatekeeper"
GATE_WAIT="$(dialog wait gatekeeper)"
if [ "$(printf '%s' "$GATE_WAIT" | jq -r '.present')" = "true" ]; then
    shot "gatekeeper-prompt" > /dev/null
    dialog answer gatekeeper allow > /dev/null
    log "gatekeeper prompted; answered allow (the dialog helper logs which button that pressed)"
else
    log "gatekeeper did not prompt (no quarantine attribute, or already cleared)"
fi

step "launch"
wait_for_status_item "$BUNDLE_ID" > /dev/null
journal_at "$BUNDLE_ID" "$MEETINGHOP_JOURNAL_LEAF"

step "calendar-permission"
CALENDAR_WAIT="$(dialog wait calendar)"
if [ "$(printf '%s' "$CALENDAR_WAIT" | jq -r '.present')" = "true" ]; then
    shot "calendar-prompt" > /dev/null
    dialog answer calendar allow > /dev/null
    log "calendar permission prompted; answered allow (the dialog helper logs which button that pressed)"
else
    log "calendar permission did not prompt"
fi
# Asserted before anything calendar-shaped below: if the grant itself
# silently failed, Coordinator.start() takes its early-return branch and
# never calls calendar.start() at all, so `calendars counted` (and
# everything after it) would never appear — a bare timeout further down
# would then misleadingly blame the count or the card instead of the grant
# that never happened.
expect_event "calendar access" granted=true > /dev/null

step "dismiss-first-run-card"
expect_event "guidance shown" state=first_run > /dev/null
click "$BUNDLE_ID" "guidance.dismiss"
expect_event "guidance dismissed" state=first_run > /dev/null

step "predict-meeting-id"
EVENT_UID="$(fixtures_guest_capture "$HARNESS_STEP_TIMEOUT" "$(fx_state_read_command event-uid)")"
if [ -z "$EVENT_UID" ]; then
    verdict fail "the calendar fixture reported no event uid to predict the meeting id hash from."
fi
ID_HASH="$(fixtures_path_hash "$EVENT_UID")"
log "predicted meeting id hash: $ID_HASH (from the seeded event's Calendar-scripting uid — see seed-calendar.applescript's UNVERIFIED note)"

step "calendars-counted"
expect_event "calendars counted" count=1 > /dev/null

step "upcoming-counted"
expect_event "upcoming counted" count=1 > /dev/null

step "card-shown"
TITLE_HASH="$(fixtures_path_hash "$TITLE")"
expect_event "card shown" title_hash="$TITLE_HASH" count=1 > /dev/null
shot "card-before-start" > /dev/null

step "join"
click "$BUNDLE_ID" "hud.join.$ID_HASH"

step "join-fired"
expect_event "join fired" scheme=zoommtg host=zoom.us meeting_id_hash="$ID_HASH" > /dev/null
shot "after-join" > /dev/null

finding "no-zoom-installed"

verdict pass
