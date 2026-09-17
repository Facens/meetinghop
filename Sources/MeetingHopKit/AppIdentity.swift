import Foundation

/// R19: MeetingHop uses one bundle identifier everywhere — its plist
/// (`packaging/Info.plist`), its `UserDefaults` keys and its logging
/// subsystem. This is the single source of truth for that identifier and
/// for the names built from it, so the app target (`SettingsStore`,
/// `Coordinator`, `Support.swift`) has no literal of its own left to drift.
///
/// Why this is a blocker rather than a cleanup: a bundle identifier becomes
/// permanent at first public release. Changing it afterwards orphans every
/// `SMAppService` (launch-at-login) registration and resets every TCC grant
/// (Calendar access) already handed to the old one.
public enum AppIdentity {
    public static let bundleIdentifier = "dev.facens.meetinghop"

    /// Defaults keys the app itself defines, namespaced under
    /// `bundleIdentifier`.
    ///
    /// Deliberately just these four, not a scan of the `UserDefaults`
    /// domain: Sparkle will later write its own `SU`-prefixed keys into
    /// this same domain, and a naive "every key in the domain starts with
    /// the identifier" check would fail the day that lands. `all` is the
    /// list a test enumerates instead.
    public enum DefaultsKeys {
        public static let leadMinutes = "\(AppIdentity.bundleIdentifier).leadMinutes"
        public static let endingLeadMinutes = "\(AppIdentity.bundleIdentifier).endingLeadMinutes"
        public static let hideWhileSharing = "\(AppIdentity.bundleIdentifier).hideWhileSharing"
        public static let dismissedMeetingIDs = "\(AppIdentity.bundleIdentifier).dismissedMeetingIDs"

        public static let all: [String] = [
            leadMinutes, endingLeadMinutes, hideWhileSharing, dismissedMeetingIDs,
        ]
    }

    /// Fallback values `SettingsStore.registerDefaults()` writes into
    /// `UserDefaults.standard`, kept here (rather than only in the app
    /// target) so a Kit test can register the same fallbacks on a scratch
    /// `UserDefaults(suiteName:)` without reaching into `SettingsStore`,
    /// which lives in the app target and isn't linkable from this suite.
    public enum DefaultsValues {
        public static let leadMinutes = 2
        public static let endingLeadMinutes = 2
        public static let hideWhileSharing = true
    }
}
