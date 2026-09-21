#!/bin/bash
# HARNESS_STRANGER_ONLY: answers the Calendar permission dialog, opens the
# menu-bar popover and screenshots it — screen-driving work this harness
# confines to the stranger tier (harness/README.md, "Only the stranger tier
# drives the screen").
#
# R10/AE: a stranger installs MeetingHop on a machine that has one extra
# local calendar on top of macOS's own built-ins, and nothing in it, answers
# Allow, and the app finds calendars but no meeting. Stated end state (R11's
# vocabulary): `calendar access` is `granted: true`, `calendars counted` is
# 4, and `upcoming counted` is 0, because none of those calendars holds an
# event.
#
# `4`, not `1`: `store.calendars(for: .event)` always carries three built-in
# local calendars on this image — "Calendar", "US Holidays", "Birthdays" —
# whether or not any account or fixture ever touches Calendar.app (see
# `no-accounts.sh`'s own header, which is where that fact is verified, with
# how). `fixture meetinghop/calendar` adds exactly one more, "MeetingHop
# Harness", on top of those three: 3 + 1 = 4. `count=1` (this scenario's own
# assertion before 2026-09-21) assumed the golden image started at zero,
# which was never true and was never checked until now.
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
# distinguishable from: `calendars counted: 4` here is a different fact from
# `calendars counted: 3` there, so a guest that unexpectedly has (or is
# missing) the fixture's own calendar fails the matching scenario loudly
# rather than passing as the other.
#
# The two scenarios are coupled the other way too: this one's own
# `calendars counted: 4` only means "the built-in three plus this fixture's
# one" if the built-in count is itself three — which is what `no-accounts.sh`
# actually proves. If this scenario ever reports a count other than 4, check
# whether `no-accounts.sh` still reports 3 before assuming this fixture is
# at fault.
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
# Finder clears the quarantine flag when a person answers Open; `mv` from a
# shell does not, so without this the app keeps running translocated.
clear_quarantine MeetingHop

step "launch"
wait_for_status_item "$BUNDLE_ID" > /dev/null
journal_at "$BUNDLE_ID" "$MEETINGHOP_JOURNAL_LEAF"

step "calendar-permission"
# confirm_dialog, not dialog+expect_event: a click succeeding is not the
# same fact as the grant it was meant to produce landing in the journal —
# see confirm_dialog's own doc comment (harness/lib/scenario.sh) for the
# diagnosis. Also covers the early-return risk the old comment here named:
# if the grant itself silently failed, Coordinator.start() never calls
# calendar.start() at all, so neither `calendars counted` nor `upcoming
# counted` would ever appear either — a bare count timeout further down
# would then misleadingly blame the count instead of the grant that never
# happened.
confirm_dialog calendar allow "calendar access" granted=true > /dev/null

step "first-run-card"
expect_event "guidance shown" state=first_run > /dev/null
shot "first-run-card" > /dev/null

step "dismiss-first-run-card"
click "$BUNDLE_ID" "guidance.dismiss"
expect_event "guidance dismissed" state=first_run > /dev/null

step "calendars-counted"
# count=4: the golden image's own three built-in calendars plus this
# fixture's one — see this file's own header for why.
expect_event "calendars counted" count=4 > /dev/null

step "upcoming-counted"
expect_event "upcoming counted" count=0 > /dev/null

step "menu-bar"
open_status_item "$BUNDLE_ID"
shot "empty-upcoming-menu" > /dev/null

verdict pass
