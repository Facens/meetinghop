import Foundation

/// The onboarding guidance: what MeetingHop tells a user who has just
/// installed it, when it tells them, and what the one button does.
///
/// Every rule here is a pure function over primitives, in the Kit rather than
/// in a view, for the reason `AccessibilityID` and `JournalData` already give:
/// `Tests/MeetingHopKitTests` is a plain executable that links `MeetingHopKit`
/// alone and cannot import the app target (see `Package.swift`), so a decision
/// buried inside `GuidanceView.swift` or `Coordinator.swift` could not be
/// proven at all. The decision of *whether* to speak is exactly the kind of
/// logic that belongs here; the panel that draws it is not.
///
/// The copy lives here too, next to the decision, matching the split
/// `Scheduler` already set for the meeting card: "the strings are built in the
/// Kit; nothing here decides wording" (`HUDModel`'s own doc comment).

// MARK: - What the guidance is about

/// One of the four things MeetingHop may have to explain about its calendar
/// connection. The raw values are the scalars a journal line carries under
/// `data.state`, so a scenario asserts on the same word this enum is named by
/// (`JournalEvent`'s own rule).
public enum GuidanceState: String, CaseIterable, Sendable {
    /// First launch: nobody has been told yet what this app reads.
    case firstRun = "first_run"
    /// Calendar access was refused. macOS does not ask twice, so this is the
    /// only place the user learns the app was told no.
    case accessDenied = "access_denied"
    /// Access is granted and Calendar.app holds no calendars at all. Never a
    /// card of its own — see `Onboarding.decide` — only the popover's own
    /// empty state, which the user opened deliberately.
    case noCalendars = "no_calendars"
    /// The running bundle is translocated (`BundleTranslocation`), so
    /// `Coordinator.start()` never even asked for calendar access — there is
    /// nothing to grant that would still be true by the next launch. This is
    /// the one state whose fix is not a permission: it is moving the app,
    /// which is also the only thing that makes it updatable later (a
    /// read-only, per-launch-random mount is nothing Sparkle can replace).
    case translocated = "translocated"

    /// The defaults key that remembers the user has answered this state, or
    /// `nil` for a state that is never persisted.
    ///
    /// `noCalendars` has no key on purpose: it is only ever shown inside the
    /// popover, which the user opens themselves. There is nothing to suppress
    /// — a surface that appears only when asked for cannot nag — and a key
    /// for it would be a promise this app never keeps.
    ///
    /// `translocated` has no key for a different reason: it is re-decided
    /// fresh on every single launch, from the CURRENT bundle path
    /// (`BundleTranslocation.isTranslocated`), never from a remembered fact —
    /// so there is nothing a "seen" flag could mean here that is not already
    /// true or false on its own. Suppressing it after one dismissal would
    /// silence the one card that explains why the app still is not working,
    /// on every later translocated launch, which is the nagging rule turned
    /// against the thing it was written to protect.
    public var seenKey: String? {
        switch self {
        case .firstRun: return AppIdentity.DefaultsKeys.firstRunGuidanceSeen
        case .accessDenied: return AppIdentity.DefaultsKeys.accessDeniedNoticeSeen
        case .noCalendars: return nil
        case .translocated: return nil
        }
    }

    /// Where this state's button goes first. The fallback is always
    /// `.calendarApp` (see `GuidanceTarget`) — except for `.translocated`,
    /// whose own target already is the fix rather than a place to look for
    /// one.
    public var target: GuidanceTarget {
        switch self {
        case .firstRun, .noCalendars: return .accountsSettings
        case .accessDenied: return .privacySettings
        case .translocated: return .applicationsFolder
        }
    }
}

/// Where the button actually sends the user, as a scalar a scenario can
/// assert on (`data.target`).
///
/// UNVERIFIED, and deliberately so: no one may open either pane from this
/// machine to check (the maintainer is sitting at it), so what follows is
/// what the system's own bundles state, not what was observed.
///
///   * Both panes opt into the scheme themselves, on this macOS 26.6:
///     `SecurityPrivacyExtension.appex` and
///     `InternetAccountsSettingsExtension.appex` each declare
///     `allowsXAppleSystemPreferencesURLScheme = true` under
///     `EXAppExtensionAttributes`, keyed by the two bundle identifiers used
///     below. That is the part that is not guesswork.
///   * `Privacy_Calendars` is an anchor, not a guess and not a localized
///     string: it is a top-level key in the privacy pane's own
///     `Resources/*.lproj/PrivacySecurity.searchTerms`, whose value is the
///     section's search entry ("Allow applications to access Calendar"), and
///     it sits in the extension binary's string table immediately beside
///     `Privacy_Pasteboard`/`privacy-pasteboard`/`SectionServiceList`. It is
///     how Settings' own search navigates to that section.
///   * What remains unproven is whether the `x-apple.systempreferences:`
///     handler forwards that anchor to the extension on this OS version. If
///     it does not, Settings opens on the privacy pane without scrolling to
///     Calendars — the user is one screen away rather than in the wrong app,
///     which is why an anchor is worth carrying at all.
///   * The accounts pane gets no anchor. Nothing in that extension's binary
///     or plist names one, and inventing a fragment that silently lands
///     somewhere else is exactly what the maintainer ruled out.
public enum GuidanceTarget: String, CaseIterable, Sendable {
    /// System Settings ▸ Internet Accounts: the page where a Google or
    /// Outlook account is actually added. Opening Calendar.app shows the user
    /// the problem; this is the only one of the three that takes them
    /// somewhere they can fix it.
    case accountsSettings = "accounts_settings"
    /// System Settings ▸ Privacy & Security ▸ Calendars: the only way back
    /// from a refused permission, since macOS never re-prompts.
    case privacySettings = "privacy_settings"
    /// Calendar.app itself, opened by bundle identifier through
    /// `NSWorkspace`. The fallback, never the first choice: it shows the user
    /// exactly what MeetingHop reads, which is worth something when a
    /// Settings URL does not open, and nothing when it does.
    case calendarApp = "calendar_app"
    /// `/Applications`, revealed in Finder. Not a System Settings pane like
    /// the two above: what a translocated launch needs fixed is the app's
    /// own location, not a permission, so this is the only target here that
    /// is a plain file URL rather than an `x-apple.systempreferences:` one.
    case applicationsFolder = "applications_folder"

    /// The URL to hand `NSWorkspace.open`, or `nil` for `.calendarApp`, which
    /// is resolved from a bundle identifier instead and so has no literal URL
    /// this enum could carry.
    public var url: URL? {
        switch self {
        case .accountsSettings:
            return URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
        case .privacySettings:
            return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars")
        case .calendarApp:
            return nil
        case .applicationsFolder:
            return URL(fileURLWithPath: "/Applications")
        }
    }

    /// Calendar.app's bundle identifier. Stable since iCal was renamed, and
    /// the documented way to find an app without hard-coding a path that a
    /// future macOS may move.
    public static let calendarBundleIdentifier = "com.apple.iCal"
}

/// Which surface a button press came from, as a scalar (`data.source`), so a
/// scenario can tell the first-run card's own button from the same action
/// offered inside the popover.
public enum GuidanceSource: String, CaseIterable, Sendable {
    case card
    case popover
}

/// Why nothing was shown, as a scalar (`data.reason`). A field rather than a
/// second event name, the same shape `JournalData.cardConcealed` uses, so a
/// later reason needs no new vocabulary.
public enum GuidanceSuppression: String, CaseIterable, Sendable {
    case alreadySeen = "already_seen"
}

/// What the app does about the guidance on this launch. `suppress` carries the
/// state it would have shown, so the journal says which card stayed away and
/// why — the only way a scenario can prove the no-nag rule, since a matcher
/// that waits for a line cannot wait for the absence of one.
public enum GuidanceDecision: Equatable, Sendable {
    case show(GuidanceState)
    case suppress(GuidanceState, reason: GuidanceSuppression)
}

/// What the popover says in place of a meeting list.
///
/// Three cases, not two, because `calendars counted: 0` and `upcoming
/// counted: 0` are different problems for the user and the journal has
/// distinguished them since U8. Before this unit the popover did not: an empty
/// Calendar.app and a quiet afternoon both read "Nothing else today", which is
/// true in one case and a falsehood in the other.
public enum CalendarEmptyState: String, CaseIterable, Sendable {
    case accessDenied
    case noCalendars
    case noMeetings

    /// The guidance this empty state offers a button for, or `nil` when there
    /// is nothing to do — a day with no meetings left needs no action.
    public var guidance: GuidanceState? {
        switch self {
        case .accessDenied: return .accessDenied
        case .noCalendars: return .noCalendars
        case .noMeetings: return nil
        }
    }
}

// MARK: - The rules

public enum Onboarding {

    /// Whether to speak on this launch, and about what.
    ///
    /// Three rules, in this order:
    ///
    /// 0. Translocation wins over everything, including a refusal: it is
    ///    checked before calendar access is even requested
    ///    (`Coordinator.start()`), so `accessGranted` for a translocated
    ///    launch is always `false` without ever having been *refused* —
    ///    showing `.accessDenied` there would tell the user to turn back on
    ///    a permission nobody actually turned off. Always `.show`, never
    ///    `.suppress`: see `GuidanceState.translocated`'s own `seenKey` note
    ///    for why there is nothing here to remember.
    /// 1. Otherwise, a refused permission wins. It is the more specific
    ///    problem, it is the one macOS will never raise again on its own,
    ///    and telling someone what MeetingHop reads is beside the point
    ///    while it is not allowed to read anything.
    /// 2. Otherwise the first-run card, once, for everyone — including the
    ///    user whose calendars are already there and for whom the app simply
    ///    works. That is the maintainer's call and this function implements
    ///    it rather than second-guessing it: a card conditional on a problem
    ///    never appears for the user who is one account short of a problem
    ///    they cannot yet see.
    ///
    /// `noCalendars` is never returned. It has no card of its own on purpose:
    /// after the first-run card has said "MeetingHop reads Calendar.app; add
    /// your Google or Outlook account there", raising a second, unprompted
    /// panel to say the same thing in other words is the nagging this feature
    /// was told not to do. It earns a surface the user opens deliberately —
    /// the popover's own empty state — and that is `emptyState` below.
    public static func decide(
        translocated: Bool,
        accessGranted: Bool,
        firstRunSeen: Bool,
        accessDeniedSeen: Bool
    ) -> GuidanceDecision {
        guard !translocated else {
            return .show(.translocated)
        }
        guard accessGranted else {
            return accessDeniedSeen
                ? .suppress(.accessDenied, reason: .alreadySeen)
                : .show(.accessDenied)
        }
        return firstRunSeen
            ? .suppress(.firstRun, reason: .alreadySeen)
            : .show(.firstRun)
    }

    /// What the popover shows instead of a list of meetings, or `nil` when it
    /// has meetings to show.
    ///
    /// Denial is checked before the counts: an unauthorized store reports zero
    /// calendars too, and "add an account" is the wrong thing to tell someone
    /// whose accounts are fine and whose permission is not.
    public static func emptyState(
        accessGranted: Bool,
        calendarCount: Int,
        meetingCount: Int
    ) -> CalendarEmptyState? {
        guard accessGranted else { return .accessDenied }
        guard meetingCount == 0 else { return nil }
        return calendarCount == 0 ? .noCalendars : .noMeetings
    }
}

// MARK: - Storage

/// The two "the user has answered this" flags, read and written through
/// whichever `UserDefaults` the caller hands in — `AppIdentity.activeDefaults()`
/// in the app, which is `.standard` on a normal launch and the suite
/// `-MeetingHopDefaultsSuite <name>` names during a harness run (KTD4). No
/// call site here names `UserDefaults.standard`; that resolution belongs to
/// `AppIdentity` and to nothing else.
public enum OnboardingStorage {

    /// Has the user already answered this state? A state with no key (see
    /// `GuidanceState.seenKey`) is never "seen": there is nothing to suppress.
    public static func seen(_ state: GuidanceState, in defaults: UserDefaults) -> Bool {
        guard let key = state.seenKey else { return false }
        return AppIdentity.SettingsStorage.storedBool(defaults, forKey: key, default: false)
    }

    /// Records that the card was answered — acted on or dismissed, which
    /// amount to the same promise: it does not come back.
    public static func remember(_ state: GuidanceState, in defaults: UserDefaults) {
        guard let key = state.seenKey else { return }
        defaults.set(true, forKey: key)
    }

    /// Forgets an answer, so the state can be announced again.
    ///
    /// Called for `.accessDenied` every time access is granted: a permission
    /// the user turns back on and later revokes is a new refusal, and an old
    /// dismissal from months ago should not be what swallows the notice. The
    /// first-run flag is never forgotten — a first run happens once.
    public static func forget(_ state: GuidanceState, in defaults: UserDefaults) {
        guard let key = state.seenKey else { return }
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Copy

/// Every word the guidance puts on screen.
///
/// Written for someone who installed this five minutes ago and is looking at
/// an app that appears to work and shows them nothing: say what MeetingHop
/// reads, what may be missing, and what to do about it. No exclamation mark,
/// no apology, nothing that reads as an error dialog.
public enum GuidanceCopy {

    /// A card's heading.
    ///
    /// `.noCalendars` shares the first-run wording only to keep the switch
    /// total: no card is ever built for that state (`Onboarding.decide` never
    /// returns it), and the surface that does show it — the popover — renders
    /// `popover(_:)` instead. Anyone changing these words is changing what the
    /// first-run and denied cards say, and nothing else.
    public static func title(_ state: GuidanceState) -> String {
        switch state {
        case .firstRun, .noCalendars:
            return "MeetingHop reads Calendar.app"
        case .accessDenied:
            return "Calendar access is off"
        case .translocated:
            return "Move MeetingHop to Applications"
        }
    }

    /// The card's body. Google and Outlook are named because that is the
    /// case the confused user almost always has: their meetings are real,
    /// they are just in an account macOS has never been told about.
    ///
    /// `.noCalendars` is total-switch filler here too — see `title(_:)`.
    /// Unlike the two above it, `action(_:)` and `GuidanceState.target` do
    /// really answer for that state: the popover's own button uses both.
    public static func body(_ state: GuidanceState) -> String {
        switch state {
        case .firstRun, .noCalendars:
            return """
            Your meetings appear when the account they live in is in Calendar.app. \
            A Google or Outlook account has to be added once, in System Settings under Internet Accounts.
            """
        case .accessDenied:
            return """
            MeetingHop was refused permission to read your calendar, and macOS does not ask a second time. \
            Turn it back on in System Settings, under Privacy & Security, then Calendars.
            """
        case .translocated:
            return """
            MeetingHop is running from a temporary location macOS made for it, not from Applications. \
            Move it there and open it again to use Calendar access and get updates.
            """
        }
    }

    /// The button's label. It names where the button goes, not what the body
    /// is about: the body says Calendar.app, the button opens System Settings,
    /// and a label that blurred the two would be the dead-button problem in
    /// words instead of in code.
    public static func action(_ state: GuidanceState) -> String {
        switch state {
        case .firstRun, .noCalendars:
            return "Add an account"
        case .accessDenied:
            return "Open Privacy Settings"
        case .translocated:
            return "Open Applications Folder"
        }
    }

    /// The dismiss button. Not "Not now", which promises a later that never
    /// comes: this card is answered once and does not return.
    public static let dismiss = "Got it"

    /// The popover's sentence in place of a meeting list. Shorter than the
    /// card's: the popover is a glance, and the user standing in it has
    /// already been through the card once.
    public static func popover(_ state: CalendarEmptyState) -> String {
        switch state {
        case .accessDenied:
            return "MeetingHop cannot read your calendar. The permission was refused; turn it back on in System Settings, under Privacy & Security, then Calendars."
        case .noCalendars:
            return "Calendar.app has no calendars yet. MeetingHop reads what is in it, so add your Google or Outlook account and your meetings will follow."
        case .noMeetings:
            return "Nothing else today. The card appears on its own when a meeting is close."
        }
    }
}
