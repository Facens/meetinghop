import AppKit
import SwiftUI
import MeetingHopKit

/// What the menu-bar popover shows. Built by the coordinator and handed over
/// whole, so the popover never reaches back into scheduling state.
struct MenuBarModel {
    var meetings: [UpcomingMeeting] = []
    var currentTitle: String?
    var calendarAuthorized: Bool = true
    /// How many calendars Calendar.app holds. The popover needs it to tell
    /// "Calendar.app is empty" from "nothing left today" — the same
    /// distinction the journal has drawn since U8, where `calendars counted`
    /// and `upcoming counted` are two events precisely because they are two
    /// different problems for the user.
    var calendarCount: Int = 0
    /// Shown in the menu bar itself. Set when a meeting is close enough to
    /// matter, including one whose card the user has already closed: dismissing
    /// the card should quieten the reminder, not delete it.
    var pill: Pill?

    struct Pill {
        var text: String
        var urgent: Bool
        /// The meeting is under way and unanswered — see `Scheduler.Pill`.
        var started: Bool = false
    }

    /// What the popover shows in place of a meeting list, or `nil` when it
    /// has meetings to show. The rule is `MeetingHopKit.Onboarding`'s, so the
    /// test suite can reach it; this is only where the view asks.
    var emptyState: CalendarEmptyState? {
        Onboarding.emptyState(
            accessGranted: calendarAuthorized,
            calendarCount: calendarCount,
            meetingCount: meetings.count
        )
    }

    /// Stated, not measured. `NSHostingController.view.fittingSize` is zero
    /// until the view is in a window, and a popover presented at zero size is
    /// placed nowhere near the thing it belongs to.
    var preferredSize: NSSize {
        let width: CGFloat = 320
        let header: CGFloat = 52
        // Two rows (see `footer` in MenuBarView), stacked with no inter-row
        // spacing of their own — the gap between them comes only from the
        // button row's own top padding, so it is counted once, not twice:
        //   version row: top padding 9 + ~14pt line at 10.5pt (10.5 × ~1.3,
        //     the same line-height estimate the button row below uses)  = 23
        //   button row:  top padding 9 + ~15pt line at 11.5pt + bottom
        //     padding 9 (unchanged from before this unit)                = 33
        //   footer = 23 + 33
        let footer: CGFloat = 56
        let dividers: CGFloat = 2

        let body: CGFloat
        // Each empty state gets its own height rather than one shared number:
        // the two that carry a button are two lines of text plus a control,
        // and "nothing else today" is a single line. Sharing one figure
        // either clips the first two or leaves a hole under the third.
        switch emptyState {
        case .accessDenied: body = 124
        case .noCalendars: body = 124
        case .noMeetings: body = 68
        case nil:
            body = min(CGFloat(meetings.count) * 45 + CGFloat(max(0, meetings.count - 1)), 260)
        }
        return NSSize(width: width, height: header + dividers + body + footer)
    }
}

@MainActor
final class MenuBarState: ObservableObject {
    @Published var model = MenuBarModel()
}

// MARK: - Popover content

struct MenuBarView: View {
    @ObservedObject var state: MenuBarState
    var onJoin: (UpcomingMeeting) -> Void
    var onCalendarHelp: (GuidanceState) -> Void
    var onSettings: () -> Void
    var onPreview: () -> Void
    var onQuit: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var accent: Color { Brand.accent(scheme, urgent: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.6)

            if let empty = state.model.emptyState {
                // One branch for all three empty states now, where there used
                // to be two: an empty Calendar.app and a quiet afternoon both
                // read "Nothing else today" before this, which is true of one
                // of them. The wording is MeetingHopKit's (`GuidanceCopy`),
                // the same wording the onboarding card uses, so the popover
                // cannot drift into saying something else about the same
                // situation.
                emptyBody(empty)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(state.model.meetings, id: \.id) { meeting in
                            MeetingRow(meeting: meeting, accent: accent) { onJoin(meeting) }
                            if meeting.id != state.model.meetings.last?.id {
                                Divider().opacity(0.35).padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider().opacity(0.6)

            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("MeetingHop")
                    .font(.system(size: 13, weight: .semibold))
                if let current = state.model.currentTitle {
                    Text("In \(current)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
    }

    /// An empty state's sentence, plus the way out of it when there is one.
    ///
    /// This is where the guidance lives permanently, after the onboarding
    /// card has been answered and gone: the card is shown once and never
    /// nags, so the same route has to stay reachable somewhere the user can
    /// go back to on purpose. "Nothing else today" gets no button — there is
    /// nothing for the user to fix about an afternoon with no meetings in it.
    @ViewBuilder
    private func emptyBody(_ empty: CalendarEmptyState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(GuidanceCopy.popover(empty))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let guidance = empty.guidance {
                Button(GuidanceCopy.action(guidance)) { onCalendarHelp(guidance) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .accessibilityIdentifier(AccessibilityID.MenuBar.calendarHelp)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            versionRow
            buttonRow
        }
    }

    // Row 1: the version a user can read to tell which build they're
    // running (R22). Left as its own `HStack` with a trailing `Spacer()` —
    // not folded into a single `Text` — because a later unit adds an update
    // control beside it, and that control belongs after the spacer.
    private var versionRow: some View {
        HStack(spacing: 8) {
            Text("Version \(AppVersion.display())")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }

    private var buttonRow: some View {
        HStack(spacing: 14) {
            Button("Settings…", action: onSettings)
                .accessibilityIdentifier(AccessibilityID.MenuBar.settings)
            // Here because the card only appears on its own schedule, and
            // judging how it looks should not mean waiting for a meeting.
            Button("Preview card", action: onPreview)
                .accessibilityIdentifier(AccessibilityID.MenuBar.previewCard)
            Spacer()
            Button("Quit", action: onQuit)
                .accessibilityIdentifier(AccessibilityID.MenuBar.quit)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct MeetingRow: View {
    let meeting: UpcomingMeeting
    let accent: Color
    let onJoin: () -> Void

    // `@State` is a macro in the macOS 26 SDK and its plugin ships with Xcode,
    // which this project does not build with — see `ViewLocal` in Support.swift.
    // The row is rebuilt inside a `ForEach` on every tick, so this has to be
    // storage tied to the row's identity, not a value re-created with the struct.
    @StateObject private var hoveredLocal = ViewLocal(false)

    private var hovered: Bool {
        get { hoveredLocal.value }
        nonmutating set { hoveredLocal.value = newValue }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jm")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.clock.string(from: meeting.start))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(meeting.isInProgress ? accent : .secondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(meeting.link.provider.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            Button("Join", action: onJoin)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(accent))
                .opacity(hovered ? 1 : 0)
                .accessibilityIdentifier(AccessibilityID.MenuBar.row(meeting))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovered ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovered = $0 }
        // Two controls in one row — the clock/title text and the Join
        // button — kept addressable as two identifiers rather than merged
        // into one (KTD9/U5's pattern).
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Status item

/// The menu-bar item and the popover hanging off it. Ported from AgentMenu's
/// StatusItemController, including the parts that look like details and are
/// not: an animated popover is positioned before its SwiftUI content has laid
/// out, and `.transient` counts a click inside a menu the popover itself opened
/// as an outside click.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let state = MenuBarState()

    var onJoin: ((UpcomingMeeting) -> Void)?
    var onPreviewCard: (() -> Void)?
    /// The popover's own way out of an empty state — the same action the
    /// onboarding card's button takes.
    var onCalendarHelp: ((GuidanceState) -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "MeetingHop"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.toolTip = "MeetingHop — your next meeting"
        statusItem.button?.setAccessibilityIdentifier(AccessibilityID.MenuBar.statusItem)
        renderIdleIcon()

        // .transient, unlike the sibling app: it closes on an outside click and
        // on deactivation for free. AgentMenu needs .applicationDefined because
        // its popover opens menus of its own, which .transient would treat as
        // outside clicks; this popover has plain buttons, so it does not.
        popover.behavior = .transient
        popover.animates = false                 // a menu-bar popover should feel instant
        let hosting = NSHostingController(
            rootView: MenuBarView(
                state: state,
                onJoin: { [weak self] meeting in
                    self?.close()
                    self?.onJoin?(meeting)
                },
                onCalendarHelp: { [weak self] state in
                    // Closed first, like every other control here: the page
                    // that opens takes the foreground, and a transient
                    // popover left behind it closes itself half a second
                    // later anyway, which reads as a glitch.
                    self?.close()
                    self?.onCalendarHelp?(state)
                },
                onSettings: { [weak self] in
                    self?.close()
                    SettingsWindowController.shared.show()
                },
                onPreview: { [weak self] in
                    self?.close()
                    self?.onPreviewCard?()
                },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        popover.contentViewController = hosting
        // The popover's own hosting content view is what makes it a
        // findable "window" to System Events rather than an anonymous one
        // (KTD9, mirroring AgentMenu's `Popover.container`).
        hosting.view.setAccessibilityIdentifier(AccessibilityID.MenuBar.popover)
    }


    func update(_ model: MenuBarModel) {
        state.model = model
        if let pill = model.pill {
            statusItem.button?.title = ""
            statusItem.button?.image = Self.pillImage(pill)
            statusItem.button?.image?.isTemplate = false
        } else {
            renderIdleIcon()
        }
    }

    @objc private func toggle() {
        popover.isShown ? close() : show()
    }

    private func show() {
        guard let button = statusItem.button else { return }
        // An accessory app is never "active" on its own, and a popover that
        // never takes key never gets deactivated either — which is what
        // .transient closes on.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = state.model.preferredSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

        // The status item's window is taller than the button inside it, so
        // anchoring to the button's own bounds leaves a gap between the menu
        // bar and the arrow. Pull the popover back up against the bar.
        if let window = popover.contentViewController?.view.window,
           let screen = button.window?.screen {
            let menuBarBottom = screen.visibleFrame.maxY
            var frame = window.frame
            let overshoot = menuBarBottom - frame.maxY
            if overshoot > 0 {
                frame.origin.y += overshoot
                window.setFrame(frame, display: false)
            }
        }

        // The popover is key so its own controls work.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func close() {
        popover.performClose(nil)
    }


    private func renderIdleIcon() {
        statusItem.button?.image = Self.idleIcon()
        statusItem.button?.title = ""
    }

    /// The mark ships in the assembled bundle, not in the package, because it
    /// is generated rather than committed. Running from `swift run` therefore
    /// has no Resources directory, and the SF Symbol stands in.
    private static func idleIcon() -> NSImage? {
        // Every scale is loaded into one image and the size is then declared in
        // points. NSImage(contentsOf:) reads a single file and takes its pixel
        // dimensions as points, so the 1x bitmap alone renders the mark at half
        // size and blurred on a Retina display.
        let reps = ["MenuBarIconTemplate", "MenuBarIconTemplate@2x", "MenuBarIconTemplate@3x"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "png") }
            .compactMap { NSImage(contentsOf: $0)?.representations.first }
        if !reps.isEmpty {
            let image = NSImage()
            reps.forEach(image.addRepresentation)
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "MeetingHop"
            return image
        }
        let fallback = NSImage(
            systemSymbolName: "arrow.forward.circle",
            accessibilityDescription: "MeetingHop"
        )
        fallback?.isTemplate = true
        return fallback
    }

    /// Drawn rather than set as text: a filled capsule in the brand colour is
    /// findable in a menu bar of monochrome glyphs, which a countdown that has
    /// already been dismissed once needs to be.
    private static func pillImage(_ pill: MenuBarModel.Pill) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = pill.text as NSString
        let textSize = text.size(withAttributes: [.font: font])
        let padH: CGFloat = 7
        let height: CGFloat = 16
        let width = ceil(textSize.width) + padH * 2

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let fill = pill.urgent
                ? NSColor(red: 0.902, green: 0.114, blue: 0.325, alpha: 1)
                : NSColor(red: 0.839, green: 0.200, blue: 0.424, alpha: 1)
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2),
                withAttributes: attrs
            )
            return true
        }
        image.accessibilityDescription = pill.started
            ? "Meeting starting now"
            : "Next meeting in \(pill.text)"
        return image
    }
}
