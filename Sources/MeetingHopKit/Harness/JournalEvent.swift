import Foundation

/// The journal's event vocabulary (KTD3).
///
/// A closed enum rather than free strings, because a scenario waits on an
/// event by name (`harness/guest/wait.sh --event "card shown"`) and a typo in
/// a name is indistinguishable from a step that never happened — the scenario
/// simply times out, and the report blames the app. The raw values are the
/// names the plan writes, spaces and all, so the vocabulary in the plan, in a
/// scenario and in the journal are one string.
///
/// This is MeetingHop's half of KTD3's list. AgentMenu's events (`setup
/// shown`, `launch requested`, …) live in that app; the two never share a
/// process.
public enum JournalEvent: String, CaseIterable, Sendable {
    /// The first line of every run: the fixture echo and the boot counter.
    case harnessStarted = "harness started"
    case calendarAccess = "calendar access"
    case calendarsCounted = "calendars counted"
    case upcomingCounted = "upcoming counted"
    case menuBarState = "menu bar state"
    case cardShown = "card shown"
    case cardConcealed = "card concealed"
    case joinFired = "join fired"
    case dismissed = "dismissed"
    /// The onboarding guidance appeared, in one of its states.
    case guidanceShown = "guidance shown"
    /// It did not appear, and why — the no-nag rule's only provable form.
    /// `harness/guest/wait.sh` matches the presence of a line and has no way
    /// to wait for the absence of one, so "the first-run card did not come
    /// back after the reboot" is unassertable as a negative; it is asserted
    /// as this positive instead.
    case guidanceSuppressed = "guidance suppressed"
    /// Its button was pressed, and what that actually opened.
    case guidanceAction = "guidance action"
    /// It was answered without acting.
    case guidanceDismissed = "guidance dismissed"
}

/// A value a journal line can carry.
///
/// A closed set rather than `Any`, so a line is JSON by construction: there is
/// no way to hand the writer a value that serialises to something else, or to
/// nothing, half way through a run.
public enum JournalValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case list([JournalValue])
    case object([String: JournalValue])

    /// A single value is truncated at this length. The journal has a fixed
    /// size cap and drops the oldest lines to stay under it, so one unbounded
    /// string — an error message that quotes a whole file, say — would evict
    /// the run's own history to make room for itself. Long enough for any
    /// value this app hands the journal.
    public static let maximumStringLength = 512

    /// The Foundation value `JSONSerialization` accepts. Strings are truncated
    /// here rather than at each call site, so the rule holds for every payload
    /// including the ones a later unit adds.
    var jsonObject: Any {
        switch self {
        case .string(let value):
            guard value.count > Self.maximumStringLength else { return value }
            return String(value.prefix(Self.maximumStringLength - 1)) + "…"
        case .integer(let value):
            return value
        case .boolean(let value):
            return value
        case .list(let values):
            return values.map(\.jsonObject)
        case .object(let values):
            return values.mapValues(\.jsonObject)
        }
    }
}

/// Payloads whose shape is a rule rather than a convenience.
///
/// Built in the Kit rather than at `Coordinator`'s call sites, the same
/// reason AgentMenuKit's `JournalData.launchRequested` gives: the app target
/// is not linked into `Tests/MeetingHopKitTests`, the Kit is, so a rule that
/// only lives at a call site inside `Coordinator.swift` cannot be tested —
/// and the rule that matters most here, "the password and the raw join URL
/// are never serialized", is exactly the one a privacy bug would slip into
/// silently if it were only ever eyeballed.
public enum JournalData {
    /// UTC with milliseconds, matching `Journal`'s own line timestamps —
    /// kept as a second formatter rather than reaching into `Journal`'s
    /// private one, since a payload builder has no business depending on the
    /// writer's internals.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// `calendar access`: granted or denied, nothing else — EventKit hands
    /// back only a `Bool` here, and that is all R13 asks this event to carry.
    /// `calendar access`: whether EventKit granted access, plus WHY when it
    /// did not.
    ///
    /// `granted` alone was not diagnosable. A stranger run recorded
    /// `granted: false` for two different states — the user refusing the
    /// prompt, and EventKit failing before any prompt was shown — and the
    /// scenarios could not tell them apart, so a real defect read exactly
    /// like the denial that `access-denied.sh` is written to produce.
    ///
    /// `status_before` is the status the launch found, before anything was
    /// asked: `notDetermined` there and `denied` in `status` is a person
    /// refusing the prompt just now, while `denied` in both is a refusal from
    /// some earlier launch that macOS will never ask about again.
    ///
    /// `status` is EventKit's own authorization status after the request, so
    /// "notDetermined" (nothing was ever asked) is distinguishable from
    /// "denied" (asked and refused). `failure` is present only when the
    /// request threw, and carries the error's description, which names no
    /// calendar content — it is about the request, not what it would have
    /// read (KTD3).
    ///
    /// `skippedReason` is additive: present only when `Coordinator.start()`
    /// never called `requestAccess()` at all, currently just `"translocated"`
    /// (`BundleTranslocation`). `granted` stays `false` in that case too, but
    /// it is not a refusal — nobody was asked and nothing was denied — which
    /// is exactly what this field distinguishes it from, the same way
    /// `status`/`status_before` already distinguish a fresh refusal from an
    /// old one. Every existing field keeps its old meaning, so an
    /// `expect_event "calendar access" granted=…` line written before this
    /// field existed still matches exactly what it matched before.
    public static func calendarAccess(
        granted: Bool,
        status: String? = nil,
        failure: String? = nil,
        statusBefore: String? = nil,
        skippedReason: String? = nil
    ) -> [String: JournalValue] {
        var data: [String: JournalValue] = ["granted": .boolean(granted)]
        if let status { data["status"] = .string(status) }
        if let failure { data["failure"] = .string(failure) }
        if let statusBefore { data["status_before"] = .string(statusBefore) }
        if let skippedReason { data["skipped_reason"] = .string(skippedReason) }
        return data
    }

    /// `calendars counted` / `upcoming counted`: one scalar field, `count`,
    /// so `harness/guest/wait.sh --field count=0` can match either — R13
    /// names these as separate *events*, each with its own scalar, precisely
    /// so a fixture that produced zero calendars and a fixture that produced
    /// zero upcoming meetings are two different, diagnosable failures rather
    /// than one ambiguous "nothing found".
    public static func counted(_ count: Int) -> [String: JournalValue] {
        ["count": .integer(count)]
    }

    /// `menu bar state`: the authorized flag and whether a countdown pill is
    /// showing — the two facts the popover's own header and menu-bar icon
    /// already expose (R16).
    public static func menuBarState(authorized: Bool, countdown: Bool) -> [String: JournalValue] {
        ["authorized": .boolean(authorized), "countdown": .boolean(countdown)]
    }

    /// `card shown`: a hash of the leading offer's title and its start time,
    /// plus how many meetings the card is offering and whether it is urgent
    /// — `count` and `urgent` are additions beyond KTD3's literal "a hash of
    /// the title and the start time", added because R13 asks every end state
    /// a scenario asserts to carry a checkable field, and "a card is up" is
    /// not the same end state as "a card holding a double booking is up".
    ///
    /// `id_hash` is additive, added the day a scenario's own predicted click
    /// target turned out to be built on a guess that was never actually
    /// true. `AccessibilityID.HUD.join(idHash:)` — the leading offer's own
    /// Join button — is `hash(meeting.id)`, and `meeting.id` is EventKit's
    /// `eventIdentifier` (`CalendarSource.fetch`). A scenario fixture that
    /// seeds an event through Calendar's own AppleScript dictionary gets
    /// back that dictionary's `uid` instead, which reads like the same kind
    /// of identifier and is not: measured directly against the same seeded
    /// event on 2026-09-21, `uid` and `eventIdentifier` are two different
    /// strings in two different formats (Calendar's own single UUID versus
    /// EventKit's `<calendar-id>:<event-id>` pair), and nothing has ever
    /// documented them as equal — `seed-calendar.applescript`'s own header
    /// flagged exactly this as unverified from the day it was written. A
    /// scenario predicting the click target from `uid` was therefore always
    /// one hash away from the button EventKit's own identifier actually
    /// named; this field lets it stop predicting and read the real one
    /// instead. It carries only the hash, never the raw id: the hash is
    /// already public on the accessibility surface as the Join button's own
    /// `AXIdentifier` suffix (KTD9), so journaling it crosses nothing R13
    /// does not already allow past the accessibility tree.
    ///
    /// `verbose` is `AppIdentity.isVerbose()` — U8 wires the flag through
    /// (echoed on `harness started`) but leaves its enforcement (the
    /// app-fresh tier's exit 2, the gate's refusal of a report built with
    /// it) to U14, which actually drives that fixture flag from the runner.
    /// With `verbose` false — every real user launch — `title` never
    /// appears; only its hash does. `id` is never revealed even under
    /// `verbose`: nothing has asked for the raw identifier, only for the
    /// hash the button already carries.
    public static func cardShown(id: String, title: String, start: Date, count: Int, urgent: Bool, verbose: Bool) -> [String: JournalValue] {
        var data: [String: JournalValue] = [
            "id_hash": .string(AccessibilityID.hash(id)),
            "title_hash": .string(AccessibilityID.hash(title)),
            "start": .string(timestampFormatter.string(from: start)),
            "count": .integer(count),
            "urgent": .boolean(urgent),
        ]
        if verbose {
            data["title"] = .string(title)
        }
        return data
    }

    /// `card concealed`: the reason the card is off screen while still being
    /// offered — currently always `"screen_sharing"`, the only conceal path
    /// `Scheduler.decide` has, but a field rather than a fixed event name so
    /// a later reason needs no new vocabulary.
    public static func cardConcealed(reason: String) -> [String: JournalValue] {
        ["reason": .string(reason)]
    }

    /// `join fired`: scheme and host only, plus a hash of the meeting id.
    /// The meeting's password and its raw join URL — `url.absoluteString`,
    /// `url.query`, the `MeetingLink.password` field itself — are never
    /// touched here at all, which is what makes "never serialized" provable
    /// rather than asserted: this function has no parameter they could reach
    /// the journal through.
    public static func joinFired(url: URL, meetingIDHash: String, ok: Bool) -> [String: JournalValue] {
        [
            "scheme": .string(url.scheme ?? ""),
            "host": .string(url.host ?? ""),
            "meeting_id_hash": .string(meetingIDHash),
            "ok": .boolean(ok),
        ]
    }

    /// `dismissed`: how many offers the close button answered at once.
    public static func dismissed(count: Int) -> [String: JournalValue] {
        ["count": .integer(count)]
    }

    /// `guidance shown` / `guidance dismissed`: which card it was. One scalar,
    /// `state`, so `harness/guest/wait.sh --field state=first_run` can match
    /// it — the matcher flattens `data` and compares scalars, and cannot
    /// reach into an array, which is why every field these builders add is a
    /// string, an integer or a boolean and never a list.
    public static func guidance(state: GuidanceState) -> [String: JournalValue] {
        ["state": .string(state.rawValue)]
    }

    /// `guidance suppressed`: the card that stayed away, and why.
    public static func guidanceSuppressed(
        state: GuidanceState,
        reason: GuidanceSuppression
    ) -> [String: JournalValue] {
        ["state": .string(state.rawValue), "reason": .string(reason.rawValue)]
    }

    /// `guidance action`: what the button actually did.
    ///
    /// `target` is where it ended up, not where it aimed, and `fell_back`
    /// says whether the first choice refused — the pair a scenario needs to
    /// tell "System Settings opened" from "System Settings would not open and
    /// Calendar.app opened instead", neither of which is visible in a
    /// screenshot of MeetingHop.
    ///
    /// `ok` is `NSWorkspace`'s own answer and means "something accepted the
    /// URL", which is weaker than "the user is looking at the right page":
    /// `x-apple.systempreferences:` is handled by System Settings whatever
    /// the pane identifier and whatever the anchor, so a wrong one still
    /// reports success. See `GuidanceTarget`'s own UNVERIFIED note.
    public static func guidanceAction(
        state: GuidanceState,
        target: GuidanceTarget,
        source: GuidanceSource,
        ok: Bool,
        fellBack: Bool
    ) -> [String: JournalValue] {
        [
            "state": .string(state.rawValue),
            "target": .string(target.rawValue),
            "source": .string(source.rawValue),
            "ok": .boolean(ok),
            "fell_back": .boolean(fellBack),
        ]
    }
}
