#!/bin/bash
# HARNESS_STRANGER_ONLY: answers the Calendar permission dialog, opens the
# menu-bar popover and screenshots it — screen-driving work this harness
# confines to the stranger tier (harness/README.md, "Only the stranger tier
# drives the screen").
#
# R10/AE: a stranger installs MeetingHop on a machine that has exactly one
# local calendar and nothing in it, answers Allow, and the app finds a
# calendar but no meeting. Stated end state (R11's vocabulary):
# `calendar access` is `granted: true`, `calendars counted` is 1 — the
# calendar `fixture meetinghop/calendar` seeds — and `upcoming counted` is
# 0, because that calendar holds no event at all.
#
# This is also the scenario that proves the onboarding card is genuinely
# unconditional. Nothing is wrong on this guest: access was granted, a
# calendar is there, the app works. The card appears anyway — that is the
# maintainer's rule, and a card that only showed up when something was
# broken would never reach the user who is one account short of a problem
# they cannot yet see. It is dismissed here rather than acted on, which is
# the other half of the contract: `guidance dismissed` and then nothing
# further, no second card, no reappearance on the next tick.
#
# This is the scenario `no-accounts.sh`'s own edge case exists to be
# distinguishable from: `calendars counted: 1` here is a different fact
# from `calendars counted: 0` there, so a guest that unexpectedly has (or
# is missing) a calendar fails the matching scenario loudly rather than
# passing as the other.
#
# The two scenarios are coupled the other way too: this one's own
# `calendars counted: 1` only means "the golden image starts at zero and
# this fixture added exactly one" if that starting-at-zero fact is itself
# true — which is what `no-accounts.sh` actually proves. If this scenario
# ever reports more than one calendar, check whether `no-accounts.sh` still
# passes before assuming this fixture is at fault.
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?nothing-upcoming.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
. "$HARNESS_DIR/lib/scenario.sh"
. "$HARNESS_DIR/fixtures/meetinghop/_lib.sh"

BUNDLE_ID="$MEETINGHOP_BUNDLE_ID"

if [ -z "${HARNESS_ASSET:-}" ]; then
    verdict fail "no --asset was given; the stranger tier installs a Developer ID preview build, not a local build."
fi

step "fixture"
fixture meetinghop/calendar "$HARNESS_NONCE"

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
# Asserted before the counts below, not folded into either: if the grant
# itself silently failed, Coordinator.start() takes its early-return branch
# and never calls calendar.start() at all, so neither `calendars counted`
# nor `upcoming counted` would ever appear — a bare count timeout would then
# misleadingly blame the count instead of the grant that never happened.
expect_event "calendar access" granted=true > /dev/null

step "first-run-card"
expect_event "guidance shown" state=first_run > /dev/null
shot "first-run-card" > /dev/null

step "dismiss-first-run-card"
click "$BUNDLE_ID" "guidance.dismiss"
expect_event "guidance dismissed" state=first_run > /dev/null

step "calendars-counted"
expect_event "calendars counted" count=1 > /dev/null

step "upcoming-counted"
expect_event "upcoming counted" count=0 > /dev/null

step "menu-bar"
open_status_item "$BUNDLE_ID"
shot "empty-upcoming-menu" > /dev/null

verdict pass
