import Foundation

/// R20 / KTD10 (as amended): `packaging/bundle.sh` stamps
/// `CFBundleShortVersionString` with the version as the caller wrote it and
/// derives `CFBundleVersion` from it through `packaging/version.sh` — a
/// numeric fourth component, because Sparkle's comparator
/// (`SUStandardVersionComparator`) stops reading at the first "-", and
/// without that fourth component `0.2.0-beta.1` and `0.2.0` would tie. A
/// version outside the three-channel grammar (stable, beta, alpha; see
/// `packaging/version.sh` for the table) must fail the bundle step before a
/// build is even started, rather than stamping a build number no client
/// could order.
///
/// Ported from AgentMenu's `BundleVersionTests.swift`. The rejection cases run
/// the real script. They are fast because the check sits before `swift build`;
/// a rejection that took seconds would mean the validation had drifted below
/// the build and was no longer the gate.
func runBundleVersionTests(_ t: TestRunner) {
    t.suite("BundleVersion")

    let root = repositoryRoot()
    let script = root.appendingPathComponent("packaging/bundle.sh").path
    let versionScript = root.appendingPathComponent("packaging/version.sh").path
    let template = root.appendingPathComponent("packaging/Info.plist").path
    guard FileManager.default.isExecutableFile(atPath: script),
          FileManager.default.isReadableFile(atPath: template) else {
        print("   (skipped: packaging/bundle.sh or packaging/Info.plist not found at \(root.path))")
        return
    }

    // Happy path: the two placeholders feed the two keys separately now —
    // CFBundleShortVersionString gets the version as written, CFBundleVersion
    // gets the derived build number.
    if let source = try? String(contentsOfFile: template, encoding: .utf8) {
        let rendered = source
            .replacingOccurrences(of: "__VERSION__", with: "0.2.0-beta.3")
            .replacingOccurrences(of: "__BUILD__", with: "0.2.0.3")
        let plist = (try? PropertyListSerialization.propertyList(
            from: Data(rendered.utf8), format: nil
        )) as? [String: Any]
        t.expectEqual(plist?["CFBundleShortVersionString"] as? String, "0.2.0-beta.3", "display version is the version as written")
        t.expectEqual(plist?["CFBundleVersion"] as? String, "0.2.0.3", "build version is the derived, orderable number")
        t.expect(!rendered.contains("__VERSION__"), "no __VERSION__ placeholder survives rendering")
        t.expect(!rendered.contains("__BUILD__"), "no __BUILD__ placeholder survives rendering")
    } else {
        t.expect(false, "packaging/Info.plist is readable")
    }

    // The table from packaging/version.sh's header, run against the real
    // script rather than restated here — restating it would let the two
    // drift apart silently. Each version prints its channel, then its build
    // number, one per line.
    let table: [(version: String, channel: String, build: String)] = [
        ("0.2.0", "stable", "0.2.0.100"),
        ("0.2.0-beta.1", "beta", "0.2.0.1"),
        ("0.2.0-beta.99", "beta", "0.2.0.99"),
        ("0.2.0-alpha", "alpha", "0.2.0.0"),
    ]
    guard FileManager.default.isReadableFile(atPath: versionScript) else {
        t.expect(false, "packaging/version.sh is readable")
        return
    }
    for entry in table {
        let result = runProcess(
            "/bin/bash",
            ["-c", "source packaging/version.sh && version_channel \"$1\" && version_build \"$1\"", "_", entry.version],
            in: root
        )
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        t.expect(result.status == 0, "\(entry.version) is accepted by packaging/version.sh")
        t.expectEqual(lines.first ?? "", entry.channel, "\(entry.version) reports channel \(entry.channel)")
        t.expectEqual(lines.count > 1 ? lines[1] : "", entry.build, "\(entry.version) reports build \(entry.build)")
    }

    // Rejection: N out of 1...99 on both ends, an unknown pre-release tag, an
    // alpha with a trailing component, a leading v (the workflow strips it,
    // the script does not), too few or too many components, and plain
    // garbage. Each must exit non-zero, name the problem, and leave no bundle
    // behind. The script writes to dist/ under the repository, so the "no
    // bundle" assertion is that the refusal happened before the build — the
    // mtime of dist/MeetingHop.app, if one exists from an earlier real
    // build, is untouched.
    let rejected = [
        "0.2.0-beta.0", "0.2.0-beta.100", "0.2.0-rc1", "0.2.0-alpha.1",
        "v0.2.0", "0.2", "1.2.3.4", "abc",
    ]
    let existing = root.appendingPathComponent("dist/MeetingHop.app").path
    let before = (try? FileManager.default.attributesOfItem(atPath: existing))?[.modificationDate] as? Date
    for version in rejected {
        let started = Date()
        let result = runProcess("/bin/bash", [script], environment: ["VERSION": version])
        let elapsed = Date().timeIntervalSince(started)

        t.expect(result.status != 0, "VERSION=\(version) fails the bundle step")
        t.expect(result.stderr.contains("VERSION must be"), "VERSION=\(version) says what a version must look like")
        let after = (try? FileManager.default.attributesOfItem(atPath: existing))?[.modificationDate] as? Date
        t.expectEqual(after, before, "VERSION=\(version) leaves dist/ untouched")
        t.expect(elapsed < 5, "VERSION=\(version) is refused before anything is built (took \(Int(elapsed))s)")
    }
}
