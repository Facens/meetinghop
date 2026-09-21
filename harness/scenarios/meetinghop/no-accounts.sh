#!/bin/bash
# HARNESS_STRANGER_ONLY: answers the Calendar permission dialog, opens the
# menu-bar popover and screenshots it — screen-driving work this harness
# confines to the stranger tier (harness/README.md, "Only the stranger tier
# drives the screen").
#
# R10/AE: a stranger installs MeetingHop on a machine with no Calendar
# accounts configured at all, answers Allow, and the app finds nothing to
# read. Stated end state (R11's vocabulary): the onboarding card comes up
# telling them MeetingHop reads Calendar.app and where a Google or Outlook
# account is added; pressing its button opens that page; and `calendar
# access` is `granted: true` while `calendars counted` is 3 —
# CalendarSource.calendarCount reads `store.calendars(for: .event).count` on
# a machine with no accounts and no local calendar ever created, which is
# exactly this fixture's own starting point: meetinghop/base turns the
# journal on and seeds nothing else, leaving the golden image's own Calendar
# state untouched.
#
# That state is NOT empty, and `count=0` (this scenario's own assertion
# before 2026-09-21) was never reachable: `store.calendars(for: .event)`
# always carries macOS's own built-in local calendars — "Calendar", "US
# Holidays" and "Birthdays" on this image — whether or not any account is
# ever added. Verified directly, not inferred: a small EventKit probe
# (MeetingHopProbe, the same `store.calendars(for: .event)` call
# `CalendarSource.calendarCount` makes) run on a fresh clone of
# first-run-golden (build 20260921063507, macOS 26.6.2) with no fixture and
# no prior Calendar.app access at all reported exactly those three, count 3.
# One consequence worth knowing rather than fixing here: since
# `calendarCount == 0` is unreachable on a stock Mac, the app's own
# `CalendarEmptyState.noCalendars` — "Calendar.app has no calendars yet" —
# is dead UI; nothing in this harness exercises it, and nothing a real user
# with a factory-fresh Mac would ever see either.
#
# THIS SCENARIO IS WHERE THE BUTTON'S URL IS ACTUALLY CHECKED. Nobody could
# press it on the maintainer's own machine (a settings window opening on
# them is the intrusion this harness exists to avoid), so what
# `MeetingHopKit.GuidanceTarget` documents about
# `x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension`
# is evidence from the system's own bundles, never an observation. Here the
# guest presses it for real and the journal says what happened:
# `fell_back=false` means the accounts page took the URL, and
# `fell_back=true` — which fails this scenario rather than passing quietly —
# means it refused and Calendar.app opened instead. The screenshot taken
# straight after is the only thing that can show *which* page landed; no
# assertion can, because System Settings accepts the scheme whatever pane
# identifier follows it (see `JournalData.guidanceAction`).
#
# Edge case (this unit's own test-scenario list): if the guest unexpectedly
# has an ACCOUNT-BACKED calendar beyond the three built-in ones, this
# scenario fails loudly rather than quietly reading as `nothing-upcoming.sh`
# (whose own fixture calendar brings the count to 4, not 3). No special-case
# code makes that true — it falls straight out of `expect_event`'s own
# contract: it matches the first journal line named `calendars counted`
# whose `count` field equals exactly `3` (harness/guest/wait.sh); a guest
# that reports anything else never produces such a line, so the wait simply
# times out and the scenario fails (exit 1) rather than the assertion below
# being reinterpreted as anything else.
set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:?no-accounts.sh must be run by harness/run.sh, which exports HARNESS_DIR.}"
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
# confirm_dialog, not dialog+expect_event: a click succeeding is not the
# same fact as the grant it was meant to produce landing in the journal —
# see confirm_dialog's own doc comment (harness/lib/scenario.sh) for the
# diagnosis. Also covers the early-return risk the old comment here named:
# if the grant itself silently failed, Coordinator.start() never calls
# calendar.start() at all, so `calendars counted` would never appear either
# — a bare `count=3` timeout further down would then misleadingly blame the
# count instead of the grant that never happened.
confirm_dialog calendar allow "calendar access" granted=true > /dev/null

# Asserted before the card is touched, deliberately. The count is written
# at the app's first fetch, seconds after the grant and well before
# anything below opens another application on this guest — ordering the
# steps the other way round would still pass (wait.sh scans the file from
# the start and would match that same early line), while reading as though
# the count had been observed on a machine that now has System Settings in
# the foreground.
#
# `count=3`, not `count=0` — see this file's own header for why zero was
# never reachable here.
step "calendars-counted"
expect_event "calendars counted" count=3 > /dev/null

# The onboarding card is unconditional: every user meets it once, whatever
# their calendar state, so it is on screen here before anything else this
# scenario cares about. `state=first_run` is what says it is the
# introduction rather than the refused-permission card this scenario's
# sibling (access-denied.sh) gets.
step "first-run-card"
expect_event "guidance shown" state=first_run > /dev/null
shot "first-run-card" > /dev/null

step "add-account"
click "$BUNDLE_ID" "guidance.action"
# `fell_back=false` is the real assertion: it fails loudly if the accounts
# page would not open and Calendar.app was opened instead, rather than
# reporting a pass on a button that went somewhere else. `ok=true` alone
# would be satisfied by either.
expect_event "guidance action" state=first_run target=accounts_settings source=card ok=true fell_back=false > /dev/null
shot "accounts-page" > /dev/null

# The card is answered and gone, so this is the popover's own empty state —
# `Onboarding.emptyState(accessGranted: true, calendarCount: 3,
# meetingCount: 0)`, which is `.noMeetings` ("Nothing else today"), not
# `.noCalendars` ("Calendar.app has no calendars yet"): `calendarCount` is
# never 0 here (see this file's own header), so `.noCalendars` cannot be the
# state a real "no accounts" machine ever shows, and this screenshot is what
# proves it rather than asserting it. Captured, never asserted on — R17
# allows reading UI content only as a screenshot.
step "menu-bar"
open_status_item "$BUNDLE_ID"
shot "no-accounts-menu" > /dev/null

finding "no-calendar-accounts"

verdict pass
