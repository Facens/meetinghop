import AppKit
import MeetingHopKit

/// Wires the calendar and Zoom state into `Scheduler.decide` and drives the
/// UI callbacks from the result.
///
/// The scheduling rule itself — when the card appears, what it says, and
/// what the button does — lives in `MeetingHopKit.Scheduler`. This type only
/// gathers the inputs and executes the decision.
///
/// Leaving the previous meeting is Zoom's job, not this app's: firing the
/// native join deep link while already in a meeting hands the decision to
/// Zoom's own prompt. That is why nothing here drives the Accessibility API
/// beyond reading state.
@MainActor
final class Coordinator {

    private let calendar = CalendarSource()
    private let settings = SettingsStore.shared

    private var upcoming: [UpcomingMeeting] = []
    /// Persisted: a card the user has answered must stay answered across a
    /// restart. Held in memory only, every relaunch re-offers a meeting they
    /// already joined, which is indistinguishable from nagging.
    private var dismissedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.dismissedKey) }
    }

    private static let dismissedKey = AppIdentity.DefaultsKeys.dismissedMeetingIDs
    private var tick: Timer?

    /// The meetings the card is currently offering — more than one when the
    /// user is double booked. Once set, they stay set: the card does not time
    /// out, drift away when the meeting starts, or vanish because a later tick
    /// preferred a different candidate. Only the close button or a join
    /// clears an entry. Passed to `Scheduler.decide` as
    /// `SchedulerInput.offered` on every tick — see that type's doc comment
    /// for why these are full meetings, not ids.
    private var offered: [UpcomingMeeting] = []

    /// The whole card, built by `Scheduler`. A positional argument list stopped
    /// being readable once a card could hold several offers.
    var present: ((Card) -> Void)?
    /// Take the card off screen without forgetting what it was offering.
    var conceal: (() -> Void)?
    /// Forget the offer entirely.
    var dismissCard: (() -> Void)?
    var report: ((String) -> Void)?
    /// Everything the menu-bar popover renders.
    var menuBar: ((MenuBarModel) -> Void)?

    // MARK: - Lifecycle

    func start() async {
        guard await calendar.requestAccess() else {
            report?("MeetingHop cannot see your meetings until you allow calendar access.")
            menuBar?(MenuBarModel(meetings: [], currentTitle: nil, calendarAuthorized: false))
            return
        }
        calendar.onChange = { [weak self] meetings in
            self?.upcoming = meetings
            self?.evaluate()
        }
        calendar.start()

        let t = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    // MARK: - Decision

    func evaluate() {
        let now = Date()
        pruneDismissed(now: now)
        publishMenuBar(now: now)

        let input = SchedulerInput(
            now: now,
            meetings: upcoming,
            isSharingScreen: ZoomPresence.isSharingScreen,
            leadMinutes: settings.leadMinutes,
            endingLeadMinutes: settings.endingLeadMinutes,
            hideWhileSharing: settings.hideWhileSharing,
            dismissedIDs: dismissedIDs,
            offered: offered
        )

        switch Scheduler.decide(input) {
        case .conceal:
            conceal?()
        case .hide:
            dismissCard?()
        case .present(let card):
            // Idempotent whether this reaffirms the sticky card or offers a
            // new one — see `SchedulerInput.offered`'s doc comment. The
            // overflow rides along in `card.meetings`, so an offer with no
            // room for a row stays offered and takes one as soon as a row
            // above it is answered.
            offered = card.meetings
            present?(card)
        }
    }

    /// Drops entries whose meeting has ended, so the set stays the size of a
    /// day rather than growing for as long as the app is installed.
    private func pruneDismissed(now: Date) {
        let live = Set(upcoming.filter { $0.end > now }.map(\.id))
        let kept = dismissedIDs.intersection(live)
        if kept != dismissedIDs { dismissedIDs = kept }
    }

    private func publishMenuBar(now: Date) {
        let current = Scheduler.currentMeeting(in: upcoming, now: now)
        let list = upcoming
            .filter { $0.end > now && $0.id != current?.id }
            .prefix(6)
        let pill = Scheduler.pill(in: upcoming, current: current, leadMinutes: settings.leadMinutes, now: now)

        menuBar?(MenuBarModel(
            meetings: Array(list),
            currentTitle: current?.title,
            calendarAuthorized: true,
            pill: pill.map { MenuBarModel.Pill(text: $0.text, urgent: $0.urgent) }
        ))
    }

    // MARK: - Actions

    /// The close button. The only thing that makes a card go away unjoined.
    /// It answers every offer on the card at once: closing a double booking
    /// row by row would mean three clicks to say one thing.
    func dismissAll() {
        for meeting in offered { dismissedIDs.insert(meeting.id) }
        offered = []
        dismissCard?()
    }

    /// Open the meeting. Zoom owns the transition: given its native deep link
    /// while the user is already in a call, it asks them whether to leave.
    ///
    /// Answering one offer does not answer the others: the card is rebuilt
    /// from what is left, and only goes when nothing is left. Joining the
    /// first of three otherwise takes the other two off screen unanswered.
    func join(_ meeting: UpcomingMeeting) {
        let target = meeting.link.appURL ?? meeting.link.url
        guard NSWorkspace.shared.open(target) else {
            report?("Could not open \(meeting.title).")
            return
        }
        answer(meeting)
    }

    /// Records the answer and re-runs the decision straight away, rather than
    /// waiting out the rest of the five-second tick with a row on screen the
    /// user has already dealt with.
    private func answer(_ meeting: UpcomingMeeting) {
        dismissedIDs.insert(meeting.id)
        offered.removeAll { $0.id == meeting.id }
        evaluate()
    }
}
