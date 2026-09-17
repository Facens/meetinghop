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
/// `CFBundleVersion` is deliberately not read: `packaging/bundle.sh` stamps
/// one `__VERSION__` placeholder into both keys (see
/// `BundleVersionTests.runBundleVersionTests`), so the two keys are identical
/// by construction and there is nothing a second read would add.
public enum AppVersion {
    /// What `swift run` sees: no Info.plist exists outside an assembled
    /// bundle, so there is no real version to report. Clearly marked as a
    /// fallback rather than an empty string, so it cannot be mistaken for a
    /// real (if blank) version number.
    public static let developmentFallback = "dev"

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
