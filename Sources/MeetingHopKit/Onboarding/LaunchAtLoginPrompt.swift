import Foundation

/// A second, first-run question, independent of `Onboarding`'s calendar
/// guidance above it: whether to open MeetingHop automatically at login.
///
/// Not a fifth `GuidanceState`. That enum's own doc comment scopes it to
/// "the four things MeetingHop may have to explain about its calendar
/// connection", and its `target`/`GuidanceTarget` machinery exists to open a
/// System Settings pane or Calendar.app — neither of which is what answering
/// this question does. A separate type here keeps that contract intact and
/// keeps this one small enough to read on its own, the same split
/// `GuidanceView` already draws against `HUDView` for a reason unrelated to
/// this one (a second panel rather than a second state of the same view).
///
/// Everything here is a pure function over primitives, for the reason
/// `Onboarding` gives for itself: `Tests/MeetingHopKitTests` links
/// `MeetingHopKit` alone and cannot reach a decision buried inside
/// `Coordinator` or a SwiftUI view.
public enum LaunchAtLoginPrompt {

    /// Whether to ask on this launch.
    ///
    /// Three rules, in this order:
    ///
    /// 1. A translocated launch is never asked, and — see `Storage` below —
    ///    never marked asked either. `SMAppService.mainApp.register()` would
    ///    point System Settings' Login Items at the read-only
    ///    AppTranslocation mount this process happens to be running from,
    ///    which will not exist by the next launch (the same reason
    ///    `Coordinator.start()` never requests calendar access from a
    ///    translocated launch either — see that guard's own doc comment).
    ///    A registration with nothing left to launch is worse than useless:
    ///    it is a Login Items entry that silently does nothing forever.
    /// 2. Already asked outranks "already enabled" — checked first,
    ///    deliberately, even though accepting the prompt always leaves both
    ///    true together. Once this app relaunches at login (`alreadyEnabled`
    ///    is now true, by construction), the only honest reason to report is
    ///    the one this domain actually remembers: the answer, not a fact
    ///    `SMAppService` would report anyway with no memory of this prompt
    ///    at all. Checking `alreadyEnabled` first would still suppress
    ///    correctly, but every relaunch afterward would report
    ///    `.alreadyEnabled` forever, which is indistinguishable from "this
    ///    was never actually asked" — exactly the fact a scenario proving
    ///    persistence across a reboot needs to tell apart.
    /// 3. Otherwise, already enabled: someone who turned the Settings toggle
    ///    on themselves, before this prompt ever got to them, has answered
    ///    the question in the only way that matters. Asking anyway would be
    ///    the nagging this whole feature exists to avoid, so this is
    ///    suppressed and marked asked in the same motion — there is no
    ///    future launch worth asking on, because there is nothing left to
    ///    offer that Settings does not already reflect as done.
    /// 4. Otherwise, once — for everyone, the same "unconditional" rule
    ///    `Onboarding.decide` states for the first-run card, and for the
    ///    same reason: an existing user who upgraded into this feature has
    ///    never been asked either, so `asked` starts `false` for them too,
    ///    with nothing here caring whether this is their first launch ever
    ///    or their hundredth.
    public static func decide(translocated: Bool, alreadyEnabled: Bool, asked: Bool) -> LaunchAtLoginPromptDecision {
        guard !translocated else {
            return .suppress(.translocated)
        }
        guard !asked else {
            return .suppress(.alreadyAsked)
        }
        guard !alreadyEnabled else {
            return .suppress(.alreadyEnabled)
        }
        return .show
    }
}

/// What `LaunchAtLoginPrompt.decide` returned, as a scalar a scenario can
/// assert on (mirrors `GuidanceDecision`'s own shape).
public enum LaunchAtLoginPromptDecision: Equatable, Sendable {
    case show
    case suppress(LaunchAtLoginPromptSuppression)
}

/// Why the prompt did not appear (`data.reason` on `launch at login prompt
/// suppressed`) — a field rather than three event names, the same choice
/// `GuidanceSuppression` makes and for the same reason: `harness/guest/
/// wait.sh` can wait for a line's presence but never for one's absence, so
/// "the prompt did not come back" is asserted as this positive instead.
public enum LaunchAtLoginPromptSuppression: String, CaseIterable, Sendable {
    case translocated
    case alreadyEnabled = "already_enabled"
    case alreadyAsked = "already_asked"
}

// MARK: - Storage

/// The one "has this been answered" flag, read and written through whichever
/// `UserDefaults` the caller hands in — `AppIdentity.activeDefaults()` in the
/// app, the same resolution `OnboardingStorage` uses (KTD4).
public enum LaunchAtLoginPromptStorage {

    /// Has the question already been settled — by an answer, or by the
    /// Settings toggle already being on?
    public static func asked(in defaults: UserDefaults) -> Bool {
        AppIdentity.SettingsStorage.storedBool(
            defaults, forKey: AppIdentity.DefaultsKeys.launchAtLoginPromptAsked, default: false
        )
    }

    /// Records that the question is settled. Called when the user answers
    /// the prompt — accepted or declined, the same "answered, not merely
    /// shown" rule `Onboarding.remember` follows — and when `decide` itself
    /// finds nothing left to ask (`.alreadyEnabled`). Never called for
    /// `.translocated`: see `decide`'s own doc comment for why that one asks
    /// again on the next real launch instead.
    public static func remember(in defaults: UserDefaults) {
        defaults.set(true, forKey: AppIdentity.DefaultsKeys.launchAtLoginPromptAsked)
    }
}

// MARK: - Copy

/// Every word the prompt puts on screen.
///
/// `decline` says "Not Now" rather than following `GuidanceCopy.dismiss`'s
/// own rule against it ("no 'Not now', which promises a later that never
/// comes"). That rule is correct for the calendar cards, which never return
/// once answered either way — but it does not apply here by accident of
/// wording, it applies because of what stays true afterward: Settings' own
/// "Launch at login" toggle (`Sources/MeetingHop/UI/Settings.swift`) is
/// still sitting right there, unaffected by declining, so "not now" is a
/// literal, honest description of what just happened rather than a promise
/// this prompt cannot keep. It never returns; the toggle does.
public enum LaunchAtLoginPromptCopy {
    public static let title = "Launch MeetingHop at login?"
    public static let body = """
    MeetingHop can open itself automatically whenever you log in, so your \
    meetings are already being tracked. You can change this later in Settings.
    """
    public static let accept = "Launch at Login"
    public static let decline = "Not Now"
}
