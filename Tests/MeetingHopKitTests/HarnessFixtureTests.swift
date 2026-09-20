import Foundation
import MeetingHopKit

/// U10: every R10 scenario as a file, plus the fixture builders they name
/// through `fixture <name> [args...]` (harness/lib/scenario.sh) — the same
/// shape AgentMenu's own `Tests/AgentMenuKitTests/HarnessFixtureTests.swift`
/// proved for U9, adapted to what this unit actually owns: five scenarios
/// that grant or deny Calendar access, seed a local calendar and one Zoom
/// meeting, and reboot the guest.
///
/// This suite never launches MeetingHop, never opens Calendar.app for real,
/// and never reboots anything. Everything it checks is either static (a
/// script parses, an AppleScript file compiles against this machine's own
/// Calendar dictionary, a scenario carries the stranger-only marker, a
/// fixture file is free of the maintainer's own username and home path) or
/// a real run of a fixture's `apply.sh` against a scratch `$HOME`, through
/// the real `fixture()` dispatch in the real `harness/lib/scenario.sh`
/// (sourced directly), with `defaults` AND `osascript` stubbed on `PATH`:
/// `defaults` so `fx_activate_journal`
/// (`harness/fixtures/meetinghop/_lib.sh`) never reaches the real
/// `dev.facens.meetinghop` preferences domain on whatever machine runs this
/// suite (the exact hazard this checkout's own ground rules call out —
/// `defaults write` resolves through the operating system's own user
/// record, not a `$HOME` override), and `osascript` so
/// `harness/fixtures/meetinghop/calendar/apply.sh` never actually drives
/// Calendar.app — real Calendar interaction needs a real, disposable
/// stranger-tier guest, not this machine.
///
/// What this suite does NOT attempt, and why: `install_app`'s own success
/// path ends in a real `mv` into `/Applications` and a real `open`
/// (`harness/guest/install.sh`), a real Gatekeeper/Calendar dialog needs one
/// actually on screen, a real Join click needs a real running app, and a
/// real reboot needs a real, disposable VM — none of that exists on the
/// machine this suite runs on, and none of it may be risked here. See this
/// unit's own report for the full list of what still needs the stranger-tier
/// VM.
func runHarnessFixtureTests(_ t: TestRunner) {
    t.suite("HarnessFixture")

    let root = repositoryRoot()
    let harnessDir = root.appendingPathComponent("harness")
    let fixturesDir = harnessDir.appendingPathComponent("fixtures/meetinghop")
    let scenariosDir = harnessDir.appendingPathComponent("scenarios/meetinghop")

    guard FileManager.default.fileExists(atPath: fixturesDir.path) else {
        t.expect(false, "harness/fixtures/meetinghop is missing at \(fixturesDir.path) — this suite fails rather than skipping")
        return
    }

    hfix_testShellFilesParseAndAreExecutable(t, harnessDir: harnessDir, fixturesDir: fixturesDir, scenariosDir: scenariosDir)
    hfix_testSeedCalendarAppleScript(t, fixturesDir: fixturesDir)
    hfix_testScenariosAreStrangerOnly(t, scenariosDir: scenariosDir)
    hfix_testFixtureFilesAreSynthetic(t, fixturesDir: fixturesDir)
    hfix_testScenarioClicksNameKnownIdentifiers(t, scenariosDir: scenariosDir)
    hfix_testPathHashMatchesAccessibilityID(t, harnessDir: harnessDir)
    hfix_testBaseFixture(t, harnessDir: harnessDir)
    hfix_testCalendarFixtureWithoutEvent(t, harnessDir: harnessDir)
    hfix_testCalendarFixtureWithEvent(t, harnessDir: harnessDir)
    hfix_testCalendarFixtureFailsLoudlyWithoutUID(t, harnessDir: harnessDir)
}

// MARK: - Every new shell file parses under `bash -n`, and every apply.sh /
// scenario is executable. Mirrors HarnessScriptTests.swift's / AgentMenu's
// own HarnessFixtureTests.swift's equivalent check.

private let hfix_scenarioNames = [
    "access-denied",
    "no-accounts",
    "nothing-upcoming",
    "meeting-in-three",
    "launch-at-login-reboot",
]

private func hfix_testShellFilesParseAndAreExecutable(
    _ t: TestRunner, harnessDir: URL, fixturesDir: URL, scenariosDir: URL
) {
    var files: [String] = [
        // Shared, not owned by this unit — read-only sanity check that it is
        // actually there and parses, since harness/scenarios/meetinghop/
        // meeting-in-three.sh depends on it directly.
        harnessDir.appendingPathComponent("lib/fixtures.sh").path,
        fixturesDir.appendingPathComponent("_lib.sh").path,
        fixturesDir.appendingPathComponent("base/apply.sh").path,
        fixturesDir.appendingPathComponent("calendar/apply.sh").path,
    ]
    for scenario in hfix_scenarioNames {
        files.append(scenariosDir.appendingPathComponent("\(scenario).sh").path)
    }

    for path in files {
        guard FileManager.default.fileExists(atPath: path) else {
            t.expect(false, "expected file is missing at \(path)")
            continue
        }
        let parsed = runProcess("/bin/bash", ["-n", path])
        t.expectEqual(parsed.status, 0, "\(path) parses — \(parsed.stderr)")
        t.expect(FileManager.default.isExecutableFile(atPath: path), "\(path) is executable")
    }
}

// MARK: - seed-calendar.applescript: compiles against this machine's own
// Calendar.app dictionary (syntax and term resolution only — this proves
// the vocabulary parses, never that it behaves correctly against a real,
// empty "On My Mac" source; see the file's own UNVERIFIED header), plus
// every argument-validation path that raises before ever reaching `tell
// application "Calendar"` — safe to run for real, the same reasoning
// HarnessGuestTests.swift already applies to ax.applescript/dialogs.applescript.

private func hfix_testSeedCalendarAppleScript(_ t: TestRunner, fixturesDir: URL) {
    let script = fixturesDir.appendingPathComponent("seed-calendar.applescript").path
    guard FileManager.default.isReadableFile(atPath: script) else {
        t.expect(false, "harness/fixtures/meetinghop/seed-calendar.applescript is missing or not readable at \(script)")
        return
    }

    do {
        let out = NSTemporaryDirectory() + "seed-calendar-compile-check-\(UUID().uuidString).scpt"
        let compiled = runProcess("/usr/bin/osacompile", ["-o", out, script])
        defer { try? FileManager.default.removeItem(atPath: out) }
        t.expectEqual(compiled.status, 0, "seed-calendar.applescript compiles against this machine's own Calendar.app dictionary (syntax and term resolution only): \(compiled.stderr)")
    }

    let usageCases: [(args: [String], expectedSubstring: String, what: String)] = [
        ([], "a verb is required", "no verb at all"),
        (["bogus-verb"], "unknown verb", "an unrecognized verb"),
        (["calendar"], "calendar requires a name", "calendar with no name"),
        (["event", "Cal"], "event requires", "event with too few arguments"),
    ]
    for testCase in usageCases {
        let result = runProcess("/usr/bin/osascript", [script] + testCase.args)
        t.expect(result.status != 0, "\(testCase.what) is refused (nonzero exit) — got status \(result.status)")
        t.expect(
            result.stderr.contains(testCase.expectedSubstring),
            "\(testCase.what) names '\(testCase.expectedSubstring)' in its refusal — got: \(result.stderr)"
        )
    }
}

// MARK: - Every scenario clicks, drives a dialog, or takes a screenshot, so
// every scenario declares HARNESS_STRANGER_ONLY — the exact marker
// harness/run.sh greps for (`grep -q '^# HARNESS_STRANGER_ONLY'`) before it
// will refuse a scenario on the app-fresh tier.

private func hfix_testScenariosAreStrangerOnly(_ t: TestRunner, scenariosDir: URL) {
    for scenario in hfix_scenarioNames {
        let path = scenariosDir.appendingPathComponent("\(scenario).sh").path
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            t.expect(false, "could not read \(path)")
            continue
        }
        let hasMarker = content.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.hasPrefix("# HARNESS_STRANGER_ONLY") }
        t.expect(hasMarker, "\(scenario).sh declares # HARNESS_STRANGER_ONLY at the start of a line, matching harness/run.sh's own grep")
    }
}

// MARK: - Every fixture file is synthetic: none may contain the
// maintainer's own username or home directory.

private func hfix_testFixtureFilesAreSynthetic(_ t: TestRunner, fixturesDir: URL) {
    let realUsername = NSUserName()
    let realHome = FileManager.default.homeDirectoryForCurrentUser.path

    guard let subpaths = try? FileManager.default.subpathsOfDirectory(atPath: fixturesDir.path) else {
        t.expect(false, "could not list \(fixturesDir.path)")
        return
    }

    var checked = 0
    for subpath in subpaths {
        let fullPath = fixturesDir.appendingPathComponent(subpath).path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            continue
        }
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            continue
        }
        checked += 1
        // "dev.facens.meetinghop" is a required, public, shipped constant
        // that legitimately contains the maintainer's own reverse-DNS
        // handle as a substring — every fixture file has to name it (or the
        // bundle it's built from) to work at all. Stripped out before the
        // username check below, so the real hazard this rule guards
        // against — a fixture accidentally spelling the maintainer's own
        // home directory or account name as "realistic" content — still
        // fails loudly, without a false positive against the one string
        // that is supposed to be there.
        let withoutBundleID = content.replacingOccurrences(of: "dev.facens.meetinghop", with: "")
        t.expect(
            !withoutBundleID.contains(realUsername),
            "\(fullPath) contains the real username '\(realUsername)' outside the bundle id — every fixture file must be synthetic"
        )
        t.expect(
            !content.contains(realHome),
            "\(fullPath) contains the real home directory '\(realHome)' — every fixture file must be synthetic"
        )
    }
    t.expect(checked > 0, "at least one file was actually checked under \(fixturesDir.path) — an empty enumeration would make the two checks above vacuous")
}

// MARK: - A static form of the plan's own identifier-prediction contract:
// every literal (or hash-interpolated) identifier a scenario clicks matches
// a known AccessibilityID shape. A full, live check needs a built app and
// the stranger-tier VM (see this unit's own report).

private func hfix_testScenarioClicksNameKnownIdentifiers(_ t: TestRunner, scenariosDir: URL) {
    let knownLiterals: Set<String> = [
        "menuBar.settings",
        "settings.launchAtLoginToggle",
        "hud.join.<hash>",
        // The onboarding card, which every scenario now meets at launch:
        // `guidance.action` where the scenario is the one proving the button
        // reaches the right page, `guidance.dismiss` everywhere the card is
        // merely in the way of what the scenario was actually testing.
        "guidance.action",
        "guidance.dismiss",
    ]

    // All five call `click` now: the onboarding card appears on every launch,
    // so a scenario either answers it (access-denied.sh and no-accounts.sh
    // press its button, which is the only check anywhere that the System
    // Settings URL opens at all) or dismisses it to reach what it came for.
    // This total is asserted non-zero (the same `checked > 0` idiom
    // hfix_testFixtureFilesAreSynthetic uses) so an empty extraction across
    // every file — a broken regex, say — fails loudly instead of the whole
    // check quietly passing on nothing.
    var totalFound = 0
    for scenario in hfix_scenarioNames {
        let path = scenariosDir.appendingPathComponent("\(scenario).sh").path
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            t.expect(false, "could not read \(path)")
            continue
        }
        for identifier in hfix_clickedIdentifiers(in: content) {
            totalFound += 1
            t.expect(knownLiterals.contains(identifier), "\(scenario).sh clicks '\(identifier)', which does not match a known AccessibilityID shape")
        }
    }
    t.expect(totalFound > 0, "at least one click identifier was actually extracted across the five scenarios — an empty extraction would make the check above vacuous")
}

/// Every string literal (or `"prefix$VAR"` interpolation, reduced to its
/// literal parts) that `click "$BUNDLE_ID" "..."` names, across a
/// scenario's whole text. Deliberately simple — a line-oriented regex, not
/// a shell parser — because the five scenarios this file owns are the only
/// input it ever has to handle, and each one calls `click` with a plain
/// double-quoted second argument.
private func hfix_clickedIdentifiers(in content: String) -> [String] {
    var found: [String] = []
    let pattern = #"click\s+"\$BUNDLE_ID"\s+"([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    for line in content.split(separator: "\n") {
        let text = String(line)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let group = Range(match.range(at: 1), in: text) else { continue }
            let literal = text[group].replacingOccurrences(
                of: #"\$[A-Za-z_][A-Za-z0-9_]*"#, with: "<hash>", options: .regularExpression
            )
            found.append(literal)
        }
    }
    return found
}

// MARK: - fixtures_path_hash reproduces AccessibilityID.hash exactly:
// SHA-256, hex, first 12 characters. Computed both ways — through the real
// shell helper and through the real Swift function this test target already
// links (MeetingHopKit) — and compared, rather than hard-coding an expected
// hex string that could itself drift from AccessibilityID.hash unnoticed.

private func hfix_testPathHashMatchesAccessibilityID(_ t: TestRunner, harnessDir: URL) {
    let inputs = ["Harness Standup", "meetinghop-harness-fixture", "stub-event-uid-000111222"]
    for input in inputs {
        let expected = AccessibilityID.hash(input)
        let result = runProcess("/bin/bash", [
            "-c",
            "set -euo pipefail; . \(singleQuoted(harnessDir.path))/lib/fixtures.sh; fixtures_path_hash \(singleQuoted(input))",
        ])
        t.expectEqual(result.status, 0, "fixtures_path_hash ran for '\(input)' — \(result.stderr)")
        t.expectEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            expected,
            "fixtures_path_hash('\(input)') matches AccessibilityID.hash's own algorithm exactly — a scenario predicting a meeting id hash depends on this"
        )
    }
}

// MARK: - The fixture rig: a scratch $HOME, `defaults` and `osascript`
// stubbed on PATH, and the real harness/lib/scenario.sh sourced for real —
// the same idiom AgentMenu's own HarnessFixtureTests.swift rig uses.

private struct HFRig {
    let dir: TempDir
    let home: String
    let defaultsLog: String
    let osascriptLog: String
    let environment: [String: String]
}

/// `stubEventUID`, when non-nil, is what the stub `osascript` reports back
/// as the "uid" of a seeded event — exercising
/// `harness/fixtures/meetinghop/calendar/apply.sh`'s own success path
/// (persisting it via `fx_write_state`). `nil` makes the stub answer an
/// "event" call with no "uid" field at all, exercising that apply.sh's own
/// fail-loud check instead.
private func hfix_makeRig(_ label: String, harnessDir: URL, t: TestRunner, stubEventUID: String? = "stub-event-uid-abc123") -> HFRig? {
    let dir = TempDir(label)
    do {
        try FileManager.default.createDirectory(atPath: dir.path("home"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir.path("rundir/screenshots"), withIntermediateDirectories: true)
        for file in ["steps.ndjson", "findings.list", "journal.ndjson", "evidence.ndjson"] {
            FileManager.default.createFile(atPath: dir.path("rundir/\(file)"), contents: Data())
        }
        // A stub `defaults`: fx_activate_journal (harness/fixtures/meetinghop/_lib.sh)
        // calls the real binary otherwise, which resolves the account's
        // preferences through the operating system's own user record, not
        // through $HOME — a real hazard, not a hypothetical one (this
        // checkout's own ground rules for this unit call it out by name).
        try dir.write(
            "#!/bin/bash\necho \"defaults $*\" >> \"$DEFAULTS_LOG\"\nexit 0\n",
            to: "bin/defaults"
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path("bin/defaults"))

        // A stub `osascript`: harness/fixtures/meetinghop/calendar/apply.sh
        // calls it twice (`calendar`, and `event` when asked) against
        // harness/fixtures/meetinghop/seed-calendar.applescript. Real
        // Calendar.app interaction needs the stranger-tier VM (see this
        // unit's own report) — this stub never opens Calendar.app at all,
        // it answers by inspecting its own argv, the same idiom
        // HarnessGuestTests.swift's hg_writeOsascriptStub already uses for
        // ax.applescript/dialogs.applescript.
        let uidField = stubEventUID.map { "\"uid\":\"\($0)\"" } ?? "\"uid\":null"
        let osascriptStub = """
        #!/bin/bash
        printf 'osascript %s\\n' "$*" >> "$OSASCRIPT_LOG"
        verb="$2"
        case "$verb" in
          calendar)
            printf '{"calendar":"%s"}\\n' "$3"
            ;;
          event)
            printf '{"calendar":"%s","title":"%s","start":"2026-01-01T00:00:00Z",\(uidField)}\\n' "$3" "$4"
            ;;
          probe)
            echo '{"calendars":[]}'
            ;;
          *)
            echo '{"error":"stub: unknown verb"}' >&2
            exit 1
            ;;
        esac
        """
        try dir.write(osascriptStub, to: "bin/osascript")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path("bin/osascript"))
    } catch {
        t.expect(false, "built the fixture rig: \(error)")
        dir.cleanup()
        return nil
    }

    let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let environment: [String: String] = [
        "HARNESS_DIR": harnessDir.path,
        "HARNESS_GUEST_TRANSPORT": "local",
        "HARNESS_GUEST_IP": "local",
        "HARNESS_GUEST_USER": "nobody",
        "HARNESS_GUEST_HOME": ".harness",
        "HARNESS_SHOT_DIR": dir.path("rundir/screenshots"),
        "HARNESS_STEPS": dir.path("rundir/steps.ndjson"),
        "HARNESS_FINDINGS": dir.path("rundir/findings.list"),
        "HARNESS_JOURNAL": dir.path("rundir/journal.ndjson"),
        "HARNESS_EVIDENCE": dir.path("rundir/evidence.ndjson"),
        "HARNESS_STEP_TIMEOUT": "10",
        "HOME": dir.path("home"),
        "DEFAULTS_LOG": dir.path("defaults.log"),
        "OSASCRIPT_LOG": dir.path("osascript.log"),
        "PATH": dir.path("bin") + ":" + existingPath,
    ]
    FileManager.default.createFile(atPath: dir.path("defaults.log"), contents: Data())
    FileManager.default.createFile(atPath: dir.path("osascript.log"), contents: Data())
    return HFRig(dir: dir, home: dir.path("home"), defaultsLog: dir.path("defaults.log"), osascriptLog: dir.path("osascript.log"), environment: environment)
}

/// Runs `body` (a real `fixture ...` call) in the rig, exactly the way
/// `harness/scenarios/meetinghop/*.sh` do.
private func hfix_runDriver(_ rig: HFRig, _ body: String) -> ScriptOutput {
    let driverPath = rig.dir.path("driver.sh")
    let script = """
    #!/bin/bash
    set -euo pipefail
    . \(singleQuoted(rig.environment["HARNESS_DIR"]!))/lib/scenario.sh
    \(body)
    """
    do {
        try script.write(toFile: driverPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: driverPath)
    } catch {
        return ScriptOutput(status: -1, stdout: "", stderr: "could not write the driver script: \(error)")
    }
    return runProcess("/bin/bash", [driverPath], environment: rig.environment)
}

// MARK: - meetinghop/base: journal activation only.

private func hfix_testBaseFixture(_ t: TestRunner, harnessDir: URL) {
    guard let rig = hfix_makeRig("hf-base", harnessDir: harnessDir, t: t) else { return }
    defer { rig.dir.cleanup() }

    let result = hfix_runDriver(rig, #"fixture meetinghop/base "nonce-base""#)
    t.expectEqual(result.status, 0, "meetinghop/base applied cleanly — \(result.stderr)")

    let defaultsLog = (try? String(contentsOfFile: rig.defaultsLog, encoding: .utf8)) ?? ""
    t.expect(defaultsLog.contains("harnessJournal -string run.ndjson"), "the fixture turns the journal on with the leaf name every scenario passes to journal_at — got: \(defaultsLog)")
    t.expect(defaultsLog.contains("harnessNonce -string nonce-base"), "the fixture echoes the run nonce into harnessNonce — got: \(defaultsLog)")

    let osascriptLog = (try? String(contentsOfFile: rig.osascriptLog, encoding: .utf8)) ?? ""
    t.expect(osascriptLog.isEmpty, "meetinghop/base never touches Calendar at all — got: \(osascriptLog)")
}

// MARK: - meetinghop/calendar, no --event: journal on, one calendar seeded,
// no event, nothing persisted to the state file.

private func hfix_testCalendarFixtureWithoutEvent(_ t: TestRunner, harnessDir: URL) {
    guard let rig = hfix_makeRig("hf-calendar-no-event", harnessDir: harnessDir, t: t) else { return }
    defer { rig.dir.cleanup() }

    let result = hfix_runDriver(rig, #"fixture meetinghop/calendar "nonce-cal-1""#)
    t.expectEqual(result.status, 0, "meetinghop/calendar with no --event applied cleanly — \(result.stderr)")

    let defaultsLog = (try? String(contentsOfFile: rig.defaultsLog, encoding: .utf8)) ?? ""
    t.expect(defaultsLog.contains("harnessJournal -string run.ndjson"), "the calendar fixture also turns the journal on")

    let osascriptLog = (try? String(contentsOfFile: rig.osascriptLog, encoding: .utf8)) ?? ""
    t.expect(osascriptLog.contains("seed-calendar.applescript calendar MeetingHop Harness"), "the fixture asks seed-calendar.applescript to ensure the calendar exists — got: \(osascriptLog)")
    t.expect(!osascriptLog.contains(" event "), "with no --event, the fixture never asks seed-calendar.applescript to seed an event — got: \(osascriptLog)")

    let stateFile = rig.home + "/.meetinghop-harness-state/event-uid"
    t.expect(!FileManager.default.fileExists(atPath: stateFile), "with no --event, nothing is persisted for a scenario to read back as a meeting id")
}

// MARK: - meetinghop/calendar --event: journal on, calendar seeded, event
// seeded, and the stub's uid persisted to the state file
// meeting-in-three.sh reads back with fixtures_guest_capture.

private func hfix_testCalendarFixtureWithEvent(_ t: TestRunner, harnessDir: URL) {
    guard let rig = hfix_makeRig("hf-calendar-event", harnessDir: harnessDir, t: t, stubEventUID: "stub-event-uid-abc123") else { return }
    defer { rig.dir.cleanup() }

    let result = hfix_runDriver(rig, #"fixture meetinghop/calendar "nonce-cal-2" --event "Harness Standup" 3 30 "https://zoom.us/j/5551234567?pwd=HarnessSyntheticPwd42""#)
    t.expectEqual(result.status, 0, "meetinghop/calendar --event applied cleanly — \(result.stderr)")

    let osascriptLog = (try? String(contentsOfFile: rig.osascriptLog, encoding: .utf8)) ?? ""
    t.expect(osascriptLog.contains("seed-calendar.applescript calendar MeetingHop Harness"), "the fixture still ensures the calendar exists first — got: \(osascriptLog)")
    t.expect(osascriptLog.contains("seed-calendar.applescript event MeetingHop Harness Harness Standup"), "the fixture asks seed-calendar.applescript to seed the event with the title this scenario passed — got: \(osascriptLog)")
    t.expect(osascriptLog.contains("zoom.us/j/5551234567"), "the Zoom location reaches seed-calendar.applescript unchanged — got: \(osascriptLog)")

    let stateFile = rig.home + "/.meetinghop-harness-state/event-uid"
    guard let uid = try? String(contentsOfFile: stateFile, encoding: .utf8) else {
        t.expect(false, "the fixture persisted the seeded event's uid at \(stateFile), for a scenario to read back with fixtures_guest_capture")
        return
    }
    t.expectEqual(uid, "stub-event-uid-abc123", "the persisted uid is exactly what seed-calendar.applescript reported back, unmodified")
}

// MARK: - meetinghop/calendar --event fails loudly (never silently) when
// seed-calendar.applescript reports no uid at all — this unit's own
// instruction ("make the fixture fail loudly rather than silently seed
// nothing").

private func hfix_testCalendarFixtureFailsLoudlyWithoutUID(_ t: TestRunner, harnessDir: URL) {
    guard let rig = hfix_makeRig("hf-calendar-no-uid", harnessDir: harnessDir, t: t, stubEventUID: nil) else { return }
    defer { rig.dir.cleanup() }

    let result = hfix_runDriver(rig, #"fixture meetinghop/calendar "nonce-cal-3" --event "Harness Standup" 3 30 "https://zoom.us/j/5551234567?pwd=HarnessSyntheticPwd42""#)
    t.expect(result.status != 0, "a seed-calendar.applescript response with no uid is refused rather than silently accepted — got exit \(result.status)")

    let stateFile = rig.home + "/.meetinghop-harness-state/event-uid"
    t.expect(!FileManager.default.fileExists(atPath: stateFile), "nothing is persisted when there is no uid to persist — a scenario reading this back must see a hard failure, not an empty or stale value")
}
