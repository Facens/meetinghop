#!/bin/bash
# fixture meetinghop/base <nonce>
#
# The baseline every calendar-agnostic R10 scenario builds on: turns the
# journal on and nothing else — no calendar, no account, no event. Used by
# `access-denied.sh` (permission is refused before any calendar would
# matter), `no-accounts.sh` (which needs the golden image's own, genuinely
# zero, calendar count untouched), and `launch-at-login-reboot.sh` (which
# grants access during the run itself and cares about the toggle and the
# reboot, not what the calendar holds).
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

NONCE="${1:?the base fixture requires the run nonce as its first argument.}"

fx_activate_journal "$NONCE"
