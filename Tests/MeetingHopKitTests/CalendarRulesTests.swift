import Foundation
import MeetingHopKit

/// U3/R4: the calendar filtering and dedup rules extracted into
/// `CalendarRules` and `Array<UpcomingMeeting>.deduplicatedMeetings()` — pure
/// functions over plain values, no EventKit.
///
/// One scenario from the plan is not expressed here: "an all-day event is
/// excluded even when its body carries a join link." That filter
/// (`guard !event.isAllDay else { return nil }`) lives only in the app
/// target's `CalendarSource.fetch` (and `MeetingHopProbe/main.swift`) — it
/// reads `EKEvent.isAllDay` directly and was never extracted into
/// `CalendarRules`, which has no `isAllDay` parameter. There is no pure
/// function in `MeetingHopKit` to drive with a fixture, and `EKEvent` has no
/// public initializer to construct a fixture with in this target's
/// dependency (`MeetingHopKit` only, no EventKit). See the report for
/// details.
func runCalendarRulesTests(_ t: TestRunner) {
    t.suite("CalendarRules")

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(30 * 60)

    func zoomLink(_ meetingID: String) -> MeetingLink {
        MeetingLink(
            provider: .zoom,
            url: URL(string: "https://zoom.us/j/\(meetingID)")!,
            appURL: nil,
            meetingID: meetingID,
            password: nil
        )
    }

    // MARK: - Dedup: same id, same start -> collapses

    do {
        let link = zoomLink("1234567890")
        // Different UpcomingMeeting.id (as if synced into two local
        // calendars) is the real shape this collapses: dedup keys on
        // `link.meetingID`, not on `UpcomingMeeting.id`.
        let a = UpcomingMeeting(id: "cal1-evtA", title: "Standup", start: start, end: end, link: link)
        let b = UpcomingMeeting(id: "cal2-evtA", title: "Standup (synced copy)", start: start, end: end, link: link)
        let deduped = [a, b].deduplicatedMeetings()
        t.expectEqual(deduped.count, 1, "same meeting id and start time collapse to one")
    }

    do {
        let link = zoomLink("1234567890")
        let a = UpcomingMeeting(id: "cal1-evtA", title: "Standup", start: start, end: end, link: link)
        let laterStart = start.addingTimeInterval(3600)
        let c = UpcomingMeeting(id: "cal1-evtB", title: "Standup (next week)", start: laterStart, end: laterStart.addingTimeInterval(1800), link: link)
        let deduped = [a, c].deduplicatedMeetings()
        t.expectEqual(deduped.count, 2, "same meeting id at a different start time does not collapse")
    }

    // MARK: - Dedup fallback: no meetingID (e.g. Teams) keys on the URL instead

    do {
        let teamsLink = MeetingLink(
            provider: .teams,
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xxx%40thread.v2/0")!,
            appURL: nil,
            meetingID: nil,
            password: nil
        )
        let a = UpcomingMeeting(id: "cal1-evtT", title: "Sync", start: start, end: end, link: teamsLink)
        let b = UpcomingMeeting(id: "cal2-evtT", title: "Sync (synced copy)", start: start, end: end, link: teamsLink)
        let deduped = [a, b].deduplicatedMeetings()
        t.expectEqual(deduped.count, 1, "same url and start time collapse to one when meetingID is nil")
    }

    // MARK: - Declined-title prefixes, every locale the code lists

    for prefix in CalendarRules.declinedTitlePrefixes {
        let title = prefix.capitalized + " Weekly Sync"
        let included = CalendarRules.selfParticipationIsNotDeclined(
            title: title, isCancelled: false, currentUserDeclined: nil
        )
        t.expect(!included, "a title prefixed '\(prefix)' is excluded")
    }

    t.expect(
        !CalendarRules.selfParticipationIsNotDeclined(
            title: "  Declined: Weekly Sync", isCancelled: false, currentUserDeclined: nil
        ),
        "a declined-prefix title with leading whitespace is still excluded"
    )

    t.expect(
        CalendarRules.selfParticipationIsNotDeclined(
            title: "Weekly Sync", isCancelled: false, currentUserDeclined: nil
        ),
        "a plain title with no attendee record is included"
    )

    // MARK: - Attendee status

    t.expect(
        !CalendarRules.selfParticipationIsNotDeclined(
            title: "Weekly Sync", isCancelled: false, currentUserDeclined: true
        ),
        "an attendee record marked declined is excluded"
    )
    t.expect(
        CalendarRules.selfParticipationIsNotDeclined(
            title: "Weekly Sync", isCancelled: false, currentUserDeclined: false
        ),
        "an attendee record explicitly not declined is included"
    )

    // MARK: - Cancelled events

    t.expect(
        !CalendarRules.selfParticipationIsNotDeclined(
            title: "Weekly Sync", isCancelled: true, currentUserDeclined: nil
        ),
        "a cancelled event is excluded"
    )
    t.expect(
        !CalendarRules.selfParticipationIsNotDeclined(
            title: "Weekly Sync", isCancelled: true, currentUserDeclined: false
        ),
        "cancellation excludes an event even when the attendee record says not declined"
    )
}

/// The all-day exclusion now lives in the Kit alongside the other calendar
/// rules, so it can be pinned here instead of only existing inside the
/// EventKit reader.
func runAllDayRuleTests(_ t: TestRunner) {
    t.suite("AllDayRule")
    let now = Date()
    let later = now.addingTimeInterval(3600)

    t.expect(
        CalendarRules.isJoinable(isAllDay: false, end: later, now: now),
        "a timed meeting that has not ended is joinable"
    )
    t.expect(
        !CalendarRules.isJoinable(isAllDay: true, end: later, now: now),
        "an all-day entry is never joinable, however much time is left on it"
    )
    t.expect(
        !CalendarRules.isJoinable(isAllDay: false, end: now.addingTimeInterval(-1), now: now),
        "a meeting that has already ended is not joinable"
    )
}
