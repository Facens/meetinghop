# Contributing to MeetingHop

Small project, one maintainer, short rules.

## Licence, and why a pull request needs a grant

MeetingHop is released under the **MIT licence** (see [LICENSE](LICENSE)), and
that stays true: what is published here stays MIT, and nothing below takes back
a right that licence already gives you.

A paid version of MeetingHop may exist later. If it does, it will be
**additional code that is never published**, not a relicensing of this
repository. That shape is deliberate, and it is what makes the next paragraph
necessary.

**By submitting a contribution (a pull request, a patch, code in an issue), you
grant Andrea Giannangelo a perpetual, irrevocable, worldwide, non-exclusive,
royalty-free licence to use, reproduce, modify, prepare derivative works of,
publicly display, sublicense, distribute and relicense your contribution,
including under terms different from the project's current licence, and
including commercial terms.** You keep the copyright in your contribution. You
confirm you are entitled to grant this — that the work is yours, or that your
employer has authorised it.

**You also grant, on the same terms, a patent licence** covering any patent
claim you own or control that your contribution — alone, or combined with this
project — would otherwise infringe, to make, use, sell, offer to sell, import
and otherwise transfer it.

Concretely: your contribution may end up in a paid build of MeetingHop. That is
stated here, upfront, rather than announced after the fact.

A `Signed-off-by` trailer (a DCO) would **not** carry this grant — it licenses a
patch under the project's *current* terms only. Projects that collected only a
DCO and later needed to change licence had to go back and ask every past
contributor, and some never finished. That is why the grant is a merge
precondition here from the first day rather than something added later.

The grant is enforced automatically: a bot asks you to accept it on your first
pull request, and no outside contribution is merged before that acceptance is
recorded.

## Build and test

```sh
make build     # swift build -c release
make test      # the MeetingHopKit suite
make probe     # read-only diagnostics
```

Command Line Tools plus SwiftPM is the supported toolchain, and Xcode must not
become a requirement — that's why the test target is a plain executable
instead of an XCTest bundle: neither XCTest nor swift-testing ships with
Command Line Tools.

## Keep `MeetingHopKit` free of UI

`Sources/MeetingHopKit` holds the logic that doesn't need a screen: calendar
filtering and dedup, the meeting-link parser, Zoom's window-title vocabulary
and state classification, and the scheduling rule that decides when the card
appears. No file under it may import AppKit, SwiftUI, or EventKit — that
boundary is what makes the logic testable with string and date fixtures
instead of a running Zoom and a real calendar. Before opening a pull request,
check it yourself:

```sh
grep -rlE '^import (AppKit|SwiftUI|EventKit)' Sources/MeetingHopKit
```

An empty result is a pass. CI runs the same check on every push and pull
request through `packaging/check-source.sh`, which also refuses a Sparkle
dependency on the Kit target in `Package.swift`; running it yourself first
just saves a round trip.

The app target (`Sources/MeetingHop`) is where AppKit, SwiftUI, and EventKit
belong — it's verified by running it, not by the test suite.

## Accessibility identifiers are part of a control's contract

Not incidental UI detail (KTD9). The black-box test harness drives the
built app by `AXIdentifier` — never by coordinate, never by title — so
every control a scenario clicks carries a stable identifier from the one
builder in `Sources/MeetingHopKit/Support/AccessibilityID.swift`. Renaming
or removing one is a harness-facing change, on purpose: it should be as
deliberate as changing a public API. A dynamic identifier never embeds a
raw calendar title, a filesystem path, or any other user-supplied free
text — hash it instead, the way the builders already do — because an
`AXIdentifier` sits in the same accessibility tree a screen reader walks,
and a leaked automation log can capture it wholesale.

One deliberate departure: a meeting row keys on a hash of the meeting's
*id*, not its title. Two meetings can share a title — a recurring
one-to-one happening twice in the same day is the ordinary case, not an
edge one — and the harness's identifier lookup returns the first match it
walks to, so a title-keyed row would silently send a scenario aimed at the
second meeting to the first. The journal still hashes the title separately,
where it records what was shown on screen — a different field answering a
different question.

## Commit messages

Conventional commits, scoped to match the module split:

- `feat(kit)`, `fix(kit)`, `test(kit)` — `MeetingHopKit`
- `feat(app)`, `fix(app)` — `Sources/MeetingHop`
- `docs` — README, this file, anything under `docs/`
- `chore(release)` — packaging, CI, and release-workflow changes

Write a body that explains the decision, not one that restates the diff — if
the subject line already says what changed, the body's job is to say why.
