import Foundation

/// `MeetingProvider` is declared in Links/MeetingLink.swift — the parser owns
/// the case list. This decorates it for the card's context line; it lives
/// here rather than there because it exists to serve `Scheduler.decide`, and
/// moved out of the app target's HUDView.swift, which used to own it.
extension MeetingProvider {
    public var displayName: String {
        switch self {
        case .zoom:  return "Zoom"
        case .meet:  return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .other: return "Meeting"
        }
    }
}

/// The pure decision: given the calendar, Zoom's state, and the app's
/// settings, what should the card show right now — if anything.
///
/// Everything here is a value in, value out. `Coordinator` (app target) is
/// the only caller: it gathers a `SchedulerInput` from `CalendarSource`,
/// `ZoomPresence`, and `SettingsStore`, and drives the UI callbacks from
/// the `SchedulerDecision` it gets back.
public enum Scheduler {

    /// The meeting the user is sitting in right now, as far as the calendar
    /// knows. Kept separate from the next candidate on purpose: a single
    /// first-match scan over meetings sorted by start time always returns the
    /// one in progress, so the next was never reached while in a call.
    public static func currentMeeting(in meetings: [UpcomingMeeting], now: Date) -> UpcomingMeeting? {
        meetings.first { $0.start <= now && $0.end > now }
    }

    /// The candidate that leads the slot.
    ///
    /// `meetings` is start-ascending, so a meeting that has already started
    /// sorts ahead of one starting in two minutes. Taking the first candidate
    /// outright would therefore let a missed meeting shadow an imminent one —
    /// which is KTD7 all over again, and worst on Meet/Teams/Webex, where a
    /// join is never observable and so a meeting the user is sitting in is
    /// never in `dismissedIDs`. An imminent meeting can still be caught in
    /// time; a missed one is already lost, so it leads only when nothing
    /// upcoming is inside the lead window.
    public static func nextCandidate(
        in meetings: [UpcomingMeeting],
        now: Date,
        dismissedIDs: Set<String>,
        leadMinutes: Int
    ) -> UpcomingMeeting? {
        let candidates = meetings.filter { isCandidate($0, now: now, dismissedIDs: dismissedIDs) }
        let window = Double(leadMinutes * 60)
        let imminent = candidates.first {
            $0.start > now && $0.start.timeIntervalSince(now) <= window
        }
        return imminent ?? candidates.first
    }

    /// Two calendar entries can occupy the same slot — a double booking the
    /// user has to choose between. Offering only the first one hides the
    /// choice, so the candidate scan returns the whole slot: the earliest
    /// candidate plus every other candidate starting within
    /// `concurrencyWindow` of it.
    ///
    /// Order is fixed here rather than left to the calendar fetch, which has
    /// no guaranteed order between two events with the same start: the rows
    /// would reshuffle under the user's cursor on every five-second tick.
    public static func nextCandidates(
        in meetings: [UpcomingMeeting],
        now: Date,
        dismissedIDs: Set<String>,
        leadMinutes: Int
    ) -> [UpcomingMeeting] {
        guard let leader = nextCandidate(
            in: meetings, now: now, dismissedIDs: dismissedIDs, leadMinutes: leadMinutes
        ) else { return [] }

        return meetings
            .filter {
                isCandidate($0, now: now, dismissedIDs: dismissedIDs)
                    && abs($0.start.timeIntervalSince(leader.start)) <= concurrencyWindow
            }
            .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }

    /// How far apart two starts can be and still count as the same slot.
    ///
    /// Exact equality would be wrong in practice: the same 15:00 slot arrives
    /// from Exchange, Google and a hand-typed entry with starts seconds apart,
    /// and one straggler outside the window would be offered as a second,
    /// separate card seconds later.
    public static let concurrencyWindow: TimeInterval = 60

    /// How long a meeting that has already started keeps being offered when
    /// the user never answered it.
    ///
    /// A calendar entry that starts is not a meeting the user joined — the app
    /// learns about a join only when the Join button is pressed. Treating
    /// "started" as "handled" is what made a meeting the user was late for
    /// vanish from the card the moment it began, which is exactly when they
    /// need it. The window is bounded rather than the meeting's whole duration
    /// because a card pinned under the menu bar is an interruption: the
    /// permanent affordance is the menu-bar list, which keeps the meeting for
    /// as long as it runs.
    public static let missedGrace: TimeInterval = 10 * 60

    /// How many offers the card renders. The rest ride along in the decision
    /// as `Card.overflow` — they are still offered, still sticky, and they
    /// take a visible row as soon as one above them is answered — but a card
    /// pinned under the menu bar is an interruption, not a schedule, and six
    /// rows of it is a wall.
    public static let maxCardItems = 4

    /// `currentMeeting` is deliberately not consulted here: a meeting is
    /// skipped because the user answered it, never because the clock passed
    /// its start. A meeting they joined is in `dismissedIDs` —
    /// `Coordinator.join` puts it there — so the first guard already covers
    /// the real "I am in this one" case, while an unanswered meeting stays
    /// offerable for `missedGrace` past its start instead of disappearing
    /// into the meeting-in-progress lookup.
    private static func isCandidate(
        _ meeting: UpcomingMeeting,
        now: Date,
        dismissedIDs: Set<String>
    ) -> Bool {
        guard !dismissedIDs.contains(meeting.id) else { return false }
        return meeting.end > now && meeting.start >= now.addingTimeInterval(-missedGrace)
    }

    /// The single scheduling decision: conceal, hide, or present a card.
    public static func decide(_ input: SchedulerInput) -> SchedulerDecision {
        // Privacy outranks persistence: a card at the top of the screen
        // during a full-display share is visible to everyone in the call.
        // Concealing keeps `input.offered` unchanged in the caller, so the
        // card comes back once the share ends — this is a conceal, not a
        // dismissal (KTD6, KTD8).
        if input.hideWhileSharing, input.isSharingScreen {
            return .conceal
        }

        let current = currentMeeting(in: input.meetings, now: input.now)

        // A card, once shown, is sticky (KTD8): the caller re-passes the same
        // offers on every tick, and as long as they have not been dismissed
        // and have not ended, they win over recomputing the candidates — even
        // if a fresher calendar fetch would now prefer something else. An
        // offer that is answered or ends drops out here and the rest of the
        // card stays up; the card only goes when the last one does.
        //
        // The one bound on that: an offer the user never answered stops being
        // re-presented `missedGrace` past its own start. Without it the grace
        // window is unreachable in the running app — the offer is carried
        // forward on every tick, sticky fires before the candidate scan is
        // consulted, and a card for a meeting nobody answered camps under the
        // menu bar for the meeting's whole duration. The menu-bar list is
        // what keeps the meeting joinable after that.
        let sticky = input.offered.filter {
            !input.dismissedIDs.contains($0.id)
                && $0.end > input.now
                && $0.start >= input.now.addingTimeInterval(-missedGrace)
        }
        if !sticky.isEmpty {
            return .present(card(for: sticky, current: current, input: input))
        }

        let candidates = nextCandidates(
            in: input.meetings, now: input.now,
            dismissedIDs: input.dismissedIDs, leadMinutes: input.leadMinutes
        )
        guard let next = candidates.first else {
            return .hide
        }

        let secondsUntilNext = next.start.timeIntervalSince(input.now)
        let startingSoon = secondsUntilNext <= Double(input.leadMinutes * 60)
        let currentEndingSoon = current.map {
            $0.end.timeIntervalSince(input.now) <= Double(input.endingLeadMinutes * 60)
        } ?? false

        // A handoff is a back-to-back, not "the current one is ending and there
        // is something later today". The next meeting has to start close to
        // where this one ends, and how close is the user's lead time rather
        // than a number chosen here — an earlier hard-coded half hour is why
        // the card could appear twenty minutes early.
        let isHandoff = currentEndingSoon && current.map {
            next.start.timeIntervalSince($0.end) <= Double(input.leadMinutes * 60)
        } ?? false

        guard startingSoon || isHandoff else {
            return .hide
        }

        return .present(card(for: candidates, current: current, input: input))
    }

    /// Builds the card for one slot. `meetings` is never empty — both callers
    /// guard that — and the countdown comes from the first of them, which the
    /// `concurrencyWindow` grouping keeps within a minute of all the rest.
    private static func card(for meetings: [UpcomingMeeting], current: UpcomingMeeting?, input: SchedulerInput) -> Card {
        let leader = meetings[0]
        let secondsUntil = leader.start.timeIntervalSince(input.now)
        let window = Double(input.leadMinutes * 60)
        let progress = max(0, min(1, 1 - (secondsUntil / max(window, 1))))
        let minutes = Int((secondsUntil / 60).rounded(secondsUntil >= 0 ? .up : .down))

        // A sticky card keeps offering a meeting past its own start time, at
        // which point that meeting *is* the one in progress. It is not
        // something the user is leaving, so `current` only counts when it is
        // none of the offers.
        let leaving = current.flatMap { c in
            meetings.contains(where: { $0.id == c.id }) ? nil : c
        }
        let clock = clockFormatter.string(from: leader.start)
        let after = leaving.map { " · after \($0.title)" } ?? ""

        // One offer reads as a sentence about itself; several read as a slot
        // with a choice in it, so the clock moves up to a headline and each
        // row keeps only what tells the two apart.
        let headline: String? = meetings.count > 1
            ? "\(meetings.count) meetings at \(clock)\(after)"
            : nil

        let visible = meetings.prefix(maxCardItems)
        let items = visible.map { meeting in
            Card.Item(
                meeting: meeting,
                context: headline == nil
                    ? "\(meeting.link.provider.displayName) · \(clock)\(after)"
                    : meeting.link.provider.displayName,
                primaryLabel: "Join"
            )
        }

        return Card(
            items: Array(items),
            overflow: Array(meetings.dropFirst(visible.count)),
            headline: headline,
            minutes: minutes,
            progress: progress,
            urgent: secondsUntil <= 30,
            isLeavingAnother: leaving != nil
        )
    }

    // A computed property rather than a stored `static let`: `DateFormatter`
    // is a mutable, non-`Sendable` class, and this enum has no actor
    // isolation to protect a shared instance with. A fresh formatter per call
    // is cheap next to a 5-second tick, and it sidesteps the question rather
    // than papering over it.
    private static var clockFormatter: DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jm")
        return f
    }

    // MARK: - Menu-bar pill

    /// The pill outlives the card. Closing the card says "stop covering my
    /// screen", not "forget the meeting", so a closed meeting keeps a
    /// countdown up in the menu bar until it starts.
    ///
    /// It keeps the pill after that too. A meeting that has started and was
    /// not joined reads "now" rather than a countdown, and `silencedIDs` —
    /// `MeetingAnswers.silenced`, which is joins and post-start closes, not
    /// every dismissal — is what stops it. The card's own set was used here
    /// once, and that is how one stray click on the close button, two seconds
    /// after a card the user never registered dropped in, took a meeting off
    /// the card *and* out of the menu bar with nothing left to say it had
    /// ever been offered. The window is still bounded by `missedGrace`: the
    /// pill is a reminder, and the menu-bar list is what keeps the meeting
    /// for the rest of its run.
    public static func pill(
        in meetings: [UpcomingMeeting],
        leadMinutes: Int,
        now: Date,
        silencedIDs: Set<String> = []
    ) -> Pill? {
        // Same leadership order as the card: an imminent meeting outranks a
        // missed one, so a countdown is never replaced by "now" for a meeting
        // the user has already lost.
        if let upcoming = meetings.first(where: {
            $0.end > now && $0.start > now
                && $0.start.timeIntervalSince(now) <= Double(leadMinutes * 60)
        }) {
            let seconds = upcoming.start.timeIntervalSince(now)
            let minutes = Int((seconds / 60).rounded(.up))
            return Pill(
                text: minutes <= 1 ? "1 min" : "\(minutes) min",
                urgent: seconds <= 60
            )
        }

        // Started. Silenced means the user dealt with it — they joined, or
        // they closed a card for a meeting that was already running and so
        // said no to it on purpose. Otherwise they are late for it and the
        // pill is the only thing still saying so.
        let missed = meetings.first { m in
            m.end > now && m.start <= now
                && !silencedIDs.contains(m.id)
                && m.start >= now.addingTimeInterval(-missedGrace)
        }
        guard missed != nil else { return nil }
        return Pill(text: "now", urgent: true, started: true)
    }

    public struct Pill: Equatable, Sendable {
        public let text: String
        public let urgent: Bool
        /// The meeting is under way and unanswered, so `text` is "now" rather
        /// than a countdown. Carried as a flag because the accessibility
        /// label reads as a sentence, and "Next meeting in now" is not one.
        public let started: Bool

        public init(text: String, urgent: Bool, started: Bool = false) {
            self.text = text
            self.urgent = urgent
            self.started = started
        }
    }
}

// MARK: - Input / decision

/// Everything `Scheduler.decide` needs, gathered by `Coordinator` each tick.
public struct SchedulerInput: Sendable {
    public var now: Date
    public var meetings: [UpcomingMeeting]
    public var isSharingScreen: Bool
    /// Minutes before a meeting starts that the card appears.
    public var leadMinutes: Int
    /// Minutes before the current meeting ends that the handoff card appears.
    public var endingLeadMinutes: Int
    public var hideWhileSharing: Bool
    public var dismissedIDs: Set<String>
    /// The meetings the card is currently offering. Empty when no card is up,
    /// and more than one when the user is double booked.
    ///
    /// These are the full meetings, not ids: the caller passes the same values
    /// through unchanged from one tick to the next, so they are judged by the
    /// snapshot the user was first shown rather than re-derived from
    /// `meetings` on every tick. That is what makes the card sticky (KTD8) —
    /// an id-plus-lookup would silently break stickiness the moment a
    /// meeting's calendar record changes, or the meeting drops out of
    /// `meetings` entirely.
    ///
    /// It carries the offers the card had no room to render as well (see
    /// `Scheduler.maxCardItems`), so answering a visible one promotes the next
    /// in line instead of losing it.
    public var offered: [UpcomingMeeting]

    public init(
        now: Date,
        meetings: [UpcomingMeeting],
        isSharingScreen: Bool,
        leadMinutes: Int,
        endingLeadMinutes: Int,
        hideWhileSharing: Bool,
        dismissedIDs: Set<String>,
        offered: [UpcomingMeeting]
    ) {
        self.now = now
        self.meetings = meetings
        self.isSharingScreen = isSharingScreen
        self.leadMinutes = leadMinutes
        self.endingLeadMinutes = endingLeadMinutes
        self.hideWhileSharing = hideWhileSharing
        self.dismissedIDs = dismissedIDs
        self.offered = offered
    }
}

public enum SchedulerDecision: Equatable, Sendable {
    /// Take the card off screen without forgetting what it was offering.
    case conceal
    /// Forget the offer entirely.
    case hide
    case present(Card)
}

/// Everything the HUD needs to render one slot: a shared countdown, and one
/// row per meeting starting in it.
public struct Card: Equatable, Sendable {

    /// One offer — one row on the card.
    public struct Item: Equatable, Sendable {
        public let meeting: UpcomingMeeting
        /// The row's second line. On a card with a single offer this is the
        /// full context — the service, the clock time, and what the user is
        /// leaving; on a card with several it is just the service, because
        /// the clock and the meeting being left are shared and moved up into
        /// `headline`. Built here, using a Kit-owned clock formatter and the
        /// `displayName` above, rather than passed in pieces: the app target
        /// just renders the string.
        public let context: String
        /// Always "Join". The app opens the meeting; leaving the previous one
        /// is Zoom's own prompt, so a label promising otherwise would be a lie.
        public let primaryLabel: String

        public init(meeting: UpcomingMeeting, context: String, primaryLabel: String) {
            self.meeting = meeting
            self.context = context
            self.primaryLabel = primaryLabel
        }
    }

    /// The rows to render, at most `Scheduler.maxCardItems` of them.
    public let items: [Item]
    /// Offers that did not fit. Still offered and still sticky — the caller
    /// passes them back as part of `SchedulerInput.offered` — they simply have
    /// no row until one above them is answered.
    public let overflow: [UpcomingMeeting]
    /// One line above the rows when the slot holds more than one meeting:
    /// how many, at what time, and what is being left. `nil` for a single
    /// offer, whose row carries all of that itself.
    public let headline: String?
    /// Minutes until the slot starts. Negative once it has started.
    public let minutes: Int
    /// The dial's fill, 0 at the moment the card appears, 1 at start time.
    public let progress: Double
    public let urgent: Bool
    /// True when this slot follows a meeting the user is currently in.
    public let isLeavingAnother: Bool

    /// Everything the card is offering, rendered or not — what the caller
    /// hands back as `SchedulerInput.offered` on the next tick.
    public var meetings: [UpcomingMeeting] { items.map(\.meeting) + overflow }

    public init(
        items: [Item],
        overflow: [UpcomingMeeting] = [],
        headline: String? = nil,
        minutes: Int,
        progress: Double,
        urgent: Bool,
        isLeavingAnother: Bool
    ) {
        self.items = items
        self.overflow = overflow
        self.headline = headline
        self.minutes = minutes
        self.progress = progress
        self.urgent = urgent
        self.isLeavingAnother = isLeavingAnother
    }
}
