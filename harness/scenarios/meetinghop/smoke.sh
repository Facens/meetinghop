#!/bin/bash
# HARNESS_STRANGER_ONLY: installs the app, answers Gatekeeper and clicks by identifier, which only the stranger tier may do.
# MeetingHop's stranger-tier smoke scenario — U4, Milestone A. Installs the
# shipped v0.1.0 zip like a stranger would (KTD8), clears Gatekeeper and the
# Calendar permission prompt, and proves the menu-bar item appears, by
# screenshot and window listing only (R15, R17). Declares no fixtures.
#
# BLACK BOX ON PURPOSE: v0.1.0 has no journal hook, so this never calls
# expect_event — it proves the app is up by AX-level process/status-item
# presence (wait_for_status_item, which itself first proves the process is
# running at all) plus screenshots for a human reviewer (R18), never by
# reading or asserting on menu copy or layout (R17).
#
# Whether Gatekeeper prompted at all is recorded (a screenshot when it
# does, a log line either way), never asserted: a zip with no quarantine
# attribute is a legitimate pass with no prompt at all (U4's own edge test
# case), and a real Gatekeeper refusal is caught downstream instead, by
# wait_for_status_item simply timing out — the app never got permission to
# launch — which fails the scenario with the last screenshot taken
# attached, exactly as the plan's own error test case describes.
#
# The menu necessarily comes up empty on this first run — that is the
# expected state being proved here, not something this black-box scenario
# can check by reading menu content (R17), so it is recorded as a
# screenshot of the opened, empty menu plus a finding code.
#
# WHICH code depends on what actually happened, and the distinction is not
# cosmetic. The first real stranger run (2026-09-20) showed that v0.1.0
# never asks for calendar access at all: its menu reads "MeetingHop needs
# access to your calendar to find meetings. Grant it in System Settings,
# under Privacy & Security." No prompt is ever raised, so nothing is ever
# granted. "no-calendar-accounts" would be a false report of that run —
# harness/findings.txt defines it as "calendar access was granted but
# Calendar.app has no accounts configured", and a release gate reads these
# codes. So the empty menu is reported as "no-calendar-permission-prompt"
# when no prompt came, and "no-calendar-accounts" only when one did.
#
# DELIBERATELY NOT UPDATED for the onboarding card that every launch of a
# newer build now shows. This scenario installs the shipped v0.1.0 zip,
# which has neither the card nor the journal hook, so a `click
# guidance.dismiss` here would not find a control and would fail every run
# against the asset this file is written for — the sibling scenarios drive
# that card because they install a preview build that has it. If this is
# ever pointed at a build newer than v0.1.0, expect an onboarding card in
# the top centre of both screenshots below. That is the app working, not a
# defect, and it is left alone rather than dismissed because this scenario
# drives nothing by identifier at all: adding its first `click` to prove
# something it does not test would make it fail on the one asset it is for.
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?smoke.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
. "$HARNESS_DIR/lib/scenario.sh"

BUNDLE_ID="dev.facens.meetinghop"

if [ -z "${HARNESS_ASSET:-}" ]; then
    verdict fail "no --asset was given; the stranger tier installs the v0.1.0 zip, not a local build."
fi

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

step "calendar-permission"
# 20s, not the 120s step default. On v0.1.0 this wait always expires -- the
# app never asks -- so the default spent two minutes of every run proving
# something the next branch already documents. A TCC sheet appears within a
# second or two of an app requesting access, so 20s is generous for a build
# that does ask, and a build that somehow asks later than that reports the
# honest no-calendar-permission-prompt finding rather than a false pass.
CALENDAR_WAIT="$(dialog wait calendar 20)"
CALENDAR_PROMPTED=0
if [ "$(printf '%s' "$CALENDAR_WAIT" | jq -r '.present')" = "true" ]; then
    CALENDAR_PROMPTED=1
    shot "calendar-prompt" > /dev/null
    dialog answer calendar allow > /dev/null
    log "calendar permission prompted; answered allow (the dialog helper logs which button that pressed)"
else
    # Until 2026-09-21 this was the ordinary path: the app shipped without
    # the calendar entitlement, so TCC refused to show the prompt at all.
    # With that fixed, no prompt here is a finding about the build, which is
    # what the `no-calendar-permission-prompt` code below records — this
    # scenario keeps tolerating it rather than failing, because smoke's job
    # is to report what a first run looks like, not to assert a grant.
    log "calendar permission did not prompt — since the entitlement fix this is a defect, not the normal path"
fi

step "launch"
IDIOM="$(wait_for_status_item "$BUNDLE_ID")"
log "status item present, idiom: $IDIOM"
shot "menu-bar" > /dev/null

step "empty-state"
open_status_item "$BUNDLE_ID"
shot "empty-menu" > /dev/null
if [ "$CALENDAR_PROMPTED" -eq 1 ]; then
    finding "no-calendar-accounts"
else
    finding "no-calendar-permission-prompt"
fi

verdict pass
