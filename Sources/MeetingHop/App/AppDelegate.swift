import AppKit
import SwiftUI
import MeetingHopKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panel: HUDPanel?
    private var hosting: HUDHostingController?
    /// Created in applicationDidFinishLaunching, not as a property
    /// initialiser: an NSStatusItem made before NSApplication has finished
    /// launching is silently never installed.
    private var menuBar: MenuBarController!
    private let coordinator = Coordinator()
    /// A sample card belongs to the user, not to the schedule: the coordinator
    /// would tear it down on its next tick, five seconds later.
    private var showingSample = false
    /// What the sample card is still offering. Answering a row takes it out,
    /// so the preview shrinks exactly as the real card does.
    private var sampleMeetings: [UpcomingMeeting] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        SettingsStore.registerDefaults()
        menuBar = MenuBarController()
        menuBar.onJoin = { [weak self] meeting in self?.coordinator.join(meeting) }
        menuBar.onPreviewCard = { [weak self] in
            self?.showSampleCard()
        }

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

        // A card on demand at launch, for looking at it without waiting for a
        // meeting: MEETINGHOP_PREVIEW=1 open dist/MeetingHop.app
        if ProcessInfo.processInfo.environment["MEETINGHOP_PREVIEW"] == "1" {
            showSampleCard()
        }

        Task { await coordinator.start() }
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
        if let hosting, let panel {
            hosting.update(model: model)
            HUDWindow.fit(panel, hosting: hosting.view)
            HUDWindow.position(panel)
            panel.orderFrontRegardless()
            return
        }

        let controller = HUDHostingController(model: model) { [weak self] action in
            self?.handle(action)
        }
        hosting = controller

        let panel = HUDWindow.make(hosting: controller.view)
        self.panel = panel

        HUDWindow.position(panel)
        panel.orderFrontRegardless()
    }

    private func tearDownCard() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
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
