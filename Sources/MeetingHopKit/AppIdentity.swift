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
    /// Deliberately just these six, not a scan of the `UserDefaults`
    /// domain: Sparkle will later write its own `SU`-prefixed keys into
    /// this same domain, and a naive "every key in the domain starts with
    /// the identifier" check would fail the day that lands. `all` is the
    /// list a test enumerates instead.
    public enum DefaultsKeys {
        public static let leadMinutes = "\(AppIdentity.bundleIdentifier).leadMinutes"
        public static let endingLeadMinutes = "\(AppIdentity.bundleIdentifier).endingLeadMinutes"
        public static let hideWhileSharing = "\(AppIdentity.bundleIdentifier).hideWhileSharing"
        public static let dismissedMeetingIDs = "\(AppIdentity.bundleIdentifier).dismissedMeetingIDs"
        /// The first-run guidance has been answered. Written once, never
        /// cleared: a first run happens once (`OnboardingStorage`).
        public static let firstRunGuidanceSeen = "\(AppIdentity.bundleIdentifier).firstRunGuidanceSeen"
        /// The refused-permission notice has been answered. Cleared again
        /// whenever access is granted, so a permission revoked later is a
        /// new refusal rather than one an old dismissal silently swallows.
        public static let accessDeniedNoticeSeen = "\(AppIdentity.bundleIdentifier).accessDeniedNoticeSeen"

        public static let all: [String] = [
            leadMinutes, endingLeadMinutes, hideWhileSharing, dismissedMeetingIDs,
            firstRunGuidanceSeen, accessDeniedNoticeSeen,
        ]
    }

    /// Fallback values `SettingsStorage.registerDefaults(on:)` writes into
    /// `UserDefaults`, kept here (rather than only in the app target) so a
    /// Kit test can register the same fallbacks on a scratch
    /// `UserDefaults(suiteName:)` without reaching into `SettingsStore`,
    /// which lives in the app target and isn't linkable from this suite.
    public enum DefaultsValues {
        public static let leadMinutes = 2
        public static let endingLeadMinutes = 2
        public static let hideWhileSharing = true
        /// The Stepper's bound in `Settings.swift` — kept here, not just
        /// there, so `SettingsStorage.clampMinutes` can be proven from this
        /// suite.
        public static let minuteRange = 1...15
    }

    /// The storage rules `SettingsStore` applies to every property it
    /// persists: clamped `Int`s, a `Bool` that falls back to `default` on a
    /// type mismatch rather than trapping, and the registered-fallback
    /// contract `registerDefaults(on:)` promises. Pulled out of the app
    /// target — `SettingsStore` itself is unreachable from
    /// `Tests/MeetingHopKitTests` (see `Package.swift`) — so this suite can
    /// prove "a suite-scoped run with no prior writes resolves the
    /// registered fallback values inside the suite" (U8's own test
    /// scenario) against the rule `SettingsStore` actually runs, not a
    /// re-description of it that could quietly drift from the real one.
    public enum SettingsStorage {
        public static func clampMinutes(_ value: Int) -> Int {
            min(max(value, DefaultsValues.minuteRange.lowerBound), DefaultsValues.minuteRange.upperBound)
        }

        /// `object(forKey:)` + a conditional cast never traps, unlike
        /// `integer(forKey:)`'s silent-zero-on-type-mismatch: a stray
        /// non-Int value written by a future version falls back to
        /// `default` instead of quietly becoming 0 and failing the clamp in
        /// a confusing way.
        public static func storedInt(_ defaults: UserDefaults, forKey key: String, default value: Int) -> Int {
            guard let stored = defaults.object(forKey: key) as? Int else { return value }
            return clampMinutes(stored)
        }

        public static func storedBool(_ defaults: UserDefaults, forKey key: String, default value: Bool) -> Bool {
            guard let stored = defaults.object(forKey: key) as? Bool else { return value }
            return stored
        }

        /// Safe to call at launch, before anything reads a `SettingsStore`
        /// property — the per-property readers carry their own `default:`
        /// too, so this is belt-and-braces rather than load-bearing.
        public static func registerDefaults(on defaults: UserDefaults) {
            defaults.register(defaults: [
                AppIdentity.DefaultsKeys.leadMinutes: DefaultsValues.leadMinutes,
                AppIdentity.DefaultsKeys.endingLeadMinutes: DefaultsValues.endingLeadMinutes,
                AppIdentity.DefaultsKeys.hideWhileSharing: DefaultsValues.hideWhileSharing,
            ])
        }
    }

    // MARK: - Harness isolation (U8; KTD4)

    /// The launch arguments that redirect every `UserDefaults` access and
    /// the harness directory to an isolated location, and that opt the
    /// journal into carrying a raw meeting title instead of only its hash.
    ///
    /// Unlike AgentMenu's environment-variable overrides, none of these
    /// needs a second gate flag: each one *is* itself a launch argument, and
    /// `harnessSuiteName`/`harnessDirectoryOverride`/`isVerbose` below read
    /// it from the argument domain specifically — the one `UserDefaults`
    /// domain `launchctl setenv` cannot reach and a persisted `defaults
    /// write` cannot populate, so nothing but an actual launch argument can
    /// open this gate (R3). Verified empirically on this machine with a
    /// throwaway `swiftc` binary before writing this: a value persisted with
    /// `UserDefaults.standard.set(_:forKey:)` is visible to the merged
    /// `string(forKey:)` search but invisible to
    /// `volatileDomain(forName: .argumentDomain)`, while a value injected
    /// with `setVolatileDomain(_:forName: .argumentDomain)` — the same
    /// technique `JournalTests.swift`/`SettingsStoreTests.swift` use — is
    /// visible to both, exactly matching a real `-Key Value` launch
    /// argument.
    public enum HarnessArguments {
        /// `-MeetingHopDefaultsSuite <name>`: every `SettingsStore`
        /// property, its `didSet` writers, `registerDefaults(on:)`, and the
        /// `Coordinator`'s dismissed-meeting property read and write through
        /// the suite this names instead of `.standard`.
        public static let defaultsSuite = "MeetingHopDefaultsSuite"
        /// `-MeetingHopHarnessDir <path>`: relocates the harness journal's
        /// directory away from `~/Library/Application Support/
        /// dev.facens.meetinghop/harness/`.
        public static let harnessDir = "MeetingHopHarnessDir"
        /// `-MeetingHopVerbose YES`: the only way a raw meeting title ever
        /// reaches the journal (see `JournalData.cardShown`). Its own
        /// refusal — the app-fresh tier exits 2 rather than honouring it,
        /// and the gate refuses any report built from a run that set it —
        /// is U14's, not this unit's; this file only makes the flag
        /// readable and echoes it onto `harness started` so that refusal is
        /// something a later reader can actually check for.
        public static let verbose = "MeetingHopVerbose"
    }

    /// Reads `key` from the argument domain only — never the merged search
    /// `UserDefaults.string(forKey:)` performs, which would also return a
    /// value some earlier run left behind with a plain, persisted `defaults
    /// write`. `defaults` defaults to `.standard` because the argument
    /// domain is a process-global volatile domain every `UserDefaults`
    /// instance exposes the same way; a test injects one with
    /// `setVolatileDomain(_:forName: .argumentDomain)`.
    private static func argumentValue(_ key: String, defaults: UserDefaults) -> String? {
        let argv = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        guard let value = argv[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// The suite name `-MeetingHopDefaultsSuite` named, or `nil` when the
    /// argument is absent — the standard domain is the normal case.
    public static func harnessSuiteName(defaults: UserDefaults = .standard) -> String? {
        argumentValue(HarnessArguments.defaultsSuite, defaults: defaults)
    }

    /// The `UserDefaults` every reader and writer in the app takes (KTD4).
    public static func activeDefaults(defaults: UserDefaults = .standard) -> UserDefaults {
        guard let suite = harnessSuiteName(defaults: defaults) else { return .standard }
        return UserDefaults(suiteName: suite) ?? .standard
    }

    /// Where the harness journal lives: `-MeetingHopHarnessDir <path>` when
    /// set, tilde-expanded, otherwise `Journal.defaultDirectory` —
    /// `~/Library/Application Support/dev.facens.meetinghop/harness/`.
    public static func harnessDirectory(defaults: UserDefaults = .standard) -> URL {
        guard let path = argumentValue(HarnessArguments.harnessDir, defaults: defaults) else {
            return Journal.defaultDirectory
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// `-MeetingHopVerbose YES`, read the same argument-domain-only way as
    /// the two overrides above. Compared against the literal string `"YES"`
    /// because that is what `-Key YES` on argv actually parses to in the
    /// argument domain — never a `Bool` — matching the empirical check
    /// AgentMenu's own `OverridesTests.swift` documents for the equivalent
    /// flag there.
    public static func isVerbose(defaults: UserDefaults = .standard) -> Bool {
        argumentValue(HarnessArguments.verbose, defaults: defaults) == "YES"
    }
}
