import AppKit
import SwiftUI
import MeetingHopKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: HUDPanel?
    private var hosting: HUDHostingController?
    /// The onboarding card's own panel, separate from the meeting card's.
    /// Never on screen at the same time as one: see `showGuidance`.
    private var guidancePanel: HUDPanel?
    private var guidanceHosting: GuidanceHostingController?
    /// True while the onboarding card is still unanswered — including while
    /// it is off screen because a meeting card took the space. Distinct from
    /// `guidancePanel != nil`, which only says a window exists.
    private var guidanceIsPending = false
    /// Created in applicationDidFinishLaunching, not as a property
    /// initialiser: an NSStatusItem made before NSApplication has finished
    /// launching is silently never installed.
    private var menuBar: MenuBarController!
    private let coordinator = Coordinator()
    /// Sparkle (U13). A stored property, never a local: a
    /// `SPUStandardUpdaterController` that goes out of scope is deallocated
    /// and stops checking with no error anywhere.
    private var updater: UpdaterController!

    /// So the settings window can reach the updater without threading it
    /// through the menu-bar closure that opens it. Weak and set once at
    /// launch; the delegate outlives every window anyway, and a strong
    /// static would keep a terminated app's delegate alive in tests.
    private(set) static weak var shared: AppDelegate?

    /// The updater, for the settings window's Updates section. Nil before
    /// `applicationDidFinishLaunching` has run.
    var updaterController: UpdaterController? { updater }
    /// A sample card belongs to the user, not to the schedule: the coordinator
    /// would tear it down on its next tick, five seconds later.
    private var showingSample = false
    /// What the sample card is still offering. Answering a row takes it out,
    /// so the preview shrinks exactly as the real card does.
    private var sampleMeetings: [UpcomingMeeting] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        SettingsStore.registerDefaults()
        menuBar = MenuBarController()
        menuBar.onJoin = { [weak self] meeting in self?.coordinator.join(meeting) }
        menuBar.onPreviewCard = { [weak self] in
            self?.showSampleCard()
        }
        menuBar.onCalendarHelp = { [weak self] state in
            self?.coordinator.calendarHelpRequested(state)
        }
        menuBar.onCheckForUpdates = { [weak self] in self?.updater.checkForUpdates() }

        // Started here rather than on the first visit to Settings, which
        // most people never make (R12). It refuses on an alpha build or one
        // with no signing key, says why on stderr, and the footer control
        // then stays hidden because `canCheck` is false.
        updater = UpdaterController(
            betaEnabled: {
                UpdatePolicy.betaEnabled(
                    preference: SettingsStore.shared.betaUpdates,
                    version: AppVersion.display()
                )
            },
            updatePending: { [weak self] pending in
                guard let self else { return }
                self.menuBar.setUpdateState(canCheck: self.updater.refusal == nil, pending: pending)
            }
        )
        menuBar.setUpdateState(canCheck: updater.refusal == nil, pending: false)

        coordinator.present = { [weak self] card in self?.show(HUDModel(card: card)) }
        coordinator.conceal = { [weak self] in
            guard self?.showingSample != true else { return }
            self?.panel?.orderOut(nil)
        }
        coordinator.dismissCard = { [weak self] in
            guard self?.showingSample != true else { return }
            self?.tearDownCard()
        }
        coordinator.report = { [weak self] message in self?.notify(message) }
        coordinator.menuBar = { [weak self] model in self?.menuBar?.update(model) }
        coordinator.presentGuidance = { [weak self] state in self?.showGuidance(state) }
        coordinator.dismissGuidance = { [weak self] in self?.tearDownGuidance() }
        coordinator.presentLaunchAtLoginPrompt = { [weak self] in self?.showLaunchAtLoginPrompt() }

        activateHarnessJournal()

        // A card on demand at launch, for looking at it without waiting for a
        // meeting: MEETINGHOP_PREVIEW=1 open dist/MeetingHop.app
        if ProcessInfo.processInfo.environment["MEETINGHOP_PREVIEW"] == "1" {
            showSampleCard()
        }

        Task { await coordinator.start() }
    }

    /// The About panel, from the status item's menu.
    ///
    /// AppKit's standard panel rather than a window of our own: it reads the
    /// bundle's name, icon and version itself, so the only thing worth adding
    /// is the licence and where the source is. `activate` first — an accessory
    /// app has no Dock icon to bring it forward, and the panel would open
    /// behind whatever the user was looking at.
    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "MIT licensed.\nhttps://github.com/Facens/meetinghop",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Test surface (U8; KTD3, KTD4, R13, R16)

    /// Turns the read-only state hook on when `harnessJournal` names a file
    /// in the active defaults domain — the same suite
    /// `-MeetingHopDefaultsSuite <name>` selects, resolved once here and
    /// handed to `Coordinator` so every tap writes through the one instance
    /// this call opens. A normal launch (no key, no suite argument) leaves
    /// nothing behind: `Journal.activate` deletes any journal a previous run
    /// left, and otherwise does nothing (AE6).
    ///
    /// Placed next to the `MEETINGHOP_PREVIEW` read above — both are launch
    /// affordances that do nothing unless deliberately asked for.
    private func activateHarnessJournal() {
        let defaults = AppIdentity.activeDefaults()
        let directory = AppIdentity.harnessDirectory()
        switch Journal.activate(defaults: defaults, directory: directory, build: AppVersion.display()) {
        case .inert:
            return
        case .refused(let reason):
            // One line, once — the only trace a rejected key may leave.
            // There is no logging layer to route it through beyond `log`
            // (Support.swift); this goes to standard error as well, which is
            // where the harness — launching from a shell — actually reads it.
            FileHandle.standardError.write(Data("MeetingHop: \(reason)\n".utf8))
            log.error("harness journal refused: \(reason, privacy: .public)")
        case .writing(let journal):
            coordinator.journal = journal
            journal.start(fixture: [
                "suite": .string(AppIdentity.harnessSuiteName() ?? "standard"),
                "harness_dir": .string(directory.path),
                "lead_minutes": .integer(SettingsStore.shared.leadMinutes),
                "verbose": .boolean(AppIdentity.isVerbose()),
            ])
        }
    }

    // MARK: - Onboarding card

    /// Builds the onboarding card's panel and shows it, unless a meeting card
    /// is already on screen.
    ///
    /// Both panels sit at the top centre of the screen (`HUDWindow.position`),
    /// so only one of them may be visible at a time, and the meeting card is
    /// the one that wins: a meeting starting in two minutes is worth more than
    /// an explanation of where calendars come from, and the explanation has
    /// nothing time-bound about it. The onboarding card is ordered out rather
    /// than answered — it stays pending, and `restoreGuidanceIfPending` brings
    /// it back once the meeting card is gone. Marking it seen here instead
    /// would be the opposite failure: the one card everybody is supposed to
    /// get, silently spent on a screen nobody read.
    private func showGuidance(_ state: GuidanceState) {
        guidanceIsPending = true

        if guidancePanel == nil {
            let controller = GuidanceHostingController(
                state: state,
                onAction: { [weak self] in self?.coordinator.guidanceActed() },
                onDismiss: { [weak self] in self?.coordinator.guidanceDismissed() }
            )
            guidanceHosting = controller
            guidancePanel = HUDWindow.make(
                hosting: controller.view,
                identifier: AccessibilityID.Guidance.panel
            )
        }

        guard panel == nil else { return }   // a meeting card owns the space
        placeGuidance()
    }

    /// Sizes, places and shows the onboarding panel.
    ///
    /// Fitted on every appearance, not only when it is built: `fittingSize` is
    /// zero until the hosting view has laid out, so a panel created and shown
    /// in one breath comes up at `HUDWindow`'s 86pt floor and clips its own
    /// body text. A panel that was built while a meeting card held the screen
    /// has never laid out at all by the time it is restored, which is the same
    /// problem arriving later.
    private func placeGuidance() {
        guard let guidancePanel, let guidanceHosting else { return }
        HUDWindow.fit(guidancePanel, hosting: guidanceHosting.view)
        HUDWindow.position(guidancePanel)
        guidancePanel.orderFrontRegardless()
    }

    /// The onboarding card was answered — acted on or dismissed. It does not
    /// come back, in this launch or any later one.
    private func tearDownGuidance() {
        guidanceIsPending = false
        guidancePanel?.orderOut(nil)
        guidancePanel = nil
        guidanceHosting = nil
    }

    /// Brings the onboarding card back after a meeting card released the
    /// screen. Guarded on visibility because the scheduler's `.hide` decision
    /// runs every five seconds, and re-ordering a window to the front on every
    /// tick is a flicker with no cause the user can see.
    private func restoreGuidanceIfPending() {
        guard guidanceIsPending, panel == nil, let guidancePanel, !guidancePanel.isVisible else { return }
        placeGuidance()
    }

    // MARK: - Launch-at-login prompt
    //
    // Not a fourth panel-management method mirroring the onboarding card's
    // above: `LaunchAtLoginAlert` is a native, modal `NSAlert`, which draws
    // and positions itself — there is nothing here to build, fit or tear
    // down. `Coordinator.decideLaunchAtLoginPrompt` never calls this until
    // the guidance card is already answered or suppressed, so the two never
    // compete for attention.
    //
    // Unlike the HUD-panel version this replaced, the alert is shown even
    // if a meeting card currently owns the screen, rather than waiting its
    // turn: `HUDPanel.worksWhenModal` (set in `HUDWindow.make`) is Apple's
    // own documented mechanism for keeping an auxiliary panel clickable
    // during another window's modal session, which is what should keep the
    // meeting card's Join button reachable while this alert is up —
    // expected per that API's stated purpose, though not exercised end to
    // end by an actual click during a live modal session here (UNVERIFIED,
    // no VM tier available in this unit's own report).

    private func showLaunchAtLoginPrompt() {
        // One turn of the run loop later, never synchronous with the call
        // that triggered it (`Coordinator.decideLaunchAtLoginPrompt`, itself
        // reached from a button press or from `start()`'s own async chain).
        //
        // `RunLoop.main.perform`, deliberately not `DispatchQueue.main.async`
        // (AgentMenu's own recipe, `LaunchAtLoginPrompt.presentIfNeeded`):
        // measured directly (see this unit's own report). Entering
        // `NSAlert.runModal()` from inside a block already running on the
        // GCD main queue starves that queue for the rest of the modal
        // session — nothing else dispatched to it, including every
        // `Task { @MainActor in }` hop this app's own timers use
        // (`Coordinator.start()`, `CalendarSource.start()`), runs again
        // until the alert is dismissed. Entering the same `runModal()` from
        // a block scheduled through `RunLoop.main.perform` instead does not
        // have that effect — the main dispatch queue keeps draining
        // normally throughout — which is what keeps the rest of the app,
        // including the meeting card's own countdown, alive while this
        // alert is up.
        RunLoop.main.perform { [weak self] in
            // `RunLoop.main.perform`'s closure type is plain `() -> Void`,
            // not `@MainActor () -> Void`, so the compiler cannot see what
            // is structurally guaranteed here: `RunLoop.main` only ever runs
            // this block on the main thread. `MainActor.assumeIsolated`
            // states that guarantee explicitly rather than leaving every
            // main-actor call inside silently flagged as "implicitly
            // asynchronous" — the same shape `Coordinator.start()`'s own
            // Timer closure would need if it called back into `self`
            // directly instead of through `Task { @MainActor in }`.
            MainActor.assumeIsolated {
                guard let self else { return }
                LaunchAtLoginAlert.present { accepted in
                    self.coordinator.launchAtLoginPromptAnswered(accepted: accepted)
                }
            }
        }
    }

    // MARK: - Card

    private func show(_ model: HUDModel) {
        showingSample = false
        present(model)
    }

    /// Shows the card with stand-in content so its appearance can be judged
    /// without waiting for a real meeting. Answers and dismisses like any
    /// other card — including shrinking a row at a time, which is the part
    /// worth being able to look at.
    private func showSampleCard() {
        showingSample = true
        sampleMeetings = Self.sampleMeetings()
        presentSample()
    }

    /// Runs the stand-in meetings through the real `Scheduler`, so the preview
    /// shows the strings the scheduler actually builds rather than a
    /// hand-written imitation of them that can drift away from it.
    private func presentSample() {
        let input = SchedulerInput(
            now: Date(),
            meetings: sampleMeetings,
            isSharingScreen: false,
            leadMinutes: settingsLead,
            endingLeadMinutes: SettingsStore.shared.endingLeadMinutes,
            // The preview is asked for, so nothing about the machine's state
            // should take it away: offered makes it sticky, and the sharing
            // gate is off.
            hideWhileSharing: false,
            dismissedIDs: [],
            offered: sampleMeetings
        )
        guard case .present(let card) = Scheduler.decide(input) else {
            showingSample = false
            tearDownCard()
            return
        }
        present(HUDModel(card: card))
    }

    private var settingsLead: Int { SettingsStore.shared.leadMinutes }

    /// Two offers rather than one: the double-booked card is the layout that
    /// needs looking at, and the single-offer one is what is left after
    /// joining a row.
    private static func sampleMeetings() -> [UpcomingMeeting] {
        func meeting(_ id: String, _ title: String, _ provider: MeetingProvider) -> UpcomingMeeting {
            UpcomingMeeting(
                id: id,
                title: title,
                start: Date().addingTimeInterval(2 * 60),
                end: Date().addingTimeInterval(32 * 60),
                link: MeetingLink(
                    provider: provider,
                    url: URL(string: "https://example.com/\(id)")!,
                    appURL: nil,
                    meetingID: id,
                    password: nil
                )
            )
        }
        return [
            meeting("sample-1", "Pricing review", .meet),
            meeting("sample-2", "Weekly Hub <> DS", .zoom),
        ]
    }

    /// The one path onto the screen, for the real card and the sample alike.
    /// Reuses the panel when there is one — rebuilding the hosting view would
    /// restart the entrance animation on every countdown tick — and resizes it,
    /// because a card holding a double booking is taller than one holding a
    /// single offer, and shrinks again as rows are answered.
    ///
    /// The action closure is bound once, at construction, and `handle` reads
    /// the meeting off the action rather than off stored state. An earlier
    /// shape passed a closure in here per presentation, which the reuse branch
    /// above quietly ignored: a real card shown over a sample panel kept the
    /// sample's handler, so Join tore the card down instead of opening
    /// anything.
    private func present(_ model: HUDModel) {
        // The meeting card takes the screen from the onboarding card, which
        // stays pending and comes back when this one goes (`showGuidance`).
        // The launch-at-login alert is not ordered out here: it is a modal
        // `NSAlert`, not a panel this delegate owns, and it stays up — see
        // `showLaunchAtLoginPrompt`'s own header for why that is safe.
        guidancePanel?.orderOut(nil)

        if let hosting, let panel {
            // Whether the card is arriving or merely ticking. A card already
            // on screen keeps whatever armed state the pointer has earned it;
            // one coming back from a conceal is arriving, and is judged again.
            let arriving = !panel.isVisible
            hosting.update(model: model)
            HUDWindow.fit(panel, hosting: hosting.view)
            HUDWindow.position(panel)
            panel.orderFrontRegardless()
            if arriving { hosting.armed(!panel.frame.contains(NSEvent.mouseLocation)) }
            return
        }

        let controller = HUDHostingController(model: model) { [weak self] action in
            self?.handle(action)
        }
        hosting = controller

        let panel = HUDWindow.make(hosting: controller.view, identifier: AccessibilityID.HUD.panel)
        self.panel = panel

        HUDWindow.position(panel)
        panel.orderFrontRegardless()
        // Read after `position`, never before: the frame this compares against
        // is the one the card actually lands in. `NSEvent.mouseLocation` and
        // `NSWindow.frame` are both in screen coordinates, so they compare
        // directly. See `HUDView.act` for what being disarmed costs a press.
        controller.armed(!panel.frame.contains(NSEvent.mouseLocation))
    }

    private func tearDownCard() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        // The space is free again, so an onboarding card this one displaced
        // gets it back rather than being lost for the rest of the launch.
        restoreGuidanceIfPending()
    }

    private func handle(_ action: HUDAction) {
        guard !showingSample else { return handleSample(action) }
        switch action {
        case .join(let meeting): coordinator.join(meeting)
        case .dismissAll: coordinator.dismissAll()
        }
    }

    /// The sample answers rows without opening anything: joining one takes its
    /// row away and leaves the rest, the close button takes the card.
    private func handleSample(_ action: HUDAction) {
        switch action {
        case .join(let meeting):
            sampleMeetings.removeAll { $0.id == meeting.id }
            guard !sampleMeetings.isEmpty else { return handleSample(.dismissAll) }
            presentSample()
        case .dismissAll:
            showingSample = false
            sampleMeetings = []
            tearDownCard()
        }
    }

    private func notify(_ message: String) {
        log.info("\(message, privacy: .public)")
    }
}
