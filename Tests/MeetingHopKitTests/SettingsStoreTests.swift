import Foundation
import MeetingHopKit

// U8 — `SettingsStore` itself lives in the `MeetingHop` app target and is
// unreachable from this suite, which links `MeetingHopKit` only (see
// `Package.swift`) — the same limitation `AppIdentityTests.swift` already
// works around for `DefaultsKeys`/`DefaultsValues`. This file extends that
// precedent to the rest of what U8 moved into the Kit:
// `AppIdentity.SettingsStorage` (the clamp and the stored-value readers
// `SettingsStore`'s initializer and `didSet`s actually call) and
// `AppIdentity.activeDefaults()`/`harnessSuiteName()` (the suite resolution
// `SettingsStore.shared` and `Coordinator`'s dismissed-ids property actually
// use). Testing these here is testing the real code path, not a
// re-description of it: `SettingsStore` calls exactly these functions and
// nothing else to decide what it reads and writes.

private func harnessDefaults(_ values: [String: Any]) -> UserDefaults {
    let defaults = UserDefaults.standard
    defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    return defaults
}

private func resetHarnessDefaults() {
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
}

func runSettingsStoreTests(_ t: TestRunner) {
    t.suite("SettingsStore")

    // MARK: - 1. clampMinutes clamps both directions and leaves the middle alone

    ({
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(0), 1, "below the range clamps to the floor")
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(1), 1, "the floor is kept")
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(7), 7, "a value inside the range is unchanged")
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(15), 15, "the ceiling is kept")
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(99), 15, "above the range clamps to the ceiling")
        t.expectEqual(AppIdentity.SettingsStorage.clampMinutes(-5), 1, "a negative value clamps to the floor too")
    })()

    // MARK: - 2. storedInt/storedBool fall back to `default`, never trap, on
    // a missing key or a type mismatch — the property SettingsStore's own
    // property initializers depend on to survive a future version's stray
    // write.

    ({
        let suiteName = "SettingsStoreTests.storedValues.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        t.expectEqual(
            AppIdentity.SettingsStorage.storedInt(scratch, forKey: "missing", default: 4), 4,
            "a missing key falls back to default"
        )
        scratch.set("not an int", forKey: "wrongType")
        t.expectEqual(
            AppIdentity.SettingsStorage.storedInt(scratch, forKey: "wrongType", default: 4), 4,
            "a stray non-Int value falls back to default instead of trapping or becoming 0"
        )
        scratch.set(23, forKey: "outOfRange")
        t.expectEqual(
            AppIdentity.SettingsStorage.storedInt(scratch, forKey: "outOfRange", default: 4), 15,
            "a stored value is clamped on the way out, not just on the way in"
        )

        t.expectEqual(
            AppIdentity.SettingsStorage.storedBool(scratch, forKey: "missingBool", default: true), true,
            "a missing bool key falls back to default"
        )
        scratch.set(42, forKey: "wrongTypeBool")
        t.expectEqual(
            AppIdentity.SettingsStorage.storedBool(scratch, forKey: "wrongTypeBool", default: true), true,
            "a stray non-Bool value falls back to default"
        )
        scratch.set(false, forKey: "realBool")
        t.expectEqual(
            AppIdentity.SettingsStorage.storedBool(scratch, forKey: "realBool", default: true), false,
            "a real stored value is read back as itself"
        )
    })()

    // MARK: - 3. Edge: a suite-scoped run with no prior writes resolves the
    // registered fallback values inside the suite.

    ({
        let suiteName = "SettingsStoreTests.fallback.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        AppIdentity.SettingsStorage.registerDefaults(on: scratch)

        t.expectEqual(
            AppIdentity.SettingsStorage.storedInt(scratch, forKey: AppIdentity.DefaultsKeys.leadMinutes, default: -1),
            AppIdentity.DefaultsValues.leadMinutes,
            "with no prior write, leadMinutes resolves to the registered fallback inside the suite"
        )
        t.expectEqual(
            AppIdentity.SettingsStorage.storedInt(scratch, forKey: AppIdentity.DefaultsKeys.endingLeadMinutes, default: -1),
            AppIdentity.DefaultsValues.endingLeadMinutes,
            "same for endingLeadMinutes"
        )
        t.expectEqual(
            AppIdentity.SettingsStorage.storedBool(scratch, forKey: AppIdentity.DefaultsKeys.hideWhileSharing, default: false),
            AppIdentity.DefaultsValues.hideWhileSharing,
            "same for hideWhileSharing"
        )
    })()

    // MARK: - 4. Happy path: `AppIdentity.activeDefaults()` resolves inside
    // a suite when `-MeetingHopDefaultsSuite <name>` is present, and a value
    // written through it lands only there — not in `.standard`, not in a
    // second, differently-named suite. This is the mechanism
    // `SettingsStore`'s writers and `Coordinator`'s dismissed-ids property
    // both go through; "changing lead minutes writes only to that suite" is
    // this property plus a `set(_:forKey:)`, which case 2 above already
    // proves reads back correctly.

    ({
        let suiteName = "SettingsStoreTests.isolation.\(UUID().uuidString)"
        let otherSuiteName = "SettingsStoreTests.isolation.other.\(UUID().uuidString)"
        guard let otherSuite = UserDefaults(suiteName: otherSuiteName) else {
            t.expect(false, "could create the second scratch suite")
            return
        }
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            otherSuite.removePersistentDomain(forName: otherSuiteName)
        }

        let argv = harnessDefaults([AppIdentity.HarnessArguments.defaultsSuite: suiteName])
        defer { resetHarnessDefaults() }

        let resolved = AppIdentity.activeDefaults(defaults: argv)
        resolved.set(9, forKey: AppIdentity.DefaultsKeys.leadMinutes)

        t.expectEqual(
            resolved.object(forKey: AppIdentity.DefaultsKeys.leadMinutes) as? Int, 9,
            "the write lands in the resolved suite"
        )
        t.expect(
            UserDefaults.standard.object(forKey: AppIdentity.DefaultsKeys.leadMinutes) as? Int != 9,
            "the write does not land in .standard"
        )
        // Not "is nil": a suite instance's search list still reaches the
        // registration domain, which another suite in this process may have
        // filled with a fallback for the same key. What isolation means here
        // is that the *written* value does not travel, so that is what this
        // asks.
        t.expect(
            (otherSuite.object(forKey: AppIdentity.DefaultsKeys.leadMinutes) as? Int) != 9,
            "the write does not land in a second, differently-named suite"
        )
    })()

    // MARK: - 5. Edge: with no argument, behavior and keys are unchanged —
    // `activeDefaults()` is exactly `.standard`, and the keys `SettingsStore`
    // reads and writes are still the four this app has always defined.

    ({
        let argv = harnessDefaults([:])
        defer { resetHarnessDefaults() }
        t.expect(
            AppIdentity.activeDefaults(defaults: argv) === UserDefaults.standard,
            "with no suite argument, the active defaults are exactly .standard, unchanged from before this unit"
        )
        t.expectEqual(
            AppIdentity.DefaultsKeys.all,
            [
                AppIdentity.DefaultsKeys.leadMinutes,
                AppIdentity.DefaultsKeys.endingLeadMinutes,
                AppIdentity.DefaultsKeys.hideWhileSharing,
                AppIdentity.DefaultsKeys.dismissedMeetingIDs,
                AppIdentity.DefaultsKeys.firstRunGuidanceSeen,
                AppIdentity.DefaultsKeys.accessDeniedNoticeSeen,
            ],
            "the key list is the original four plus the onboarding guidance's own two"
        )
    })()

    // MARK: - 7. The onboarding guidance's dismissal is remembered through the
    // same resolver, so it lands in the harness suite during a harness run and
    // in the standard domain in real life — the property the whole "shown once,
    // never nags" rule rests on, and the one that would fail silently: a flag
    // written to `.standard` from inside a suite-scoped run would leave the
    // maintainer's own machine permanently believing it had seen the card.

    ({
        let suiteName = "SettingsStoreTests.guidance.\(UUID().uuidString)"
        let argv = harnessDefaults([AppIdentity.HarnessArguments.defaultsSuite: suiteName])
        defer {
            resetHarnessDefaults()
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let resolved = AppIdentity.activeDefaults(defaults: argv)

        t.expect(
            !OnboardingStorage.seen(.firstRun, in: resolved),
            "a suite with no prior writes has not seen the first-run card"
        )
        t.expect(
            !OnboardingStorage.seen(.accessDenied, in: resolved),
            "…nor the refused-permission notice"
        )

        OnboardingStorage.remember(.firstRun, in: resolved)
        t.expect(
            OnboardingStorage.seen(.firstRun, in: resolved),
            "the answer is read back inside the suite it was written to"
        )
        t.expect(
            UserDefaults.standard.object(forKey: AppIdentity.DefaultsKeys.firstRunGuidanceSeen) == nil,
            "the answer does not land in .standard — a harness run must not mark the real machine as onboarded"
        )
        t.expect(
            !OnboardingStorage.seen(.accessDenied, in: resolved),
            "answering one card does not answer the other: a denial is still announced after the first-run card is gone"
        )

        // The denial notice is the one that can be forgotten again, so a
        // permission revoked after being granted is announced afresh.
        OnboardingStorage.remember(.accessDenied, in: resolved)
        t.expect(OnboardingStorage.seen(.accessDenied, in: resolved), "the denial notice is remembered")
        OnboardingStorage.forget(.accessDenied, in: resolved)
        t.expect(
            !OnboardingStorage.seen(.accessDenied, in: resolved),
            "granting access forgets it, so a later refusal is announced again"
        )
        t.expect(
            OnboardingStorage.seen(.firstRun, in: resolved),
            "forgetting the denial notice leaves the first-run answer alone — a first run happens once"
        )

        // `noCalendars` has no key at all: it lives only in the popover, which
        // the user opens themselves, and a flag for it would promise a
        // suppression this app never performs.
        t.expect(
            GuidanceState.noCalendars.seenKey == nil,
            "the zero-calendars state persists nothing, because nothing about it is ever suppressed"
        )
        OnboardingStorage.remember(.noCalendars, in: resolved)
        t.expect(
            !OnboardingStorage.seen(.noCalendars, in: resolved),
            "remembering a state with no key is a no-op rather than a write under some improvised name"
        )
    })()

    // MARK: - 6. Dismissed-ids round-trip under a resolved suite — the same
    // key `Coordinator`'s `dismissedIDs` property reads and writes, proven
    // through the same resolver it uses.

    ({
        let suiteName = "SettingsStoreTests.dismissedIDs.\(UUID().uuidString)"
        let argv = harnessDefaults([AppIdentity.HarnessArguments.defaultsSuite: suiteName])
        defer {
            resetHarnessDefaults()
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let resolved = AppIdentity.activeDefaults(defaults: argv)

        t.expect(
            resolved.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs) == nil,
            "nothing stored yet under the dismissed-identifiers key inside the suite"
        )

        let stored: Set<String> = ["meeting-1", "meeting-2"]
        resolved.set(Array(stored), forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs)

        let readBack = Set(resolved.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs) ?? [])
        t.expectEqual(readBack, stored, "dismissed identifiers round-trip through the resolved suite")
    })()

    // MARK: - 7. `harnessDirectory()` relocates when `-MeetingHopHarnessDir`
    // is present, tilde-expanded, and falls back to `Journal.defaultDirectory`
    // otherwise.

    ({
        let argv = harnessDefaults([AppIdentity.HarnessArguments.harnessDir: "/tmp/meetinghop-harness-test"])
        defer { resetHarnessDefaults() }
        t.expectEqual(
            AppIdentity.harnessDirectory(defaults: argv).path, "/tmp/meetinghop-harness-test",
            "an explicit harness directory argument is honoured"
        )

        let noArgv = harnessDefaults([:])
        defer { resetHarnessDefaults() }
        t.expectEqual(
            AppIdentity.harnessDirectory(defaults: noArgv).path, Journal.defaultDirectory.path,
            "with no argument, the harness directory is exactly Journal.defaultDirectory"
        )
    })()
}
