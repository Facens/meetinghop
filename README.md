# MeetingHop

A macOS menu-bar app that watches your calendars for the next event with a
joinable link and, a couple of minutes before it matters, puts a floating card
at the top of the screen: a rose countdown dial, the meeting name, and one
button.

<p align="center">
  <img src="assets/screenshots/card.png" width="440" alt="The MeetingHop card: a rose countdown dial reading 2 min, the meeting name Sprint planning with its service and start time under it, a Join button, and a close button">
</p>

## What it does

- **The card is sticky.** It does not time out, does not swap itself for a
  different meeting because a later tick preferred one, and does not vanish
  because the meeting started while you were looking at something else. Only
  the close button or joining clears it.
- **Closing it does not delete the reminder.** The menu-bar item becomes a
  filled rose pill counting down to the meeting's start. Clicking it opens a
  popover listing what is coming, each row joinable on its own.
- **It suppresses itself while you are screen sharing.** Concealing it is not
  the same as dismissing it — it comes back the moment the share ends, still
  offering the same meeting.
- **It does not leave your current meeting.** MeetingHop fires the next
  meeting's native deep link and lets Zoom's own prompt ask whether to leave
  the one you're in. Driving that leave step through the Accessibility API was
  built, then deleted: matching a confirmation button by its title is
  guesswork in every locale, and being wrong ends somebody else's meeting
  instead of yours. A Zoom App built on the official SDK would sidestep all of
  that, and is not available to build against: on a managed workspace the Zoom
  Marketplace shows "Request to add" rather than a way to self-install one.
- **It uses no Accessibility permission at all.** It once read Zoom's window
  titles to decide whether the button should say Join or Leave & Join, which
  was the only thing that surface bought and was a label rather than a
  behaviour — the button does the same thing either way. The one fact it still
  needs about Zoom is whether you are presenting, so the card can take itself
  off screen, and that is read from window owner names, which carry no
  permission requirement.

## Supported services

Zoom, Google Meet, Microsoft Teams, and Webex links are found and offered.
You might expect all four to jump the same way; only Zoom does — it's the only
one of the four with a native deep link MeetingHop can fire. The rest open in
the browser.

## Permissions

Calendars, full access. That's the only permission MeetingHop asks for —
finding your next joinable meeting is the whole job, and reading it needs
nothing else.

## Install

Download `MeetingHop-<version>.zip` from the
[Releases page](https://github.com/Facens/meetinghop/releases), unzip it, and
move `MeetingHop.app` to `/Applications`. It's signed with a Developer ID and
notarized, so it opens with no warning.

**Apple Silicon only.** The build is arm64 and does not run on an Intel Mac.

**Betas.** A release marked Pre-release on the Releases page is a beta: built,
signed, and notarized the same way as a final release, just published first
so people can try it before it ships to everyone. It's published on the beta
update channel and gets superseded once the matching final release lands. If
you want to try one early, turn on **Receive beta updates** in Settings and a
released copy will offer it to you; installing it by hand works too.

## Build from source

**Xcode is not required.** Command Line Tools plus SwiftPM is the whole
toolchain — there is no Xcode project.

```sh
make build     # swift build -c release
make test      # the MeetingHopKit suite
make probe     # read-only diagnostics: whether Zoom is running and sharing,
               # and the joinable meetings MeetingHop can see right now
```

`make bundle` assembles `MeetingHop.app`, generates its icon, and signs it —
with a Developer ID when that certificate is in the keychain running the
build (normally only the maintainer's machine), ad-hoc otherwise. An ad-hoc
build only runs on the machine that built it: it re-asks for Calendar access
after every rebuild, and its launch-at-login toggle won't hold, because
`SMAppService` refuses to register an ad-hoc build. See
[docs/releasing.md](docs/releasing.md) for the release pipeline built on top
of it.

## Status

Early, but shipping. `v0.2.0` is on the
[Releases page](https://github.com/Facens/meetinghop/releases) — Developer ID
signed, notarized and stapled. The overlay, the calendar reading, the link
parsing and the Zoom state reading all work, and the suite covering them runs
on every push and again before every release.

**It updates itself.** `v0.2.0` carries Sparkle: a copy checks the release
feed on its own, offers what it finds, and Settings holds the switches —
whether to check automatically, and whether to receive betas. Two things that
do not update themselves, both deliberately: a copy built locally with
`make bundle`, which is on the alpha channel and is replaced by the next
`make bundle`, and `v0.1.0`, which shipped before any of this existed and has
to be replaced by hand once.

## Test surface

A release is exercised on a clean machine before it ships, by a script that
clicks the app rather than calling into it. A script cannot see what the app
decided, only what it drew — so the app can be asked, at launch, to keep a
journal of what it detected, what it is showing and what you chose. It is a
read-only record: it performs no action and changes nothing about how the app
behaves.

**It is off, and only you can turn it on.** There is one switch, a preference
key, and it names a file:

```sh
defaults write dev.facens.meetinghop harnessJournal journal.ndjson   # on
defaults delete dev.facens.meetinghop harnessJournal                 # off
```

The value is a **file name, not a path**. MeetingHop writes it in one fixed
place — `~/Library/Application Support/dev.facens.meetinghop/harness/` — and a
value containing `/` or `..` is refused outright: nothing is written anywhere,
and one line in the app's log is the only trace. The file is created at mode
0600, is never written through a symbolic link, and is only ever appended to.

Each line is one JSON object: a sequence number, a timestamp, the schema
version, the build, and an event with its data. The events are the app's own
decisions — `calendar access`, `calendars counted`, `upcoming counted`, `menu
bar state`, `card shown`, `card concealed`, `join fired`, `dismissed` — and
the values are the ones the popover and the card were already showing you:
whether calendar access is granted, how many calendars and how many upcoming
meetings were found, whether the countdown pill is up, and whether a join
opened. **A meeting's title, its join password and its raw join URL never
appear.** A title is recorded only as a short hash, a joined meeting is
recorded as its scheme and host (`zoommtg`/`https`, `zoom.us`) plus a hash of
its id, and the password field of a meeting link is never serialized at all.

Three more things worth knowing before you switch it on:

- **It stops growing.** The journal is capped at 1 MiB; past that, the oldest
  lines are dropped to make room for the newest. A single value longer than
  512 characters is shortened, so one long error message cannot push a run's
  own history out of the file.
- **It cleans up after itself.** Launch MeetingHop with the key unset and any
  journal left in that directory is deleted. Files in there that are not
  journals are left alone.
- **It is readable by anything running as you.** The directory carries no
  secret and confinement is not the point — any process that could read it
  could also have set the key in the first place. The point is that the app
  writes nothing outside that one directory.

**Nothing listens.** There is no socket, no port and no network traffic; the
journal is a file, and the only way to read it is to read it.

**Every control this exercises carries a stable accessibility identifier.**
The harness drives the built app by `AXIdentifier` alone — never a
coordinate, never a label — so the same identifiers a screen reader would
see are also what the script clicks. They're part of the app's contract with
that script, not incidental UI detail; see
[CONTRIBUTING.md](CONTRIBUTING.md) for the rule.

**Every release carries the redacted result of a real run.** Before a
release is presented as current, this exact asset — the same zip you'd
download — is installed and driven through every scenario on a vanilla
macOS VM that never saw this machine before, and the release carries the
result: `report.public.json`, attached to it on GitHub. It holds a verdict,
a list of finding codes, the asset's SHA-256, which build of the golden
image it ran against (the macOS and Claude Code versions, and when it was
built), the scenario names, and a run id — and nothing else. No value in it
may contain a `/`, so no screenshot, no host path and no hostname ever
reaches it, and a finding is always one of a fixed, published set of codes,
never free text.

## Contributing

Pull requests are welcome, and they carry a licence grant:
[CONTRIBUTING.md](CONTRIBUTING.md) says what and why, upfront. A bot asks you
to accept it on your first pull request.

## Licence

MIT. See [LICENSE](LICENSE).

A paid version may exist later. If it does, it will be **code that is never
published**, not a relicensing of this repository — what is MIT here stays MIT.
Contributions carry a grant that permits that; it is stated upfront in
[CONTRIBUTING.md](CONTRIBUTING.md) rather than announced afterwards.
