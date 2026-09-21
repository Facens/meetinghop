import Foundation
import MeetingHopKit

/// The onboarding guidance's rules and its words.
///
/// Everything here is a pure function over primitives, which is the whole
/// reason `Onboarding` lives in the Kit: the app target is not linked into
/// this suite (see `Package.swift`), so a decision made inside a SwiftUI view
/// or inside `Coordinator` could not be proven at all. What still needs a
/// running app, and is therefore not here: that the panel actually appears,
/// that its buttons are reachable by identifier, and that either System
/// Settings URL opens the pane it names (see `GuidanceTarget`'s own UNVERIFIED
/// note — nobody may open a settings pane on the maintainer's own machine to
/// find out).
///
/// The persistence half is proven in `SettingsStoreTests.swift` instead, next
/// to the rest of the `AppIdentity.activeDefaults()` isolation work, because
/// what matters about it is the domain it lands in rather than the rule.
func runOnboardingTests(_ t: TestRunner) {
    t.suite("Onboarding")

    // MARK: - 1. Happy path: the first-run card is shown to everybody, once.
    //
    // Unconditional by design — not "only when something is wrong". Someone
    // whose calendars are already in Calendar.app is exactly the user who
    // cannot tell a working app from a silent one, and they are told the same
    // thing as everybody else.

    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: true, firstRunSeen: false, accessDeniedSeen: false),
        .show(.firstRun),
        "a granted first launch shows the first-run card"
    )
    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: true, firstRunSeen: true, accessDeniedSeen: false),
        .suppress(.firstRun, reason: .alreadySeen),
        "a second launch shows nothing, and says in the journal which card stayed away"
    )

    // MARK: - 2. A refusal wins over the first-run card, and is its own,
    // separately-remembered state: dismissing one never answers the other.

    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: false, firstRunSeen: false, accessDeniedSeen: false),
        .show(.accessDenied),
        "a refused permission is what a first launch says, not the general introduction"
    )
    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: false, firstRunSeen: true, accessDeniedSeen: false),
        .show(.accessDenied),
        "a refusal still speaks after the first-run card has been dismissed — two states, one surface"
    )
    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: false, firstRunSeen: false, accessDeniedSeen: true),
        .suppress(.accessDenied, reason: .alreadySeen),
        "a refusal answered once does not nag on every launch"
    )
    t.expectEqual(
        Onboarding.decide(translocated: false, accessGranted: true, firstRunSeen: false, accessDeniedSeen: true),
        .show(.firstRun),
        "granting access after a refusal reaches the introduction the user never got"
    )

    // MARK: - 2b. Translocation outranks everything, including a refusal —
    // it is decided, and the calendar request skipped, before access is ever
    // asked for (`Coordinator.start()`), so there is no refusal to compare it
    // against in the first place. Never suppressed: see
    // `GuidanceState.translocated`'s own `seenKey` doc comment for why.

    for accessGranted in [true, false] {
        for firstRunSeen in [true, false] {
            for accessDeniedSeen in [true, false] {
                t.expectEqual(
                    Onboarding.decide(
                        translocated: true,
                        accessGranted: accessGranted,
                        firstRunSeen: firstRunSeen,
                        accessDeniedSeen: accessDeniedSeen
                    ),
                    .show(.translocated),
                    "translocated always shows .translocated, whatever else is true "
                        + "(accessGranted: \(accessGranted), firstRunSeen: \(firstRunSeen), accessDeniedSeen: \(accessDeniedSeen))"
                )
            }
        }
    }

    // MARK: - 3. `noCalendars` is never an unprompted card.
    //
    // The zero-calendar case is real and it is the case the whole feature is
    // about — but after the first-run card has said "MeetingHop reads
    // Calendar.app, add your Google or Outlook account", raising a second
    // panel to say it again is the nagging this feature was told not to do.
    // It gets the popover instead, which the user opens deliberately.

    for translocated in [true, false] {
        for granted in [true, false] {
            for firstRunSeen in [true, false] {
                for deniedSeen in [true, false] {
                    let decision = Onboarding.decide(
                        translocated: translocated,
                        accessGranted: granted, firstRunSeen: firstRunSeen, accessDeniedSeen: deniedSeen
                    )
                    let state: GuidanceState
                    switch decision {
                    case .show(let shown): state = shown
                    case .suppress(let suppressed, _): state = suppressed
                    }
                    t.expect(
                        state != .noCalendars,
                        "the card decision never reaches the zero-calendars state (translocated: \(translocated), granted: \(granted), firstRunSeen: \(firstRunSeen), deniedSeen: \(deniedSeen))"
                    )
                }
            }
        }
    }

    // MARK: - 4. The popover's three empty states, including the one this
    // unit added. `calendars counted: 0` and `upcoming counted: 0` have been
    // two journal events since U8 because they are two different problems;
    // before this unit the popover called them both "Nothing else today".

    t.expectEqual(
        Onboarding.emptyState(accessGranted: true, calendarCount: 0, meetingCount: 0),
        .noCalendars,
        "granted, no calendars at all: the account, not the day, is what is missing"
    )
    t.expectEqual(
        Onboarding.emptyState(accessGranted: true, calendarCount: 3, meetingCount: 0),
        .noMeetings,
        "granted, calendars present, nothing upcoming: an ordinary quiet afternoon"
    )
    t.expectEqual(
        Onboarding.emptyState(accessGranted: true, calendarCount: 3, meetingCount: 2),
        nil,
        "with meetings to show, the popover shows meetings"
    )
    t.expectEqual(
        Onboarding.emptyState(accessGranted: false, calendarCount: 0, meetingCount: 0),
        .accessDenied,
        "a refused permission is reported as a refusal, never as an empty Calendar.app"
    )
    // Edge: an unauthorized store reports zero calendars too, so the denial
    // has to be checked first — telling someone to add an account when their
    // accounts are fine and their permission is not would send them to the
    // wrong page entirely.
    t.expectEqual(
        Onboarding.emptyState(accessGranted: false, calendarCount: 9, meetingCount: 4),
        .accessDenied,
        "denial outranks whatever counts a stale model still carries"
    )

    // MARK: - 5. Every empty state that can be acted on offers an action, and
    // the one that cannot, does not.

    t.expectEqual(CalendarEmptyState.accessDenied.guidance, .accessDenied, "the denied popover offers the recovery")
    t.expectEqual(CalendarEmptyState.noCalendars.guidance, .noCalendars, "the empty-Calendar popover offers the accounts page")
    t.expectEqual(CalendarEmptyState.noMeetings.guidance, nil, "a quiet afternoon offers no button, because there is nothing to fix")

    // MARK: - 6. Where the buttons go.
    //
    // The two Settings URLs are asserted as literals rather than rebuilt from
    // parts: their exact spelling is the contract with macOS, and a typo in a
    // pane identifier produces a URL that still opens System Settings (see
    // `JournalData.guidanceAction`'s note on what `ok` does and does not
    // prove), so nothing at runtime would catch it.

    t.expectEqual(
        GuidanceState.firstRun.target, .accountsSettings,
        "the first-run card goes where an account is added, not to Calendar.app, which shows the problem and no way to fix it"
    )
    t.expectEqual(GuidanceState.noCalendars.target, .accountsSettings, "the popover's empty-Calendar state goes to the same page")
    t.expectEqual(GuidanceState.accessDenied.target, .privacySettings, "a refused permission goes to the privacy pane")
    t.expectEqual(
        GuidanceState.translocated.target, .applicationsFolder,
        "a translocated launch goes to /Applications — the fix itself, not a place to look for one"
    )

    t.expectEqual(
        GuidanceTarget.accountsSettings.url?.absoluteString,
        "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
        "the accounts pane is addressed by the identifier its own bundle declares, with no invented anchor"
    )
    t.expectEqual(
        GuidanceTarget.privacySettings.url?.absoluteString,
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
        "the privacy pane carries the anchor the pane's own searchTerms file names for its Calendars section"
    )
    t.expectEqual(
        GuidanceTarget.calendarApp.url, nil,
        "the fallback has no URL: it is resolved from a bundle identifier through NSWorkspace, never from a hard-coded path"
    )
    t.expectEqual(
        GuidanceTarget.calendarBundleIdentifier, "com.apple.iCal",
        "Calendar.app's bundle identifier, which is what /System/Applications/Calendar.app's Info.plist actually declares"
    )
    t.expectEqual(
        GuidanceTarget.applicationsFolder.url, URL(fileURLWithPath: "/Applications"),
        "the Applications target is a plain file URL, not a System Settings pane — there is no permission to open a pane for"
    )
    // Only the two Settings panes use that scheme: `.calendarApp` has no URL
    // at all, and `.applicationsFolder` is a `file://` URL on purpose (see
    // its own doc comment).
    for target in GuidanceTarget.allCases where target != .calendarApp && target != .applicationsFolder {
        t.expectEqual(
            target.url?.scheme, "x-apple.systempreferences",
            "\(target.rawValue) uses the scheme both panes opt into (allowsXAppleSystemPreferencesURLScheme)"
        )
    }
    t.expectEqual(
        GuidanceTarget.applicationsFolder.url?.scheme, "file",
        "the Applications target is addressed as a local file, never as a Settings scheme"
    )

    // MARK: - 7. Every scalar a scenario asserts on is a distinct, non-empty,
    // lower-snake word. The journal matcher compares scalars under `data` and
    // cannot reach into an array, so these raw values are the whole surface a
    // scenario has to work with.

    let scalars: [String] =
        GuidanceState.allCases.map(\.rawValue)
        + GuidanceTarget.allCases.map(\.rawValue)
        + GuidanceSource.allCases.map(\.rawValue)
        + GuidanceSuppression.allCases.map(\.rawValue)
    for scalar in scalars {
        t.expect(!scalar.isEmpty, "a journal scalar is non-empty")
        t.expect(
            scalar.allSatisfy { $0.isLowercase || $0 == "_" },
            "a journal scalar is lower-snake, so a scenario's --field never has to quote it — got '\(scalar)'"
        )
    }
    t.expectEqual(
        Set(GuidanceState.allCases.map(\.rawValue)).count, GuidanceState.allCases.count,
        "no two guidance states share a scalar"
    )
    t.expectEqual(
        Set(GuidanceTarget.allCases.map(\.rawValue)).count, GuidanceTarget.allCases.count,
        "no two targets share a scalar"
    )

    // MARK: - 8. The copy. The words are the feature here, so the rules the
    // brief set for them are assertions rather than a note in a review.
    //
    // `title(.noCalendars)` and `body(.noCalendars)` are swept up by the
    // `allCases` loops below and are never rendered anywhere: no card is built
    // for that state (case 3 above), and the popover has its own sentence.
    // They are held to the same rules anyway — the cost is nothing, and the
    // day a card *is* built for it, the words are already sound.

    let bodies = GuidanceState.allCases.map { GuidanceCopy.body($0) }
    let everything = GuidanceState.allCases.flatMap {
        [GuidanceCopy.title($0), GuidanceCopy.body($0), GuidanceCopy.action($0)]
    } + CalendarEmptyState.allCases.map { GuidanceCopy.popover($0) } + [GuidanceCopy.dismiss]

    for line in everything {
        t.expect(!line.isEmpty, "no piece of copy is empty")
        t.expect(!line.contains("!"), "no exclamation marks — got '\(line)'")
        let lowered = line.lowercased()
        for apology in ["oops", "sorry", "we apologise", "we apologize", "unfortunately"] {
            t.expect(!lowered.contains(apology), "no apology: '\(apology)' appears in '\(line)'")
        }
    }

    // Short enough to read in one breath: two sentences, and a cap well under
    // what would turn the card into a document.
    for body in bodies {
        t.expect(body.count <= 200, "a card body stays readable in one breath — \(body.count) characters in '\(body)'")
    }

    // Says what MeetingHop reads, and names the case the confused user
    // actually has.
    let firstRunBody = GuidanceCopy.body(.firstRun)
    t.expect(firstRunBody.contains("Calendar.app"), "the first-run card names Calendar.app, which is the only thing this app reads")
    t.expect(firstRunBody.contains("Google"), "…and names a Google account")
    t.expect(firstRunBody.contains("Outlook"), "…and an Outlook account")
    t.expect(
        GuidanceCopy.popover(.noCalendars).contains("Calendar.app"),
        "the popover's empty-Calendar state names Calendar.app too, for the user who meets it without ever reading the card"
    )
    t.expect(
        GuidanceCopy.popover(.noCalendars).contains("Google") && GuidanceCopy.popover(.noCalendars).contains("Outlook"),
        "…and names the two accounts as well"
    )

    // The denied copy has to state the recovery in words, not only in a
    // button: macOS never re-prompts, and the button's URL is the one part of
    // this feature nobody could verify (GuidanceTarget's UNVERIFIED note). A
    // user whose button lands on the wrong pane still has the path.
    let deniedBody = GuidanceCopy.body(.accessDenied)
    t.expect(deniedBody.contains("System Settings"), "the denied card names System Settings in words")
    t.expect(deniedBody.contains("Privacy & Security"), "…and the pane")
    t.expect(deniedBody.contains("Calendars"), "…and the section inside it")
    t.expect(
        GuidanceCopy.popover(.accessDenied).contains("Privacy & Security"),
        "the popover's denied state carries the same path, since it is where the user lands after the card is gone"
    )

    // The translocated card names the fix in words, the same way the other
    // two name theirs, and never claims the problem is a permission — it is
    // not "System Settings" here, and "Calendar" appears only as the reason
    // moving the app matters, never as something to configure.
    let translocatedBody = GuidanceCopy.body(.translocated)
    t.expect(translocatedBody.contains("Applications"), "the translocated card names the Applications folder")
    t.expect(!translocatedBody.contains("System Settings"), "…and never sends the user to Settings — there is no permission to fix")

    // A button label names where it goes. The body says Calendar.app and the
    // button opens System Settings, which is only honest if the label says so.
    t.expect(
        GuidanceCopy.action(.firstRun).lowercased().contains("account"),
        "the first-run button says it adds an account — got '\(GuidanceCopy.action(.firstRun))'"
    )
    t.expect(
        !GuidanceCopy.action(.firstRun).contains("Calendar.app"),
        "…and does not claim to open Calendar.app, which is the fallback, not the destination"
    )
    t.expect(
        GuidanceCopy.action(.accessDenied).lowercased().contains("settings"),
        "the denied button says it opens Settings — got '\(GuidanceCopy.action(.accessDenied))'"
    )
    t.expect(
        GuidanceCopy.action(.translocated).lowercased().contains("application"),
        "the translocated button names the Applications folder it opens — got '\(GuidanceCopy.action(.translocated))'"
    )
    t.expect(
        !GuidanceCopy.dismiss.lowercased().contains("later") && !GuidanceCopy.dismiss.lowercased().contains("not now"),
        "the dismiss button promises no return, because the card does not come back — got '\(GuidanceCopy.dismiss)'"
    )

    // The quiet-afternoon sentence is the one piece of copy this unit did not
    // write: it is what the popover already said, kept verbatim so a user who
    // knows it does not meet a reworded version of the same nothing.
    t.expectEqual(
        GuidanceCopy.popover(.noMeetings),
        "Nothing else today. The card appears on its own when a meeting is close.",
        "the no-meetings sentence is unchanged from before this unit"
    )
}
