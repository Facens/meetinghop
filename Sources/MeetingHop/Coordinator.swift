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

    /// KTD4: the same defaults instance `SettingsStore.shared` resolved —
    /// `.standard` on a normal launch, or the suite
    /// `-MeetingHopDefaultsSuite <name>` names on the app-fresh and stranger
    /// tiers. Defaulted rather than always passed explicitly so `Coordinator()`
    /// at `AppDelegate`'s own construction time keeps working unchanged;
    /// `AppIdentity.activeDefaults()` resolves correctly at that point
    /// because argv is parsed into the argument domain before any Swift code
    /// runs, not at some later, harder-to-reason-about moment.
    private let defaults: UserDefaults

    /// The read-only state hook's writer (U8; KTD3, R13). `nil` on a normal
    /// launch — set once, by `AppDelegate`, only when `Journal.activate`
    /// finds a key — and every tap below reads it through the optional, so a
    /// journal that could not be opened, or was never asked for, changes
    /// nothing about what this type does (R13).
    var journal: Journal?

    private var upcoming: [UpcomingMeeting] = []
    /// Persisted: a card the user has answered must stay answered across a
    /// restart. Held in memory only, every relaunch re-offers a meeting they
    /// already joined, which is indistinguishable from nagging.
    private var dismissedIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.dismissedKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: Self.dismissedKey) }
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

    /// What `card shown` last reported, as the ordered ids of the offer it
    /// described — compared against `card.meetings` on every tick so a
    /// sticky card re-affirming itself every five seconds (KTD8) writes one
    /// journal line, not one per tick. `nil` once nothing is offered, so a
    /// later offer of the very same meetings is reported again rather than
    /// silently matching a stale signature.
    private var lastCardSignature: [String]?
    /// Whether the last tick's decision was `.conceal`, so `card concealed`
    /// is written on the transition into concealment and not once per tick
    /// for as long as the share lasts.
    private var wasConcealed = false
    /// The menu-bar fields last journalled, so `menu bar state` is written
    /// only when the authorized flag or the countdown pill actually changes
    /// — `publishMenuBar` otherwise runs on every five-second tick.
    private var lastMenuBarState: (authorized: Bool, countdown: Bool)?

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
    /// Put the onboarding card on screen, in the state `Onboarding.decide`
    /// chose. Called at most once per launch.
    var presentGuidance: ((GuidanceState) -> Void)?
    /// Take it off, for good: it is answered, not concealed.
    var dismissGuidance: (() -> Void)?

    /// What the onboarding card is showing, or `nil` when there is none.
    /// Held rather than passed back in from the view so the view has one job
    /// (draw a state and report a press) and this type keeps the decision.
    private var guidance: GuidanceState?

    /// The last calendar count `CalendarSource` reported, so the popover can
    /// tell "Calendar.app is empty" from "nothing left today" without asking
    /// EventKit again on every five-second tick — `calendarCount` walks the
    /// store's calendars each time it is read. Zero until the first fetch,
    /// which is also what it means before access is granted.
    private var calendarCount = 0

    init(defaults: UserDefaults = AppIdentity.activeDefaults()) {
        self.defaults = defaults
    }

    // MARK: - Lifecycle

    func start() async {
        // Checked before anything else, and before calendar access is ever
        // requested: a translocated launch (`BundleTranslocation`) sits on a
        // read-only mount that will not exist by the next launch, so asking
        // EventKit for access from here would grant it to a path with no
        // future. Skipping the request also removes the one thing that made
        // the harness's install-then-relaunch race dangerous — an in-flight
        // TCC prompt with nobody able to answer it before this process is
        // killed and relaunched from `/Applications` (see
        // `harness/lib/scenario.sh`'s `clear_quarantine`, and
        // `BundleTranslocation`'s own doc comment for the VM test that
        // disproved the harness-side fix this replaces).
        if BundleTranslocation.isTranslocated(bundlePath: Bundle.main.bundlePath) {
            journal?.append(.calendarAccess, JournalData.calendarAccess(
                granted: false,
                skippedReason: "translocated"
            ))
            decideGuidance(translocated: true, accessGranted: false)
            report?("MeetingHop is running from a temporary location. Move it to Applications, then open it again.")
            menuBar?(MenuBarModel(meetings: [], currentTitle: nil, calendarAuthorized: false, calendarCount: 0))
            return
        }

        let statusBefore = CalendarSource.authorizationStatusName
        let granted = await calendar.requestAccess()
        journal?.append(.calendarAccess, JournalData.calendarAccess(
            granted: granted,
            status: CalendarSource.authorizationStatusName,
            failure: calendar.lastAccessFailure,
            statusBefore: statusBefore
        ))
        // Before the early return below, not after it: the refused-permission
        // card is the one state this feature exists for most, and a denial
        // branch that returns first would be the one launch that never
        // reaches the guidance at all.
        decideGuidance(translocated: false, accessGranted: granted)

        guard granted else {
            report?("MeetingHop cannot see your meetings until you allow calendar access.")
            menuBar?(MenuBarModel(meetings: [], currentTitle: nil, calendarAuthorized: false, calendarCount: 0))
            return
        }
        calendar.onChange = { [weak self] meetings in
            guard let self else { return }
            // Two distinct scalar events, on every fetch (R13): a fixture
            // that produced no calendars and a fixture that produced no
            // upcoming meetings are different failures, and `calendars
            // counted: 0` next to `upcoming counted: 0` is what tells them
            // apart without a screenshot.
            self.calendarCount = self.calendar.calendarCount
            self.journal?.append(.calendarsCounted, JournalData.counted(self.calendarCount))
            self.journal?.append(.upcomingCounted, JournalData.counted(meetings.count))
            self.upcoming = meetings
            self.evaluate()
        }
        calendar.start()

        let t = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    // MARK: - Onboarding guidance

    /// Runs `Onboarding.decide` against what this domain remembers, and does
    /// what it says. Called once per launch, from `start()`.
    ///
    /// The rule itself is in the Kit, where the test suite can reach it; what
    /// is left here is reading two booleans, writing a journal line and
    /// calling a closure — the parts that need a running app anyway.
    private func decideGuidance(translocated: Bool, accessGranted: Bool) {
        if accessGranted {
            // A grant makes an old dismissal stale: the user who turns access
            // back on and revokes it again months later is being refused
            // afresh, and deserves to be told afresh. Doing this on every
            // granted launch rather than only on a transition keeps it a fact
            // about the current state instead of a fact about a history this
            // app does not keep.
            OnboardingStorage.forget(.accessDenied, in: defaults)
        }

        switch Onboarding.decide(
            translocated: translocated,
            accessGranted: accessGranted,
            firstRunSeen: OnboardingStorage.seen(.firstRun, in: defaults),
            accessDeniedSeen: OnboardingStorage.seen(.accessDenied, in: defaults)
        ) {
        case .show(let state):
            guidance = state
            journal?.append(.guidanceShown, JournalData.guidance(state: state))
            presentGuidance?(state)
        case .suppress(let state, let reason):
            journal?.append(.guidanceSuppressed, JournalData.guidanceSuppressed(state: state, reason: reason))
        }
    }

    /// The card's own button. Opens the page, records the answer, and takes
    /// the card away: acting on it and dismissing it are the same promise —
    /// the user has dealt with this and it does not come back.
    ///
    /// Unless nothing opened. A card that disappears on a button that did
    /// nothing is the exact failure this feature was told to avoid, and
    /// `report` is not a user-visible surface in this app — it only logs. So
    /// when neither the page nor Calendar.app would open, the card stays
    /// where it is, unanswered and still carrying the written path. The user
    /// can read it, or dismiss it themselves.
    func guidanceActed() {
        guard let state = guidance else { return }
        guard open(state, source: .card) else { return }
        answerGuidance(state)
    }

    /// The card's other button.
    func guidanceDismissed() {
        guard let state = guidance else { return }
        journal?.append(.guidanceDismissed, JournalData.guidance(state: state))
        answerGuidance(state)
    }

    /// The same action offered inside the popover, after the card is long
    /// gone. Nothing is remembered here: the popover is a surface the user
    /// opened on purpose, so there is nothing to suppress next time.
    func calendarHelpRequested(_ state: GuidanceState) {
        // The result is ignored rather than acted on: the popover has nothing
        // to keep open or take away, and the failure is already both logged
        // and journalled.
        _ = open(state, source: .popover)
    }

    private func answerGuidance(_ state: GuidanceState) {
        OnboardingStorage.remember(state, in: defaults)
        guidance = nil
        dismissGuidance?()
    }

    /// Opens where the state says to go, and falls back to Calendar.app when
    /// that refuses.
    ///
    /// The Settings URL is tried first because it is the only one of the two
    /// that lands somewhere the user can fix the problem; Calendar.app shows
    /// them what MeetingHop reads and no way to change it. `NSWorkspace.open`
    /// reporting `false` is what "refused" means here — an unhandled scheme,
    /// or a System Settings that would not come up — and it is weaker than it
    /// looks: a `true` says something accepted the URL, not that the right
    /// pane is on screen (see `GuidanceTarget`'s UNVERIFIED note). Both
    /// outcomes reach the journal, so a scenario can tell which of the two
    /// actually happened without reading the screen.
    ///
    /// Returns whether anything opened at all, which is what the card's own
    /// button uses to decide whether it has been answered.
    private func open(_ state: GuidanceState, source: GuidanceSource) -> Bool {
        let primary = state.target
        var target = primary
        var fellBack = false
        var ok = primary.url.map { NSWorkspace.shared.open($0) } ?? false

        if !ok {
            fellBack = true
            target = .calendarApp
            ok = openCalendarApp()
        }

        journal?.append(.guidanceAction, JournalData.guidanceAction(
            state: state,
            target: target,
            source: source,
            ok: ok,
            fellBack: fellBack
        ))

        if !ok {
            // Never a button that looks like it worked: when neither the
            // page nor Calendar.app would open, say so rather than closing
            // the card on a promise nothing kept. The copy already names the
            // System Settings path in words, so the user is not left without
            // a route even when every URL this app can fire refuses.
            report?("MeetingHop could not open System Settings or Calendar.")
        }
        return ok
    }

    /// Calendar.app by bundle identifier, never by path: `/System/
    /// Applications/Calendar.app` is where it lives today and not a promise
    /// macOS makes. `open(_ url:)` rather than `openApplication(at:…)`
    /// because it answers synchronously — the journal line above needs a
    /// result now, not in a completion handler that may outlive the card.
    private func openCalendarApp() -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: GuidanceTarget.calendarBundleIdentifier
        ) else {
            return false
        }
        return NSWorkspace.shared.open(app)
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
            if !wasConcealed {
                journal?.append(.cardConcealed, JournalData.cardConcealed(reason: "screen_sharing"))
                wasConcealed = true
            }
            conceal?()
        case .hide:
            wasConcealed = false
            lastCardSignature = nil
            dismissCard?()
        case .present(let card):
            wasConcealed = false
            // Idempotent whether this reaffirms the sticky card or offers a
            // new one — see `SchedulerInput.offered`'s doc comment. The
            // overflow rides along in `card.meetings`, so an offer with no
            // room for a row stays offered and takes one as soon as a row
            // above it is answered.
            offered = card.meetings
            let signature = card.meetings.map(\.id)
            if signature != lastCardSignature, let leader = card.items.first {
                journal?.append(.cardShown, JournalData.cardShown(
                    id: leader.meeting.id,
                    title: leader.meeting.title,
                    start: leader.meeting.start,
                    count: card.meetings.count,
                    urgent: card.urgent,
                    verbose: AppIdentity.isVerbose()
                ))
                lastCardSignature = signature
            }
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

    /// The list keeps a meeting for as long as it runs, including the one in
    /// progress. Dropping the current meeting from it was how a meeting the
    /// user had not joined became unreachable the moment it started: the card
    /// was gone, and the popover showed the title in the header with no Join
    /// button anywhere. The header still names it; the row is what makes it
    /// joinable.
    private func publishMenuBar(now: Date) {
        let current = Scheduler.currentMeeting(in: upcoming, now: now)
        let list = upcoming
            .filter { $0.end > now }
            .prefix(6)
        let pill = Scheduler.pill(
            in: upcoming,
            leadMinutes: settings.leadMinutes,
            now: now,
            dismissedIDs: dismissedIDs
        )

        // "In <meeting>" claims the user is sitting in it. The clock passing a
        // start time does not make that true — only answering the card does —
        // so a meeting that started unanswered is named by its row, not by a
        // header telling the user they are already there.
        let inMeeting = current.flatMap { dismissedIDs.contains($0.id) ? $0 : nil }

        let model = MenuBarModel(
            meetings: Array(list),
            currentTitle: inMeeting?.title,
            calendarAuthorized: true,
            calendarCount: calendarCount,
            pill: pill.map { MenuBarModel.Pill(text: $0.text, urgent: $0.urgent, started: $0.started) }
        )
        let state = (authorized: model.calendarAuthorized, countdown: model.pill != nil)
        if lastMenuBarState == nil || lastMenuBarState! != state {
            journal?.append(.menuBarState, JournalData.menuBarState(authorized: state.authorized, countdown: state.countdown))
            lastMenuBarState = state
        }
        menuBar?(model)
    }

    // MARK: - Actions

    /// The close button. The only thing that makes a card go away unjoined.
    /// It answers every offer on the card at once: closing a double booking
    /// row by row would mean three clicks to say one thing.
    func dismissAll() {
        let count = offered.count
        for meeting in offered { dismissedIDs.insert(meeting.id) }
        offered = []
        journal?.append(.dismissed, JournalData.dismissed(count: count))
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
        let ok = NSWorkspace.shared.open(target)
        // Built from `target` and `meeting.id` only — never `meeting.title`,
        // `meeting.link.password`, or the URL's own `.absoluteString`/`.query`,
        // which is what carries a Zoom `pwd=` parameter. See
        // `JournalData.joinFired`'s doc comment for why that is provable
        // rather than merely intended.
        journal?.append(.joinFired, JournalData.joinFired(
            url: target,
            meetingIDHash: AccessibilityID.hash(meeting.id),
            ok: ok
        ))
        guard ok else {
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
