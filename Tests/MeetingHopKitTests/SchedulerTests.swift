import Foundation
import MeetingHopKit

/// U8/R5/R6: `Scheduler.decide` is the rule that was rewritten to fix a real
/// bug — a meeting in progress always won the single first-match scan, so the
/// next meeting was never reached while the user was in a call (KTD7).
/// `currentMeeting` and `nextCandidate` are now two separate lookups,
/// combined only at the decision point; these tests pin that combination,
/// the sticky-card rule (KTD8), and the share-conceal rule (KTD6).
///
/// `leadMinutes` is set deliberately low (1 minute = 60s) in the
/// current-meeting-ending scenarios below so the ordinary lead-window branch
/// (`startingSoon`) cannot reach `.present` on its own — with a 5-minute
/// default lead and a next meeting only 2 minutes out, the lead-window
/// branch would already fire and the test would pass even if the whole
/// `currentEndingSoon` clause in `Scheduler.decide` were deleted. Isolating
/// the branch by fixture choice is what makes these tests actually exercise
/// KTD7 rather than the ordinary path.
func runSchedulerTests(_ t: TestRunner) {
    t.suite("Scheduler")

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func zoomMeeting(_ id: String, title: String = "Meeting", start: Date, end: Date, meetingID: String? = "0") -> UpcomingMeeting {
        let link = MeetingLink(
            provider: .zoom,
            url: URL(string: "https://zoom.us/j/\(meetingID ?? id)")!,
            appURL: nil,
            meetingID: meetingID,
            password: nil
        )
        return UpcomingMeeting(id: id, title: title, start: start, end: end, link: link)
    }

    func makeInput(
        now: Date,
        meetings: [UpcomingMeeting],
        isSharingScreen: Bool = false,
        leadMinutes: Int = 5,
        endingLeadMinutes: Int = 5,
        hideWhileSharing: Bool = true,
        dismissedIDs: Set<String> = [],
        offered: [UpcomingMeeting] = []
    ) -> SchedulerInput {
        SchedulerInput(
            now: now, meetings: meetings, isSharingScreen: isSharingScreen,
            leadMinutes: leadMinutes, endingLeadMinutes: endingLeadMinutes,
            hideWhileSharing: hideWhileSharing, dismissedIDs: dismissedIDs, offered: offered
        )
    }

    // MARK: - No handoff: next meeting is an hour away

    do {
        let current = zoomMeeting("current", start: base.addingTimeInterval(-28 * 60), end: base.addingTimeInterval(2 * 60), meetingID: "1")
        let next = zoomMeeting("next", start: base.addingTimeInterval(60 * 60), end: base.addingTimeInterval(90 * 60), meetingID: "2")
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [current, next], isSharingScreen: false, leadMinutes: 1, endingLeadMinutes: 5
        ))
        t.expectEqual(decision, .hide, "in progress ending in two minutes, next meeting an hour away — nothing offered")
    }

    // MARK: - Handoff: in progress ending in two minutes, next starts at that end time

    let handoffCurrent = zoomMeeting("current", start: base.addingTimeInterval(-28 * 60), end: base.addingTimeInterval(2 * 60), meetingID: "1")
    let handoffNext = zoomMeeting("next", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60), meetingID: "2")

    do {
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [handoffCurrent, handoffNext], isSharingScreen: false, leadMinutes: 1, endingLeadMinutes: 5
        ))
        guard case .present(let card) = decision else {
            t.expect(false, "handoff case should present a card, got \(decision)")
            return
        }
        t.expectEqual(card.items.count, 1, "one meeting in the slot means one row")
        t.expectEqual(card.items[0].meeting.id, "next", "handoff card offers the next meeting, not the one ending")
        t.expectEqual(card.headline, nil, "a single offer has no headline — its own row carries the clock")
        t.expectEqual(card.items[0].primaryLabel, "Join", "handoff card label is Leave & Join while in the current meeting")
        t.expect(card.isLeavingAnother, "handoff card is marked as leaving another meeting")
    }

    // MARK: - Same handoff case while Zoom reports sharing: conceal, not hide, not present

    do {
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [handoffCurrent, handoffNext], isSharingScreen: true,
            leadMinutes: 1, endingLeadMinutes: 5, hideWhileSharing: true
        ))
        // SchedulerDecision is Equatable with three distinct cases, so
        // pinning it to .conceal directly rules out both .hide and
        // .present(_) in the same assertion — conceal is distinguishable
        // from dismissing by construction, not just by this test's intent.
        t.expectEqual(decision, .conceal, "handoff case while sharing conceals rather than hides")
    }

    // MARK: - hideWhileSharing must actually be the gate: sharing + the flag off does not conceal

    do {
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [handoffCurrent, handoffNext], isSharingScreen: true,
            leadMinutes: 1, endingLeadMinutes: 5, hideWhileSharing: false
        ))
        t.expect(decision != .conceal, "sharing with hideWhileSharing=false does not conceal")
        guard case .present(let card) = decision else {
            t.expect(false, "expected a present when hideWhileSharing is off, got \(decision)")
            return
        }
        t.expectEqual(card.items[0].primaryLabel, "Join", "label is still Leave & Join while sharing (sharing counts as in-call)")
    }

    // MARK: - No meeting in progress, next one inside the lead window: plain Join

    do {
        let next = zoomMeeting("solo-next", start: base.addingTimeInterval(3 * 60), end: base.addingTimeInterval(33 * 60), meetingID: "3")
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [next], isSharingScreen: false, leadMinutes: 5, endingLeadMinutes: 5
        ))
        guard case .present(let card) = decision else {
            t.expect(false, "expected a present for a meeting inside the lead window, got \(decision)")
            return
        }
        t.expectEqual(card.items[0].primaryLabel, "Join", "plain join label when not currently in a call")
        t.expect(!card.isLeavingAnother, "not leaving another meeting when none is in progress")
    }

    // MARK: - Lead-window boundary: exactly at the window presents, one second past it hides

    do {
        let next = zoomMeeting("boundary-next", start: base.addingTimeInterval(5 * 60), end: base.addingTimeInterval(35 * 60), meetingID: "4")
        let atBoundary = Scheduler.decide(makeInput(now: base, meetings: [next], leadMinutes: 5))
        if case .present = atBoundary {
            t.expect(true, "exactly at the lead window boundary presents")
        } else {
            t.expect(false, "exactly at the lead window boundary should present, got \(atBoundary)")
        }

        let past = zoomMeeting("boundary-next-2", start: base.addingTimeInterval(5 * 60 + 1), end: base.addingTimeInterval(35 * 60), meetingID: "4")
        let afterBoundary = Scheduler.decide(makeInput(now: base, meetings: [past], leadMinutes: 5))
        t.expectEqual(afterBoundary, .hide, "one second past the lead window hides")
    }

    // MARK: - currentMeeting boundary: in progress at exactly start, not in progress at exactly end

    do {
        let m = zoomMeeting("cm-boundary", start: base, end: base.addingTimeInterval(30 * 60), meetingID: "5")
        t.expectEqual(Scheduler.currentMeeting(in: [m], now: base), m, "a meeting is in progress at exactly its start time")
        t.expectEqual(Scheduler.currentMeeting(in: [m], now: base.addingTimeInterval(30 * 60)), nil, "a meeting is no longer in progress at exactly its end time")
    }

    // MARK: - nextCandidate's grace window for a meeting that has started

    do {
        let justStarted = zoomMeeting("grace-inside", start: base.addingTimeInterval(-Scheduler.missedGrace), end: base.addingTimeInterval(30 * 60), meetingID: "6")
        t.expectEqual(
            Scheduler.nextCandidate(in: [justStarted], now: base, dismissedIDs: [], leadMinutes: 5),
            justStarted,
            "a meeting still inside the missed grace window is a next-candidate"
        )
        let startedEarlier = zoomMeeting("grace-outside", start: base.addingTimeInterval(-Scheduler.missedGrace - 1), end: base.addingTimeInterval(30 * 60), meetingID: "7")
        t.expectEqual(
            Scheduler.nextCandidate(in: [startedEarlier], now: base, dismissedIDs: [], leadMinutes: 5),
            nil,
            "one second past the grace window it is no longer a next-candidate"
        )
    }

    // MARK: - Stickiness: keeps offering the same meeting even when another would now score better

    do {
        let sticky = zoomMeeting("sticky", start: base.addingTimeInterval(10 * 60), end: base.addingTimeInterval(40 * 60), meetingID: "8")
        // Starts sooner than `sticky` and is inside the lead window — this is
        // what `nextCandidate` would return on a fresh scan.
        let wouldWinFresh = zoomMeeting("fresher", start: base.addingTimeInterval(60), end: base.addingTimeInterval(30 * 60 + 60), meetingID: "9")

        let firstTick = Scheduler.decide(makeInput(
            now: base, meetings: [wouldWinFresh, sticky], leadMinutes: 5, offered: [sticky]
        ))
        guard case .present(let firstCard) = firstTick else {
            t.expect(false, "expected the sticky meeting to be presented, got \(firstTick)")
            return
        }
        t.expectEqual(firstCard.items[0].meeting.id, "sticky", "a sticky offer wins over a fresher candidate that would score better")

        // Advance past the sticky meeting's own start time; it should still
        // be the one offered, unchanged, until it ends or is dismissed.
        let afterItsStart = base.addingTimeInterval(15 * 60)
        let secondTick = Scheduler.decide(makeInput(
            now: afterItsStart, meetings: [wouldWinFresh, sticky], leadMinutes: 5, offered: [sticky]
        ))
        guard case .present(let secondCard) = secondTick else {
            t.expect(false, "expected the sticky meeting still presented after its start time passed, got \(secondTick)")
            return
        }
        t.expectEqual(secondCard.items[0].meeting.id, "sticky", "stickiness survives past the offered meeting's own start time")

        // Stickiness lapses at exactly the offered meeting's end time —
        // `offered.end > now` is false there, so decide() falls through to a
        // fresh scan. Both fixture meetings have themselves ended by this
        // instant (wouldWinFresh ends at +30m, sticky at +40m, and `now` is
        // sticky's own end at +40m), so the fresh scan finds no candidate
        // either: the precise, provable outcome is `.hide`, not merely
        // "not sticky".
        let atItsEnd = sticky.end
        let thirdTick = Scheduler.decide(makeInput(
            now: atItsEnd, meetings: [wouldWinFresh, sticky], leadMinutes: 5, offered: [sticky]
        ))
        t.expectEqual(thirdTick, .hide, "stickiness lapses at exactly the offered meeting's end time, and nothing else is left to offer")
    }

    // MARK: - A dismissed meeting is not re-offered

    do {
        // (a) dismissing the currently-offered meeting breaks stickiness, and
        // the fresh scan also excludes it, so there is nothing left to show.
        let onlyCandidate = zoomMeeting("dismissed-only", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60), meetingID: "10")
        let decisionA = Scheduler.decide(makeInput(
            now: base, meetings: [onlyCandidate], leadMinutes: 5,
            dismissedIDs: ["dismissed-only"], offered: [onlyCandidate]
        ))
        t.expectEqual(decisionA, .hide, "dismissing the currently-offered meeting stops it from being re-offered")

        // (b) a meeting dismissed before ever being offered is never picked
        // up by a fresh scan either — nextCandidate filters dismissedIDs.
        let decisionB = Scheduler.decide(makeInput(
            now: base, meetings: [onlyCandidate], leadMinutes: 5,
            dismissedIDs: ["dismissed-only"], offered: []
        ))
        t.expectEqual(decisionB, .hide, "a dismissed meeting is never freshly offered either")
    }

    // MARK: - The menu-bar pill

    do {
        let watched = zoomMeeting("pill-watched", start: base.addingTimeInterval(3 * 60), end: base.addingTimeInterval(33 * 60), meetingID: "11")
        let pill = Scheduler.pill(in: [watched], leadMinutes: 5, now: base)
        t.expectEqual(pill, Scheduler.Pill(text: "3 min", urgent: false), "the pill is present for a meeting whose card was dismissed and has not started")
    }
    do {
        // A meeting the user never answered does not stop mattering when the
        // clock reaches its start — that is the moment they are late for it.
        let watched = zoomMeeting("pill-starts", start: base, end: base.addingTimeInterval(30 * 60), meetingID: "12")
        let atStart = Scheduler.pill(in: [watched], leadMinutes: 5, now: base)
        t.expectEqual(atStart, Scheduler.Pill(text: "now", urgent: true, started: true), "the pill reads \"now\" for an unanswered meeting that has started")

        let justBefore = Scheduler.pill(in: [watched], leadMinutes: 5, now: base.addingTimeInterval(-1))
        t.expect(justBefore != nil, "the pill is still present one second before start")

        // Bounded: the pill is a reminder, not a permanent badge. The
        // menu-bar list keeps the meeting for the rest of its run.
        let inGrace = base.addingTimeInterval(Scheduler.missedGrace)
        t.expect(
            Scheduler.pill(in: [watched], leadMinutes: 5, now: inGrace) != nil,
            "the pill survives to exactly the end of the missed-meeting grace window"
        )
        let pastGrace = base.addingTimeInterval(Scheduler.missedGrace + 1)
        t.expectEqual(
            Scheduler.pill(in: [watched], leadMinutes: 5, now: pastGrace), nil,
            "the pill gives up one second past the grace window"
        )
    }
    do {
        // Answered and in progress: the user is in it, so there is nothing to
        // remind them of.
        let joined = zoomMeeting("pill-joined", start: base.addingTimeInterval(-3 * 60), end: base.addingTimeInterval(27 * 60), meetingID: "13")
        let pillForJoined = Scheduler.pill(in: [joined], leadMinutes: 5, now: base, dismissedIDs: ["pill-joined"]
        )
        t.expectEqual(pillForJoined, nil, "the pill never watches a meeting the user has answered and is in")

        // Answered before it started is the ordinary dismissed card: the
        // countdown survives, because closing the card quietens the reminder
        // rather than deleting it.
        let dismissedAhead = zoomMeeting("pill-dismissed-ahead", start: base.addingTimeInterval(3 * 60), end: base.addingTimeInterval(33 * 60), meetingID: "17")
        let stillCounting = Scheduler.pill(in: [dismissedAhead], leadMinutes: 5, now: base, dismissedIDs: ["pill-dismissed-ahead"]
        )
        t.expectEqual(stillCounting, Scheduler.Pill(text: "3 min", urgent: false), "a card dismissed before the meeting starts keeps its countdown")
    }

    // MARK: - A meeting that started unanswered is still offered

    do {
        // The reported bug: the meeting begins, the user has not joined, and
        // every surface drops it — the candidate scan because `currentMeeting`
        // claimed it, and again because it started more than 30 seconds ago.
        let missed = zoomMeeting("missed", title: "Sprint review", start: base.addingTimeInterval(-4 * 60), end: base.addingTimeInterval(26 * 60), meetingID: "20")
        let decision = Scheduler.decide(makeInput(now: base, meetings: [missed], leadMinutes: 5))
        guard case .present(let card) = decision else {
            t.expect(false, "a meeting that started four minutes ago and was never answered should still be offered, got \(decision)")
            return
        }
        t.expectEqual(card.items.count, 1, "the missed meeting takes the only row")
        t.expectEqual(card.items[0].meeting.id, "missed", "the row offers the missed meeting")
        t.expectEqual(card.minutes, -4, "the countdown has gone negative — the HUD renders it as minutes ago")
        t.expect(card.urgent, "a meeting already under way is urgent")
        t.expect(!card.isLeavingAnother, "the missed meeting is not something the user is leaving — it is the one they are late for")

        // Bounded, so a long unanswered block does not camp a card all day.
        let atEdge = missed.start.addingTimeInterval(Scheduler.missedGrace)
        t.expect(
            Scheduler.decide(makeInput(now: atEdge, meetings: [missed], leadMinutes: 5)) != .hide,
            "still offered at exactly the end of the grace window"
        )
        let pastEdge = atEdge.addingTimeInterval(1)
        t.expectEqual(
            Scheduler.decide(makeInput(now: pastEdge, meetings: [missed], leadMinutes: 5)), .hide,
            "one second past the grace window the card gives up — the menu-bar list is what keeps it"
        )

        // The grace window has to hold for an offer carried forward on every
        // tick too — that is the only shape the running app ever has, and
        // `decide` consults stickiness before it consults candidacy.
        t.expectEqual(
            Scheduler.decide(makeInput(now: pastEdge, meetings: [missed], leadMinutes: 5, offered: [missed])),
            .hide,
            "a carried-forward offer nobody answered ages out of the card at the same grace window"
        )

        // Answering is what retires it, not the clock.
        t.expectEqual(
            Scheduler.decide(makeInput(now: base, meetings: [missed], leadMinutes: 5, dismissedIDs: ["missed"])), .hide,
            "a missed meeting the user has answered is not re-offered"
        )
    }

    // MARK: - A missed meeting never shadows an imminent one

    do {
        // `meetings` is start-ascending, so the missed meeting comes first in
        // the array. It must not come first in the decision: on Meet, Teams
        // and Webex a join is invisible to the app, so the meeting the user is
        // actually sitting in is never in `dismissedIDs`, and letting it lead
        // would take every back-to-back handoff off the card (KTD7).
        let stale = zoomMeeting("stale", title: "Standup", start: base.addingTimeInterval(-3 * 60), end: base.addingTimeInterval(27 * 60), meetingID: "23")
        let imminent = zoomMeeting("imminent", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60), meetingID: "24")

        t.expectEqual(
            Scheduler.nextCandidate(in: [stale, imminent], now: base, dismissedIDs: [], leadMinutes: 5)?.id,
            "imminent",
            "an upcoming meeting inside the lead window leads over one that has already started"
        )

        guard case .present(let card) = Scheduler.decide(makeInput(
            now: base, meetings: [stale, imminent], leadMinutes: 5
        )) else {
            t.expect(false, "the imminent meeting should still be offered alongside a missed one")
            return
        }
        t.expectEqual(card.items.count, 1, "the missed meeting is a different slot, not a second row")
        t.expectEqual(card.items[0].meeting.id, "imminent", "the card offers the imminent meeting, not the missed one")

        t.expectEqual(
            Scheduler.pill(in: [stale, imminent], leadMinutes: 5, now: base),
            Scheduler.Pill(text: "2 min", urgent: false),
            "the pill counts down to the imminent meeting rather than reading \"now\" for the missed one"
        )

        // With nothing imminent, the missed meeting leads again.
        let laterOn = zoomMeeting("later", start: base.addingTimeInterval(4 * 60 * 60), end: base.addingTimeInterval(5 * 60 * 60), meetingID: "25")
        t.expectEqual(
            Scheduler.nextCandidate(in: [stale, laterOn], now: base, dismissedIDs: [], leadMinutes: 5)?.id,
            "stale",
            "a missed meeting leads when nothing upcoming is inside the lead window"
        )
    }

    do {
        // The handoff still works while genuinely in a joined call: the
        // meeting in progress is answered, so it is not re-offered as a
        // missed one, and the next meeting is what the card shows.
        let joined = zoomMeeting("joined", title: "Standup", start: base.addingTimeInterval(-3 * 60), end: base.addingTimeInterval(2 * 60), meetingID: "21")
        let next = zoomMeeting("after", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60), meetingID: "22")
        let decision = Scheduler.decide(makeInput(
            now: base, meetings: [joined, next], leadMinutes: 1, endingLeadMinutes: 5,
            dismissedIDs: ["joined"]
        ))
        guard case .present(let card) = decision else {
            t.expect(false, "the handoff card should still appear while in an answered meeting, got \(decision)")
            return
        }
        t.expectEqual(card.items.count, 1, "only the next meeting is offered, not the one already answered")
        t.expectEqual(card.items[0].meeting.id, "after", "the handoff offers the next meeting")
        t.expect(card.isLeavingAnother, "the card says what is being left")
    }
    do {
        let almostUrgent = zoomMeeting("pill-59s", start: base.addingTimeInterval(59), end: base.addingTimeInterval(30 * 60), meetingID: "14")
        let p59 = Scheduler.pill(in: [almostUrgent], leadMinutes: 5, now: base)
        t.expectEqual(p59, Scheduler.Pill(text: "1 min", urgent: true), "the pill is urgent under a minute out (59s)")

        let exactly60 = zoomMeeting("pill-60s", start: base.addingTimeInterval(60), end: base.addingTimeInterval(30 * 60), meetingID: "15")
        let p60 = Scheduler.pill(in: [exactly60], leadMinutes: 5, now: base)
        t.expectEqual(p60, Scheduler.Pill(text: "1 min", urgent: true), "the pill is still urgent at exactly 60 seconds (<= 60)")

        // Characterized, not asserted as a bug: 61s rounds up to "2 min" via
        // `.rounded(.up)` and stops being urgent.
        let past60 = zoomMeeting("pill-61s", start: base.addingTimeInterval(61), end: base.addingTimeInterval(30 * 60), meetingID: "16")
        let p61 = Scheduler.pill(in: [past60], leadMinutes: 5, now: base)
        t.expectEqual(p61, Scheduler.Pill(text: "2 min", urgent: false), "61 seconds out is no longer urgent and rounds up to 2 min")
    }
}

/// Two meetings in the same slot is a choice, not a queue: offering only the
/// first one hides the second entirely, and the user finds out they missed it
/// when someone asks where they were. These pin the grouping, the ordering,
/// and what happens as the rows are answered one at a time.
///
/// The `leadMinutes: 1` trick documented at the top of this file applies here
/// too, in the handoff case: it keeps the ordinary lead-window branch out of
/// the way so the assertion is about grouping, not about the window.
func runConcurrentMeetingTests(_ t: TestRunner) {
    t.suite("ConcurrentMeetings")

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func meeting(
        _ id: String, title: String, start: Date, end: Date, provider: MeetingProvider = .zoom
    ) -> UpcomingMeeting {
        UpcomingMeeting(
            id: id, title: title, start: start, end: end,
            link: MeetingLink(
                provider: provider,
                url: URL(string: "https://zoom.us/j/\(id)")!,
                appURL: nil, meetingID: id, password: nil
            )
        )
    }

    func input(
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        meetings: [UpcomingMeeting],
        leadMinutes: Int = 5,
        endingLeadMinutes: Int = 5,
        dismissedIDs: Set<String> = [],
        offered: [UpcomingMeeting] = []
    ) -> SchedulerInput {
        SchedulerInput(
            now: now, meetings: meetings, isSharingScreen: false,
            leadMinutes: leadMinutes, endingLeadMinutes: endingLeadMinutes,
            hideWhileSharing: true, dismissedIDs: dismissedIDs, offered: offered
        )
    }

    let start = base.addingTimeInterval(3 * 60)
    let end = base.addingTimeInterval(33 * 60)

    // MARK: - The premise: two same-start meetings survive dedup

    do {
        // If `deduplicatedMeetings()` collapsed on start time, this whole
        // feature would be unreachable — the second meeting would never make
        // it as far as the scheduler. It keys on the join target too, so two
        // genuinely different meetings at 15:00 both survive.
        let a = meeting("a", title: "Pricing review", start: start, end: end)
        let b = meeting("b", title: "Design sync", start: start, end: end, provider: .meet)
        t.expectEqual([a, b].deduplicatedMeetings().count, 2, "two different meetings at the same time both survive dedup")

        // And the same meeting arriving twice still collapses.
        t.expectEqual([a, a].deduplicatedMeetings().count, 1, "the same meeting synced twice still collapses to one")
    }

    // MARK: - Two at once: two rows, one dial, a headline

    do {
        let a = meeting("a", title: "Pricing review", start: start, end: end)
        let b = meeting("b", title: "Design sync", start: start, end: end, provider: .meet)
        guard case .present(let card) = Scheduler.decide(input(meetings: [a, b])) else {
            t.expect(false, "two meetings in the lead window should present a card")
            return
        }
        t.expectEqual(card.items.count, 2, "a double booking gets a row each")
        t.expectEqual(card.items.map(\.meeting.id), ["b", "a"], "rows are ordered by title, not by fetch order")
        t.expectEqual(card.items[0].context, "Google Meet", "with a headline above them, rows carry only what tells them apart")
        t.expect(card.headline?.hasPrefix("2 meetings at ") == true, "the shared clock moves up into the headline, got \(card.headline ?? "nil")")
        t.expectEqual(card.minutes, 3, "one countdown for the slot, from the earliest of them")
        t.expectEqual(card.overflow, [], "nothing overflows at two")
    }

    // MARK: - Starts within a minute of each other are the same slot; a minute past is not

    do {
        let a = meeting("a", title: "A", start: start, end: end)
        let straggler = meeting("b", title: "B", start: start.addingTimeInterval(60), end: end)
        t.expectEqual(
            Scheduler.nextCandidates(in: [a, straggler], now: base, dismissedIDs: [], leadMinutes: 5).count,
            2,
            "a start exactly one minute later is still the same slot"
        )

        let separate = meeting("c", title: "C", start: start.addingTimeInterval(61), end: end)
        t.expectEqual(
            Scheduler.nextCandidates(in: [a, separate], now: base, dismissedIDs: [], leadMinutes: 5).map(\.id),
            ["a"],
            "a start 61 seconds later is a different slot and waits its turn"
        )
    }

    // MARK: - More than three: the card caps its rows and keeps the rest offered

    do {
        let many = (1...6).map { n in
            meeting("m\(n)", title: "Meeting \(n)", start: start, end: end)
        }
        guard case .present(let card) = Scheduler.decide(input(meetings: many)) else {
            t.expect(false, "six meetings at once should still present a card")
            return
        }
        t.expectEqual(card.items.count, Scheduler.maxCardItems, "the card renders at most maxCardItems rows")
        t.expectEqual(card.overflow.count, 2, "the rest are carried as overflow rather than dropped")
        t.expectEqual(card.meetings.count, 6, "every offer is handed back to the caller to re-offer next tick")
        t.expect(card.headline?.hasPrefix("6 meetings at ") == true, "the headline counts every offer, not just the visible rows")
    }

    // MARK: - Answering one row leaves the others up

    do {
        let a = meeting("a", title: "A", start: start, end: end)
        let b = meeting("b", title: "B", start: start, end: end)
        let c = meeting("c", title: "C", start: start, end: end)
        // What the coordinator passes on the tick after the user joined "a":
        // its id is dismissed, and it has been taken out of `offered`.
        guard case .present(let card) = Scheduler.decide(input(
            meetings: [a, b, c], dismissedIDs: ["a"], offered: [b, c]
        )) else {
            t.expect(false, "joining one of three should leave the other two on screen")
            return
        }
        t.expectEqual(card.items.map(\.meeting.id), ["b", "c"], "the answered row goes, the rest stay")

        // And once the last one is answered, the card goes — the fresh scan
        // has nothing left that is not dismissed.
        t.expectEqual(
            Scheduler.decide(input(meetings: [a, b, c], dismissedIDs: ["a", "b", "c"], offered: [])),
            .hide,
            "the card only goes when the last offer is answered"
        )
    }

    // MARK: - An overflowed offer takes a row as soon as one is answered

    do {
        let many = (1...5).map { n in
            meeting("m\(n)", title: "Meeting \(n)", start: start, end: end)
        }
        // The fifth had no row on the first card; it is still in `offered`.
        guard case .present(let card) = Scheduler.decide(input(
            meetings: many, dismissedIDs: ["m1"], offered: Array(many.dropFirst())
        )) else {
            t.expect(false, "expected the remaining four to be presented")
            return
        }
        t.expectEqual(card.items.count, 4, "the fifth offer takes the row the answered one gave up")
        t.expectEqual(card.overflow, [], "and nothing is left over")
    }

    // MARK: - A slot arriving as a handoff carries all of its meetings

    do {
        let current = meeting("current", title: "Standup", start: base.addingTimeInterval(-28 * 60), end: base.addingTimeInterval(2 * 60))
        let a = meeting("a", title: "A", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60))
        let b = meeting("b", title: "B", start: base.addingTimeInterval(2 * 60), end: base.addingTimeInterval(32 * 60))
        guard case .present(let card) = Scheduler.decide(input(
            meetings: [current, a, b], leadMinutes: 1, endingLeadMinutes: 5
        )) else {
            t.expect(false, "a handoff into a double booking should present a card")
            return
        }
        t.expectEqual(card.items.count, 2, "the handoff card offers both meetings in the slot")
        t.expect(card.isLeavingAnother, "the card still knows it is leaving the meeting in progress")
        t.expect(card.headline?.hasSuffix(" · after Standup") == true, "what is being left is shared, so it sits in the headline, got \(card.headline ?? "nil")")
    }

    // MARK: - A sticky offer past its own start is not "another meeting" to leave

    do {
        let started = meeting("started", title: "Started", start: base.addingTimeInterval(-5 * 60), end: base.addingTimeInterval(25 * 60))
        guard case .present(let card) = Scheduler.decide(input(meetings: [started], offered: [started])) else {
            t.expect(false, "a sticky offer stays presented past its own start time")
            return
        }
        t.expect(!card.isLeavingAnother, "the meeting the card is offering is not a meeting the card is leaving")
    }
}

/// The handoff trigger is a back-to-back, not "something later today". A
/// hard-coded half-hour window here once put the card on screen twenty
/// minutes early.
func runHandoffWindowTests(_ t: TestRunner) {
    t.suite("HandoffWindow")
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func zoomMeeting(_ id: String, start: Date, end: Date) -> UpcomingMeeting {
        UpcomingMeeting(
            id: id, title: id, start: start, end: end,
            link: MeetingLink(
                provider: .zoom,
                url: URL(string: "https://zoom.us/j/\(id)")!,
                appURL: nil, meetingID: id, password: nil
            )
        )
    }

    let current = zoomMeeting("current", start: base.addingTimeInterval(-28 * 60), end: base.addingTimeInterval(2 * 60))

    func decision(nextStartsInMinutes minutes: Double) -> SchedulerDecision {
        let next = zoomMeeting("next",
                               start: base.addingTimeInterval(minutes * 60),
                               end: base.addingTimeInterval((minutes + 30) * 60))
        return Scheduler.decide(SchedulerInput(
            now: base, meetings: [current, next], isSharingScreen: false,
            leadMinutes: 2, endingLeadMinutes: 5,
            hideWhileSharing: true, dismissedIDs: [], offered: []
        ))
    }

    if case .present = decision(nextStartsInMinutes: 2) {
        t.expect(true, "a meeting starting when this one ends is a handoff")
    } else {
        t.expect(false, "a meeting starting when this one ends is a handoff")
    }
    t.expectEqual(decision(nextStartsInMinutes: 20), .hide, "a meeting twenty minutes out is not a handoff")
    t.expectEqual(decision(nextStartsInMinutes: 10), .hide, "a meeting ten minutes out is not a handoff either")
}
