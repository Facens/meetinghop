#!/bin/bash
# HARNESS_STRANGER_ONLY: toggles a Settings control, opens the menu-bar
# popover and Settings window, and screenshots both by AXIdentifier —
# screen-driving work this harness confines to the stranger tier
# (harness/README.md, "Only the stranger tier drives the screen"). Also the
# one scenario in this unit that reboots the guest itself, which only makes
# sense on a disposable stranger-tier clone.
#
# R10/AE5, proven on the notarized build only (R10's own wording): with
# launch-at-login toggled on, a guest reboot and auto-login leaves
# MeetingHop running, its launch-at-login toggle still reading on, and no
# fresh Calendar prompt. This is the one MeetingHop scenario that needs a
# stable code identity across a relaunch it did not itself build — an
# ad-hoc build's signature is not stable across relaunches, so its Calendar
# grant and its SMAppService registration would not survive one either
# (docs/releasing.md, "What a contributor without the certificate gets") —
# which is exactly why R10 restricts this scenario to the notarized build,
# not this file's own doing.
#
# Stated end state (R11's vocabulary): after the reboot, the app's own
# status item is present again (`wait_for_status_item`, which itself first
# proves the process is running at all); the harness journal — the same
# file, continued rather than recreated, at the same path `journal_at`
# named before the reboot — carries a second `harness started` line with
# `boot: 2` (`Journal.bootCount`, Sources/MeetingHopKit/Harness/Journal.swift,
# bumped by `continueFromExistingContent` whenever an existing journal is
# reopened rather than created fresh); and no Calendar permission dialog is
# on screen (`dialog wait calendar` with a short bound, `present: false`).
# Whether the launch-at-login toggle still reads on is judged the only way
# R17 allows reading UI state at all: a screenshot of Settings before the
# reboot and another after, for a human to compare — never asserted in
# code, because nothing in the journal or the AXIdentifier surface exposes
# a toggle's own boolean value to read back.
#
# This scenario also carries the onboarding card's no-nag proof, because it
# is the only one that relaunches the app at all. Before the reboot the card
# appears and is dismissed (`guidance shown` then `guidance dismissed`);
# after it, the app writes `guidance suppressed` with `reason=already_seen`
# instead of showing anything.
#
# That is asserted as a positive on purpose. `harness/guest/wait.sh` matches
# the presence of a line and has no way to wait for the absence of one, so
# "the card did not come back" is not directly assertable at all — which is
# exactly why the app journals the suppression rather than staying silent
# about it. It also sidesteps the first-match trap this header warns about
# just below: the pre-reboot launch *showed* the card rather than
# suppressing it, so the first `guidance suppressed` line anywhere in the
# file can only have been written after the reboot.
#
# What that proves, in turn, is the whole persistence claim: the dismissal
# was written to the same `UserDefaults` domain a plain Finder launch reads
# (KTD4 — no `-MeetingHopDefaultsSuite` argument reaches an app opened by
# harness/guest/install.sh, so `AppIdentity.activeDefaults()` is `.standard`
# here), and it survived a real reboot rather than living in memory.
#
# Deliberately NOT re-asserted after the reboot: `calendar access`.
# `harness/guest/wait.sh` matches the *first* journal line satisfying its
# criteria across the whole file, not the newest one, and this scenario
# already wrote one `calendar access granted=true` line before ever
# scheduling the reboot (below) — re-running the identical `expect_event`
# afterwards would match that same old line instantly and prove nothing
# about what happened post-reboot. The live `dialog wait calendar` probe
# below is what actually answers "did a fresh prompt appear", which is what
# AE5 asks; `harness started boot=2` is what answers "did the journal (and
# so the app) really continue across the reboot, not restart from
# scratch". Together they are the honest pair of facts this scenario can
# prove; a redundant, misleading expect_event is not added just because
# the event name matches R10's own wording.
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?launch-at-login-reboot.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
. "$HARNESS_DIR/lib/scenario.sh"
. "$HARNESS_DIR/fixtures/meetinghop/_lib.sh"

BUNDLE_ID="$MEETINGHOP_BUNDLE_ID"

if [ -z "${HARNESS_ASSET:-}" ]; then
    verdict fail "no --asset was given; the stranger tier installs a Developer ID preview build, not a local build. R10 further requires the notarized build for this scenario specifically."
fi

# The guest-side path to harness/guest/reboot.sh, mirroring
# harness/lib/scenario.sh's own two-transport split (its private
# _scenario_guest_path) without reaching into that file's underscore-
# prefixed internals: this scenario owns its own reboot handling (see this
# file's header) using only the public, documented surface
# harness/README.md's "Writing a scenario" table lists —
# $HARNESS_GUEST_TRANSPORT, $HARNESS_DIR and $HARNESS_GUEST_HOME among
# them — plus harness/lib/vm.sh's own guest_run/vm_wait_ssh, which
# scenario.sh already sources.
_reboot_script_path() {
    if [ "$HARNESS_GUEST_TRANSPORT" = "local" ]; then
        printf '%s/guest/reboot.sh' "$HARNESS_DIR"
    else
        printf '~/%s/guest/reboot.sh' "$HARNESS_GUEST_HOME"
    fi
}

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

step "launch"
wait_for_status_item "$BUNDLE_ID" > /dev/null
journal_at "$BUNDLE_ID" "$MEETINGHOP_JOURNAL_LEAF"
expect_event "harness started" boot=1 > /dev/null

step "calendar-permission"
CALENDAR_WAIT="$(dialog wait calendar)"
if [ "$(printf '%s' "$CALENDAR_WAIT" | jq -r '.present')" = "true" ]; then
    shot "calendar-prompt" > /dev/null
    dialog answer calendar allow > /dev/null
    log "calendar permission prompted; answered allow (the dialog helper logs which button that pressed)"
else
    log "calendar permission did not prompt"
fi
expect_event "calendar access" granted=true > /dev/null

# Answered before the Settings window is opened: the onboarding card sits at
# the top centre of the screen and would otherwise be in every screenshot
# this scenario asks a human to compare.
step "dismiss-first-run-card"
expect_event "guidance shown" state=first_run > /dev/null
click "$BUNDLE_ID" "guidance.dismiss"
expect_event "guidance dismissed" state=first_run > /dev/null

step "open-settings"
open_status_item "$BUNDLE_ID"
click "$BUNDLE_ID" "menuBar.settings"
shot "settings-before-toggle" > /dev/null

step "toggle-launch-at-login"
click "$BUNDLE_ID" "settings.launchAtLoginToggle"
shot "settings-toggled-on" > /dev/null

step "reboot"
REBOOT_CMD="bash $(_reboot_script_path)"
if ! bounded_run 30 guest_run "$HARNESS_GUEST_IP" "$REBOOT_CMD" > /dev/null 2>&1; then
    warn "reboot: could not reach the guest to schedule the restart."
    exit 3
fi
log "reboot scheduled; waiting for the guest to go down"

# Phase 1: wait for the guest to actually go down, proving the reboot really
# started rather than this ssh round-trip racing ahead of it — a `guest_run
# ... true` that happens to succeed against a session the shutdown has not
# yet torn down would otherwise look identical to "already back up".
DOWN_BOUND_SECS=90
DOWN_DEADLINE=$(( $(date +%s) + DOWN_BOUND_SECS ))
while guest_run "$HARNESS_GUEST_IP" true > /dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$DOWN_DEADLINE" ]; then
        warn "reboot: the guest never went down within ${DOWN_BOUND_SECS}s of the reboot being scheduled."
        exit 3
    fi
    sleep 2
done
log "guest is down; waiting for it to come back"

# Phase 2: wait for a guest shell to answer again — on the golden image's
# automation user, the same proof of "auto-login happened" that
# harness/lib/vm.sh's own vm_wait_ssh already uses while first provisioning
# a clone, reused here at its own (generous) default bound rather than
# $HARNESS_STEP_TIMEOUT: nothing external enforces the step bound as a
# watchdog (harness/README.md: only the per-scenario and per-run bounds
# are), so there is no reason to make a reboot-and-reconnect fit inside a
# number sized for a single AX click.
UP_BOUND_SECS="${HARNESS_SSH_TIMEOUT:-300}"
if ! vm_wait_ssh "$HARNESS_GUEST_IP" "$UP_BOUND_SECS"; then
    warn "reboot: the guest did not come back within ${UP_BOUND_SECS}s."
    exit 3
fi
log "guest is back; waiting for auto-login and the app to relaunch"

step "post-reboot-launch"
wait_for_status_item "$BUNDLE_ID" > /dev/null

step "harness-continuity"
expect_event "harness started" boot=2 > /dev/null

# The no-nag rule, across a real relaunch. The first `guidance suppressed`
# line in this journal can only be post-reboot: the pre-reboot launch wrote
# `guidance shown` instead (see this file's header on why the negative is
# asserted as this positive, and why first-match semantics are safe here).
step "no-second-first-run-card"
expect_event "guidance suppressed" state=first_run reason=already_seen > /dev/null

step "no-new-calendar-prompt"
POST_CAL_WAIT="$(dialog wait calendar 10)"
if [ "$(printf '%s' "$POST_CAL_WAIT" | jq -r '.present')" = "true" ]; then
    shot "unexpected-calendar-prompt" > /dev/null
    verdict fail "a Calendar permission prompt reappeared after the reboot; AE5 requires the grant to survive it."
fi
log "no calendar prompt reappeared after the reboot"

step "post-reboot-settings"
open_status_item "$BUNDLE_ID"
click "$BUNDLE_ID" "menuBar.settings"
shot "settings-after-reboot" > /dev/null

verdict pass
