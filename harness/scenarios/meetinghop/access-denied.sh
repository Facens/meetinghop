#!/bin/bash
# HARNESS_STRANGER_ONLY: answers the Calendar permission dialog by
# AXIdentifier-free system dialog matching, opens the menu-bar popover and
# screenshots it — screen-driving work this harness confines to the
# stranger tier (harness/README.md, "Only the stranger tier drives the
# screen").
#
# R10/AE: a stranger installs MeetingHop, is shown the Calendar permission
# prompt, and answers Don't Allow. Stated end state (R11's vocabulary): the
# app records `calendar access` with `granted: false` and `status: denied`
# — never retrying, never popping a second prompt — and tells the user, unprompted, that it
# was refused and how to undo that. macOS never asks a second time, so a
# refusal the app stayed quiet about is a permanent, unexplained silence:
# `guidance shown` with `state=access_denied` is the card that breaks it,
# and pressing its button is the recovery path.
#
# The refused-permission card and the first-run card are one surface in two
# states (`MeetingHopKit.Onboarding`), which is why this scenario asserts
# `state=access_denied` rather than merely that a card appeared: a denial
# that produced the general introduction instead would be a real defect and
# would otherwise pass.
#
# THE PRIVACY PANE'S ANCHOR IS CHECKED HERE, as far as anything can check
# it. `?Privacy_Calendars` is not invented: it is a top-level key in the
# pane's own Resources/*.lproj/PrivacySecurity.searchTerms, whose value is
# that section's search entry. What no assertion can prove is whether the
# URL handler forwards the anchor — System Settings accepts the scheme
# whatever follows it, so `ok=true` says only that something took the URL
# (`JournalData.guidanceAction`). The screenshot after the click is the
# evidence for the anchor itself, for a human to look at: privacy pane
# scrolled to Calendars, privacy pane at the top, or the wrong pane
# entirely.
#
# The popover is still captured afterwards. It carries the same recovery
# permanently, after the card has been answered and gone
# (`MenuBarView`'s empty states), and it is read the only way R17 allows
# reading UI content at all: as a screenshot, never asserted on.
#
# No calendar is seeded (fixture meetinghop/base): denial happens before
# any calendar would matter, and R10's `no-accounts.sh` already owns
# proving the golden image starts with zero calendars.
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?access-denied.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
. "$HARNESS_DIR/lib/scenario.sh"
. "$HARNESS_DIR/fixtures/meetinghop/_lib.sh"

BUNDLE_ID="$MEETINGHOP_BUNDLE_ID"

if [ -z "${HARNESS_ASSET:-}" ]; then
    verdict fail "no --asset was given; the stranger tier installs a Developer ID preview build, not a local build."
fi

step "fixture"
fixture meetinghop/base "$HARNESS_NONCE"

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
# The presence check stays a scenario-level guard, ahead of confirm_dialog:
# a missing prompt is a failure of this scenario's premise, not a quiet path
# through it (unlike the "allow" scenarios, where no prompt legitimately
# means access was already granted). It read as a pass once: the app
# shipped without the calendar entitlement, TCC refused to ask, the journal
# said `granted: false`, and an assertion on that alone matched a denial
# nobody had made.
CALENDAR_WAIT="$(dialog wait calendar)"
if [ "$(printf '%s' "$CALENDAR_WAIT" | jq -r '.present')" != "true" ]; then
    verdict fail "the calendar prompt never appeared, so there was nothing to refuse; the app was denied before the user was asked (see packaging/MeetingHop.entitlements)"
fi

step "access-denied"
# confirm_dialog, not dialog+expect_event: a click succeeding is not the
# same fact as the state it was meant to produce landing in the journal —
# see confirm_dialog's own doc comment (harness/lib/scenario.sh) for the
# diagnosis; the same race that could orphan an "allow" can orphan a
# "deny". `status=denied` is the half that says a person refused. A build
# that TCC never asks for records `notDetermined` here, which is the
# defect the guard above already catches, and this assertion is what tells
# the two apart regardless.
confirm_dialog calendar deny "calendar access" granted=false status=denied > /dev/null

step "denied-card"
expect_event "guidance shown" state=access_denied > /dev/null
shot "denied-card" > /dev/null

step "open-privacy-settings"
click "$BUNDLE_ID" "guidance.action"
# `fell_back=false` fails this scenario if the privacy pane would not open
# and Calendar.app was opened instead — which would be the wrong recovery
# entirely, since Calendar.app has no control over MeetingHop's permission.
expect_event "guidance action" state=access_denied target=privacy_settings source=card ok=true fell_back=false > /dev/null
# The evidence for the anchor. Nothing in the journal can distinguish "the
# Calendars section" from "the top of Privacy & Security"; this can.
shot "privacy-pane" > /dev/null

step "menu-bar-state"
open_status_item "$BUNDLE_ID"
shot "denied-menu" > /dev/null

verdict pass
