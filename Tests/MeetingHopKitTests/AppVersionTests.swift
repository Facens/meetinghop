import Foundation
import MeetingHopKit

/// U18/R22: MeetingHop displays its own version somewhere a user can read it.
///
/// `AppVersion.display(from:)` takes the bundle to read as a parameter —
/// unlike AgentMenu's `agentMenuVersion`, which is a global computed once
/// against `Bundle.main` — precisely so this suite can hand it a scratch
/// bundle instead of the real one, without a running `.app` to launch from.
///
/// Deliberately not ported from AgentMenu: the walk-up from the running
/// executable's path, hunting for an `Info.plist` above it. That fallback
/// exists there only because AgentMenu's CLI binary lives nested at
/// `Contents/Resources/bin/agentmenu`, where `Bundle.main` resolves to its
/// own directory rather than the surrounding `.app` — see
/// `AgentMenuKit.agentMenuVersion`'s doc comment. MeetingHop ships no such
/// nested executable, so there is nothing for that walk-up to find, and
/// porting it would be dead code pretending to be a safety net.
func runAppVersionTests(_ t: TestRunner) {
    t.suite("AppVersion")

    // MARK: - Inside a bundle with a stamped Info.plist

    do {
        let dir = TempDir("app-version-bundle")
        defer { dir.cleanup() }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>3.4.5</string>
            <key>CFBundleVersion</key>
            <string>3.4.5</string>
        </dict>
        </plist>
        """
        t.expectNoThrow("writes Scratch.app/Contents/Info.plist") {
            try dir.write(plist, to: "Scratch.app/Contents/Info.plist")
        }

        guard let bundle = Bundle(path: dir.path("Scratch.app")) else {
            t.expect(false, "Bundle(path:) loads the scratch .app")
            return
        }
        t.expectEqual(
            AppVersion.display(from: bundle), "3.4.5",
            "the accessor reads CFBundleShortVersionString back out of a real bundle"
        )
    }

    // MARK: - No Info.plist at all (what `swift run` sees)

    do {
        let dir = TempDir("app-version-bare")
        defer { dir.cleanup() }

        // A bare directory with nothing written into it. Bundle(path:) still
        // hands back a non-nil Bundle for any existing directory — it is
        // `object(forInfoDictionaryKey:)` that comes back nil, because there
        // is no Info.plist to read. That is the case this asserts: no crash,
        // no empty string, a clearly-marked development fallback instead.
        guard let bundle = Bundle(path: dir.url.path) else {
            t.expect(false, "Bundle(path:) loads a bare directory")
            return
        }
        let version = AppVersion.display(from: bundle)
        t.expectEqual(
            version, AppVersion.developmentFallback,
            "a bundle with no Info.plist reports the development fallback"
        )
        t.expect(!version.isEmpty, "the fallback is never an empty string")
    }

    // MARK: - The default argument: Bundle.main, with no bundle around it

    // This test binary (`MeetingHopKitTests`) is a bare SwiftPM executable —
    // the same shape `MeetingHop` has under `swift run` or `swift build -c
    // release --product MeetingHop`, before `make bundle` wraps it in a
    // `.app` with a real Info.plist. So `display()` with no argument here
    // exercises the exact call `MenuBarView.versionRow` makes, in the exact
    // situation the orchestrator's build (which cannot run `make bundle`)
    // leaves it in.
    t.expectEqual(
        AppVersion.display(), AppVersion.developmentFallback,
        "running outside an assembled bundle reports the development fallback, the same as Bundle.main would for the app under swift run"
    )
}
