import Foundation

/// R22: MeetingHop displays its own version somewhere a user can read it.
///
/// Reads `CFBundleShortVersionString` from the bundle it is asked about, the
/// same key AgentMenu's `agentMenuVersion` reads from `Bundle.main` — see
/// `AgentMenuKit.swift`. That accessor also walks up from the running
/// executable's path when `Bundle.main` has no Info.plist, because
/// AgentMenu's CLI binary lives nested at `Contents/Resources/bin/agentmenu`,
/// where `Bundle.main` resolves to its own directory rather than the
/// surrounding `.app`. MeetingHop ships no such nested executable — the
/// bundle it runs inside either is the `.app` (a real build) or does not
/// exist at all (`swift run`) — so that walk-up has nothing to find and is
/// deliberately not ported here.
///
/// `CFBundleVersion` is deliberately not read: since the three release
/// channels landed (R20 / KTD10, as amended), the two keys are no longer
/// identical. `packaging/bundle.sh` stamps `CFBundleShortVersionString` with
/// the version as written and derives `CFBundleVersion` from it — a fourth,
/// numeric component that breaks Sparkle's tie between a pre-release and its
/// final (see `packaging/version.sh` and
/// `BundleVersionTests.runBundleVersionTests`). `CFBundleShortVersionString`
/// is the one a person reads, so it is the one this accessor returns.
public enum AppVersion {
    /// What `swift run` sees: no Info.plist exists outside an assembled
    /// bundle, so there is no real version to report. This is also what
    /// `packaging/bundle.sh` stamps `CFBundleShortVersionString` with when
    /// `make bundle` runs with no `VERSION` (see the Makefile's default) —
    /// a local build is an alpha by definition — so `display()` reports the
    /// same string a fallback local build would carry, and `0.0.0` is never
    /// a version that ships, so it cannot be mistaken for a real release.
    public static let developmentFallback = "0.0.0-alpha"

    /// - Parameter bundle: the bundle to read the version from. Defaults to
    ///   `Bundle.main` — the running app in a real build, a bundle with no
    ///   Info.plist under `swift run`. Overridable so a test can hand in a
    ///   scratch bundle instead of relaunching as one.
    public static func display(from bundle: Bundle = .main) -> String {
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return developmentFallback
    }
}
