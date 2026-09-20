#!/bin/bash
# Guest-side plumbing every MeetingHop fixture's apply.sh shares — turning on
# the journal hook, and the state-file convention `harness/fixtures/meetinghop/
# calendar/apply.sh` uses to report back a value (a seeded event's identifier)
# the host-side scenario cannot compute for itself. NOT harness/lib/fixtures.sh
# — that file is shared byte-for-byte with AgentMenu (harness/SHARED.sha256)
# and may carry no MeetingHop knowledge at all, while this one is free to,
# because it lives under harness/fixtures/, which is never shared and IS
# copied into the guest whole (harness/run.sh's copy_in_guest_tree copies
# harness/fixtures/ recursively, unlike harness/lib/, which never reaches the
# guest on the stranger tier — see harness/lib/fixtures.sh's own header).
#
# This file is sourced twice, by design: guest-side, by every apply.sh under
# this directory (`"$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"`), where the
# functions below actually run; and host-side, by every one of R10's five
# scenarios, purely to share the two constants below rather than each
# scenario carrying its own copy of the bundle id and the journal leaf name
# that could drift out of sync with what a fixture actually writes. Sourcing
# this on the host is safe precisely because the file carries no top-level
# executable statement — only constants and function *definitions* — so a
# scenario that sources it never calls `defaults write` itself; only an
# apply.sh, actually executing in the guest, ever does (this checkout's own
# ground rule: `defaults write` resolves through the OS user record, not a
# `$HOME` override, so nothing here may risk running it against a real,
# logged-in Mac).
#
# Every value here is synthetic by construction: no path below ever spells
# the maintainer's own username or home directory, only $HOME as the guest
# itself resolves it at apply time. Tests/MeetingHopKitTests/HarnessFixtureTests.swift
# greps this whole tree for both and expects neither.
set -euo pipefail

MEETINGHOP_BUNDLE_ID="dev.facens.meetinghop"

# The leaf name every MeetingHop fixture writes into the `harnessJournal`
# default (below) and every scenario passes to `journal_at` — one constant,
# so the two can never name two different files.
MEETINGHOP_JOURNAL_LEAF="run.ndjson"

# Where `harness/fixtures/meetinghop/calendar/apply.sh` persists a value it
# computed in the guest and a host-side scenario cannot predict on its own —
# the seeded event's Calendar-scripting `uid`, which
# `harness/scenarios/meetinghop/meeting-in-three.sh` reads back and hashes
# with `harness/lib/fixtures.sh`'s own `fixtures_path_hash` (see that
# fixture's own apply.sh and harness/fixtures/meetinghop/seed-calendar.applescript
# for why this has to be reported rather than computed host-side, and what
# is still unverified about it).
MEETINGHOP_STATE_LEAF=".meetinghop-harness-state"

# fx_activate_journal <nonce>
#
# KTD3/KTD4: on a real Finder launch (how harness/guest/install.sh's own
# `open` starts the app on the stranger tier — no `-MeetingHopDefaultsSuite`
# argument ever reaches it, so `AppIdentity.activeDefaults()` resolves to
# `.standard`, the ordinary, non-isolated domain), the journal hook is a
# *separate*, ungated mechanism: `Journal.activate` reads the `harnessJournal`
# key straight out of the active `UserDefaults` domain
# (`Sources/MeetingHopKit/Harness/Journal.swift`), which is exactly the
# domain `defaults write` edits. Writing both keys here, before the app is
# ever installed or opened, is what turns the journal on for a scenario that
# never passes a launch argument at all — skip this and every `expect_event`
# in every scenario times out identically, for a reason none of them would
# explain.
fx_activate_journal() {
    local nonce="${1:?fx_activate_journal requires the run nonce.}"
    defaults write "$MEETINGHOP_BUNDLE_ID" harnessJournal -string "$MEETINGHOP_JOURNAL_LEAF"
    defaults write "$MEETINGHOP_BUNDLE_ID" harnessNonce -string "$nonce"
}

# fx_write_state <key> <value>
#
# GUEST-SIDE ONLY: persists <value> under a leaf named <key>, in a directory
# under the guest's own $HOME that nothing but this fixture tree writes to
# or reads from. Called only from an apply.sh actually executing in the
# guest — never from a scenario, which reads the value back with
# `fixtures_guest_capture` and the command `fx_state_read_command` below
# builds, not by calling this function itself (a scenario runs on the host;
# this writes to the *guest's* $HOME).
fx_write_state() {
    local key="${1:?fx_write_state requires a key.}" value="${2:?fx_write_state requires a value.}"
    mkdir -p "$HOME/$MEETINGHOP_STATE_LEAF"
    printf '%s' "$value" > "$HOME/$MEETINGHOP_STATE_LEAF/$key"
}

# fx_state_read_command <key>
#
# HOST-SIDE: the shell snippet a scenario hands to `harness/lib/fixtures.sh`'s
# `fixtures_guest_capture` to read back a value `fx_write_state` wrote. The
# `$HOME` in the returned string is deliberately left unexpanded here — it is
# meant to be expanded by the *guest's* own shell, the same way
# `fixtures_guest_home` in harness/lib/fixtures.sh leaves it for the guest to
# resolve, not this (host) process, whose own $HOME is a different machine
# entirely on the stranger tier.
fx_state_read_command() {
    local key="${1:?fx_state_read_command requires a key.}"
    printf 'cat "$HOME/%s/%s"' "$MEETINGHOP_STATE_LEAF" "$key"
}
