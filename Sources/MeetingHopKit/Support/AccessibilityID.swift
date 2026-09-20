import CryptoKit
import Foundation

/// KTD9's "one enum": every stable identifier a harness scenario clicks by,
/// built once, in one place, so a rename is a deliberate change to the
/// control's contract (R12) rather than a UI file drifting out from under the
/// driver that reads it.
///
/// This builder lives in `MeetingHopKit` rather than only under
/// `Sources/MeetingHop/Support/AccessibilityID.swift` — that file still
/// exists, as the app-facing surface — because `Tests/MeetingHopKitTests` is
/// a plain executable that depends on `MeetingHopKit` alone (see
/// `Package.swift`); it cannot import the `MeetingHop` app target, so a test
/// asserting uniqueness and the no-raw-value rule has to reach the actual
/// string builders, not a description of them written against types it
/// cannot see. This mirrors the identical split in AgentMenuKit, down to the
/// doc comment explaining it.
///
/// Every builder below takes primitive Foundation types and returns a
/// `String`, by construction: a function that accepted a SwiftUI view or an
/// AppKit type could not live in this target, and `packaging/check-source.sh`
/// enforces that `MeetingHopKit` imports neither AppKit nor SwiftUI (nor
/// EventKit nor Sparkle).
public enum AccessibilityID {

    /// KTD9: a raw path never reaches an `AXIdentifier` un-hashed, and
    /// neither does a raw calendar title. SHA-256, hex, truncated to 12
    /// characters (48 bits): plenty to make a collision on one machine a
    /// non-concern, short enough to still read as an identifier rather than
    /// a hash dump.
    ///
    /// Used for two different inputs, deliberately: an `UpcomingMeeting`'s
    /// `id` for a row's own `AXIdentifier` (see `HUD.join`/`MenuBar.row`
    /// below), and a meeting's `title` for the journal's `card shown` event
    /// (`JournalData.cardShown`). KTD9's own wording says "meetings use a
    /// hash of the title" for the identifier case; this hashes the id there
    /// instead, for the same reason AgentMenu's `Popover.rowLaunch` comment
    /// gives for a folder row's key: two different meetings can share one
    /// title — a recurring "1:1" appearing twice in the same day is the
    /// ordinary case here, not an edge one — and `findByIdentifier` returns
    /// the first match it walks to, so a title-keyed identifier would make a
    /// scenario aimed at the second occurrence silently drive the first.
    /// `UpcomingMeeting.id` has no such collision (`CalendarSource.fetch`
    /// builds it from the calendar's own event identifier, falling back to
    /// title-plus-start only when EventKit supplies none). No raw title
    /// reaches an `AXIdentifier` either way, which is the property KTD9 is
    /// actually protecting.
    public static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    // MARK: HUD

    /// The floating card (`HUDView.swift`, `HUDPanel.swift`).
    public enum HUD {
        /// The panel itself — an `NSPanel`, not a SwiftUI view, so this is
        /// applied with `setAccessibilityIdentifier` in `HUDWindow.make`.
        public static let panel = "hud.panel"
        /// The only way to make the card go away unjoined; singular, since
        /// it always answers every offer on the card at once.
        public static let close = "hud.close"
        /// One Join button per row. `idHash` is `hash(meeting.id)` — see the
        /// doc comment on `hash(_:)` for why the id and not the title.
        public static func join(idHash: String) -> String { "hud.join.\(idHash)" }
    }

    // MARK: Guidance

    /// The onboarding card (`GuidanceView.swift`) — the first-run panel and
    /// the refused-permission panel, which are one surface in two states
    /// (`Onboarding.decide`). One identifier per control rather than one per
    /// state: a scenario clicks the same button in either state, and *which*
    /// state it was is a scalar on the journal's own `guidance shown` line,
    /// which is where a fact a scenario asserts on belongs (R13).
    public enum Guidance {
        /// The panel itself — a borderless `HUDPanel`, like the card's, so
        /// this is applied with `setAccessibilityIdentifier` in
        /// `HUDWindow.make`. Distinct from `HUD.panel` on purpose:
        /// `findByIdentifier` returns the first window it walks to, so two
        /// panels sharing one identifier would make a Join click land
        /// wherever the walk happened to arrive first.
        public static let panel = "guidance.panel"
        /// The action: System Settings, or Calendar.app when that fails.
        public static let action = "guidance.action"
        /// Answers the card without acting on it. Either control ends the
        /// card for good.
        public static let dismiss = "guidance.dismiss"
    }

    // MARK: MenuBar

    /// The status item and the popover hanging off it (`MenuBar.swift`).
    public enum MenuBar {
        /// The menu-bar button that opens and closes the popover.
        public static let statusItem = "menuBar.statusItem"
        /// The popover's own hosting content view — what makes it a
        /// findable "window" to System Events rather than an anonymous one.
        public static let popover = "menuBar.popover"
        public static let settings = "menuBar.settings"
        public static let previewCard = "menuBar.previewCard"
        public static let quit = "menuBar.quit"
        /// The popover's own way out of an empty state — the same action the
        /// guidance card offers, kept available after that card has been
        /// answered and gone. Absent when the popover has meetings to show,
        /// and absent in the "nothing else today" state, which needs no
        /// action at all (`CalendarEmptyState.guidance`).
        public static let calendarHelp = "menuBar.calendarHelp"
        /// One row per upcoming meeting listed in the popover.
        public static func row(idHash: String) -> String { "menuBar.row.\(idHash)" }
    }

    // MARK: Settings

    /// The Settings window (`Settings.swift`) — one pane, no tabs, so no
    /// `scope` parameter is needed the way AgentMenuKit's `Settings.preset`
    /// takes one.
    public enum Settings {
        public static let window = "settings.window"
        public static let leadMinutesStepper = "settings.leadMinutesStepper"
        public static let endingLeadMinutesStepper = "settings.endingLeadMinutesStepper"
        public static let hideWhileSharingToggle = "settings.hideWhileSharingToggle"
        public static let launchAtLoginToggle = "settings.launchAtLoginToggle"
    }
}
