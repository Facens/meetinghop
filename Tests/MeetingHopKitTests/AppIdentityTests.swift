import Foundation
import MeetingHopKit

/// U1/R19: MeetingHop uses one bundle identifier — `dev.facens.meetinghop` —
/// in its plist, its `UserDefaults` keys and its logging subsystem. Before
/// this unit, the app's `UserDefaults` keys and `Logger` subsystem were
/// still built from a different, previously-retired prefix while
/// `packaging/Info.plist`'s `CFBundleIdentifier` had already moved to
/// `dev.facens.meetinghop` — a silent split that would have shipped wrong.
///
/// `SettingsStore` and `Coordinator` (the actual key/subsystem call sites)
/// live in the `MeetingHop` executable target, not in `MeetingHopKit`, so
/// this Kit test suite cannot reach them directly. Per R19's own design,
/// `AppIdentity` in the Kit is the single source of truth the app target
/// reads from — so pinning `AppIdentity` here, plus the plist, is what
/// makes drift between "the identifier the app is built with" and "the
/// identifier the app *uses*" impossible: the app target has no literal of
/// its own left to drift.
///
/// Deliberately scoped: `DefaultsKeys.all` is the list of keys *the app
/// itself defines*, not a scan of the whole `UserDefaults` domain — Sparkle
/// will later write its own `SU`-prefixed keys into that same domain, and a
/// domain scan would fail the day that lands.
func runAppIdentityTests(_ t: TestRunner) {
    t.suite("AppIdentity")

    // MARK: - The identifier itself

    t.expectEqual(
        AppIdentity.bundleIdentifier, "dev.facens.meetinghop",
        "the identifier constant is the one settled value, not the previously-retired prefix"
    )

    // MARK: - The plist agrees

    do {
        let plistURL = URL(fileURLWithPath: "packaging/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String
        else {
            t.expect(false, "packaging/Info.plist is readable from the repo root and has a CFBundleIdentifier — if this trips, re-check make test's working directory")
            return
        }
        t.expectEqual(
            bundleID, AppIdentity.bundleIdentifier,
            "packaging/Info.plist's CFBundleIdentifier matches the Kit's AppIdentity constant"
        )
    }

    // MARK: - Every key the app defines begins with the identifier

    // Scoped to the app's own keys (DefaultsKeys.all), not a scan of the
    // UserDefaults domain — see the doc comment above.
    t.expect(
        !AppIdentity.DefaultsKeys.all.isEmpty,
        "the app defines at least one defaults key, so the prefix check below is not vacuous"
    )
    for key in AppIdentity.DefaultsKeys.all {
        t.expect(
            key.hasPrefix(AppIdentity.bundleIdentifier + "."),
            "defaults key \(key) begins with the bundle identifier"
        )
    }

    // MARK: - Registering defaults yields the fallback, not nil

    do {
        let suiteName = "AppIdentityTests.registerDefaults.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        scratch.register(defaults: [
            AppIdentity.DefaultsKeys.leadMinutes: AppIdentity.DefaultsValues.leadMinutes,
            AppIdentity.DefaultsKeys.endingLeadMinutes: AppIdentity.DefaultsValues.endingLeadMinutes,
            AppIdentity.DefaultsKeys.hideWhileSharing: AppIdentity.DefaultsValues.hideWhileSharing,
        ])

        t.expectEqual(
            scratch.object(forKey: AppIdentity.DefaultsKeys.leadMinutes) as? Int,
            AppIdentity.DefaultsValues.leadMinutes,
            "leadMinutes reads back the registered fallback, not nil"
        )
        t.expectEqual(
            scratch.object(forKey: AppIdentity.DefaultsKeys.endingLeadMinutes) as? Int,
            AppIdentity.DefaultsValues.endingLeadMinutes,
            "endingLeadMinutes reads back the registered fallback, not nil"
        )
        t.expectEqual(
            scratch.object(forKey: AppIdentity.DefaultsKeys.hideWhileSharing) as? Bool,
            AppIdentity.DefaultsValues.hideWhileSharing,
            "hideWhileSharing reads back the registered fallback, not nil"
        )
    }

    // MARK: - Dismissed-identifiers round trip under the new key

    do {
        let suiteName = "AppIdentityTests.dismissedIDs.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        t.expect(
            scratch.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs) == nil,
            "nothing stored yet under the dismissed-identifiers key"
        )

        let stored: Set<String> = ["meeting-1", "meeting-2"]
        scratch.set(Array(stored), forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs)

        let readBack = Set(scratch.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs) ?? [])
        t.expectEqual(readBack, stored, "dismissed identifiers round-trip through the new key")
    }
}
