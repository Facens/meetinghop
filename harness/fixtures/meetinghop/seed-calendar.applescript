(* Seeds a synthetic local calendar (and, for the "event" verb, one event in
   it) that MeetingHop's own EventKit read can see — the engine behind
   harness/fixtures/meetinghop/calendar/apply.sh, which R10's
   nothing-upcoming.sh and meeting-in-three.sh scenarios both use through
   that fixture. Runs only in the guest, invoked by that apply.sh via
   `osascript`; never called directly from a scenario or from
   harness/lib/scenario.sh.

   Usage: osascript seed-calendar.applescript <verb> [args]
     calendar <name>
        -> {"calendar":<name>}
        Ensures a local calendar named <name> exists, creating it if this is
        the first call to ask for it this run. Idempotent: a second call
        with the same name is a no-op, not an error — a scenario that
        (re)applies this fixture more than once against one guest never
        fails on "a calendar named X already exists".
     event <calendar> <title> <start-epoch-seconds> <duration-minutes> <location>
        -> {"calendar":<calendar>,"title":<title>,"start":"<ISO8601 UTC>","uid":<uid>}
        Creates one event in <calendar>. <start-epoch-seconds> is a Unix
        timestamp (an integer, UTC) rather than a formatted date string:
        AppleScript's own date literals and `date "..."` parsing are
        locale-dependent, and that is exactly the fragility a fixture two
        scenarios depend on for a predictable start time must not carry.
     probe
        -> {"calendars":[<name>,...]}
        Every calendar this Calendar.app can currently see — for a human
        debugging a failure on the first real boot, never called by a
        scenario or a fixture.

   Unlike harness/guest/ax.applescript and harness/guest/dialogs.applescript,
   this file does NOT follow their "always exit 0, report a JSON kind on
   error" convention. That convention exists so harness/lib/scenario.sh's
   own `_scenario_check_kind` can tell a real absence from a driver failure
   through osascript's stdout-discard-on-nonzero-exit behaviour (see
   scenario.sh's own header, fact 1) — machinery built specifically around
   those two files being driven directly BY scenario.sh. This file is never
   driven by scenario.sh at all: it is called only from
   harness/fixtures/meetinghop/calendar/apply.sh, itself invoked by
   scenario.sh's `fixture` helper, which already fails the whole fixture
   application on any nonzero exit from apply.sh. So here, a real failure is
   left as a plain AppleScript `error`: osascript exits 1, apply.sh's own
   `set -euo pipefail` tears the fixture down immediately, and `fixture`
   reports it as a harness error — loud, at the first place something went
   wrong, never "seeded nothing" silently.

   ===== UNVERIFIED — confirm on the first real guest boot, not from memory
   (this unit's own execution note, and the same caution
   harness/guest/dialogs.applescript's own UNPINNED block already carries
   for system dialogs, applies here too): the golden image this runs
   against does not exist yet, so none of the following has been checked
   against a real, running Calendar.app —
     - that `make new calendar with properties {name:...}`, given no
       explicit calendar source or account, lands the new calendar under
       "On My Mac" on a machine with zero configured accounts — the
       precondition `nothing-upcoming.sh` and `meeting-in-three.sh` both
       need: EventKit's own `calendarCount`
       (Sources/MeetingHop/Calendar/CalendarSource.swift) must read 1, not
       0, once this has run;
     - the property names used below (`name`, `summary`, `start date`,
       `end date`, `location`, `uid`) against Calendar.app's actual
       AppleScript dictionary on the golden image's macOS version;
     - `exists calendar <name>` as an idempotency check;
     - `make new event at end of events of calendar <name> with
       properties {...}` as the right element-creation form.
   If calendar or event creation fails on first boot, or a scenario's
   `calendars counted` / `upcoming counted` reads something unexpected, this
   is the first file to open — run `osascript seed-calendar.applescript
   probe` by hand to see what Calendar.app actually has, then correct
   whatever property above does not match its real dictionary.

   One further thing this file cannot verify even in principle, from inside
   the guest: whether the `uid` it reads back off a freshly created event is
   the same string EventKit later reports as that event's own
   `eventIdentifier` — the value `Sources/MeetingHop/Calendar/CalendarSource.swift`'s
   `fetch` turns into `UpcomingMeeting.id`, and so the value
   `AccessibilityID.hash` turns into the Join button's AXIdentifier
   (`hud.join.<idHash>`) and the `join fired` journal event's
   `meeting_id_hash` (Sources/MeetingHopKit/Harness/JournalEvent.swift).
   Calendar.app's scripting dictionary has historically distinguished a
   `uid` — closer to EventKit's own `calendarItemExternalIdentifier`, meant
   to survive a resync — from EventKit's local `eventIdentifier`; the two
   are not documented anywhere to be the same string. `uid` is reported
   here because it is the only per-event identifier Calendar.app's
   scripting vocabulary exposes at all.
   harness/fixtures/meetinghop/calendar/apply.sh persists it for
   harness/scenarios/meetinghop/meeting-in-three.sh to hash with
   harness/lib/fixtures.sh's own `fixtures_path_hash` — the same algorithm
   `AccessibilityID.hash` uses — and that scenario says so again, at the
   point it uses the result: if the Join click or the `join fired`
   assertion misses on the first real run, this equivalence, not the
   hashing, is the first thing to check. *)

on run argv
    if (count of argv) < 1 then
        error "seed-calendar.applescript: a verb is required. Verbs: calendar, event, probe."
    end if
    set theVerb to item 1 of argv

    if theVerb is "probe" then
        return my verbProbe()
    end if

    if theVerb is "calendar" then
        if (count of argv) < 2 then
            error "seed-calendar.applescript: calendar requires a name."
        end if
        return my verbCalendar(item 2 of argv)
    end if

    if theVerb is "event" then
        if (count of argv) < 6 then
            error "seed-calendar.applescript: event requires <calendar> <title> <start-epoch> <duration-minutes> <location>."
        end if
        set calName to item 2 of argv
        set theTitle to item 3 of argv
        set startEpoch to (item 4 of argv) as integer
        set durationMinutes to (item 5 of argv) as integer
        set theLocation to item 6 of argv
        return my verbEvent(calName, theTitle, startEpoch, durationMinutes, theLocation)
    end if

    error "seed-calendar.applescript: unknown verb: " & theVerb & "."
end run

-- Ensures a local calendar named `calName` exists, creating it if this is
-- the first fixture call to ask for it this run.
on verbCalendar(calName)
    tell application "Calendar"
        if not (exists calendar calName) then
            make new calendar with properties {name:calName}
        end if
    end tell
    return "{\"calendar\":" & my jsonString(calName) & "}"
end verbCalendar

on verbEvent(calName, theTitle, startEpoch, durationMinutes, theLocation)
    tell application "Calendar"
        if not (exists calendar calName) then
            error "seed-calendar.applescript: calendar '" & calName & "' does not exist; call the calendar verb first."
        end if
        -- Epoch arithmetic rather than parsing a formatted date string —
        -- see this file's own header for why.
        set nowEpoch to (do shell script "date +%s") as integer
        set theStartDate to (current date) + (startEpoch - nowEpoch)
        set theEndDate to theStartDate + (durationMinutes * 60)
        set newEvent to make new event at end of events of calendar calName with properties {summary:theTitle, start date:theStartDate, end date:theEndDate, location:theLocation}
        set theUID to uid of newEvent
    end tell
    if theUID is missing value or (theUID as text) is "" then
        error "seed-calendar.applescript: the new event reported no uid."
    end if
    set startISO to do shell script "date -u -r " & startEpoch & " +%Y-%m-%dT%H:%M:%SZ"
    return "{\"calendar\":" & my jsonString(calName) & ",\"title\":" & my jsonString(theTitle) & ",\"start\":" & my jsonString(startISO) & ",\"uid\":" & my jsonString(theUID as text) & "}"
end verbEvent

on verbProbe()
    tell application "Calendar"
        set calNames to name of every calendar
    end tell
    set out to {}
    repeat with n in calNames
        set end of out to my jsonString(n as text)
    end repeat
    return "{\"calendars\":[" & my joinComma(out) & "]}"
end verbProbe

-- ===== JSON helpers, duplicated from harness/guest/dialogs.applescript —
-- this file and that one are standalone osascript targets with no shared
-- library mechanism between them; see that file's own copy. =====

on replaceText(sourceText, searchString, replacementString)
    set {tid, AppleScript's text item delimiters} to {AppleScript's text item delimiters, searchString}
    set theItems to text items of sourceText
    set AppleScript's text item delimiters to replacementString
    set resultText to theItems as text
    set AppleScript's text item delimiters to tid
    return resultText
end replaceText

on jsonEscapeString(theText)
    set theText to my replaceText(theText, "\\", "\\\\")
    set theText to my replaceText(theText, "\"", "\\\"")
    set theText to my replaceText(theText, return, "\\n")
    set theText to my replaceText(theText, linefeed, "\\n")
    set theText to my replaceText(theText, tab, "\\t")
    return theText
end jsonEscapeString

on jsonString(theText)
    if theText is missing value then return "null"
    return "\"" & my jsonEscapeString(theText as text) & "\""
end jsonString

on joinComma(theList)
    set {tid, AppleScript's text item delimiters} to {AppleScript's text item delimiters, ","}
    set out to theList as text
    set AppleScript's text item delimiters to tid
    return out
end joinComma
