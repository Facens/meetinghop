import Foundation
import MeetingHopKit

/// The launch-at-login prompt's decision and its "ask once" persistence —
/// the two halves the brief asks for tests of. The view and the actual
/// `SMAppService` call are unreachable from this suite for the same reason
/// `Onboarding`'s own tests give: `Tests/MeetingHopKitTests` links
/// `MeetingHopKit` alone (`Package.swift`), which is exactly why `decide` and
/// `Storage` live there rather than only inside `Coordinator`.
func runLaunchAtLoginPromptTests(_ t: TestRunner) {
    t.suite("LaunchAtLoginPrompt")

    // MARK: - 1. Happy path: shown once, for everyone — including someone
    // whose calendars already work, the same unconditional rule
    // `Onboarding.decide` states for the first-run card.

    t.expectEqual(
        LaunchAtLoginPrompt.decide(translocated: false, alreadyEnabled: false, asked: false),
        .show,
        "a launch nobody has answered yet, and that is not already enabled, is asked"
    )
    t.expectEqual(
        LaunchAtLoginPrompt.decide(translocated: false, alreadyEnabled: false, asked: true),
        .suppress(.alreadyAsked),
        "answered once, it does not come back"
    )

    // MARK: - 2. Already enabled (without ever being asked) is suppressed
    // and marked asked in the same motion — someone who turned the Settings
    // toggle on themselves has answered the question in the only way that
    // matters, and is never bothered with the prompt.

    t.expectEqual(
        LaunchAtLoginPrompt.decide(translocated: false, alreadyEnabled: true, asked: false),
        .suppress(.alreadyEnabled),
        "a user who already enabled it through Settings, and was never asked, is never asked at all"
    )

    // MARK: - 2b. Already asked outranks already enabled, checked first on
    // purpose — see `decide`'s own doc comment. This is exactly what
    // `launch-at-login-reboot.sh` proves on a real relaunch: once accepting
    // the prompt registers the login item, EVERY later launch finds
    // `alreadyEnabled` true too (that is what "it relaunched at login" IS),
    // and the only honest report left is the one this domain actually
    // remembers.

    t.expectEqual(
        LaunchAtLoginPrompt.decide(translocated: false, alreadyEnabled: true, asked: true),
        .suppress(.alreadyAsked),
        "once asked, later launches report .alreadyAsked even though accepting also left it enabled — "
            + "never .alreadyEnabled again, which would be indistinguishable from never having been asked at all"
    )

    // MARK: - 3. Translocation always wins, whatever else is true — the same
    // shape `Onboarding.decide` proves for `.translocated` guidance, and for
    // the analogous reason: `SMAppService.mainApp.register()` would point at
    // a mount that will not exist by the next launch.

    for alreadyEnabled in [true, false] {
        for asked in [true, false] {
            t.expectEqual(
                LaunchAtLoginPrompt.decide(translocated: true, alreadyEnabled: alreadyEnabled, asked: asked),
                .suppress(.translocated),
                "translocated always suppresses as .translocated, whatever else is true "
                    + "(alreadyEnabled: \(alreadyEnabled), asked: \(asked))"
            )
        }
    }

    // MARK: - 4. Every scalar a scenario asserts on is non-empty and
    // lower-snake, the same rule `OnboardingTests` holds `GuidanceState`'s
    // own scalars to.

    for scalar in LaunchAtLoginPromptSuppression.allCases.map(\.rawValue) {
        t.expect(!scalar.isEmpty, "a suppression scalar is non-empty")
        t.expect(
            scalar.allSatisfy { $0.isLowercase || $0 == "_" },
            "a suppression scalar is lower-snake — got '\(scalar)'"
        )
    }
    t.expectEqual(
        Set(LaunchAtLoginPromptSuppression.allCases.map(\.rawValue)).count,
        LaunchAtLoginPromptSuppression.allCases.count,
        "no two suppression reasons share a scalar"
    )

    // MARK: - 5. Storage: "asked" defaults false, round-trips through
    // `remember`, and — unlike `OnboardingStorage`'s `accessDenied` key —
    // carries no `forget`: once asked, it stays asked forever, the same
    // "a first run happens once" rule the first-run guidance flag follows.

    do {
        let suiteName = "LaunchAtLoginPromptTests.storage.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        t.expect(
            !LaunchAtLoginPromptStorage.asked(in: scratch),
            "a suite with no prior writes has not asked yet"
        )
        LaunchAtLoginPromptStorage.remember(in: scratch)
        t.expect(
            LaunchAtLoginPromptStorage.asked(in: scratch),
            "remembering marks it asked, read back from the same suite"
        )
    }

    // MARK: - 6. Isolation, mirroring `SettingsStoreTests`'s own case for the
    // guidance flags: a suite-scoped write must not land in `.standard`, or
    // a harness run would leave the maintainer's real machine believing it
    // had already asked.

    do {
        let suiteName = "LaunchAtLoginPromptTests.isolation.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        LaunchAtLoginPromptStorage.remember(in: scratch)
        t.expect(
            UserDefaults.standard.object(forKey: AppIdentity.DefaultsKeys.launchAtLoginPromptAsked) == nil,
            "the answer does not land in .standard from a suite-scoped write"
        )
    }

    // MARK: - 7. The key is namespaced under the bundle identifier, the same
    // rule `AppIdentityTests` already holds every other key to (proven again
    // here as a direct, named assertion rather than relying only on the
    // generic loop over `DefaultsKeys.all`).

    t.expect(
        AppIdentity.DefaultsKeys.launchAtLoginPromptAsked.hasPrefix(AppIdentity.bundleIdentifier + "."),
        "the launch-at-login-asked key is namespaced under the bundle identifier"
    )

    // MARK: - 8. The copy. Same rules `OnboardingTests` holds `GuidanceCopy`
    // to: no exclamation marks, no apology, and — the one place this prompt
    // is allowed to differ from `GuidanceCopy.dismiss` — "Not Now" is
    // exactly what the decline button says, because it is honest here (see
    // `LaunchAtLoginPromptCopy`'s own doc comment).

    let allCopy = [
        LaunchAtLoginPromptCopy.title, LaunchAtLoginPromptCopy.body,
        LaunchAtLoginPromptCopy.accept, LaunchAtLoginPromptCopy.decline,
    ]
    for line in allCopy {
        t.expect(!line.isEmpty, "no piece of copy is empty")
        t.expect(!line.contains("!"), "no exclamation marks — got '\(line)'")
        let lowered = line.lowercased()
        for apology in ["oops", "sorry", "we apologise", "we apologize", "unfortunately"] {
            t.expect(!lowered.contains(apology), "no apology: '\(apology)' appears in '\(line)'")
        }
    }
    t.expectEqual(LaunchAtLoginPromptCopy.accept, "Launch at Login", "the accept button's literal label, as the brief asks for")
    t.expectEqual(LaunchAtLoginPromptCopy.decline, "Not Now", "the decline button's literal label, as the brief asks for")
    t.expect(
        LaunchAtLoginPromptCopy.body.contains("Settings"),
        "the body says the choice can be changed in Settings later, which is what makes 'Not Now' honest"
    )
}
