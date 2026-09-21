import Foundation
import MeetingHopKit

// U8 — the read-only state hook's journal (KTD3, R13, R16), ported from
// AgentMenuKit's own JournalTests.swift: `Journal.swift` here is the same
// security contract, reproduced byte-identical apart from the bundle
// identifier baked into `defaultDirectory`, so the same suite of refusals
// and edge cases applies unchanged. What is new below is MeetingHop's own
// event vocabulary, `AppIdentity`'s suite/directory/verbose resolution, and
// the privacy proof R13 and this unit's own scenario list both ask for: a
// fixture password and a raw join URL never reach a line on disk.
//
// Most of these cases are refusals rather than features. The key that turns
// the hook on can be set by any process running as the user, so "the writer
// declines and leaves no trace" is the behaviour under test: a journal that
// only ever appended what it was asked to would be a write primitive with a
// schema version. Each refusal here asserts the negative as well — that the
// file the key was aimed at is still exactly as it was.
//
// The app-side taps (Coordinator.swift, AppDelegate.swift) are not covered
// here: this suite links MeetingHopKit only (see Package.swift). That is why
// every rule worth proving — the name check, the cleanup rule, the cap, the
// "password and raw URL never appear" payload rule — lives in the Kit
// (Journal.swift, JournalEvent.swift) rather than at a Coordinator call site.

private let build = "1.2.3"

/// A defaults domain this test controls, holding `values` in the volatile
/// argument domain — not a named suite: a suite is a real file in the user's
/// own `~/Library/Preferences`, and neither `removePersistentDomain(forName:)`
/// nor `removeSuite(named:)` reliably deletes it, while the argument domain
/// is in memory, is the first domain `object(forKey:)` searches, and is
/// where a value handed to a launch would land anyway (KTD4) — the same
/// technique `AppIdentity`'s own doc comment documents verifying empirically
/// before this suite was written.
private func harnessDefaults(_ values: [String: Any]) -> UserDefaults {
    let defaults = UserDefaults.standard
    defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    return defaults
}

private func resetHarnessDefaults() {
    UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
}

private func journalLines(at url: URL) -> [[String: Any]] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return data.split(separator: 0x0A).compactMap {
        try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
    }
}

private func mode(of url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

func runJournalTests(_ t: TestRunner) {
    t.suite("Journal")

    // MARK: - 1. Happy path: three appended events, three lines

    ({
        let dir = TempDir("journal-happy")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")

        guard let journal = t.attempt("opening a journal in a fresh directory", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build, nonce: "abc123")
        }) else { return }

        journal.start(fixture: ["suite": .string("standard")])
        journal.append(.calendarAccess, JournalData.calendarAccess(granted: true))
        journal.append(.calendarsCounted, JournalData.counted(3))
        journal.append(.upcomingCounted, JournalData.counted(1))

        let lines = journalLines(at: file)
        t.expectEqual(lines.count, 4, "one line per event, the fixture echo first")
        t.expectEqual(lines.first?["event"] as? String, "harness started", "the first line is the fixture echo")

        let appended = Array(lines.dropFirst())
        t.expectEqual(appended.count, 3, "three appended events produce three lines")
        t.expectEqual(appended.compactMap { $0["seq"] as? Int }, [2, 3, 4], "seq increases by one per line")
        t.expectEqual(Set(appended.compactMap { $0["schema"] as? Int }), [Journal.schemaVersion], "one schema for the run")
        t.expect(appended.allSatisfy { $0["build"] as? String == build }, "every line carries the build")
        t.expect(appended.allSatisfy { $0["nonce"] as? String == "abc123" }, "every line carries the run nonce")
        t.expect(appended.allSatisfy { $0["t"] is String }, "every line is timestamped")
        t.expectEqual(
            (lines.first?["data"] as? [String: Any])?["boot"] as? Int, 1,
            "the first run of a journal is boot 1"
        )

        // The file is created inside the harness directory, at 0600, and the
        // directory itself is not readable by other users' processes.
        t.expectEqual(mode(of: file), 0o600, "the journal is created at mode 0600")
        t.expectEqual(mode(of: harness), 0o700, "the harness directory is created at mode 0700")

        let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        t.expect(raw.hasSuffix("\n"), "every line, including the last, is terminated")
        t.expectEqual(raw.split(separator: "\n").count, 4, "one line per event and no stray newlines")
    })()

    // MARK: - 2. No key set: nothing is created at all (AE6)

    ({
        let dir = TempDir("journal-inert")
        defer { dir.cleanup() }
        let defaults = harnessDefaults([:])
        defer { resetHarnessDefaults() }
        let harness = dir.url.appendingPathComponent("harness")

        let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
        guard case .inert = activation else {
            t.expect(false, "AE6: no key means inert, got \(activation)")
            return
        }
        t.expect(
            !FileManager.default.fileExists(atPath: harness.path),
            "AE6: a launch with no key does not even create the harness directory"
        )
    })()

    // MARK: - 3. A key that names a path is refused

    ({
        let dir = TempDir("journal-refused")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let escape = dir.url.appendingPathComponent("escaped.ndjson")

        let refused = ["/tmp/x", "../x", "a/b", escape.path, "..", ".", "", "a/../b", "x\ny"]
        for name in refused {
            let defaults = harnessDefaults([Journal.journalKey: name])
            defer { resetHarnessDefaults() }
            let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
            guard case .refused(let reason) = activation else {
                t.expect(false, "\(name.debugDescription) must be refused, got \(activation)")
                continue
            }
            t.expect(!reason.isEmpty, "the refusal of \(name.debugDescription) says why")
            t.expect(!reason.contains("\n"), "the refusal of \(name.debugDescription) is one line the app can log")
        }

        t.expect(!FileManager.default.fileExists(atPath: escape.path), "no file is written outside the harness directory")
        t.expect(!FileManager.default.fileExists(atPath: harness.path), "a refusal creates nothing at all, not even the harness directory")
        t.expectEqual(
            (try? FileManager.default.contentsOfDirectory(atPath: dir.url.path))?.count, 0,
            "the refusal is the only trace"
        )
    })()

    // MARK: - 4. A value that is not a string is refused

    ({
        let dir = TempDir("journal-not-a-string")
        defer { dir.cleanup() }
        let defaults = harnessDefaults([Journal.journalKey: 7])
        defer { resetHarnessDefaults() }

        let activation = Journal.activate(defaults: defaults, directory: dir.url.appendingPathComponent("harness"), build: build)
        guard case .refused = activation else {
            t.expect(false, "a number written with `defaults write -int` is not a file name, got \(activation)")
            return
        }
    })()

    // MARK: - 5. A relaunch continues the journal (seq and boot)

    ({
        let dir = TempDir("journal-relaunch")
        defer { dir.cleanup() }
        let defaults = harnessDefaults([Journal.journalKey: "journal.ndjson"])
        defer { resetHarnessDefaults() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")

        for run in 1...2 {
            let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
            guard case .writing(let journal) = activation else {
                t.expect(false, "run \(run) should write, got \(activation)")
                return
            }
            t.expectEqual(journal.bootCount, run, "the boot counter counts launches")
            journal.start(fixture: ["suite": .string("standard")])
            journal.append(.calendarAccess, JournalData.calendarAccess(granted: true))
        }

        let lines = journalLines(at: file)
        t.expectEqual(lines.count, 4, "the second launch appends rather than replacing")
        t.expectEqual(lines.compactMap { $0["seq"] as? Int }, [1, 2, 3, 4], "seq continues across a relaunch")
        let started = lines.filter { $0["event"] as? String == "harness started" }
        t.expectEqual(started.count, 2, "each launch writes a fresh harness started")
        t.expectEqual(
            started.compactMap { ($0["data"] as? [String: Any])?["boot"] as? Int }, [1, 2],
            "the second harness started carries an incremented boot counter, and seq stays unbroken across it"
        )
    })()

    // MARK: - 6. A symlink at the journal path is refused, not followed

    ({
        let dir = TempDir("journal-symlink")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        try? FileManager.default.createDirectory(at: harness, withIntermediateDirectories: true)
        let victim = dir.url.appendingPathComponent("victim.txt")
        FileManager.default.createFile(atPath: victim.path, contents: Data())
        let link = harness.appendingPathComponent("journal.ndjson")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)

        let defaults = harnessDefaults([Journal.journalKey: "journal.ndjson"])
        defer { resetHarnessDefaults() }

        let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
        guard case .refused(let reason) = activation else {
            t.expect(false, "a symlink at the journal path must be refused, got \(activation)")
            return
        }
        t.expect(reason.contains("symlink"), "the refusal names the symlink — \(reason)")
        t.expectEqual((try? Data(contentsOf: victim))?.count, 0, "the file the link pointed at was not written through")
        t.expect(
            (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil,
            "the link itself is left where it was, to be refused again"
        )
    })()

    // MARK: - 7. Anything that is not a plain file this user owns is refused

    ({
        let dir = TempDir("journal-not-regular")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        try? FileManager.default.createDirectory(
            at: harness.appendingPathComponent("journal.ndjson"),
            withIntermediateDirectories: true
        )

        t.expectThrows("a directory at the journal path is refused") {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }

        // A second name for the same bytes is the one way a regular file
        // this user owns can still be a write primitive.
        let linked = TempDir("journal-hard-link")
        defer { linked.cleanup() }
        let second = linked.url.appendingPathComponent("harness")
        let file = second.appendingPathComponent("journal.ndjson")
        if let journal = t.attempt("opening a journal to hard-link", {
            try Journal.open(directory: second, name: "journal.ndjson", build: build)
        }) {
            journal.start(fixture: [:])
        }
        try? FileManager.default.linkItem(at: file, to: linked.url.appendingPathComponent("elsewhere.ndjson"))
        t.expectThrows("a journal with a second hard link is refused") {
            try Journal.open(directory: second, name: "journal.ndjson", build: build)
        }
    })()

    // MARK: - 8. An existing journal is reopened at 0600, never truncated

    ({
        let dir = TempDir("journal-mode")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")

        if let journal = t.attempt("opening the first time", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) {
            journal.start(fixture: [:])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: file.path)

        if let journal = t.attempt("reopening a journal left group- and world-writable", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) {
            journal.append(.calendarAccess, JournalData.calendarAccess(granted: true))
        }
        t.expectEqual(mode(of: file), 0o600, "reopening restores the mode the contract promises")
        t.expectEqual(journalLines(at: file).count, 2, "reopening appends; it never truncates")
    })()

    // MARK: - 9. The cap drops the oldest lines, never the newest

    ({
        let dir = TempDir("journal-cap")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        let cap = 4096

        guard let journal = t.attempt("opening a capped journal", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build, maximumBytes: cap)
        }) else { return }

        journal.start(fixture: [:])
        for index in 1...200 {
            journal.append(.upcomingCounted, ["index": .integer(index), "pad": .string(String(repeating: "x", count: 64))])
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int ?? 0
        t.expect(size <= cap, "the journal stops growing at the cap — \(size) bytes, cap \(cap)")

        let lines = journalLines(at: file)
        t.expect(lines.count > 1, "the cap keeps more than one line")
        let sequences = lines.compactMap { $0["seq"] as? Int }
        t.expectEqual(sequences.count, lines.count, "every retained line is whole and parses")
        t.expect(sequences.first ?? 0 > 1, "the oldest lines are the ones dropped")
        t.expectEqual(sequences.last, 201, "the newest line is always kept")
        t.expectEqual(sequences, Array(sequences.sorted()), "seq never rewinds when the file is trimmed")
        t.expectEqual(
            (lines.last?["data"] as? [String: Any])?["index"] as? Int, 200,
            "the last event written is the last event on disk"
        )
        let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        t.expect(raw.hasSuffix("\n"), "a trimmed journal still ends on a line boundary")
        t.expect(!raw.hasPrefix("\n"), "a trimmed journal starts at a line boundary")
    })()

    // MARK: - 10. A launch with no key deletes the journal, and nothing else

    ({
        let dir = TempDir("journal-cleanup")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")

        if let journal = t.attempt("opening a journal to leave behind", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) {
            journal.start(fixture: [:])
        }
        // The harness run directory holds its own evidence beside the
        // journal it collects; a cleanup that deleted everything here would
        // destroy the evidence of the very run asking for the journal.
        let report = harness.appendingPathComponent("report.json")
        try? Data(#"{"verdict":"pass"}"#.utf8).write(to: report)
        let victim = dir.url.appendingPathComponent("victim.ndjson")
        try? Data("keep me\n".utf8).write(to: victim)
        try? FileManager.default.createSymbolicLink(
            at: harness.appendingPathComponent("elsewhere.ndjson"),
            withDestinationURL: victim
        )

        let defaults = harnessDefaults([:])
        defer { resetHarnessDefaults() }
        let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
        guard case .inert = activation else {
            t.expect(false, "no key means inert, got \(activation)")
            return
        }

        t.expect(!FileManager.default.fileExists(atPath: file.path), "the journal left by a previous run is deleted")
        t.expect(FileManager.default.fileExists(atPath: report.path), "a file that is not a journal is left alone")
        t.expectEqual(
            (try? String(contentsOf: victim, encoding: .utf8)), "keep me\n",
            "a symlink in the directory is not followed and its target is untouched"
        )
    })()

    // MARK: - 11. A refusal deletes nothing (the refusal is the only trace)

    ({
        let dir = TempDir("journal-refusal-keeps")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        if let journal = t.attempt("opening a journal a later refusal must not touch", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) {
            journal.start(fixture: [:])
        }

        let defaults = harnessDefaults([Journal.journalKey: "../x"])
        defer { resetHarnessDefaults() }
        _ = Journal.activate(defaults: defaults, directory: harness, build: build)

        t.expectEqual(journalLines(at: file).count, 1, "a refused key leaves an earlier journal exactly as it was")
    })()

    // MARK: - 12. An unwritable directory is reported, not crashed through
    // (the coordinator keeps running: it only ever sees this through a nil
    // `Journal?`, and every tap on it is `journal?.append(...)`)

    ({
        let dir = TempDir("journal-unwritable")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: dir.url.appendingPathComponent("harness").path
            )
            dir.cleanup()
        }
        let harness = dir.url.appendingPathComponent("harness")
        try? FileManager.default.createDirectory(at: harness, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: harness.path)

        let defaults = harnessDefaults([Journal.journalKey: "journal.ndjson"])
        defer { resetHarnessDefaults() }

        let activation = Journal.activate(defaults: defaults, directory: harness, build: build)
        guard case .refused(let reason) = activation else {
            t.expect(false, "a journal that cannot be created is refused, not fatal — got \(activation)")
            return
        }
        t.expect(!reason.isEmpty, "the refusal says why the file could not be created")
        t.expect(
            !FileManager.default.fileExists(atPath: harness.appendingPathComponent("journal.ndjson").path),
            "nothing is left behind when the file could not be created"
        )
    })()

    // MARK: - 13. `join fired`'s payload never carries a password or a raw
    // URL — the error scenario this unit's own list demands: grep the
    // journal for the fixture's password and confirm it is absent.

    ({
        let dir = TempDir("journal-join-privacy")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        guard let journal = t.attempt("opening a journal for a join", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) else { return }

        let password = "SuperSecret123"
        let url = URL(string: "https://zoom.us/j/1234567890?pwd=\(password)")!
        let data = JournalData.joinFired(url: url, meetingIDHash: AccessibilityID.hash("real-meeting-id"), ok: true)

        t.expectEqual(data["scheme"], .string("https"), "the payload carries the scheme")
        t.expectEqual(data["host"], .string("zoom.us"), "the payload carries the host")
        t.expect(data["url"] == nil, "the payload has no field carrying the URL at all")
        t.expect(data["password"] == nil, "the payload has no field carrying a password at all")

        journal.append(.joinFired, data)

        let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        t.expect(!raw.contains(password), "the fixture's password never reaches the journal")
        t.expect(!raw.contains("pwd="), "the pwd= query parameter never reaches the journal")
        t.expect(!raw.contains(url.absoluteString), "the raw join URL never reaches the journal")
        t.expect(!raw.contains("real-meeting-id"), "the raw meeting id never reaches the journal, only its hash")
        t.expect(raw.contains(AccessibilityID.hash("real-meeting-id")), "the hash of the meeting id does reach the journal")
    })()

    // MARK: - 14. `card shown` carries a hash of the title, never the title
    // itself — unless `verbose` is explicitly set, and only then. It also
    // carries a hash of the id (the Join button's own AXIdentifier suffix),
    // never the raw id, whatever `verbose` is — added 2026-09-21 so a
    // scenario can read the real click target instead of predicting it from
    // a value (Calendar's own `uid`) that turned out not to equal EventKit's
    // `eventIdentifier`.

    ({
        let id = "0CF804E9-0E66-436E-A0AC-0813001FA918:37A7FED8-124D-4F83-B342-571F95C1412A"
        let title = "1:1 with a direct report — confidential comp discussion"
        let start = Date()
        let quiet = JournalData.cardShown(id: id, title: title, start: start, count: 1, urgent: false, verbose: false)
        t.expect(quiet["title"] == nil, "with verbose off, no raw-title field is present at all")
        t.expect(quiet["id"] == nil, "the raw id is never present, verbose or not — only its hash")
        t.expectEqual(quiet["title_hash"], .string(AccessibilityID.hash(title)), "the title hash is present instead")
        t.expectEqual(quiet["id_hash"], .string(AccessibilityID.hash(id)), "…and the id hash, the same hash the Join button's own AXIdentifier carries")

        let loud = JournalData.cardShown(id: id, title: title, start: start, count: 1, urgent: false, verbose: true)
        t.expectEqual(loud["title"], .string(title), "verbose is the only way the raw title appears")
        t.expect(loud["id"] == nil, "…but never the raw id, even under verbose — nothing has asked for it")
    })()

    // MARK: - 15. `calendars counted` and `upcoming counted` are distinct
    // events, each with a scalar `count`, so a fixture failure in either
    // direction is separately diagnosable.

    ({
        let dir = TempDir("journal-counts")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        guard let journal = t.attempt("opening a journal for the count events", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) else { return }

        journal.append(.calendarsCounted, JournalData.counted(0))
        journal.append(.upcomingCounted, JournalData.counted(0))

        let lines = journalLines(at: file)
        t.expectEqual(lines.map { $0["event"] as? String }, ["calendars counted", "upcoming counted"], "two distinct events, in order")
        t.expect(
            lines.allSatisfy { ($0["data"] as? [String: Any])?["count"] as? Int == 0 },
            "count is a scalar under data on both, so wait.sh's getpath can match either independently"
        )
    })()

    // MARK: - 16. One event is always one line

    ({
        let dir = TempDir("journal-ndjson")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        guard let journal = t.attempt("opening a journal for awkward values", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build)
        }) else { return }

        journal.append(.cardConcealed, ["reason": .string("could not save:\nline two\t\"quoted\"")])
        journal.append(.cardConcealed, ["reason": .string(String(repeating: "p", count: 4000))])

        let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        t.expectEqual(raw.split(separator: "\n").count, 2, "a value carrying a newline stays on one line")
        let lines = journalLines(at: file)
        t.expectEqual(lines.count, 2, "both lines parse as JSON")
        let long = (lines.last?["data"] as? [String: Any])?["reason"] as? String ?? ""
        t.expect(
            long.count <= JournalValue.maximumStringLength,
            "one unbounded value cannot evict the run's own history — \(long.count) characters"
        )
    })()

    // MARK: - 17. A line bigger than the cap itself still terminates

    ({
        let dir = TempDir("journal-tiny-cap")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")
        let file = harness.appendingPathComponent("journal.ndjson")
        guard let journal = t.attempt("opening a journal with an unsatisfiable cap", {
            try Journal.open(directory: harness, name: "journal.ndjson", build: build, maximumBytes: 64)
        }) else { return }

        journal.start(fixture: [:])
        journal.append(.calendarAccess, JournalData.calendarAccess(granted: true))
        journal.append(.calendarAccess, JournalData.calendarAccess(granted: false))

        let lines = journalLines(at: file)
        t.expectEqual(lines.count, 1, "a cap no line can fit keeps exactly the newest line")
        t.expectEqual(lines.last?["seq"] as? Int, 3, "seq still counts every line that was written")
    })()

    // MARK: - 18. The name rule, both sides of it

    ({
        for name in ["journal.ndjson", ".journal", "a.b.c", "journal", String(repeating: "j", count: 255)] {
            t.expectNoThrow("\(name.prefix(16)) is a leaf file name") {
                try Journal.validate(name: name)
            }
        }
        for name in ["", ".", "..", "a/b", "/abs", "x..y", "a\nb", "a\u{0}b", String(repeating: "j", count: 256)] {
            t.expectThrows("\(name.debugDescription.prefix(20)) is refused") {
                try Journal.validate(name: name)
            }
        }
    })()

    // MARK: - 19. `AppIdentity.activeDefaults()` selects the journal's
    // domain (KTD4): with a suite argument, activation happens inside that
    // suite, and it is a *different* file from the standard domain's.

    ({
        let suiteName = "dev.facens.meetinghop.journaltest.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch suite")
            return
        }
        defer { suite.removePersistentDomain(forName: suiteName) }

        let argv = harnessDefaults([AppIdentity.HarnessArguments.defaultsSuite: suiteName])
        defer { resetHarnessDefaults() }

        let resolved = AppIdentity.activeDefaults(defaults: argv)
        t.expect(resolved !== UserDefaults.standard, "with a suite argument, the resolved defaults are not .standard")

        suite.set("suite-journal.ndjson", forKey: Journal.journalKey)
        let dir = TempDir("journal-suite-scoped")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")

        let activation = Journal.activate(defaults: resolved, directory: harness, build: build)
        guard case .writing(let journal) = activation else {
            t.expect(false, "a key set inside the resolved suite must activate the journal, got \(activation)")
            return
        }
        journal.start(fixture: ["suite": .string(suiteName)])
        t.expect(
            FileManager.default.fileExists(atPath: harness.appendingPathComponent("suite-journal.ndjson").path),
            "the journal is written under the suite-scoped name"
        )
    })()

    // MARK: - 20. `harnessJournal` set in the standard domain while a suite
    // argument is active produces no journal — the suite the harness
    // resolves to is isolated from wherever else that key might be set,
    // which is the whole point of KTD4's boundary.

    ({
        let suiteName = "dev.facens.meetinghop.journaltest.isolation.\(UUID().uuidString)"
        let argv = harnessDefaults([AppIdentity.HarnessArguments.defaultsSuite: suiteName])
        defer { resetHarnessDefaults() }

        // "the standard domain" here is simulated with a second, differently
        // named scratch suite rather than the process's real
        // `UserDefaults.standard` — writing into the real standard domain
        // from a test would leave a stray preference on the machine running
        // it. The property under test is domain isolation itself: a key set
        // in domain A must not be visible when the resolver names domain B,
        // which is exactly as true of two distinctly-named suites as it is
        // of one suite versus the app's real standard domain — verified
        // empirically before this suite was written (see `AppIdentity`'s
        // doc comment).
        let standardStandIn = "dev.facens.meetinghop.journaltest.standin.\(UUID().uuidString)"
        guard let standIn = UserDefaults(suiteName: standardStandIn) else {
            t.expect(false, "could create a scratch stand-in for the standard domain")
            return
        }
        defer { standIn.removePersistentDomain(forName: standardStandIn) }
        standIn.set("leaked.ndjson", forKey: Journal.journalKey)

        let resolved = AppIdentity.activeDefaults(defaults: argv)
        defer {
            if let suiteName = AppIdentity.harnessSuiteName(defaults: argv) {
                resolved.removePersistentDomain(forName: suiteName)
            }
        }
        let dir = TempDir("journal-cross-domain")
        defer { dir.cleanup() }
        let harness = dir.url.appendingPathComponent("harness")

        let activation = Journal.activate(defaults: resolved, directory: harness, build: build)
        guard case .inert = activation else {
            t.expect(false, "a key set in a different domain must not activate the journal, got \(activation)")
            return
        }
    })()

    // MARK: - 21. `AppIdentity.activeDefaults()` with no suite argument is
    // `.standard`, unchanged from before this unit.

    ({
        let argv = harnessDefaults([:])
        defer { resetHarnessDefaults() }
        t.expect(
            AppIdentity.activeDefaults(defaults: argv) === UserDefaults.standard,
            "with no -MeetingHopDefaultsSuite argument, the active defaults are exactly .standard"
        )
        t.expect(AppIdentity.harnessSuiteName(defaults: argv) == nil, "and there is no suite name to report either")
    })()

    // MARK: - 22. A persisted value does not open the suite gate the way a
    // real launch argument does — `harnessSuiteName` reads the argument
    // domain specifically, not the merged `string(forKey:)` search a plain
    // `defaults write` would also satisfy. A scratch suite stands in for
    // "some domain with a persisted value", so this never touches the real
    // `UserDefaults.standard` a test-running machine actually has (the
    // property under test — persisted-write versus argument-domain-only
    // read — does not depend on which domain the persisted value sits in;
    // verified empirically before this suite was written, see
    // `AppIdentity`'s doc comment).

    ({
        let suiteName = "dev.facens.meetinghop.journaltest.argvgate.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch suite")
            return
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("persisted-not-argv", forKey: AppIdentity.HarnessArguments.defaultsSuite)

        t.expect(
            suite.string(forKey: AppIdentity.HarnessArguments.defaultsSuite) == "persisted-not-argv",
            "sanity check: the merged search does see the persisted value"
        )
        t.expect(
            AppIdentity.harnessSuiteName(defaults: suite) == nil,
            "but the argument-domain-only read does not mistake it for a launch argument"
        )
    })()

    // MARK: - 23. `calendar access`'s `skipped_reason` is additive: absent by
    // default, so every line this field did not exist for still matches
    // exactly what it matched before, and present only when
    // `Coordinator.start()` skipped the request outright
    // (`BundleTranslocation`) rather than making it and being refused.

    ({
        let requested = JournalData.calendarAccess(granted: false, status: "denied", statusBefore: "notDetermined")
        t.expect(requested["skipped_reason"] == nil, "a real, answered request carries no skipped_reason field at all")
        t.expectEqual(requested["granted"], .boolean(false), "…and its other fields are exactly what they were before this field existed")

        let skipped = JournalData.calendarAccess(granted: false, skippedReason: "translocated")
        t.expectEqual(skipped["skipped_reason"], .string("translocated"), "a skipped request says why")
        t.expectEqual(skipped["granted"], .boolean(false), "…and still carries granted: false — nobody was asked, and nobody said yes")
        t.expect(skipped["status"] == nil, "…but no status: EventKit was never asked, so it has no authorization status to report")
    })()
}
