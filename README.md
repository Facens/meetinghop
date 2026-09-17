# MeetingHop

A macOS menu-bar app that watches your calendars for the next event with a
joinable link and, a couple of minutes before it matters, puts a floating card
at the top of the screen: a rose countdown dial, the meeting name, and one
button.

```
┌─────────────────────────────┐
│  ◔ 02:14                     │   rose countdown dial
│  Sprint planning             │   the meeting name
│                     Join  ✕  │   one button, and a close
└─────────────────────────────┘
```

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
  that, and is not available to build against — the team.blue Marketplace
  shows "Request to add" rather than a way to self-install one.
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

Early. The overlay, the calendar reading, the link parsing, and the Zoom state
reading are working; the test suite covering them is being built out alongside
this restructure. Packaging, CI, and the release pipeline exist; no version
has shipped yet.

## Licence

MIT. See [LICENSE](LICENSE).
