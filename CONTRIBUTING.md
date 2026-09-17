# Contributing to MeetingHop

Small project, one maintainer, short rules.

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

## Commit messages

Conventional commits, scoped to match the module split:

- `feat(kit)`, `fix(kit)`, `test(kit)` — `MeetingHopKit`
- `feat(app)`, `fix(app)` — `Sources/MeetingHop`
- `docs` — README, this file, anything under `docs/`
- `chore(release)` — packaging, CI, and release-workflow changes

Write a body that explains the decision, not one that restates the diff — if
the subject line already says what changed, the body's job is to say why.
