import Foundation

/// R6 / KTD16: `packaging/verify-signing.sh` exists to catch exactly the
/// defect its own header describes — a nested Mach-O that `codesign --verify
/// --strict --deep` waved through because `--deep` never looks in
/// `Contents/Resources`. That means the script's rejection paths are the
/// whole point of it, and none of them were ever proven to actually fail.
///
/// MeetingHop's bundle is simpler than AgentMenu's: exactly one Mach-O
/// (`Contents/MacOS/MeetingHop`), no nested CLI, and — per KTD16's own
/// comment in the script — no entitlements at all, since MeetingHop sends no
/// Apple Events. Every scenario here signs a scratch `Scratch.app` the same
/// way `packaging/bundle.sh` signs the real one — ad-hoc, `--options
/// runtime`, `--timestamp=none`, no entitlements — then mutates exactly one
/// thing about it and runs the real script as a subprocess. No `swift
/// build`, no certificate: the Mach-O is a freshly `clang`-compiled no-op,
/// which is exactly the "linker-signed" ad-hoc shape the script exists to
/// catch before anything is signed at all.
///
/// Ported from AgentMenu's `Tests/AgentMenuKitTests/VerifySigningTests.swift`.
func runVerifySigningTests(_ t: TestRunner) {
    t.suite("VerifySigning")

    let root = repositoryRoot()
    let script = root.appendingPathComponent("packaging/verify-signing.sh").path
    guard FileManager.default.isExecutableFile(atPath: script),
          FileManager.default.isExecutableFile(atPath: "/usr/bin/clang"),
          FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") else {
        print("   (skipped: packaging/verify-signing.sh, clang or codesign not found)")
        return
    }

    // 1. Properly signed bundle: consistency passes and says so.
    do {
        let dir = TempDir("verify-signing-ok")
        defer { dir.cleanup() }
        guard let app = buildScratchAppSkeleton(in: dir, t) else { return }
        t.expectEqual(signApp(app.app).status, 0, "signed the app")

        let result = runProcess(script, ["consistency", app.app.path])
        t.expectEqual(result.status, 0, "a properly signed bundle passes consistency")
        t.expect(result.stdout.contains("ok (1 Mach-O)"), "stdout reports the one Mach-O was checked")
    }

    // 2. The executable replaced by a freshly compiled (linker-signed) binary
    // after the app was already signed.
    do {
        let dir = TempDir("verify-signing-linker-signed")
        defer { dir.cleanup() }
        guard let app = buildScratchAppSkeleton(in: dir, t) else { return }
        t.expectEqual(signApp(app.app).status, 0, "signed the app")

        let recompiled = runProcess("/usr/bin/clang", ["-o", app.executable.path, dir.path("main.c")])
        t.expectEqual(recompiled.status, 0, "recompiled the executable in place, leaving it linker-signed")

        let result = runProcess(script, ["consistency", app.app.path])
        t.expect(result.status != 0, "a linker-signed executable fails consistency")
        t.expect(result.stderr.contains("linker-signed"), "stderr names the linker-signed flag")
        t.expect(result.stderr.contains("Contents/MacOS/Scratch"), "stderr names the executable's path")
    }

    // 3. The app signed WITHOUT --options runtime.
    do {
        let dir = TempDir("verify-signing-no-runtime")
        defer { dir.cleanup() }
        guard let app = buildScratchAppSkeleton(in: dir, t) else { return }
        t.expectEqual(signApp(app.app, hardenedRuntime: false).status, 0, "signed the app without the hardened runtime")

        let result = runProcess(script, ["consistency", app.app.path])
        t.expect(result.status != 0, "a bundle signed without the hardened runtime fails consistency")
        t.expect(result.stderr.contains("hardened runtime not requested"), "stderr says why")
    }

    // 4. The app signed WITH an entitlements plist — MeetingHop ships none.
    do {
        let dir = TempDir("verify-signing-entitlements")
        defer { dir.cleanup() }
        guard let app = buildScratchAppSkeleton(in: dir, t) else { return }
        t.expectEqual(signApp(app.app, entitlements: app.entitlements).status, 0, "signed the app with entitlements")

        let result = runProcess(script, ["consistency", app.app.path])
        t.expect(result.status != 0, "a bundle signed with entitlements fails consistency")
        t.expect(
            result.stderr.contains("carries entitlements; MeetingHop ships none"),
            "stderr says why"
        )
    }

    // 5. A properly signed all-ad-hoc bundle: consistency's job is done, but
    // authority — the release gate — refuses it for having no Developer ID.
    do {
        let dir = TempDir("verify-signing-authority")
        defer { dir.cleanup() }
        guard let app = buildScratchAppSkeleton(in: dir, t) else { return }
        t.expectEqual(signApp(app.app).status, 0, "signed the app")

        let result = runProcess(script, ["authority", app.app.path])
        t.expect(result.status != 0, "an ad-hoc signed bundle fails the authority check")
        t.expect(result.stderr.contains("no Developer ID Application authority"), "stderr names the missing authority")
        t.expect(result.stderr.contains("ad-hoc signed"), "stderr also flags the ad-hoc flag")
    }

    // 6. A bundle with no Mach-O at all — just an Info.plist.
    do {
        let dir = TempDir("verify-signing-no-macho")
        defer { dir.cleanup() }
        do {
            try dir.write(scratchInfoPlist, to: "Scratch.app/Contents/Info.plist")
        } catch {
            t.expect(false, "wrote a Mach-O-less bundle's Info.plist: \(error)")
            return
        }

        let result = runProcess(script, ["consistency", dir.path("Scratch.app")])
        t.expect(result.status != 0, "a bundle with no Mach-O fails")
        t.expect(result.stderr.contains("no Mach-O found"), "stderr says why")
    }
}

// MARK: - Scratch bundle

private let scratchInfoPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Scratch</string>
    <key>CFBundleIdentifier</key>
    <string>dev.facens.scratch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleName</key>
    <string>Scratch</string>
</dict>
</plist>
"""

private let scratchEntitlementsPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
"""

private struct ScratchApp {
    let app: URL
    let executable: URL
    let entitlements: URL
}

/// Builds an unsigned scratch `Scratch.app` — `Contents/MacOS/Scratch`,
/// `Contents/Info.plist`, `Contents/PkgInfo` — plus the entitlements file the
/// entitlements scenario signs with. There is no nested CLI: MeetingHop's
/// bundle carries exactly one Mach-O. It is freshly `clang`-compiled, so
/// before it is signed by this file it carries the linker's own ad-hoc
/// signature (`flags=0x20002(adhoc,linker-signed)`), matching a real
/// unsigned build product.
private func buildScratchAppSkeleton(in dir: TempDir, _ t: TestRunner) -> ScratchApp? {
    do {
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("Scratch.app/Contents/MacOS"),
            withIntermediateDirectories: true
        )
    } catch {
        t.expect(false, "created the scratch bundle's directories: \(error)")
        return nil
    }

    do {
        try dir.write(scratchInfoPlist, to: "Scratch.app/Contents/Info.plist")
        try dir.write("APPL????", to: "Scratch.app/Contents/PkgInfo")
        try dir.write(scratchEntitlementsPlist, to: "entitlements.plist")
        try dir.write("int main(void) { return 0; }\n", to: "main.c")
    } catch {
        t.expect(false, "wrote the scratch bundle's fixed files: \(error)")
        return nil
    }

    let mainExecutable = dir.path("Scratch.app/Contents/MacOS/Scratch")
    let compiled = runProcess("/usr/bin/clang", ["-o", mainExecutable, dir.path("main.c")])
    guard compiled.status == 0 else {
        t.expect(false, "compiled a trivial Mach-O with clang: \(compiled.stderr)")
        return nil
    }

    return ScratchApp(
        app: dir.url.appendingPathComponent("Scratch.app"),
        executable: URL(fileURLWithPath: mainExecutable),
        entitlements: dir.url.appendingPathComponent("entitlements.plist")
    )
}

/// Signs the app the way `packaging/bundle.sh` does: ad-hoc, the hardened
/// runtime, and (normally) no entitlements at all. Parameters let a scenario
/// deviate from that shape in exactly the one way it needs to.
@discardableResult
private func signApp(_ app: URL, hardenedRuntime: Bool = true, entitlements: URL? = nil) -> ScriptOutput {
    var args = ["--force"]
    if hardenedRuntime { args += ["--options", "runtime"] }
    args += ["--sign", "-", "--timestamp=none"]
    if let entitlements { args += ["--entitlements", entitlements.path] }
    args.append(app.path)
    return runProcess("/usr/bin/codesign", args)
}
