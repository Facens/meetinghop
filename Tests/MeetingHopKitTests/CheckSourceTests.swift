import Foundation

/// `packaging/check-source.sh` is the Kit-purity gate CI runs on every push
/// and pull request. Each scenario runs the real script against a scratch
/// export of the tracked tree — `git archive HEAD` piped into a `TempDir`,
/// with the working-tree script and `Package.swift` overlaid, so `swift
/// package dump-package` has a manifest and a `Sources`/`Tests` tree to
/// inspect. No git repository is created here: unlike the publish script,
/// check-source.sh never touches git, so the export alone is enough.
///
/// Unlike AgentMenu's `check-source.sh`, MeetingHop's carries no licence-
/// header check — MeetingHop is MIT and its files carry no headers by
/// decision — so there is no header scenario here to port.
///
/// Ported from AgentMenu's `Tests/AgentMenuKitTests/CheckSourceTests.swift`.
func runCheckSourceTests(_ t: TestRunner) {
    t.suite("CheckSource")

    let root = repositoryRoot()
    guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("packaging/check-source.sh").path),
          FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
        print("   (skipped: packaging/check-source.sh or git not found)")
        return
    }

    // The two files the mutating scenarios edit — present in every
    // checkout, so there is nothing to look up before mutating them. Two
    // distinct files so each scenario's "stderr names the file" assertion
    // proves that scenario's own edit, not the other one's leftover.
    let cocoaTarget = "Sources/MeetingHopKit/AppIdentity.swift"
    let eventKitTarget = "Sources/MeetingHopKit/AppVersion.swift"

    // 1. The untouched export passes.
    do {
        let scratch = TempDir("check-source-clean")
        defer { scratch.cleanup() }
        guard makeScratchSourceTree(from: root, at: scratch.url, t) else { return }

        let result = runProcess("/usr/bin/env", ["packaging/check-source.sh"], in: scratch.url)
        t.expectEqual(result.status, 0, "the untouched tree passes")
        t.expect(result.stdout.contains("source checks: ok"), "stdout says so")
    }

    // 2. A stray AppKit-family import (Cocoa) under MeetingHopKit fails,
    // naming the file.
    do {
        let scratch = TempDir("check-source-cocoa")
        defer { scratch.cleanup() }
        guard makeScratchSourceTree(from: root, at: scratch.url, t) else { return }

        guard appendImport("Cocoa", to: cocoaTarget, in: scratch.url, t) else { return }

        let result = runProcess("/usr/bin/env", ["packaging/check-source.sh"], in: scratch.url)
        t.expect(result.status != 0, "a Cocoa import under MeetingHopKit fails the check")
        t.expect(result.stderr.contains(cocoaTarget), "stderr names the offending file")
    }

    // 3. A stray EventKit import under MeetingHopKit — a different file —
    // fails, naming that file.
    do {
        let scratch = TempDir("check-source-eventkit")
        defer { scratch.cleanup() }
        guard makeScratchSourceTree(from: root, at: scratch.url, t) else { return }

        guard appendImport("EventKit", to: eventKitTarget, in: scratch.url, t) else { return }

        let result = runProcess("/usr/bin/env", ["packaging/check-source.sh"], in: scratch.url)
        t.expect(result.status != 0, "an EventKit import under MeetingHopKit fails the check")
        t.expect(result.stderr.contains(eventKitTarget), "stderr names the offending file")
    }
}

/// Appends `import <module>` to `target` (relative to `dir`) and records a
/// failure if reading or writing either step fails, so a broken scenario
/// stops cleanly instead of running the script against a half-mutated tree.
private func appendImport(_ module: String, to target: String, in dir: URL, _ t: TestRunner) -> Bool {
    let targetURL = dir.appendingPathComponent(target)
    guard let original = try? String(contentsOf: targetURL, encoding: .utf8) else {
        t.expect(false, "read \(target) before appending the stray import")
        return false
    }
    do {
        try (original + "\nimport \(module)\n").write(to: targetURL, atomically: true, encoding: .utf8)
    } catch {
        t.expect(false, "appended an \(module) import to \(target): \(error)")
        return false
    }
    return true
}

/// A throwaway export of the tracked tree with the working-tree
/// `check-source.sh` and `Package.swift` laid over it, so uncommitted edits
/// to either are what gets exercised. No git repository is created — the
/// script only reads files, never git state.
private func makeScratchSourceTree(from root: URL, at dir: URL, _ t: TestRunner) -> Bool {
    let export = runProcess(
        "/usr/bin/env",
        ["/bin/bash", "-c", "git -C \(singleQuoted(root.path)) archive HEAD | tar -x -C \(singleQuoted(dir.path))"],
        in: root
    )
    guard export.status == 0 else {
        t.expect(false, "exported the tracked tree into a scratch directory: \(export.stderr)")
        return false
    }
    for overlay in ["packaging/check-source.sh", "Package.swift"] {
        let source = root.appendingPathComponent(overlay)
        let overlayTarget = dir.appendingPathComponent(overlay)
        try? FileManager.default.removeItem(at: overlayTarget)
        do {
            try FileManager.default.copyItem(at: source, to: overlayTarget)
        } catch {
            t.expect(false, "copied \(overlay) into the scratch tree: \(error)")
            return false
        }
    }
    do {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: dir.appendingPathComponent("packaging/check-source.sh").path
        )
    } catch {
        t.expect(false, "made check-source.sh executable in the scratch tree: \(error)")
        return false
    }
    return true
}
