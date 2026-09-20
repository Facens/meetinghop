import Foundation
import MeetingHopKit

/// KTD9: the enum's raw values are unique and non-empty, and no dynamic
/// identifier embeds a raw calendar title or a raw meeting id. Lives in
/// `MeetingHopKitTests` rather than under a `Sources/MeetingHop` test target
/// — there is no such target; `Tests/MeetingHopKitTests` is the only suite
/// this project has, and it is a plain executable that depends on
/// `MeetingHopKit` alone (see `Package.swift`), which is exactly why the
/// builders under test live in `MeetingHopKit` and not only in
/// `Sources/MeetingHop/Support/AccessibilityID.swift` — see the comment at
/// the top of `Sources/MeetingHopKit/Support/AccessibilityID.swift`.
///
/// `HUD.join`/`MenuBar.row` take an already-hashed `idHash`, not an id:
/// `Sources/MeetingHop/Support/AccessibilityID.swift` computes that hash
/// from an `UpcomingMeeting`'s (or `HUDModel.Item`'s) `id` before calling
/// down into these builders. Tests here that want to exercise the
/// no-raw-value rule on those builders route an id through
/// `AccessibilityID.hash` first, the same way the app does, rather than
/// passing a raw id as `idHash` — that would only prove the interpolation
/// works, not that the real call path is safe.
func runAccessibilityIDTests(_ t: TestRunner) {
    t.suite("AccessibilityID")

    let meetingA = "8B4F1C2D-REAL-EVENT-IDENTIFIER-A"
    let meetingB = "8B4F1C2D-REAL-EVENT-IDENTIFIER-B"
    let idHashA = AccessibilityID.hash(meetingA)
    let idHashB = AccessibilityID.hash(meetingB)

    // MARK: Happy path — every raw value a representative sweep of the app
    // produces is non-empty, and no two of them collide.

    let representative: [String] = [
        // HUD
        AccessibilityID.HUD.panel,
        AccessibilityID.HUD.close,
        AccessibilityID.HUD.join(idHash: idHashA),
        AccessibilityID.HUD.join(idHash: idHashB),

        // Guidance — the onboarding card's own panel and its two controls.
        AccessibilityID.Guidance.panel,
        AccessibilityID.Guidance.action,
        AccessibilityID.Guidance.dismiss,

        // MenuBar
        AccessibilityID.MenuBar.statusItem,
        AccessibilityID.MenuBar.popover,
        AccessibilityID.MenuBar.settings,
        AccessibilityID.MenuBar.previewCard,
        AccessibilityID.MenuBar.quit,
        AccessibilityID.MenuBar.calendarHelp,
        AccessibilityID.MenuBar.row(idHash: idHashA),
        AccessibilityID.MenuBar.row(idHash: idHashB),

        // Settings
        AccessibilityID.Settings.window,
        AccessibilityID.Settings.leadMinutesStepper,
        AccessibilityID.Settings.endingLeadMinutesStepper,
        AccessibilityID.Settings.hideWhileSharingToggle,
        AccessibilityID.Settings.launchAtLoginToggle,
    ]

    for id in representative {
        t.expect(!id.isEmpty, "identifier is non-empty: '\(id)'")
    }
    t.expectEqual(
        Set(representative).count, representative.count,
        "every raw value in a representative sweep of the app is unique — \(representative.count - Set(representative).count) collision(s)"
    )

    // MARK: Edge — the HUD row and the popover row both carry two controls
    // in reality (title text plus a Join button), and `.accessibilityElement
    // (children: .contain)` on the row is what makes that true at runtime
    // (applied in HUDView.swift's `row(_:)` and MenuBar.swift's
    // `MeetingRow`); what a plain string builder can assert is the half of
    // the contract it owns — the Join identifier itself is distinct from
    // the panel/popover container identifiers it sits inside.

    t.expect(
        AccessibilityID.HUD.join(idHash: idHashA) != AccessibilityID.HUD.panel,
        "the HUD's Join button and the panel that contains it carry different identifiers"
    )
    t.expect(
        AccessibilityID.MenuBar.row(idHash: idHashA) != AccessibilityID.MenuBar.popover,
        "a popover row's Join button and the popover container carry different identifiers"
    )

    // MARK: Regression — the onboarding card is a second borderless panel
    // built by the same `HUDWindow.make`, and `findByIdentifier`
    // (harness/guest/ax.applescript) returns the first window it walks to. If
    // the two panels ever shared an identifier, a scenario aiming at the
    // meeting card's Join button could be driven against the onboarding card
    // instead — silently, since both are real windows of the same app.

    t.expect(
        AccessibilityID.Guidance.panel != AccessibilityID.HUD.panel,
        "the onboarding card's panel and the meeting card's panel carry different identifiers"
    )
    t.expect(
        AccessibilityID.Guidance.action != AccessibilityID.Guidance.dismiss,
        "the onboarding card's two buttons are two identifiers, not one merged element"
    )

    // MARK: Regression — two different meetings whose calendar titles
    // happen to match (a recurring "1:1" appearing twice in the same day is
    // the ordinary case for this app, not an edge one) must not collide on
    // one row identifier. This is why `HUD.join`/`MenuBar.row` are keyed by
    // a hash of the meeting's own id rather than by a hash of its title —
    // see the long comment on `AccessibilityID.hash` for the reasoning,
    // which mirrors AgentMenu's `Popover.rowLaunch` comment on the same
    // duplicate-entry problem for folder rows.

    let sameTitleDifferentID1 = AccessibilityID.hash("event-id-morning-standup")
    let sameTitleDifferentID2 = AccessibilityID.hash("event-id-afternoon-standup")
    t.expect(
        AccessibilityID.HUD.join(idHash: sameTitleDifferentID1) != AccessibilityID.HUD.join(idHash: sameTitleDifferentID2),
        "two meetings that could share a calendar title still get different HUD Join identifiers, because the key is the event id"
    )
    t.expect(
        AccessibilityID.MenuBar.row(idHash: sameTitleDifferentID1) != AccessibilityID.MenuBar.row(idHash: sameTitleDifferentID2),
        "the popover row identifier is keyed the same way, for the same reason"
    )

    // MARK: hash — deterministic and never the raw value itself

    t.expectEqual(
        AccessibilityID.hash(meetingA), AccessibilityID.hash(meetingA),
        "hash is deterministic for the same input"
    )
    t.expect(idHashA != idHashB, "two different inputs hash differently")

    t.expectEqual(idHashA.count, 12, "hash truncates to 12 hex characters")
    t.expect(idHashA.allSatisfy { $0.isHexDigit && !$0.isUppercase }, "hash is lowercase hex — got '\(idHashA)'")

    // MARK: No raw value — the hard requirement (KTD9). Feed the builders a
    // calendar title and an event id a scenario has no business leaking,
    // and confirm neither survives into any identifier a meeting-keyed
    // builder produces.

    let realTitle = "1:1 with a direct report — confidential comp discussion"
    let realEventID = "EKEvent-9F3A-real-calendar-event-identifier"
    let realIDHash = AccessibilityID.hash(realEventID)

    let dynamicIdentifiers: [(String, String)] = [
        ("HUD.join", AccessibilityID.HUD.join(idHash: realIDHash)),
        ("MenuBar.row", AccessibilityID.MenuBar.row(idHash: realIDHash)),
    ]

    for (label, id) in dynamicIdentifiers {
        t.expect(!id.contains(realTitle), "\(label) does not embed the raw calendar title — got '\(id)'")
        t.expect(!id.contains(realEventID), "\(label) does not embed the raw event id — got '\(id)'")
    }

    // MARK: KTD9's event vocabulary check, applied to this app's own
    // JournalEvent enum too: every raw value is unique and non-empty, and
    // the raw values are the literal names the plan and a scenario share
    // (spaces included), so a rename here is a deliberate contract change
    // rather than a silent drift between the enum and `wait.sh --event`.
    //
    // The four `guidance …` names are this unit's addition to KTD3's original
    // list, one per state a user can now be in: shown, not shown and why,
    // acted on, dismissed.

    let eventNames = JournalEvent.allCases.map(\.rawValue)
    t.expectEqual(Set(eventNames).count, eventNames.count, "every journal event name is unique")
    t.expect(eventNames.allSatisfy { !$0.isEmpty }, "every journal event name is non-empty")
    t.expectEqual(
        Set(eventNames),
        [
            "harness started", "calendar access", "calendars counted", "upcoming counted",
            "menu bar state", "card shown", "card concealed", "join fired", "dismissed",
            "guidance shown", "guidance suppressed", "guidance action", "guidance dismissed",
        ],
        "the vocabulary is KTD3's MeetingHop list plus the onboarding guidance's own four, spaces and all"
    )
}
